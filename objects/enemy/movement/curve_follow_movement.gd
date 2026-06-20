extends MovementPattern
class_name CurveFollowMovement

## Drives a body along a Curve2D that lives on its emitter (a StationaryTurret).
## The curve is traced in a plane: a curve point (x, y) maps to the emitter-local
## offset (x, y, 0), so the path is perpendicular to the rail's forward axis —
## lines, arcs, and sine sweeps across the player's lane.
##
## This pattern is stateless: it reads the curve, the emitter's base transform,
## and the advance speed off the body each frame (set by the emitter on spawn via
## launch_on_curve). One shared .tres can therefore drive every projectile.

## Used only if the body doesn't carry an advance_speed property.
@export var fallback_speed: float = 20.0


func compute_velocity(enemy: Node3D, _player: Node3D, time_active: float, delta: float) -> Vector3:
	if delta <= 0.0:
		return Vector3.ZERO

	var curve_v: Variant = enemy.get("follow_curve")
	if not (curve_v is Curve2D):
		return Vector3.ZERO
	var curve: Curve2D = curve_v
	if curve.point_count < 2:
		return Vector3.ZERO

	var base: Transform3D = enemy.get("curve_base_transform")
	var speed_v: Variant = enemy.get("advance_speed")
	var speed: float = float(speed_v) if speed_v != null else fallback_speed

	# Sample by arc length so speed is in world units/sec regardless of the
	# curve's point spacing. sample_baked clamps at the end, so the projectile
	# parks at the curve's tail until life_time frees it.
	var s: Vector2 = curve.sample_baked(time_active * speed, true)
	var target: Vector3 = base * Vector3(s.x, s.y, 0.0)

	# Velocity that lands exactly on the target this frame — snaps the body to
	# the curve, so the traced path is exact rather than drifting.
	return (target - enemy.global_position) / delta
