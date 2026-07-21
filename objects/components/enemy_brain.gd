extends Component
class_name EnemyBrain

## Two-layer AI for a melee enemy.
##
## TOP LAYER — a small FSM over long-lived, interruptible modes:
##   WANDER : not aware of the player. The brain stays hands-off and lets the
##            MovementComponent's own MovementPattern (e.g. NavWanderMovement) run.
##   CHASE  : aware but out of reach. Paths to the player with the NavigationAgent3D.
##   COMBAT : in reach. Runs one combat ACTION at a time, re-picking on completion.
##
## BOTTOM LAYER — combat actions. Each runs per-frame and reports when it's done,
## at which point the brain picks another. Step 1 ships the orbits; the attack
## combo (step 2) will slot in as an action that holds control across several
## swings.
##
## Movement always goes through MovementComponent.drive()/face_toward() rather
## than touching the body, so velocity keeps exactly one writer — the same
## invariant that makes knockback and the movement patterns coexist.
##
## The FSM is an enum rather than a node per state: with three modes that's far
## less ceremony, and it stays legible while the behaviour is still in flux.
## Promote to node-per-state if the mode count grows.

enum State { WANDER, CHASE, COMBAT }
enum Action { NONE, ORBIT_LEFT, ORBIT_RIGHT, ATTACK }

@export_group("Ranges")
## Preferred distance to hold in combat — the orbit radius.
@export var combat_range: float = 6.0
## Extra distance beyond `combat_range` before dropping back to CHASE. Stops the
## enemy flip-flopping between chasing and orbiting on the boundary.
@export var range_hysteresis: float = 2.5

@export_group("Speeds")
## Speed while closing on the player.
@export var chase_speed: float = 4.0
## Speed while circling.
@export var orbit_speed: float = 2.6
## How hard it corrects back toward `combat_range` while orbiting.
@export_range(0.0, 3.0, 0.1) var radial_correction: float = 1.2

@export_group("Actions")
## Chance a combat decision is an attack rather than an orbit.
@export_range(0.0, 1.0, 0.05) var attack_chance: float = 0.45
## Arc distance (world units) travelled before an orbit ends and the brain
## re-picks. "Several units", per the design.
@export var orbit_arc_units: float = 6.0
## Hard ceiling on any single action, so nothing can wedge the brain.
@export var action_timeout: float = 6.0
## How far off the navmesh a projected step may land before it counts as blocked.
@export var navmesh_tolerance: float = 1.0

@export_group("Attack")
## Swing count is rolled once, when the attack is chosen, and honoured even if
## the player moves — committing to a combo is what makes it readable/dodgeable.
@export var min_swings: int = 1
@export var max_swings: int = 3
## Distance it closes to before starting to swing. Must leave margin under the
## AttackBox's actual reach (~1.8 + the player's radius), or an off-centre swing
## sails past — the enemy would windmill at thin air.
@export var attack_range: float = 1.6
## Speed while closing for an attack.
@export var approach_speed: float = 4.5
## Give up approaching after this long (blocked, or the player kited away).
@export var approach_timeout: float = 4.0
## Extra beat between the 2nd and 3rd swing, so a triple reads differently.
@export var third_swing_delay: float = 0.45
## Clip played per swing.
@export var attack_animation: StringName = &"PracticeSwing"
## Playback rate for the swing (the raw clip is 2.25s, which is sluggish).
@export var attack_speed_scale: float = 1.4
## How far off-centre a swing may aim, in degrees. Each swing picks -this, 0, or
## +this, giving the front-left / front / front-right variation.
@export var aim_spread_deg: float = 28.0
## Normalized animation time by which the aim lerp completes ("first half").
@export_range(0.05, 1.0, 0.05) var aim_lerp_end: float = 0.5
## Normalized window during which the AttackBox is live.
@export_range(0.0, 1.0, 0.01) var hit_window_start: float = 0.5
@export_range(0.0, 1.0, 0.01) var hit_window_end: float = 0.68
## Damage per connected swing.
@export var attack_damage: int = 12
## Knockback a landed swing deals the player — deliberately gentler than the
## ZigzagTwirl's fling.
@export var swing_knockback_force: float = 8.0
## Upward pop on a swing hit.
@export var swing_knockback_up: float = 2.0
## Seconds a swing hit suppresses the player's input.
@export var swing_knockback_duration: float = 0.18

