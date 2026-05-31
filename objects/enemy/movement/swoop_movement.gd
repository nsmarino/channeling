extends MovementPattern
class_name SwoopMovement

## Arc/swoop: accelerate in toward the player along a curved path for swoop_time,
## then hold position and hover. Good for dive-bomber feel.

## Seconds spent swooping in before settling.
@export var swoop_time: float = 1.6
## Speed multiplier applied to move_speed during the swoop.
@export var swoop_speed_multiplier: float = 2.0
## How much lateral curve the swoop has (velocity at mid-swoop).
@export var curve_amount: float = 6.0
## Gentle hover bob after the swoop (velocity amplitude).
@export var hover_amplitude: float = 1.2
## Hover bob frequency.
@export var hover_frequency: float = 0.7


func compute_velocity(enemy: Node3D, player: Node3D, time_active: float, _delta: float) -> Vector3:
	var speed: float = _enemy_speed(enemy)
	var to_player: Vector3 = _to_player(enemy, player)

	if time_active < swoop_time:
		var t: float = time_active / maxf(swoop_time, 0.01)
		# Ease-out: fast at start, slowing as it arrives.
		var ease_out: float = 1.0 - t
		var forward: Vector3 = to_player * speed * swoop_speed_multiplier * ease_out
		# Lateral curve that peaks mid-swoop and fades out.
		var lateral: Vector3 = Vector3(to_player.z, 0.0, -to_player.x).normalized()
		var curve: Vector3 = lateral * sin(t * PI) * curve_amount
		return forward + curve

	# Settled: hover in place with a gentle bob.
	var bob: float = sin(time_active * TAU * hover_frequency) * hover_amplitude
	return Vector3(0.0, bob, 0.0)


func _enemy_speed(enemy: Node3D) -> float:
	var data: Variant = enemy.get("enemy_data")
	if data and data.get("move_speed") != null:
		return float(data.get("move_speed"))
	return 6.0
