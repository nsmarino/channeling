extends MovementPattern
class_name WeaveMovement

## Sine-wave side-to-side weaving. Approaches the player up to a minimum
## engagement distance, then holds its ground so the rail can fly past it —
## otherwise the enemy ends up shadowing the player at the same relative spot.

## Horizontal weave amplitude (world units of velocity at the peak).
@export var weave_amplitude: float = 5.0
## Weave oscillations per second.
@export var weave_frequency: float = 0.6
## Fraction of move_speed used to drift toward the player while outside the
## engagement range.
@export var approach_fraction: float = 0.4
## Stop approaching once within this distance — lets the rail-driven player
## advance past the weaver.
@export var approach_min_distance: float = 14.0
## Vertical bob amplitude (velocity).
@export var bob_amplitude: float = 1.5
## Vertical bob frequency.
@export var bob_frequency: float = 0.9


func compute_velocity(enemy: Node3D, player: Node3D, time_active: float, _delta: float) -> Vector3:
	var speed: float = _enemy_speed(enemy)
	var to_player: Vector3 = _to_player(enemy, player)
	var flat: Vector3 = Vector3(to_player.x, 0.0, to_player.z).normalized()

	# Approach only while outside the engagement range; once close, hold position.
	var dist: float = INF
	if player:
		dist = enemy.global_position.distance_to(player.global_position)
	var approach: Vector3 = Vector3.ZERO
	if dist > approach_min_distance:
		approach = flat * speed * approach_fraction

	# Lateral weave is perpendicular to the (flat) direction toward the player.
	# Driven by `flat` directly so weaving works whether or not we're approaching.
	var lateral: Vector3 = Vector3(flat.z, 0.0, -flat.x).normalized()
	var weave: Vector3 = lateral * sin(time_active * TAU * weave_frequency) * weave_amplitude

	var bob: float = sin(time_active * TAU * bob_frequency) * bob_amplitude

	return approach + weave + Vector3(0.0, bob, 0.0)


func _enemy_speed(enemy: Node3D) -> float:
	var data: Variant = enemy.get("enemy_data")
	if data and data.get("move_speed") != null:
		return float(data.get("move_speed"))
	return 6.0