@export_group("Zigzag Twirl")
## Chance a swing combo is chased by a ZigzagTwirl. Only ever follows swings.
@export_range(0.0, 1.0, 0.05) var zigzag_chance: float = 0.5
## Point in PracticeSwing (seconds) frozen for the twirl — arms out, weapon front.
@export var zigzag_pose_time: float = 1.7
## Hold on the frozen pose before spinning up.
@export var zigzag_windup: float = 0.25
## How long the twirl roams.
@export var zigzag_duration: float = 2.5
## Body spin speed about Y, degrees/sec. High = frantic.
@export var zigzag_spin_speed_deg: float = 540.0
## Travel speed while zigzagging.
@export var zigzag_speed: float = 5.0
## Seconds between heading changes — the "zig". Short = choppier.
@export var zigzag_reroll_interval: float = 0.4
## Minimum turn (degrees) on each reroll, for strong chaotic angles rather than
## lazy drift.
@export_range(0.0, 180.0, 5.0) var zigzag_min_turn_deg: float = 100.0
## Seconds before the twirl can fling the same target again.
@export var zigzag_hit_cooldown: float = 0.5
## Horizontal fling force — set a touch above the bump's knockback for more punch.
@export var fling_force: float = 16.0
## Upward pop on the fling.
@export var fling_up: float = 4.0
## Seconds the fling suppresses the player's input.
@export var fling_duration: float = 0.3
## Damage on a twirl hit. 0 = pure knockback.
@export var zigzag_damage: int = 15

@export_group("Reposition")
## Chance the post-attack retreat strafes sideways instead of backing straight up.
@export_range(0.0, 1.0, 0.05) var strafe_retreat_chance: float = 0.5
## Speed while retreating to orbit range.
@export var retreat_speed: float = 3.2
## Give up retreating after this long.
@export var retreat_timeout: float = 3.0

@export_group("References")
@export var movement_path: NodePath = ^"../MovementComponent"
@export var agent_path: NodePath = ^"../NavigationAgent3D"
@export var perception_path: NodePath = ^"../PerceptionComponent"
@export var attack_box_path: NodePath = ^"../AttackBox"
## AnimationPlayer for the attack clip. Empty = auto-find under the host.
@export var animation_player_path: NodePath

@export var debug_log: bool = true

var _body: CharacterBody3D = null
var _move: Node = null
var _agent: NavigationAgent3D = null
var _perception: Node = null
var _player: Node3D = null

var _hitbox: Node = null  # MeleeHitbox on the AttackBox (duck-typed)
var _ap: AnimationPlayer = null

var _state: State = State.WANDER
var _action: Action = Action.NONE
var _action_elapsed: float = 0.0
var _orbit_travelled: float = 0.0
var _orbit_flipped: bool = false

## True while a coroutine action owns the body; _run_combat stays out of its way.
var _busy: bool = false
## True while a committed action (the attack combo) is running: range-based state
## transitions are suppressed so a roaming ZigzagTwirl can't cross the combat
## boundary and abort itself. Losing the player outright still cancels.
var _committed: bool = false
## Twirl scratch: accumulated spin yaw and current heading.
var _twirl_yaw: float = 0.0
var _twirl_dir: Vector3 = Vector3.FORWARD
## Bumped by _abort_actions() to cancel any in-flight coroutine. A coroutine
## captures this at its start and bails the moment the two disagree — this is what
## keeps an aborted combo from resuming halfway through, three states later.
var _action_token: int = 0


func _setup() -> void:
	_body = host as CharacterBody3D
	_move = get_node_or_null(movement_path)
	_agent = get_node_or_null(agent_path) as NavigationAgent3D
	_perception = get_node_or_null(perception_path)
	_hitbox = get_node_or_null(attack_box_path)
	if animation_player_path != NodePath() and has_node(animation_player_path):
		_ap = get_node(animation_player_path) as AnimationPlayer
	else:
		_ap = _find_animation_player(host)
	if _move == null:
		push_warning("[EnemyBrain] No MovementComponent at '%s'; brain disabled." % movement_path)
	_close_hitbox()
	set_physics_process(false)


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
## Bumping the token is what actually stops a running combo: it can't be killed
## outright, so instead it notices the mismatch at its next await and returns.
func _abort_actions() -> void:
	_action_token += 1
	_busy = false
	_committed = false
	_action = Action.NONE
	_close_hitbox()
	if _ap:
		# The twirl parks speed_scale at 0 to freeze its pose — restore it, or every
		# later animation would play frozen.
		_ap.speed_scale = 1.0
		if _ap.is_playing() and _ap.current_animation == String(attack_animation):
			_ap.stop()


