extends EnemyAction
class_name LaunchBombAction

## Lob a volley of physics bombs at where the player is.
##
## Built for shelling a place you cannot see into. Pair it with a `required_region`
## covering the ground you want made dangerous and `los_requirement = FORBIDDEN`,
## and the creature will only shell you while you are in that space and it has no
## clear shot — the "over the wall" case. Give a second copy `REQUIRED` and a
## flatter angle if you also want a direct shot when it can see you.
##
## AIMING WITHOUT SEEING. It aims at the player's actual position, because region
## occupancy is what told it you were there — it knows roughly where you are, not
## precisely. `aim_spread_deg` and `range_jitter` are what turn that "roughly" into
## something survivable: with them at zero it drops bombs on your head every time.
##
## THE ARC. `launch_angle_deg` is the elevation you author — pick whatever clears
## the wall. With `auto_solve_speed` on, the SPEED needed to land at that angle on
## the target is solved ballistically per shot, so tuning the arc doesn't also mean
## re-tuning the range every time you move the creature. If the angle is too flat
## to reach at all, the solve fails and the shot falls back to `launch_speed`.
##
## The Muzzle child is why EnemyAction is a Node3D: drag it in the viewport to set
## where bombs leave the body.

## Bomb to throw.
@export var bomb_scene: PackedScene
## Marker the bombs spawn from. Empty = a child named "Muzzle", else the body.
@export var muzzle_path: NodePath = ^"Muzzle"

@export_group("Arc")
## Elevation of the throw, in degrees above horizontal. High lobs over cover.
@export_range(5.0, 85.0, 1.0) var launch_angle_deg: float = 55.0
## Solve the speed needed to land on the target at `launch_angle_deg`.
@export var auto_solve_speed: bool = true
## Speed used when auto-solve is off, or when the target is out of reach at this
## angle.
@export var launch_speed: float = 16.0

@export_group("Accuracy")
## Horizontal aim scatter, in degrees either side.
@export_range(0.0, 45.0, 1.0) var aim_spread_deg: float = 8.0
## Range scatter as a fraction of the distance — 0.15 means shots land anywhere
## from 85% to 115% of the way there.
@export_range(0.0, 1.0, 0.05) var range_jitter: float = 0.12

@export_group("Volley")
## Bombs per use of this action.
@export_range(1, 10, 1) var bomb_count: int = 2
## Seconds between bombs in a volley.
@export var bomb_spacing: float = 0.45
## Seconds of telegraph before the first bomb.
@export var windup: float = 0.5
## Seconds of recovery after the last bomb.
@export var recover: float = 0.4
## Face the target while throwing.
@export var face_target: bool = true

var _muzzle: Node3D = null


func _setup() -> void:
	_muzzle = get_node_or_null(muzzle_path) as Node3D


func run(token: int) -> bool:
	var target: Node3D = get_player()
	if not is_instance_valid(target) or bomb_scene == null:
		return false

	if not await _telegraph(windup, token):
		return false

	for i in bomb_count:
		if not still_running(token):
			return false
		_throw()
		if i < bomb_count - 1 and not await _telegraph(bomb_spacing, token):
			return false

	if not await _telegraph(recover, token):
		return false
	return still_running(token)


## Hold position for `seconds`, optionally tracking the target. Distinct from
## wait()/wait_still() because whether a shelling creature turns to follow you is a
## per-action choice, not a global one.
func _telegraph(seconds: float, token: int) -> bool:
	var elapsed: float = 0.0
	while elapsed < seconds:
		if not still_running(token):
			return false
		drive(Vector3.ZERO)
		if face_target:
			var target: Node3D = get_player()
			if is_instance_valid(target):
				face_toward(target.global_position)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
	return still_running(token)


func _throw() -> void:
	var target: Node3D = get_player()
	if not is_instance_valid(target):
		return
	var world: Node = get_tree().current_scene
	if world == null:
		return

	var origin: Vector3 = _muzzle.global_position if _muzzle else body.global_position
	var aim: Vector3 = _scatter(target.global_position, origin)

	var bomb := bomb_scene.instantiate() as Node3D
	if bomb == null:
		return
	world.add_child(bomb)
	bomb.global_position = origin
	if bomb.has_method("launch"):
		bomb.call("launch", _solve_impulse(origin, aim))


## Nudge the aim point so a volley scatters instead of stacking on one spot.
func _scatter(target_pos: Vector3, origin: Vector3) -> Vector3:
	var to: Vector3 = target_pos - origin
	to.y = 0.0
	var dist: float = to.length()
	if dist < 0.001:
		return target_pos

	var angle: float = deg_to_rad(randf_range(-aim_spread_deg, aim_spread_deg))
	var jitter: float = 1.0 + randf_range(-range_jitter, range_jitter)
	var dir: Vector3 = to.normalized().rotated(Vector3.UP, angle)
	return origin + dir * dist * jitter + Vector3.UP * (target_pos.y - origin.y)


## Velocity that throws from `origin` to `aim` at `launch_angle_deg`.
##
## Standard ballistic solve: for a launch at angle t covering horizontal distance d
## and height change h, v² = g·d² / (2·cos²t·(d·tan t − h)). The denominator goes
## non-positive when the target is too high or too far for that angle to ever
## reach, which is the case we fall back on rather than take the square root of a
## negative number.
func _solve_impulse(origin: Vector3, aim: Vector3) -> Vector3:
	var to: Vector3 = aim - origin
	var flat := Vector3(to.x, 0.0, to.z)
	var d: float = flat.length()
	var dir: Vector3 = flat.normalized() if d > 0.001 else -body.global_transform.basis.z
	var t: float = deg_to_rad(launch_angle_deg)

	var speed: float = launch_speed
	if auto_solve_speed and d > 0.001:
		var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
		var denom: float = 2.0 * pow(cos(t), 2.0) * (d * tan(t) - to.y)
		if denom > 0.001:
			speed = sqrt(g * d * d / denom)

	return dir * speed * cos(t) + Vector3.UP * speed * sin(t)
