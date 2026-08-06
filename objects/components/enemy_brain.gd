extends Component
class_name EnemyBrain

## Two-layer AI for an enemy.
##
## TOP LAYER — a small FSM over long-lived, interruptible modes:
##   WANDER : not aware of the player. The brain stays hands-off and lets the
##            MovementComponent's own MovementPattern (e.g. NavWanderMovement) run.
##   CHASE  : aware but out of reach. Paths to the player with the NavigationAgent3D.
##   COMBAT : in reach. Runs one ACTION at a time, re-picking on completion.
##
## BOTTOM LAYER — the actions, which are NOT written here. Each is an EnemyAction
## node under the host's `Actions` container, and this class is only their
## scheduler: gather the eligible ones, weighted-pick, await, repeat. Giving an
## enemy a new attack is "write one script, drop one node"; giving a DIFFERENT
## enemy the same attack is dropping the same node under it. Nothing in this file
## knows what a swing or a twirl is.
##
## Movement always goes through MovementComponent.drive()/face_toward() rather than
## touching the body, so velocity keeps exactly one writer — the invariant that
## lets knockback and the movement patterns coexist.
##
## The FSM is an enum rather than a node per state: with three modes that is far
## less ceremony, and it stays legible while the behaviour is still in flux.

enum State { WANDER, CHASE, COMBAT }

@export_group("Ranges")
## Preferred distance to hold in combat. Actions read this as "the usual spacing".
@export var combat_range: float = 6.0
## Extra distance beyond `combat_range` before dropping back to CHASE. Stops the
## enemy flip-flopping between chasing and orbiting on the boundary.
@export var range_hysteresis: float = 2.5

@export_group("Speeds")
## Speed while closing on the player. Per-action speeds live on the actions.
@export var chase_speed: float = 4.0
## Whether this creature closes distance at all. Turn OFF for a stationary one —
## a turret, a rooted mushroom, a blob wedged in a doorway. With it off the brain
## goes straight from WANDER to COMBAT when alerted and never drives the body
## toward the player; the actions' own range bands then decide everything.
@export var can_chase: bool = true

@export_group("Navigation")
## How far off the navmesh a projected step may land before it counts as blocked.
## Read by actions through `is_navigable()`.
@export var navmesh_tolerance: float = 1.0

@export_group("References")
## Container whose EnemyAction children are this enemy's combat repertoire.
@export var actions_path: NodePath = ^"../Actions"
@export var movement_path: NodePath = ^"../MovementComponent"
@export var agent_path: NodePath = ^"../NavigationAgent3D"
@export var perception_path: NodePath = ^"../PerceptionComponent"
@export var attack_box_path: NodePath = ^"../AttackBox"
## AnimationPlayer for action clips. Empty = auto-find under the host.
@export var animation_player_path: NodePath

@export var debug_log: bool = true

var _body: CharacterBody3D = null
var _move: Node = null
var _agent: NavigationAgent3D = null
var _perception: Node = null
var _player: Node3D = null

var _hitbox: Node = null  # MeleeHitbox on the AttackBox (duck-typed)
var _ap: AnimationPlayer = null
var _coordinator: Node = null  # EnemyCoordinator (duck-typed, optional)

## Top-level actions the brain may pick from, and the flattened list (including
## nested follow-ups) used for cooldown ticking and abort.
var _actions: Array[EnemyAction] = []
var _all_actions: Array[EnemyAction] = []
## TriggerRegions referenced by those actions. Occupancy alerts this creature.
var _regions: Array[Node] = []

var _state: State = State.WANDER
var _current: EnemyAction = null
var _action_elapsed: float = 0.0

## True while an action owns the body; the per-frame dispatcher stays out of its way.
var _busy: bool = false
## True while a committed action is running: state transitions are suppressed so a
## roaming action can't cross the combat boundary and abort itself. Set from the
## running action's `committed` flag.
var _committed: bool = false
## True while we hold the coordinator's attack slot on behalf of the running action.
var _slot_held: bool = false
## Bumped by _abort_actions() to cancel any in-flight coroutine. An action captures
## this at its start and bails the moment the two disagree — this is what keeps an
## aborted combo from resuming halfway through, three states later.
var _action_token: int = 0