func get_state_name() -> String:
	return State.keys()[_state]


func get_action_name() -> String:
	return Action.keys()[_action]


func _physics_process(delta: float) -> void:
	if _move == null or _body == null:
		return
	# Nothing to think about while dying.
	if host.has_method("is_defeated") and bool(host.call("is_defeated")):
		return

	_player = _resolve_player()
	_update_state()

	match _state:
		State.WANDER:
			pass  # hands off — the MovementPattern drives.
		State.CHASE:
			_run_chase()
		State.COMBAT:
			_run_combat(delta)


func _resolve_player() -> Node3D:
	if _perception and _perception.has_method("get_player"):
		return _perception.call("get_player") as Node3D
	return get_tree().get_first_node_in_group("player") as Node3D


func _is_alerted() -> bool:
	if _perception == null or not _perception.has_method("is_alerted"):
		return false
	return bool(_perception.call("is_alerted")) and is_instance_valid(_player)


## Mode transitions. Distance is flattened — height shouldn't decide reach.
func _update_state() -> void:
	# A committed action (the attack combo) owns the body until it finishes. It
	# suppresses ALL transitions — including perception loss — because it's already
	# bounded by its own timeouts/duration, and a blind twirl that flings the player
	# out of view must not cancel itself the instant it connects.
	if _committed:
		return

	if not _is_alerted():
		if _state != State.WANDER:
			_enter_state(State.WANDER)
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
func _run_chase() -> void:
	if _agent == null or not is_instance_valid(_player):
		return
	_agent.target_position = _player.global_position
	var to_next: Vector3 = _agent.get_next_path_position() - _body.global_position
	to_next.y = 0.0
	if to_next.length_squared() < 0.0001:
		return
	_move.call("drive", to_next.normalized() * chase_speed)


func _run_combat(delta: float) -> void:
	# A coroutine action is driving; per-frame dispatch stays out of the way.
	if _busy:
		return
	if _action == Action.NONE:
		_pick_action()
	if _busy:
		return  # the pick started a coroutine.
	if _run_action(delta):
		_action = Action.NONE


## Weighted-random action choice.
func _pick_action() -> void:
	_action_elapsed = 0.0
	_orbit_travelled = 0.0
	_orbit_flipped = false

	if randf() < attack_chance:
		_action = Action.ATTACK
		_busy = true
		if debug_log:
			print("[EnemyBrain] %s action: ATTACK" % String(host.name))
		# Fire-and-forget: the coroutine runs alongside _physics_process and
		# clears _busy when it's done (or is aborted).
		_attack_combo(_action_token)
		return

	_action = Action.ORBIT_LEFT if randf() < 0.5 else Action.ORBIT_RIGHT
	if debug_log:
		print("[EnemyBrain] %s action: %s" % [String(host.name), get_action_name()])


## Run the current action for one frame. Returns true when it's finished.
func _run_action(delta: float) -> bool:
	_action_elapsed += delta
	if _action_elapsed >= action_timeout:
		return true  # safety net: never let an action wedge the brain.

	match _action:
		Action.ORBIT_LEFT:
			return _run_orbit(delta, 1.0)
		Action.ORBIT_RIGHT:
			return _run_orbit(delta, -1.0)
	return true


## Circle the player at `combat_range` while facing them, until we've covered
## `orbit_arc_units`. Steering is direct rather than navmesh-pathed (a path query
## per frame for a tight circle is both laggy and overkill), so we check the
## projected step ourselves and turn back at the mesh edge.
func _run_orbit(delta: float, dir: float) -> bool:
	if not is_instance_valid(_player):
		return true

	var to_player: Vector3 = _player.global_position - _body.global_position
	to_player.y = 0.0
	var dist: float = to_player.length()
	if dist < 0.001:
		return true

	var radial: Vector3 = to_player / dist
	var tangent := Vector3(-radial.z, 0.0, radial.x) * dir
	# Pull back toward the preferred radius as we circle.
	var offset: float = clampf(dist - combat_range, -1.0, 1.0)
	var velocity: Vector3 = tangent * orbit_speed + radial * offset * radial_correction

	# Would this step walk us off the navmesh? Enemy bodies have no collision
	# shape, so the mesh is the only thing keeping them in the level.
	if not _is_navigable(_body.global_position + velocity * delta):
		if _orbit_flipped:
			return true  # boxed in both ways — let the brain pick something else.
		_orbit_flipped = true
		_action = Action.ORBIT_RIGHT if _action == Action.ORBIT_LEFT else Action.ORBIT_LEFT
		return false

	_move.call("drive", velocity)
	_move.call("face_toward", _player.global_position)

	_orbit_travelled += orbit_speed * delta
	return _orbit_travelled >= orbit_arc_units


