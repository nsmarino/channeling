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
## How fast the body turns to face travel (higher = snappier).
@export var turn_lerp: float = 6.0

var _body: CharacterBody3D = null
var _player: Node3D = null
var _time_active: float = 0.0


func _setup() -> void:
	if body_path != NodePath() and has_node(body_path):
		_body = get_node(body_path) as CharacterBody3D
	else:
		_body = host as CharacterBody3D
	set_physics_process(false)


func setup(player: Node3D) -> void:
	_player = player


func on_activate() -> void:
	set_physics_process(true)
	_time_active = 0.0


func on_deactivate() -> void:
	set_physics_process(false)
	if _body:
		_body.velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not is_active or not _body or not pattern:
		return

	_time_active += delta
	var v: Vector3 = pattern.compute_velocity(_body, _player, _time_active, delta)
	_body.velocity = v
	_body.move_and_slide()

	if face_travel_direction:
		var flat: Vector3 = Vector3(v.x, 0.0, v.z)
		if flat.length_squared() > 0.04:
			var target_yaw: float = atan2(flat.x, flat.z)
			_body.rotation.y = lerp_angle(_body.rotation.y, target_yaw, clampf(turn_lerp * delta, 0.0, 1.0))
