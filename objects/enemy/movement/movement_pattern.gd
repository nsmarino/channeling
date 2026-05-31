extends Resource
class_name MovementPattern

## Base class for pluggable enemy movement. A MovementComponent owns one of these
## and calls compute_velocity() each physics frame. Subclasses override it to
## produce distinct flight behavior, configured via @export params in the Inspector.

## Return the desired world-space velocity for this frame.
## - enemy: the FseEnemy (CharacterBody3D) being driven
## - player: the player node (may be null)
## - time_active: seconds since the enemy activated
## - delta: physics frame delta
func compute_velocity(_enemy: Node3D, _player: Node3D, _time_active: float, _delta: float) -> Vector3:
	return Vector3.ZERO


## Helper: flattened (XZ) direction from enemy toward player, or forward (+Z is
## toward the oncoming player in our rail setup) if no player.
func _to_player(enemy: Node3D, player: Node3D) -> Vector3:
	if not player:
		return Vector3(0.0, 0.0, 1.0)
	var d: Vector3 = player.global_position - enemy.global_position
	if d.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return d.normalized()