# --- Attack combo (coroutines) ---------------------------------------------
#
# The combo is a SEQUENCE — close in, swing, maybe pause, swing again, back off —
# so it's written with `await` and reads top-to-bottom. As per-frame state it would
# smear across a handful of sub-states and counters; here the design's two "lock it
# in" rules fall out for free, as plain local variables captured once and immune to
# whatever the player does afterwards.
#
# The catch with coroutines is cancellation. A running one cannot be killed from
# outside, and left alone it would happily resume mid-swing long after the enemy
# changed state or died. Hence the token: captured on entry, re-checked after every
# single await via _still_running(), and bumped by _abort_actions(). The rule is
# simply that no await is ever followed by anything other than that check.


func _attack_combo(token: int) -> void:
	# Commit for the whole combo: a brief dash-out by the player won't cancel it,
	# and the roaming twirl can't range-transition itself away.
	_committed = true
	# Rolled NOW, at the moment of the decision — not re-evaluated per swing.
	var swings: int = randi_range(min_swings, maxi(min_swings, max_swings))
	if debug_log:
		print("[EnemyBrain] %s combo: %d swing(s)" % [String(host.name), swings])

	if not await _approach(token):
		_finish_action(token)
		return

	# 'Front' locks to where the player is standing as the first swing starts.
	var locked_yaw: float = _yaw_toward(_player.global_position)

	for i in swings:
		# A beat before the third swing, so a triple reads differently to a double.
		if i == 2 and not await _wait(third_swing_delay, token):
			return
		if not await _swing(token, locked_yaw):
			return

	# The ZigzagTwirl only ever follows a swing combo — hence it living here,
	# after the loop, rather than as a top-level action the brain can pick.
	if randf() < zigzag_chance:
		if not await _zigzag_twirl(token):
			return

	await _retreat(token)
	_finish_action(token)


## Checked after every await: are we still the action that owns the body, and is
## there still a fight to be in?
func _still_running(token: int) -> bool:
	return token == _action_token \
		and _state == State.COMBAT \
		and is_instance_valid(_player) \
		and is_instance_valid(_body)


## Hand control back to the per-frame dispatcher — but only if we still own it.
## If the token moved on, something else has already taken over and touching
## shared state here would stomp it.
func _finish_action(token: int) -> void:
	if token != _action_token:
		return
	_busy = false
	_committed = false
	_action = Action.NONE
	_close_hitbox()


## Plant the feet for one frame. Needed rather than simply not steering: drive()
## is a one-frame latch, so a frame without it hands the body back to the wander
## pattern and the enemy strolls away mid-combo.
func _hold_still() -> void:
	_move.call("drive", Vector3.ZERO)
	if is_instance_valid(_player):
		_move.call("face_toward", _player.global_position)


func _wait(seconds: float, token: int) -> bool:
	var elapsed: float = 0.0
	while elapsed < seconds:
		if not _still_running(token):
			return false
		_hold_still()
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
	return _still_running(token)


## Close to `attack_range` through the navmesh. False = gave up (blocked, kited,
## or aborted), which cancels the combo before any swing happens.
func _approach(token: int) -> bool:
	var elapsed: float = 0.0
	while elapsed < approach_timeout:
		if not _still_running(token):
			return false
		if _flat_distance_to_player() <= attack_range:
			return true
		if _agent:
			_agent.target_position = _player.global_position
			var to_next: Vector3 = _agent.get_next_path_position() - _body.global_position
			to_next.y = 0.0
			if to_next.length_squared() > 0.0001:
				_move.call("drive", to_next.normalized() * approach_speed)
				_move.call("face_toward", _player.global_position)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
	return false