func _setup() -> void:
	_body = host as CharacterBody3D
	_move = get_node_or_null(movement_path)
	_agent = get_node_or_null(agent_path) as NavigationAgent3D
	_perception = get_node_or_null(perception_path)
	_hitbox = get_node_or_null(attack_box_path)
	# Asked of the host, never searched for. A scene-wide lookup would silently
	# merge every encounter in the level into one group — see Enemy.coordinator.
	if host.has_method("get_coordinator"):
		_coordinator = host.call("get_coordinator") as Node
	if animation_player_path != NodePath() and has_node(animation_player_path):
		_ap = get_node(animation_player_path) as AnimationPlayer
	else:
		_ap = _find_animation_player(host)
	if _move == null:
		push_warning("[EnemyBrain] No MovementComponent at '%s'; brain disabled." % movement_path)
	_gather_actions()
	_close_hitbox()
	set_physics_process(false)


## Collect the action nodes and hand each the shared context, so an action needs no
## wiring of its own — dropping the node in is the whole setup.
func _gather_actions() -> void:
	_actions.clear()
	_all_actions.clear()
	_regions.clear()
	var container: Node = get_node_or_null(actions_path)
	if container == null:
		if debug_log:
			push_warning("[EnemyBrain] No Actions container at '%s'; combat will idle." % actions_path)
		return

	var context := {
		"brain": self,
		"body": _body,
		"move": _move,
		"agent": _agent,
		"hitbox": _hitbox,
		"anim": _ap,
	}
	for child in container.get_children():
		if child is EnemyAction:
			var action := child as EnemyAction
			action.setup(context)
			_actions.append(action)
			_collect(action)


## Flatten an action and its nested follow-ups into `_all_actions`, and pick up any
## TriggerRegion they are gated on.
func _collect(action: EnemyAction) -> void:
	_all_actions.append(action)
	var region: Node = action.get_region()
	if region != null and not _regions.has(region):
		_regions.append(region)
	for child in action.get_children():
		if child is EnemyAction:
			_collect(child as EnemyAction)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	for child in node.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var found: AnimationPlayer = _find_animation_player(child)
		if found:
			return found
	return null


func on_activate() -> void:
	set_physics_process(true)


func on_deactivate() -> void:
	set_physics_process(false)
	_abort_actions()
	_enter_state(State.WANDER)


## Cancel any in-flight coroutine and put shared state back to a safe baseline.
## Bumping the token is what actually stops a running action: it can't be killed
## outright, so instead it notices the mismatch at its next await and returns.
func _abort_actions() -> void:
	_action_token += 1
	_busy = false
	_committed = false
	_current = null
	_close_hitbox()
	_release_attack_slot()
	# Every action, not just the current one: a nested follow-up may have been the
	# one actually running, and on_abort() is required to be safe on an idle action.
	for action in _all_actions:
		action.on_abort()


func get_state_name() -> String:
	return State.keys()[_state]


func get_action_name() -> String:
	return String(_current.name) if _current else "NONE"


## Read by the running action after every await: are we still the action that owns
## the body, and is there still a fight to be in?
func is_action_current(token: int) -> bool:
	return token == _action_token \
		and _state == State.COMBAT \
		and is_instance_valid(_player) \
		and is_instance_valid(_body)


## The player as the brain currently understands them. Actions read this rather
## than looking the player up themselves.
func get_player() -> Node3D:
	return _player if is_instance_valid(_player) else null


func _physics_process(delta: float) -> void:
	if _move == null or _body == null:
		return
	# Nothing to think about while dying.
	if host.has_method("is_defeated") and bool(host.call("is_defeated")):
		return

	_player = _resolve_player()
	_report_sighting()
	for action in _all_actions:
		action.tick_cooldown(delta)
	_watch_timeout(delta)
	_update_state()

	match _state:
		State.WANDER:
			pass  # hands off — the MovementPattern drives.
		State.CHASE:
			_run_chase()
		State.COMBAT:
			_run_combat()


