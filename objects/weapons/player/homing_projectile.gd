extends BaseProjectile
class_name HomingProjectile

## A projectile that curves toward a target at a capped turn rate. Because the
## turn rate is fixed, nearby/slow targets get caught while distant/fast ones
## out-run the correction — the Space Harrier "closer = more likely to hit" feel
## emerges from the cap rather than any explicit probability.

## Max turn toward the target, in degrees per second.
@export var turn_rate_deg: float = 220.0
## Stop homing once within this distance (avoids orbiting a point-blank target).
@export var lock_distance: float = 0.6

var homing_target: Node3D = null


func _physics_process(delta: float) -> void:
	if homing_target and is_instance_valid(homing_target):
		var to_target: Vector3 = homing_target.global_position - global_position
		if to_target.length() > lock_distance and to_target.length_squared() > 0.0001:
			var desired: Vector3 = to_target.normalized()
			var max_turn: float = deg_to_rad(turn_rate_deg) * delta
			var angle: float = _direction.angle_to(desired)
			if angle <= max_turn or angle < 0.0001:
				_direction = desired
			else:
				# Rotate _direction toward desired by max_turn around their shared plane.
				var axis: Vector3 = _direction.cross(desired)
				if axis.length_squared() < 0.0000001:
					_direction = desired
				else:
					_direction = _direction.rotated(axis.normalized(), max_turn).normalized()

	# Face travel direction so the mesh/trail point forward.
	if _direction.length_squared() > 0.0001:
		look_at(global_position + _direction, Vector3.UP)

	global_position += _direction * speed * delta
