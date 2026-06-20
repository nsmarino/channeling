extends FseDestructible
class_name FseTurretProjectile

## A destructible projectile launched by a StationaryTurret. It follows a Curve2D
## owned by its emitter (via CurveFollowMovement on a MovementComponent child) and
## damages the player on contact (via a ContactDamage child). The player can shoot
## it down — that's the point of basing it on FseDestructible rather than the
## plain FseBaseProjectile.
##
## The emitter calls launch_on_curve() right after instancing it into the scene,
## which stamps the curve + base transform + advance speed the pattern reads, and
## starts the lifetime countdown.

## Seconds before the projectile frees itself if it isn't shot or consumed first.
@export var life_time: float = 4.0

# Read by CurveFollowMovement each frame (duck-typed via enemy.get(...)).
var follow_curve: Curve2D = null
var curve_base_transform: Transform3D = Transform3D.IDENTITY
var advance_speed: float = 20.0


## Called by the emitter immediately after add_child. `base` is the world-space
## transform the curve is traced relative to (the emitter's muzzle transform at
## fire time), so the pattern can stay still even though the emitter keeps moving.
func launch_on_curve(curve: Curve2D, base: Transform3D, speed: float) -> void:
	follow_curve = curve
	curve_base_transform = base
	advance_speed = speed
	global_transform = base
	# Obstacles/projectiles are ACTIVE on spawn; kick the components on now.
	_dispatch_active(true)
	state = State.ACTIVE
	get_tree().create_timer(life_time).timeout.connect(_expire)


func _expire() -> void:
	# Quietly disappear at end of life — no explosion for a timed-out shot.
	if state != State.DYING:
		queue_free()


func _label() -> String:
	return "TurretBolt:" + String(name)