## Safety net: never let an action wedge the brain. Runs even for a committed
## action, which is the whole point — a committed one suppresses every other exit.
func _watch_timeout(delta: float) -> void:
	if not _busy or _current == null:
		return
	_action_elapsed += delta
	if _current.timeout > 0.0 and _action_elapsed >= _current.timeout:
		if debug_log:
			print("[EnemyBrain] %s action '%s' timed out" % [String(host.name), _current.name])
		_abort_actions()


func _resolve_player() -> Node3D:
	if _perception and _perception.has_method("get_player"):
		return _perception.call("get_player") as Node3D
	return get_tree().get_first_node_in_group("player") as Node3D


## Alerted if I personally see the player, OR the player is standing in a region
## one of my actions cares about, OR a groupmate has a fresh sighting (shared
## perception recruits the whole group off one member's eyes).
##
## The REGION clause is what makes a bombardment encounter possible at all.
## Perception needs line of sight, so a creature lobbing bombs over a wall would
## otherwise never notice the player and never fire a shot. Occupancy of a region
## it can act on counts as knowing you are there — which is exactly the fiction:
## it knows roughly where you are, it just cannot see you.
func _is_alerted() -> bool:
	if not is_instance_valid(_player):
		return false
	if _sees_player():
		return true
	if _region_occupied():
		return true
	if _coordinator and bool(_coordinator.call("has_fresh_sighting")):
		return true
	return false


func _region_occupied() -> bool:
	for region in _regions:
		if is_instance_valid(region) and bool(region.call("is_occupied")):
			return true
	return false


## Is there a clear line to the player? Read by actions with a `los_requirement`.
func has_line_of_sight() -> bool:
	return _perception != null and _perception.has_method("has_line_of_sight") \
		and bool(_perception.call("has_line_of_sight"))


func _sees_player() -> bool:
	return _perception != null and _perception.has_method("is_alerted") \
		and bool(_perception.call("is_alerted"))


## Post my own sighting to the group blackboard so allies can join in.
func _report_sighting() -> void:
	if _coordinator and is_instance_valid(_player) and _sees_player():
		_coordinator.call("report_player_seen", _player.global_position)


func _claim_attack_slot() -> bool:
	return _coordinator == null or bool(_coordinator.call("claim_attack_slot", host))


func _release_attack_slot() -> void:
	if _slot_held and _coordinator:
		_coordinator.call("release_attack_slot", host)
	_slot_held = false


## Mode transitions. Distance is flattened — height shouldn't decide reach.
func _update_state() -> void:
	# A committed action owns the body until it finishes. It suppresses ALL
	# transitions — including perception loss — because it's already bounded by its
	# own timeouts, and a blind twirl that flings the player out of view must not
	# cancel itself the instant it connects.
	if _committed:
		return

	# An enemy with an empty Actions container has no repertoire, so there is
	# nothing for chasing the player to lead to — stay hands-off and let the
	# MovementPattern have the body. This is what lets the AI ride on the BASE
	# enemy without changing anything that doesn't opt in by adding actions.
	if _actions.is_empty():
		if _state != State.WANDER:
			_enter_state(State.WANDER)
		return

	if not _is_alerted():
		if _state != State.WANDER:
			_enter_state(State.WANDER)
		return

	# A stationary creature has no CHASE: it engages where it stands and lets its
	# actions' range bands decide what, if anything, it can do from there.
	if not can_chase:
		if _state != State.COMBAT:
			_enter_state(State.COMBAT)
		return

	var dist: float = _flat_distance_to_player()
	match _state:
		State.WANDER:
			_enter_state(State.CHASE)
		State.CHASE:
			if dist <= combat_range:
				_enter_state(State.COMBAT)
		State.COMBAT:
			if dist > combat_range + range_hysteresis:
				_enter_state(State.CHASE)


