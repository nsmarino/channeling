extends CharacterBody3D

## Standard third-person character controller with a SpringArm3D camera rig, plus
## a Dark Souls-style lock-on mode driven by a sibling LockOnComponent.
##
## Free (unlocked) movement — works with mouse/keyboard and gamepad:
##   - Look: mouse motion or the right stick (look_*). Orbits the CameraPivot —
##     yaw around Y, clamped pitch — the SpringArm3D pulls the camera in on walls.
##   - Move: WASD/IJKL or the left stick (move_*), relative to the camera facing.
##     The visible Model turns to face the direction of travel.
##
## Locked movement (LockOnComponent reports a target):
##   - Camera auto-frames the target (free look is suppressed) and the FOV punches
##     in. Forward/back approaches/retreats along the player→target line and
##     left/right strafes tangentially, so you orbit the target; the Model faces
##     the target the whole time.
##
## The body itself never rotates — look lives on the pivot, facing on the Model.
## The capsule renders slightly left of center via the camera's `h_offset`.
##
## Registers into the "player" group (GameManager finds the navigator and the HUD
## reads `hp` through it). Death/fall/Restart route through GameManager.

@export_category("Movement")
## Target horizontal speed (world units/sec).
@export var move_speed: float = 6.0
## How quickly velocity reaches the target on the ground (units/sec²-ish).
@export var ground_acceleration: float = 60.0
## Same, but while airborne (lower = floatier air control).
@export var air_acceleration: float = 12.0
## Upward velocity applied on jump.
@export var jump_velocity: float = 5.0
## Downward acceleration. 0 = use the project's default gravity.
@export var gravity_override: float = 0.0
## How quickly the model swings to face its target direction (radians/sec).
@export var turn_speed: float = 12.0
## How fast an external knockback impulse bleeds off (units/sec²). Lower = you
## slide further after a bump.
@export var knockback_damping: float = 18.0

@export_category("Look")
## Mouse look sensitivity, radians per pixel of motion.
@export var mouse_sensitivity: float = 0.0025
## Gamepad look speed, radians/sec at full stick deflection.
@export var gamepad_look_speed: float = 3.0
## Camera pitch clamp, in degrees.
@export var pitch_min_deg: float = -60.0
@export var pitch_max_deg: float = 70.0

@export_category("Lock-On")
## LockOnComponent that owns targeting. Referenced duck-typed (no class_name).
@export var lock_on_path: NodePath = ^"LockOnComponent"
## Frustum offset (world units) so the capsule sits left of center in free look.
## Higher = further left. Tunable live in the Inspector.
@export var camera_h_offset: float = 0.35
## Frustum offset while locked — a touch more, to keep the target readable right.
@export var locked_h_offset: float = 0.5
## Camera FOV while locked (tighter than the base FOV for a punch-in).
@export var locked_fov: float = 50.0
## How fast the camera swings to frame the target (higher = snappier).
@export var frame_lerp_speed: float = 8.0
## How fast FOV / h_offset ease between free and locked.
@export var blend_speed: float = 6.0

@export_category("Weapon")
## Weapon instanced under the WeaponSocket on ready and fired with `attack`
## (semi/auto follows the weapon's own data). Swap it here to change loadout.
@export var weapon_scene: PackedScene = preload("res://objects/weapons/player/PlayerRifle.tscn")
## Socket the weapon is parented to. Under Model so it swings with the body's
## facing (which, when locked, points at the target).
@export var weapon_socket_path: NodePath = ^"Model/WeaponSocket"
## Unlocked aim converges shots on the camera's center ray at this distance (m).
@export var aim_distance: float = 50.0

@export_category("Health")
@export var max_hp: int = 100

@export_category("References")
## Pivot orbited for yaw/pitch. Holds the SpringArm3D + Camera3D.
@export var camera_pivot_path: NodePath = ^"CameraPivot"
## Visible body that turns to face its target direction.
@export var model_path: NodePath = ^"Model"
## The Camera3D on the spring arm (for FOV / h_offset).
@export var camera_path: NodePath = ^"CameraPivot/SpringArm3D/Camera3D"

var hp: int = 0

## Running total of collected PowerDrops.
var power: int = 0

## Cleared while a cutscene runs (Events.cutscene_started/finished). Input is
## ignored and the body coasts to a stop; the camera is handed back on finish.
var _control_enabled: bool = true

