extends Node3D
class_name EnemyAction

## One enemy behaviour, written as a coroutine.
##
## An action is a NODE you drop under an enemy's `Actions` container. The
## EnemyBrain gathers them, picks one, and awaits its `run()`. Adding a behaviour
## to an enemy is therefore "write one script, drop one node" — no brain edits, no
## enum to extend — and removing one is deleting a node. Tuning is @export knobs on
## that node, so it all happens in the Inspector while the game runs.
##
## WHY A COROUTINE. Most interesting attacks are SEQUENCES — close in, swing, pause,
## swing again, back off. As per-frame state that smears across a pile of sub-states
## and counters; as `await` it reads top-to-bottom, and "lock this in at the moment
## of the decision" falls out for free as a plain local variable, captured once and
## immune to whatever the player does afterwards.
##
## WHY Node3D RATHER THAN Node. An action often needs a point in space — a projectile
## spawn, a slam epicentre, a marker for where to land. As a Node3D it can own those
## as children and you can drag them in the viewport. The `Actions` container is a
## child of the enemy body, so those markers are relative to the enemy and rotate
## with it.
##
## THE CANCELLATION RULE. A running coroutine cannot be killed from outside, and left
## alone it would happily resume mid-swing long after the enemy changed state or
## died. So every action is handed a `token` and the rule is absolute:
##
##     NO `await` IS EVER FOLLOWED BY ANYTHING OTHER THAN `still_running(token)`.
##
## The brain bumps the token to cancel; the action notices at its next await and
## returns false. Follow that one rule and cancellation is handled.
##
## WRITING ONE. Override `run()`, loop on `await get_tree().physics_frame`, steer
## through the helpers below (never touch the body directly — MovementComponent is
## the single writer of velocity and rotation), and return when done:
##
##     func run(token: int) -> bool:
##         var elapsed: float = 0.0
##         while elapsed < duration:
##             if not still_running(token):
##                 return false
##             drive(some_velocity)
##             elapsed += get_physics_process_delta_time()
##             await get_tree().physics_frame
##         return still_running(token)
##
## NESTING. An action may own child actions and await them itself (see
## AttackComboAction). A child's POSITION IN THE TREE IS ITS RULE: ZigzagTwirl sits
## under AttackCombo precisely because it may only ever follow a swing. Nested
## children are gated by `chance` rather than `weight`, since the parent — not the
## brain — decides whether they run.

## Relative odds of being picked, among the eligible top-level actions. Ignored for
## a nested action, whose parent decides with `chance` instead.
@export var weight: float = 1.0
## Probability of running when awaited as a nested follow-up. Ignored at top level.
@export_range(0.0, 1.0, 0.05) var chance: float = 1.0
## Uncheck to disable without deleting the node — the fastest way to A/B a
## behaviour while playing.
@export var enabled: bool = true

## Line-of-sight condition for an action to be picked.
##   ANY       — don't care.
##   REQUIRED  — only with a clear view of the player (a direct shot, a charge).
##   FORBIDDEN — only WITHOUT a clear view. This is the lob-over-a-wall case: the
##               creature knows where you are because you are in its region, but
##               cannot see you, so it arcs something over instead of firing flat.
enum Sight { ANY, REQUIRED, FORBIDDEN }

@export_group("Range")
## Nearest distance to the player at which this may be picked.
@export var min_range: float = 0.0
## Furthest distance at which this may be picked. 0 = no limit.
@export var max_range: float = 0.0

@export_group("Conditions")
## A TriggerRegion the player must be inside for this action to be picked. Empty =
## no region condition.
##
## This is how a bombardment zone is expressed: the dangerous SPACE is authored in
## the level, independent of where the creature stands, so the two need not even be
## in sight of each other. Referring to a region here also makes the creature alert
## while that region is occupied — see EnemyBrain.
@export var required_region: NodePath
## Whether this action needs, forbids, or ignores line of sight to the player.
@export var los_requirement: Sight = Sight.ANY

@export_group("Rules")
## Seconds this action is off the table after it runs.
@export var cooldown: float = 0.0
## While true the brain suppresses ALL state transitions, including losing sight of
## the player. For an action already bounded by its own timeouts that owns the body
## for a while — a blind twirl must not cancel itself the instant it flings the
## player out of view.
@export var committed: bool = false
## Require the coordinator's attack slot before running, so a group doesn't all
## swing at once. Solo enemies (no coordinator) always get it.
@export var requires_attack_slot: bool = false
## Hard ceiling in seconds; the brain aborts past this so nothing can wedge it.
## 0 = no ceiling (only for actions whose own loops are all bounded). Applies to
## top-level actions — a nested follow-up runs inside its parent's ceiling.
@export var timeout: float = 8.0

# --- Runtime context, injected once by the brain via setup() ------------------