func _enter_state(next: State) -> void:
	if next == _state:
		return
	_state = next
	# Leaving the mode invalidates whatever action was mid-flight.
	_abort_actions()

	# Claim/drop a ring slot with the group so engaged enemies spread out.
	if _coordinator:
		if next == State.WANDER:
			_coordinator.call("disengage", host)
		else:
			_coordinator.call("engage", host)

	# Handing the body back to the wander pattern: clear the chase destination so
	# the pattern sees "arrived" and immediately rolls a fresh wander target,
	# instead of first walking to wherever the player last was.
	if next == State.WANDER and _agent:
		_agent.target_position = _body.global_position

	if debug_log:
		print("[EnemyBrain] %s -> %s" % [String(host.name), get_state_name()])


func _flat_distance_to_player() -> float:
	if not is_instance_valid(_player):
		return INF
	var to := _player.global_position - _body.global_position
	to.y = 0.0
	return to.length()


# --- Modes -----------------------------------------------------------------

## Path to the player through the navmesh, so walls and ledges are respected.
## With a coordinator, each enemy heads for its own slot on the ring around the
## player instead of the player's exact feet — so they converge spread out rather
## than piling onto one point.
func _run_chase() -> void:
	if _agent == null or not is_instance_valid(_player):
		return
	_agent.target_position = _chase_target()
	var to_next: Vector3 = _agent.get_next_path_position() - _body.global_position
	to_next.y = 0.0
	if to_next.length_squared() < 0.0001:
		return
	_move.call("drive", to_next.normalized() * chase_speed)


func _chase_target() -> Vector3:
	var pos: Vector3 = _player.global_position
	if _coordinator:
		var a: float = _coordinator.call("get_ring_angle", host)
		pos += Vector3(sin(a), 0.0, cos(a)) * combat_range
	return pos


func _run_combat() -> void:
	# An action is driving; per-frame dispatch stays out of the way.
	if _busy:
		return
	var action: EnemyAction = _pick_action()
	if action == null:
		return

	_current = action
	_busy = true
	_committed = action.committed
	_action_elapsed = 0.0
	if debug_log:
		print("[EnemyBrain] %s action: %s" % [String(host.name), action.name])
	# Fire-and-forget: the coroutine runs alongside _physics_process and clears
	# _busy when it's done (or is aborted).
	_dispatch(action, _action_token)


## Weighted-random choice among the eligible actions.
##
## An action needing the coordinator's attack slot only claims it once actually
## chosen; if the claim fails it is dropped and we re-pick from the rest, so a
## group with no free slot keeps pressure by orbiting instead of stalling.
func _pick_action() -> EnemyAction:
	var dist: float = _flat_distance_to_player()
	var candidates: Array[EnemyAction] = []
	for action in _actions:
		if action.is_eligible(dist):
			candidates.append(action)

	while not candidates.is_empty():
		var picked: EnemyAction = _weighted_pick(candidates)
		if picked == null:
			return null
		if not picked.requires_attack_slot:
			return picked
		if _claim_attack_slot():
			_slot_held = true
			return picked
		candidates.erase(picked)
	return null


func _weighted_pick(candidates: Array[EnemyAction]) -> EnemyAction:
	var total: float = 0.0
	for action in candidates:
		total += maxf(action.weight, 0.0)
	if total <= 0.0:
		return candidates[randi() % candidates.size()]

	var roll: float = randf() * total
	for action in candidates:
		roll -= maxf(action.weight, 0.0)
		if roll <= 0.0:
			return action
	return candidates[candidates.size() - 1]


## Run one action to completion, then hand control back to the dispatcher.
func _dispatch(action: EnemyAction, token: int) -> void:
	var completed: bool = await action.run(token)
	# If the token moved on, something else has already taken over and touching
	# shared state here would stomp it.
	if token != _action_token:
		return
	action.start_cooldown()
	if debug_log and not completed:
		print("[EnemyBrain] %s action '%s' bailed" % [String(host.name), action.name])
	_busy = false
	_committed = false
	_current = null
	_close_hitbox()
	_release_attack_slot()


func _close_hitbox() -> void:
	if _hitbox:
		_hitbox.call("close")
