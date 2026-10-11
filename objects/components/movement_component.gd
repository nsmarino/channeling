extends Component
class_name MovementComponent

## Drives the owning CharacterBody3D enemy using a pluggable MovementPattern
## resource. The host enables/disables it via the Component set_active() lifecycle.

## The movement behavior. Swap in the Inspector to change how the enemy flies.
@export var pattern: MovementPattern
## Optional explicit body to move; defaults to the parent CharacterBody3D.
@export var body_path: NodePath
## Rotate the body to face its travel direction.
@export var face_travel_direction: bool = true
## Rotate the body to look at the player instead of its travel direction. Takes
## precedence over face_travel_direction — use it for stationary sentries/turrets.
@export var face_player: bool = false
## How fast the body turns to face travel (higher = snappier).
@export var turn_lerp: float = 6.0
## Constant Y spin in degrees/sec. 0 = off.
##
## Lives here rather than in an action because this component is the single writer
## of rotation, and because an idle spin is a permanent property of a creature, not
## something it decides to do — as an action it would occupy the one action slot
## forever and starve everything else. An explicit aim (drive/face_toward/
## set_facing) still wins for the frames it is requested.
@export var spin_speed_deg: float = 0.0
## How fast an external knockback impulse bleeds off (units/sec²).
@export var knockback_damping: float = 14.0
## Keep the body at the navmesh's height as it moves, so it walks up ramps and
## stairs. Enemy bodies have no collision shape and every move here is
## horizontal, so without this a creature stays at the height it was placed and
## burrows into any slope. Off for a creature that should hold its height (one
## that flies, or hovers over a pit).
@export var follow_navmesh_height: bool = true
## How quickly the height catches up with the navmesh (higher = tighter).
@export var height_follow_speed: float = 12.0

var _body: CharacterBody3D = null
var _player: Node3D = null
var _time_active: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO
var _knockback_timer: float = 0.0
# One-frame latches set by an AI brain via drive() / face_toward(). See drive().
var _drive_velocity: Vector3 = Vector3.ZERO
var _drive_active: bool = false
var _face_point: Vector3 = Vector3.ZERO
var _face_active: bool = false
var _facing_yaw: float = 0.0
var _facing_snap: bool = false
var _agent: NavigationAgent3D = null
# Height of the body above the navmesh where it was placed (the model's origin
# needn't sit on the navmesh surface). Measured once the nav map is ready.
var _nav_height_offset: float = 0.0
var _nav_offset_known: bool = false


func _setup() -> void:
	if body_path != NodePath() and has_node(body_path):
		_body = get_node(body_path) as CharacterBody3D
	else:
		_body = host as CharacterBody3D
	if _body:
		for child: Node in _body.get_children():
			if child is NavigationAgent3D:
				_agent = child as NavigationAgent3D
				break
	set_physics_process(false)


func setup(player: Node3D) -> void:
	_player = player


func on_activate() -> void:
	set_physics_process(true)
	_time_active = 0.0
	# Re-measured from wherever the body is when it wakes (a cutscene may have
	# walked it somewhere first).
	_nav_offset_known = false


func on_deactivate() -> void:
	set_physics_process(false)
	if _body:
		_body.velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not is_active or not _body:
		return
	_move(delta)
	if follow_navmesh_height:
		_follow_navmesh_height(delta)


func _move(delta: float) -> void:
	_time_active += delta

	# A knockback overrides the pattern while it lasts, then hands back cleanly.
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		_body.velocity = _knockback_velocity
		_body.move_and_slide()
		_knockback_velocity = _knockback_velocity.move_toward(
			Vector3.ZERO, knockback_damping * delta
		)
		if _knockback_timer <= 0.0:
			_snap_to_navmesh()
		return

	# An AI brain steering us this frame outranks the pattern (but not knockback).
	if _drive_active:
		_drive_active = false
		_body.velocity = _drive_velocity
		_body.move_and_slide()
		_update_facing(delta)
		return

	# A pattern is optional: without one the body stays put (a stationary turret
	# still runs, so it can keep facing the player).
	if pattern:
		_body.velocity = pattern.compute_velocity(_body, _player, _time_active, delta)
		_body.move_and_slide()
	else:
		_body.velocity = Vector3.ZERO

	_update_facing(delta)


## Steer the body this frame from an AI brain, overriding the MovementPattern.
##
## Deliberately a ONE-FRAME latch: the brain calls this every frame it wants
## control and simply stops calling to hand the body back to its pattern — no
## release call to forget. Keeps this component the single writer of velocity,
## move_and_slide and facing, which is the invariant that lets knockback, patterns
## and AI steering coexist instead of fighting (see apply_knockback).
##
## Facing follows the driven velocity unless face_toward() is also called.
func drive(velocity: Vector3) -> void:
	if not is_active or _body == null:
		return
	_drive_velocity = velocity
	_drive_active = true


## Aim the body at a world point for this frame instead of along its travel.
## Pairs with drive() for strafing/orbiting, where you move sideways but keep
## looking at the target.
func face_toward(point: Vector3) -> void:
	if not is_active or _body == null:
		return
	_face_point = point
	_face_active = true