var brain: Node = null
var body: CharacterBody3D = null
var move: Node = null  # MovementComponent (duck-typed)
var agent: NavigationAgent3D = null
var hitbox: Node = null  # MeleeHitbox (duck-typed)
var anim: AnimationPlayer = null

var _cooldown_left: float = 0.0


## Called once by the brain with the shared context, and passed down to nested
## children so a follow-up needs no wiring of its own.
func setup(context: Dictionary) -> void:
	brain = context.get("brain") as Node
	body = context.get("body") as CharacterBody3D
	move = context.get("move") as Node
	agent = context.get("agent") as NavigationAgent3D
	hitbox = context.get("hitbox") as Node
	anim = context.get("anim") as AnimationPlayer
	for child in get_children():
		if child is EnemyAction:
			(child as EnemyAction).setup(context)
	_setup()


## Override for one-time wiring that needs the context.
func _setup() -> void:
	pass


## Override with the behaviour. Return true if it ran to completion, false if it
## bailed (cancelled, blocked, or gave up).
##
## The `await` below is load-bearing despite doing nothing useful. GDScript decides
## whether a function is a coroutine STATICALLY, per function — so if this base
## version contained no await, then every `await action.run(token)` made through an
## EnemyAction-typed reference would warn "the expression isn't a coroutine",
## even though the subclass actually running is one. It works either way at
## runtime, but the warning would be permanent noise on the system's main seam.
## Burning a frame is also the right behaviour for an unimplemented action: it
## keeps the brain's dispatch loop from spinning on it within a single frame.
func run(_token: int) -> bool:
	push_warning("[EnemyAction] %s does not override run()." % String(name))
	await get_tree().physics_frame
	return true


## Override to release anything the action was holding when it is cancelled
## mid-flight. The brain calls this on every action, so it must be safe to call on
## one that was not running.
func on_abort() -> void:
	close_hitbox()
	if anim:
		# An action may park speed_scale at 0 to freeze a pose; leaving it there
		# would make every later animation play frozen.
		anim.speed_scale = 1.0


## Can the brain pick this right now? Override to add conditions (the host's HP, a
## resource cost); call super() to keep the standard ones.
func is_eligible(distance_to_player: float) -> bool:
	if not enabled or _cooldown_left > 0.0:
		return false
	if distance_to_player < min_range:
		return false
	if max_range > 0.0 and distance_to_player > max_range:
		return false
	if not _region_satisfied():
		return false
	if not _sight_satisfied():
		return false
	return true


func _region_satisfied() -> bool:
	var region: Node = get_region()
	return region == null or bool(region.call("is_occupied"))


func _sight_satisfied() -> bool:
	if los_requirement == Sight.ANY:
		return true
	var clear: bool = brain != null and bool(brain.call("has_line_of_sight"))
	return clear if los_requirement == Sight.REQUIRED else not clear


## The TriggerRegion this action is gated on, or null. Resolved against the SCENE,
## not this node, because a region is level geometry that lives outside the
## creature — often nowhere near it.
func get_region() -> Node:
	if required_region == NodePath():
		return null
	return get_node_or_null(required_region)


func is_on_cooldown() -> bool:
	return _cooldown_left > 0.0


## Ticked by the brain. Uses the physics delta rather than wall-clock time so
## cooldowns respect `time_scale` and pausing.
func tick_cooldown(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)


func start_cooldown() -> void:
	_cooldown_left = cooldown


# --- Cancellation ------------------------------------------------------------

## The check that must follow every single await. False = we no longer own the
## body; return immediately without touching shared state.
##
## The is_inside_tree() guard is what makes this survive a LEVEL RESTART. A reload
## removes nodes from the tree before freeing them, so for a window of one frame
## is_instance_valid() still says yes while global_position and get_tree() are
## already unusable — and a coroutine suspended across that window would resume and
## dereference them. Death by an enemy's own attack is exactly when that window is
## most likely to be open, since the restart happens mid-action.
func still_running(token: int) -> bool:
	if not is_inside_tree():
		return false
	if not is_instance_valid(brain):
		return false
	return bool(brain.call("is_action_current", token))


# --- Steering ----------------------------------------------------------------
#
# All movement routes through MovementComponent so it stays the single writer of
# velocity and rotation — the invariant that lets wander patterns, knockback and AI
# steering coexist instead of fighting each other. Each is a ONE-FRAME latch: call
# it every frame you want control, stop calling to hand the body back.

func drive(velocity: Vector3) -> void:
	if move:
		move.call("drive", velocity)


func face_toward(point: Vector3) -> void:
	if move:
		move.call("face_toward", point)


## Exact yaw, no smoothing — for when the action owns the interpolation curve.
func set_facing(yaw: float) -> void:
	if move:
		move.call("set_facing", yaw)


