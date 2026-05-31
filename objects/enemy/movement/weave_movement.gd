extends MovementPattern
class_name WeaveMovement

## Sine-wave side-to-side weaving while drifting slowly toward the player.
## Reads its forward/lateral speed from the enemy's move_speed where useful.

## Horizontal weave amplitude (world units of velocity at the peak).
@export var weave_amplitude: float = 5.0
## Weave oscillations per second.
@export var weave_frequency: float = 0.6
## Fraction of move_speed used to drift toward the player along its facing.
@export var approach_fraction: float = 0.4
## Vertical bob amplitude (velocity).
@export var bob_amplitude: float = 1.5
## Vertical bob frequency.
@export var bob_frequency: float = 0.9


func compute_velocity(enemy: Node3D, player: Node3D, time_active: float, _delta: float) -> Vector3:
	var speed: float = _enemy_speed(enemy)
	var to_player: Vector3 = _to_player(enemy, player)

	# Drift toward the player (flattened) at a fraction of base speed.
	var approach: Vector3 = Vector3(to_player.x, 0.0, to_player.z).normalized() * speed * approach_fraction

	# Lateral weave perpendicular to the approach direction.
	var lateral: Vector3 = Vector3(approach.z, 0.0, -approach.x).normalized()
	var weave: Vector3 = lateral * sin(time_active * TAU * weave_frequency) * weave_amplitude

	var bob: float = sin(time_active * TAU * bob_frequency) * bob_amplitude

	return approach + weave + Vector3(0.0, bob, 0.0)


func _enemy_speed(enemy: Node3D) -> float:
	var data: Variant = enemy.get("enemy_data")
	if data and data.get("move_speed") != null:
		return float(data.get("move_speed"))
	return 6.0