## Seconds remaining in which an external impulse (bump combat) owns horizontal
## movement instead of input. See apply_knockback().
var _knockback_timer: float = 0.0

var _pivot: Node3D = null
var _model: Node3D = null
var _camera: Camera3D = null
var _lock_on: Node = null
var _gravity: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _base_fov: float = 65.0
var _weapon: Node = null
var _weapon_socket: Node3D = null
var _muzzle: Node3D = null


func _ready() -> void:
	add_to_group("player")
	_pivot = get_node_or_null(camera_pivot_path) as Node3D
	_model = get_node_or_null(model_path) as Node3D
	_camera = get_node_or_null(camera_path) as Camera3D
	_lock_on = get_node_or_null(lock_on_path)
	_gravity = gravity_override if gravity_override > 0.0 \
		else float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	hp = max_hp
	if _pivot:
		_yaw = _pivot.rotation.y
		_pitch = _pivot.rotation.x
	if _camera:
		_base_fov = _camera.fov
		_camera.h_offset = camera_h_offset
	_weapon_socket = get_node_or_null(weapon_socket_path) as Node3D
	_spawn_weapon()
	Events.cutscene_started.connect(_on_cutscene_started)
	Events.cutscene_finished.connect(_on_cutscene_finished)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _control_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_apply_look(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity)
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE \
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not _control_enabled:
		_process_frozen(delta)
		return
	_process_gamepad_look(delta)
	_process_lock_camera(delta)
	_process_movement(delta)
	_process_weapon()


## While a cutscene owns control: no input, but keep the body honest — apply
## gravity and bleed off any horizontal momentum so it settles in place.
func _process_frozen(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, ground_acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, ground_acceleration * delta)
	move_and_slide()


func _on_cutscene_started() -> void:
	_control_enabled = false


## Control returns to the player: reclaim the camera the cutscene borrowed.
func _on_cutscene_finished() -> void:
	_control_enabled = true
	if _camera:
		_camera.current = true


## Orbit the camera pivot: yaw around Y, pitch tilts the arm (clamped). Suppressed
## while locked — the auto-frame owns the pivot then (the LockOnComponent consumes
## the same look input for target switching).
func _apply_look(yaw_delta: float, pitch_delta: float) -> void:
	if _is_locked():
		return
	_yaw = wrapf(_yaw + yaw_delta, -PI, PI)
	_pitch = clampf(_pitch + pitch_delta, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	if _pivot:
		_pivot.rotation.y = _yaw
		_pivot.rotation.x = _pitch


func _process_gamepad_look(delta: float) -> void:
	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look != Vector2.ZERO:
		_apply_look(-look.x * gamepad_look_speed * delta, -look.y * gamepad_look_speed * delta)


## Blend FOV / h_offset toward the current mode every frame, and — when locked —
## swing the pivot so its forward (-Z) points at the target, framing it.
func _process_lock_camera(delta: float) -> void:
	var locked := _is_locked()
	var target: Node3D = _lock_target() if locked else null

	if _camera:
		var blend := clampf(blend_speed * delta, 0.0, 1.0)
		_camera.fov = lerpf(_camera.fov, locked_fov if locked else _base_fov, blend)
		_camera.h_offset = lerpf(_camera.h_offset, locked_h_offset if locked else camera_h_offset, blend)

	if not locked or target == null or _pivot == null:
		return

	var to := target.global_position - _pivot.global_position
	var horiz := Vector2(to.x, to.z).length()
	if horiz < 0.01:
		return
	var desired_yaw := atan2(-to.x, -to.z)
	var desired_pitch := clampf(atan2(to.y, horiz), deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	var t := clampf(frame_lerp_speed * delta, 0.0, 1.0)
	_yaw = lerp_angle(_yaw, desired_yaw, t)
	_pitch = lerpf(_pitch, desired_pitch, t)
	_pivot.rotation.y = _yaw
	_pivot.rotation.x = _pitch


func _process_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed(&"jump"):
		velocity.y = jump_velocity

	# A knockback impulse owns horizontal velocity for a moment — skip input
	# steering and let it bleed off, so the bounce actually reads.
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		var damp := knockback_damping * delta
		velocity.x = move_toward(velocity.x, 0.0, damp)
		velocity.z = move_toward(velocity.z, 0.0, damp)
		move_and_slide()
		return

	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var target: Node3D = _lock_target() if _is_locked() else null
	var direction := _orbit_direction(input, target) if target != null \
		else _camera_relative_direction(input)

	var target_vel := direction * move_speed
	var accel := ground_acceleration if is_on_floor() else air_acceleration
	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)

	if target != null:
		_face_point(target.global_position, delta)
	elif direction.length_squared() > 0.001:
		_face_point(global_position + direction, delta)

	move_and_slide()


## Map stick/WASD input onto the camera's yaw so "forward" is where you look.
## Only the yaw matters here — movement stays on the ground plane.
func _camera_relative_direction(input: Vector2) -> Vector3:
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))  # pivot -Z, flattened
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))     # pivot +X, flattened
	return (right * input.x + forward * -input.y).normalized()