## One swing: turn onto the aim during the first half of the clip, open the
## AttackBox for the contact window, close it, done.
func _swing(token: int, base_yaw: float) -> bool:
	if _ap == null or not _ap.has_animation(attack_animation):
		return false

	# Front, front-left or front-right of the locked-in facing.
	var offsets: Array[float] = [0.0, -aim_spread_deg, aim_spread_deg]
	var target_yaw: float = base_yaw + deg_to_rad(offsets[randi() % offsets.size()])
	var start_yaw: float = _body.rotation.y

	_ap.speed_scale = attack_speed_scale
	_ap.play(attack_animation)

	var open: bool = false

	while _ap.is_playing() and _ap.current_animation == String(attack_animation):
		if not _still_running(token):
			return false

		# Progress is read off the ANIMATION's clock, not a wall timer, so
		# retiming the clip (attack_speed_scale) retimes the turn and the hit
		# window with it — they can never drift apart.
		var t: float = 0.0
		if _ap.current_animation_length > 0.0:
			t = _ap.current_animation_position / _ap.current_animation_length

		if t <= aim_lerp_end:
			_move.call("set_facing", lerp_angle(start_yaw, target_yaw, clampf(t / aim_lerp_end, 0.0, 1.0)))
		else:
			_move.call("set_facing", target_yaw)
		_move.call("drive", Vector3.ZERO)

		# The MeleeHitbox owns detection + damage + knockback while open; a cooldown
		# above the window length keeps a swing to one connection. Gentle knockback.
		var should_open: bool = t >= hit_window_start and t <= hit_window_end
		if should_open != open:
			open = should_open
			if open and _hitbox:
				_hitbox.call("open", attack_damage, swing_knockback_force,
					swing_knockback_up, swing_knockback_duration, 1.0)
			else:
				_close_hitbox()

		await get_tree().physics_frame

	_close_hitbox()
	_ap.speed_scale = 1.0
	return _still_running(token)


## ZigzagTwirl: freeze on the arms-out pose, then careen around the navmesh
## spinning, flinging the player on contact. NOT aimed at the player — the spin is
## blind, so a hit is about being in the wrong place, not being targeted.
func _zigzag_twirl(token: int) -> bool:
	if debug_log:
		print("[EnemyBrain] %s ZigzagTwirl" % String(host.name))

	# Freeze PracticeSwing on the arms-out frame. speed_scale = 0 (not pause) holds
	# the pose while still reading as "playing", so LocomotionAnimator keeps its
	# hands off (pause() would blank current_animation and let idle stomp it).
	if _ap and _ap.has_animation(attack_animation):
		_ap.play(attack_animation)
		_ap.seek(zigzag_pose_time, true)
		_ap.speed_scale = 0.0

	# A held windup on the pose before the spin — plant, don't drift.
	if not await _wait_still(zigzag_windup, token):
		_twirl_cleanup()
		return false

	_twirl_yaw = _body.rotation.y
	_twirl_dir = _random_heading()
	# The sweeping "hands": the MeleeHitbox flings whoever it catches, on its own
	# per-target cooldown, so a spin is a series of impacts not a per-frame barrage.
	if _hitbox:
		_hitbox.call("open", zigzag_damage, fling_force, fling_up, fling_duration, zigzag_hit_cooldown)

	var elapsed: float = 0.0
	var reroll: float = 0.0
	var dt: float = get_physics_process_delta_time()

	while elapsed < zigzag_duration:
		if not _still_running(token):
			_twirl_cleanup()
			return false

		# Spin the body directly (single writer stays MovementComponent).
		_twirl_yaw = wrapf(_twirl_yaw + deg_to_rad(zigzag_spin_speed_deg) * dt, -PI, PI)
		_move.call("set_facing", _twirl_yaw)

		# Zig: snap to a sharply different heading every so often.
		reroll -= dt
		if reroll <= 0.0:
			_twirl_dir = _strong_turn(_twirl_dir)
			reroll = zigzag_reroll_interval
		_zigzag_move(dt)

		elapsed += dt
		await get_tree().physics_frame

	_twirl_cleanup()
	return _still_running(token)