## Set the body's yaw outright this frame, bypassing `turn_lerp`. For cases where
## the caller owns the interpolation curve — e.g. an attack that has to finish
## aiming exactly halfway through its animation. Still routed through here so this
## component remains the only thing writing rotation.
func set_facing(yaw: float) -> void:
	if not is_active or _body == null:
		return
	_facing_yaw = yaw
	_facing_snap = true


## Shove the body with an external impulse (a PowerSlam landing, say), overriding
## the movement pattern for `duration`.
##
## Knockback has to run THROUGH this component: the pattern reassigns
## `_body.velocity` every single frame, so a velocity written directly onto the
## body from outside would be overwritten before it moved anywhere.
##
## Safe for navmesh-driven movement — see _snap_to_navmesh().
func apply_knockback(impulse: Vector3, duration: float) -> void:
	if not is_active or _body == null:
		return
	_knockback_velocity = impulse
	_knockback_timer = maxf(_knockback_timer, duration)


## Pull the body back onto the navigation map once a shove ends.
##
## This is what keeps knockback from breaking a wanderer. Enemy bodies carry no
## CollisionShape3D (only their HitBox area does), so nothing stops a shove from
## pushing one through a wall or off a ledge, where it would be stranded off-mesh
## and unable to path. Snapping to the closest point on the map guarantees it
## always resumes from somewhere navigable; the NavigationAgent3D keeps its
## existing target and simply re-paths from the corrected position.
func _snap_to_navmesh() -> void:
	var map: RID = _nav_map()
	if not map.is_valid():
		return  # not nav-driven, or the map isn't ready; leave it where it landed.
	var offset: float = _nav_height_offset if _ensure_nav_offset(map) else 0.0
	_body.global_position = NavigationServer3D.map_get_closest_point(map, _body.global_position) \
			+ Vector3.UP * offset


## Ease the body's height toward the navmesh surface under it (plus its placed
## offset). Horizontal motion is left alone — this only answers "how high is the
## ground here", which is all a shapeless body moving sideways is missing.
func _follow_navmesh_height(delta: float) -> void:
	var map: RID = _nav_map()
	if not map.is_valid() or not _ensure_nav_offset(map):
		return
	var surface: Vector3 = NavigationServer3D.map_get_closest_point(map, _body.global_position)
	var target_y: float = surface.y + _nav_height_offset
	var weight: float = 1.0 - exp(-height_follow_speed * delta)
	_body.global_position.y = lerpf(_body.global_position.y, target_y, weight)


## Measure the placed offset once, and only against a real answer: for the first
## frames after a location loads the map reports "synced" before its region has
## registered, and every closest-point query returns the world origin. A surface
## point that isn't horizontally beneath the body is that bogus answer (or the
## body is genuinely off the mesh) — wait for a real one. Returns whether known.
func _ensure_nav_offset(map: RID) -> bool:
	if _nav_offset_known:
		return true
	var pos: Vector3 = _body.global_position
	var surface: Vector3 = NavigationServer3D.map_get_closest_point(map, pos)
	if Vector2(surface.x - pos.x, surface.z - pos.z).length() > 1.0:
		return false
	_nav_height_offset = pos.y - surface.y
	_nav_offset_known = true
	return true


## The navigation map, or an invalid RID when there's no agent or the map hasn't
## synced yet (until then every query answers the world origin).
func _nav_map() -> RID:
	if _agent == null:
		return RID()
	var map: RID = _agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return RID()
	return map


## Turn the body toward the player (face_player) or along its travel direction.
##
## Facing follows Godot's standard convention: the body's **-Z** is its forward,
## so `atan2(-x, -z)` (matching player.gd) puts -Z on the target. Muzzles and
## other "in front of me" markers therefore sit at negative Z.
func _update_facing(delta: float) -> void:
	# An exact yaw wins outright and skips smoothing entirely.
	if _facing_snap:
		_facing_snap = false
		_face_active = false
		_body.rotation.y = _facing_yaw
		return

	# Consume the brain's one-frame aim override, if any.
	var forced := _face_active
	var forced_point := _face_point
	_face_active = false

	var target_yaw: float
	if forced:
		var to_point: Vector3 = forced_point - _body.global_position
		if absf(to_point.x) < 0.001 and absf(to_point.z) < 0.001:
			return
		target_yaw = atan2(-to_point.x, -to_point.z)
	elif face_player and _player:
		var to_player: Vector3 = _player.global_position - _body.global_position
		if absf(to_player.x) < 0.001 and absf(to_player.z) < 0.001:
			return
		target_yaw = atan2(-to_player.x, -to_player.z)
	elif face_travel_direction:
		var flat: Vector3 = Vector3(_body.velocity.x, 0.0, _body.velocity.z)
		if flat.length_squared() <= 0.04:
			_apply_spin(delta)
			return
		target_yaw = atan2(-flat.x, -flat.z)
	else:
		_apply_spin(delta)
		return
	_body.rotation.y = lerp_angle(_body.rotation.y, target_yaw, clampf(turn_lerp * delta, 0.0, 1.0))


## Constant idle spin, applied only on frames where nothing else claimed facing.
func _apply_spin(delta: float) -> void:
	if is_zero_approx(spin_speed_deg):
		return
	_body.rotation.y = wrapf(
		_body.rotation.y + deg_to_rad(spin_speed_deg) * delta, -PI, PI
	)