## Target-relative orbit: forward/back (input.y) runs along the player→target
## line; left/right (input.x) strafes tangentially, circling the target.
func _orbit_direction(input: Vector2, target: Node3D) -> Vector3:
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return Vector3.ZERO
	var radial := to.normalized()                     # toward the target
	var tangent := Vector3(-radial.z, 0.0, radial.x)  # 90° on the ground plane
	var dir := radial * -input.y + tangent * input.x
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO


## Smoothly swing the visible model to face a world point (movement dir or target).
func _face_point(point: Vector3, delta: float) -> void:
	if not _model:
		return
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-to.x, -to.z)
	_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, turn_speed * delta)


func _is_locked() -> bool:
	if _lock_on == null:
		return false
	return bool(_lock_on.call("is_locked"))


func _lock_target() -> Node3D:
	if _lock_on == null:
		return null
	var raw: Variant = _lock_on.call("get_target")
	return raw as Node3D if is_instance_valid(raw) else null


## Instance the weapon under the socket and tell it who owns it (so its hitscan
## excludes the player). Referenced duck-typed to dodge the class-cache lag.
func _spawn_weapon() -> void:
	if weapon_scene == null or _weapon_socket == null:
		return
	_weapon = weapon_scene.instantiate()
	_weapon_socket.add_child(_weapon)
	_weapon.set("owner_character", self)
	_muzzle = _weapon.get_node_or_null("Muzzle") as Node3D


## Poll the attack action and let the weapon decide (semi vs auto) whether to fire.
## Firing is gated on lock-on — you shoot the thing you're locked to.
func _process_weapon() -> void:
	if _weapon == null or not _is_locked():
		return
	var pressed := Input.is_action_pressed(&"attack")
	var just := Input.is_action_just_pressed(&"attack")
	if not bool(_weapon.call("should_fire_for_input", pressed, just)):
		return
	var muzzle_pos := _muzzle.global_position if _muzzle else (_weapon as Node3D).global_position
	_weapon.call("try_fire", _aim_direction(muzzle_pos))


## Where the shot goes: straight at the lock-on target when locked, otherwise
## converging on the camera's center ray so it tracks the crosshair.
func _aim_direction(muzzle_pos: Vector3) -> Vector3:
	if _is_locked():
		var target: Node3D = _lock_target()
		if target != null:
			var to_target := target.global_position - muzzle_pos
			if to_target.length_squared() > 0.0001:
				return to_target.normalized()
	if _camera:
		var focus := _camera.global_position - _camera.global_transform.basis.z * aim_distance
		var to_focus := focus - muzzle_pos
		if to_focus.length_squared() > 0.0001:
			return to_focus.normalized()
	return -global_transform.basis.z


## Shove the player with an external impulse (BumpCombatComponent uses this on a
## landed bump). Movement input is suppressed for `duration` so the hit reads;
## overlapping calls keep the longest remaining window rather than cutting it short.
func apply_knockback(impulse: Vector3, duration: float) -> void:
	velocity.x = impulse.x
	velocity.z = impulse.z
	if impulse.y > 0.0:
		velocity.y = impulse.y
	_knockback_timer = maxf(_knockback_timer, duration)


## Collect a PowerDrop. Called duck-typed by the drop when we walk into it.
## Console-only for now — wire it to the HUD once the feature firms up.
func collect_power(amount: int) -> void:
	power += amount
	print("[Player] Power: %d" % power)


## Apply damage; emit player_killed at 0 HP so GameManager restarts the level.
func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = maxi(0, hp - amount)
	if hp <= 0:
		Events.player_killed.emit()