## Plant the feet for one frame, still facing the player. Needed rather than simply
## not steering: drive() is a one-frame latch, so a frame without it hands the body
## back to the wander pattern and the enemy strolls away mid-action.
func hold_still() -> void:
	drive(Vector3.ZERO)
	var target: Node3D = get_player()
	if target:
		face_toward(target.global_position)


## Like hold_still() but leaves facing alone, for a windup that shouldn't track.
func hold_facing() -> void:
	drive(Vector3.ZERO)


# --- Waits -------------------------------------------------------------------

## Hold position for `seconds`, facing the player. False = cancelled.
func wait(seconds: float, token: int) -> bool:
	var elapsed: float = 0.0
	while elapsed < seconds:
		if not still_running(token):
			return false
		hold_still()
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
	return still_running(token)


## Hold position for `seconds` without tracking the player.
func wait_still(seconds: float, token: int) -> bool:
	var elapsed: float = 0.0
	while elapsed < seconds:
		if not still_running(token):
			return false
		hold_facing()
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
	return still_running(token)


# --- Queries -----------------------------------------------------------------

## The player, or null if there isn't a usable one right now.
##
## "Usable" includes being INSIDE THE TREE, not merely un-freed: during a level
## reload the player is detached a frame before being freed, and reading
## global_position off a detached Node3D errors. Filtering here means every action
## that aims at the player is protected by one check rather than each remembering.
func get_player() -> Node3D:
	if not is_instance_valid(brain):
		return null
	var target: Node3D = brain.call("get_player") as Node3D
	if not is_instance_valid(target) or not target.is_inside_tree():
		return null
	return target


## Flattened — height shouldn't decide reach.
func flat_distance_to_player() -> float:
	var target: Node3D = get_player()
	if not is_instance_valid(target) or body == null:
		return INF
	var to: Vector3 = target.global_position - body.global_position
	to.y = 0.0
	return to.length()


## The brain's preferred combat distance. Actions that want to hold, restore or
## orbit at "the usual spacing" read it from here rather than each carrying their
## own copy that could drift out of agreement.
func combat_range() -> float:
	if brain == null:
		return 6.0
	return float(brain.get("combat_range"))


## Yaw that points the body's -Z at `point` (the project-wide facing convention).
func yaw_toward(point: Vector3) -> float:
	if body == null:
		return 0.0
	var to: Vector3 = point - body.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return body.rotation.y
	return atan2(-to.x, -to.z)


## Is `pos` on (or within tolerance of) the navigation mesh? Enemy bodies carry no
## collision shape, so the navmesh is the only thing keeping them in the level —
## steer with this rather than assuming open ground.
func is_navigable(pos: Vector3) -> bool:
	if agent == null:
		return true
	var map: RID = agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return true  # map not ready; don't block movement on it.
	var tolerance: float = 1.0
	if brain:
		tolerance = float(brain.get("navmesh_tolerance"))
	return NavigationServer3D.map_get_closest_point(map, pos).distance_to(pos) <= tolerance


## Inward navmesh normal at a blocked point: the direction from it back onto the
## mesh. Works off open ledges too, where a raycast would find no wall to hit.
func navmesh_normal(pos: Vector3) -> Vector3:
	if agent == null:
		return Vector3.ZERO
	var map: RID = agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.ZERO
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, pos)
	var n: Vector3 = closest - pos
	n.y = 0.0
	return n.normalized() if n.length_squared() > 0.0001 else Vector3.ZERO


func random_heading() -> Vector3:
	var a: float = randf() * TAU
	return Vector3(sin(a), 0.0, cos(a))


## A heading at least `min_turn_deg` off `current`, either side. The sharp changes
## are what make a path read as chaotic rather than a smooth curve.
func strong_turn(current: Vector3, min_turn_deg: float) -> Vector3:
	var base: float = atan2(current.x, current.z)
	var min_turn: float = deg_to_rad(min_turn_deg)
	var span: float = TAU - 2.0 * min_turn
	var offset: float = min_turn + randf() * maxf(span, 0.0)
	if randf() < 0.5:
		offset = -offset
	var a: float = base + offset
	return Vector3(sin(a), 0.0, cos(a))


# --- Strike windows ----------------------------------------------------------
#
# Hit detection lives entirely in MeleeHitbox: open it at a window's start and close
# it at the end, and it owns detection, per-target cooldown, damage and knockback.
# What a connection DOES is passed per-open, so one hitbox serves both a light swing
# and a big fling.

func open_hitbox(damage: int, knockback: float = 0.0, knockback_up: float = 0.0,
		knockback_duration: float = 0.0, hit_cooldown: float = 0.5) -> void:
	if hitbox:
		hitbox.call("open", damage, knockback, knockback_up, knockback_duration, hit_cooldown)


func close_hitbox() -> void:
	if hitbox:
		hitbox.call("close")