## Move along the current heading, bouncing off the navmesh edge like a pool ball.
func _zigzag_move(dt: float) -> void:
	var step: Vector3 = _twirl_dir * zigzag_speed * dt
	if _is_navigable(_body.global_position + step):
		_move.call("drive", _twirl_dir * zigzag_speed)
		return

	# Blocked: reflect the heading across the mesh edge's inward normal.
	var normal: Vector3 = _navmesh_normal(_body.global_position + step)
	if normal.length_squared() > 0.0001:
		_twirl_dir = _twirl_dir.bounce(normal).normalized()
	else:
		_twirl_dir = -_twirl_dir  # degenerate corner: just reverse.

	# Only commit the bounced heading if it actually frees us; otherwise hold this
	# frame so we can't tunnel off the mesh.
	if _is_navigable(_body.global_position + _twirl_dir * zigzag_speed * dt):
		_move.call("drive", _twirl_dir * zigzag_speed)
	else:
		_move.call("drive", Vector3.ZERO)


## Inward navmesh normal at a blocked point: the direction from it back onto the
## mesh. Works off open ledges too, where a raycast would find no wall to hit.
func _navmesh_normal(pos: Vector3) -> Vector3:
	if _agent == null:
		return Vector3.ZERO
	var map: RID = _agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.ZERO
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, pos)
	var n: Vector3 = closest - pos
	n.y = 0.0
	return n.normalized() if n.length_squared() > 0.0001 else Vector3.ZERO


func _random_heading() -> Vector3:
	var a: float = randf() * TAU
	return Vector3(sin(a), 0.0, cos(a))


## A heading at least `zigzag_min_turn_deg` off the current one, either side — the
## sharp changes are what make the path read as chaotic rather than a smooth curve.
func _strong_turn(current: Vector3) -> Vector3:
	var base: float = atan2(current.x, current.z)
	var min_turn: float = deg_to_rad(zigzag_min_turn_deg)
	var span: float = TAU - 2.0 * min_turn
	var offset: float = min_turn + randf() * maxf(span, 0.0)
	if randf() < 0.5:
		offset = -offset
	var a: float = base + offset
	return Vector3(sin(a), 0.0, cos(a))


## Fling the player if the (spinning) AttackBox is over them. Distinct from a swing
## hit: bigger knockback, away from the enemy, damage optional.
## Like _wait, but holds facing where it is (no player aim) — for the windup.
func _wait_still(seconds: float, token: int) -> bool:
	var elapsed: float = 0.0
	while elapsed < seconds:
		if not _still_running(token):
			return false
		_move.call("drive", Vector3.ZERO)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
	return _still_running(token)


func _twirl_cleanup() -> void:
	_close_hitbox()
	if _ap:
		_ap.speed_scale = 1.0
		if _ap.current_animation == String(attack_animation):
			_ap.stop()


## Back off to orbit range, straight or strafing. If the retreat would leave the
## navmesh, mirror the strafe once and then give up — bailing is a legitimate
## resolution, since the brain simply picks again and an orbit re-establishes
## spacing from wherever it is.
func _retreat(token: int) -> void:
	var strafe: bool = randf() < strafe_retreat_chance
	var dir: float = 1.0 if randf() < 0.5 else -1.0
	var flipped: bool = false
	var elapsed: float = 0.0

	while elapsed < retreat_timeout:
		if not _still_running(token):
			return

		var to_player: Vector3 = _player.global_position - _body.global_position
		to_player.y = 0.0
		var dist: float = to_player.length()
		if dist >= combat_range or dist < 0.001:
			return  # spacing restored.

		var radial: Vector3 = to_player / dist
		var velocity: Vector3 = -radial * retreat_speed
		if strafe:
			velocity += Vector3(-radial.z, 0.0, radial.x) * dir * retreat_speed * 0.8

		if not _is_navigable(_body.global_position + velocity * get_physics_process_delta_time()):
			if flipped:
				return
			flipped = true
			dir = -dir
			strafe = true
			await get_tree().physics_frame
			continue

		_move.call("drive", velocity)
		_move.call("face_toward", _player.global_position)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame


func _close_hitbox() -> void:
	if _hitbox:
		_hitbox.call("close")


## Yaw that points our -Z at `point`.
func _yaw_toward(point: Vector3) -> float:
	var to: Vector3 = point - _body.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return _body.rotation.y
	return atan2(-to.x, -to.z)


## Is `pos` on (or within tolerance of) the navigation mesh?
func _is_navigable(pos: Vector3) -> bool:
	if _agent == null:
		return true
	var map: RID = _agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return true  # map not ready; don't block movement on it.
	return NavigationServer3D.map_get_closest_point(map, pos).distance_to(pos) <= navmesh_tolerance
