extends MovementPattern
class_name StrafeMovement

## Hold a standoff distance from the player and strafe laterally, reversing
## direction periodically. Turret/gunship feel — stays at range and sidesteps.

## Preferred distance to keep from the player (world units).
@export var standoff_distance: float = 18.0
## Lateral strafe speed (world units/sec).
@export var strafe_speed: float = 6.0
## Seconds before reversing strafe direction.
@export var reverse_interval: float = 2.5
## How aggressively it corrects toward standoff distance.
@export var range_correction: float = 1.5


func compute_velocity(enemy: Node3D, player: Node3D, time_active: float, _delta: float) -> Vector3:
	if not player:
		return Vector3.ZERO

	var to_player: Vector3 = _to_player(enemy, player)
	var flat: Vector3 = Vector3(to_player.x, 0.0, to_player.z).normalized()

	# Correct toward the standoff distance (move in if too far, out if too close).
	var dist: float = enemy.global_position.distance_to(player.global_position)
	var range_error: float = dist - standoff_distance
	var radial: Vector3 = flat * clampf(range_error, -1.0, 1.0) * range_correction

	# Strafe perpendicular, flipping direction every reverse_interval.
	var lateral: Vector3 = Vector3(flat.z, 0.0, -flat.x).normalized()
	var dir_sign: float = 1.0 if int(time_active / maxf(reverse_interval, 0.1)) % 2 == 0 else -1.0
	var strafe: Vector3 = lateral * strafe_speed * dir_sign

	return radial + strafe
