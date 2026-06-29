extends CharacterBody3D

## Standard first-person character controller. Works with mouse/keyboard and
## gamepad interchangeably:
##   - Look: mouse motion or the right stick (look_*). Yaw turns the whole body
##     so movement follows where you face; pitch tilts only the camera (clamped).
##   - Move: WASD or the left stick (move_*), relative to facing.
##   - Jump: Space or the gamepad A button (jump).
##   - Escape toggles mouse capture so you can reach the editor / OS.
##
## Registers into the "player" group (GameManager finds the navigator and the HUD
## reads `hp` through it). Death/fall/Restart all route through GameManager — see
## take_damage() below and game_manager.gd.
##
## Tuning lives in the Inspector @export blocks, matching the project's
## iterate-by-playing workflow.

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

@export_category("Look")
## Mouse look sensitivity, radians per pixel of motion.
@export var mouse_sensitivity: float = 0.0025
## Gamepad look speed, radians/sec at full stick deflection.
@export var gamepad_look_speed: float = 3.0
## Camera pitch clamp, in degrees.
@export var pitch_min_deg: float = -89.0
@export var pitch_max_deg: float = 89.0

@export_category("Health")
@export var max_hp: int = 100

@export_category("References")
## Camera tilted for pitch. Yaw is applied to the body itself.
@export var camera_path: NodePath = ^"Camera3D"

var hp: int = 0

var _camera: Camera3D = null
var _gravity: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	add_to_group("player")
	_camera = get_node_or_null(camera_path) as Camera3D
	_gravity = gravity_override if gravity_override > 0.0 \
		else float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	hp = max_hp
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_apply_look(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity)
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE \
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_process_gamepad_look(delta)
	_process_movement(delta)


## Yaw rotates the body (so movement tracks facing); pitch tilts the camera only.
func _apply_look(yaw_delta: float, pitch_delta: float) -> void:
	rotate_y(yaw_delta)
	_pitch = clampf(_pitch + pitch_delta, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	if _camera:
		_camera.rotation.x = _pitch


func _process_gamepad_look(delta: float) -> void:
	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look != Vector2.ZERO:
		_apply_look(-look.x * gamepad_look_speed * delta, -look.y * gamepad_look_speed * delta)


func _process_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed(&"jump"):
		velocity.y = jump_velocity

	# Input.get_vector maps left/right to X and forward/back to Y (forward = -1),
	# so Vector3(x, 0, y) is already a forward = -Z direction in local space.
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var target := direction * move_speed
	var accel := ground_acceleration if is_on_floor() else air_acceleration
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)

	move_and_slide()


## Apply damage; emit player_killed at 0 HP so GameManager restarts the level.
func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = maxi(0, hp - amount)
	if hp <= 0:
		Events.player_killed.emit()
