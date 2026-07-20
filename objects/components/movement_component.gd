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
	if not is_active or not _body:
		return

	_time_active += delta

	# A pattern is optional: without one the body stays put (a stationary turret
	# still runs, so it can keep facing the player).
	if pattern:
		_body.velocity = pattern.compute_velocity(_body, _player, _time_active, delta)
		_body.move_and_slide()
	else:
		_body.velocity = Vector3.ZERO

	_update_facing(delta)


## Turn the body toward the player (face_player) or along its travel direction.
##
## Facing follows Godot's standard convention: the body's **-Z** is its forward,
## so `atan2(-x, -z)` (matching player.gd) puts -Z on the target. Muzzles and
## other "in front of me" markers therefore sit at negative Z.
func _update_facing(delta: float) -> void:
	var target_yaw: float
	if face_player and _player:
		var to_player: Vector3 = _player.global_position - _body.global_position
		if absf(to_player.x) < 0.001 and absf(to_player.z) < 0.001:
			return
		target_yaw = atan2(-to_player.x, -to_player.z)
	elif face_travel_direction:
		var flat: Vector3 = Vector3(_body.velocity.x, 0.0, _body.velocity.z)
		if flat.length_squared() <= 0.04:
			return
		target_yaw = atan2(-flat.x, -flat.z)
	else:
		return
	_body.rotation.y = lerp_angle(_body.rotation.y, target_yaw, clampf(turn_lerp * delta, 0.0, 1.0))
