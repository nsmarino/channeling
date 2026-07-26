extends EnemyAction
class_name GroundPoundAction

## Leap up and come down hard, shaking one bomb loose on the way.
##
## The landing damages through a BLAST rather than through the AttackBox. The
## AttackBox is a capsule out in front — right for a swing, wrong for a shockwave,
## which is radial and should catch someone standing behind you just as hard. It
## also means the pound reuses the same explosion the bombs use, so knockback and
## falloff behave identically whichever way you got hit.
##
## Enemies have no gravity of their own — a MovementPattern assigns velocity
## outright — so the arc is driven here frame by frame rather than by physics. That
## is a feature for a telegraphed attack: the hang time is authored, not simulated,
## so it reads the same every time regardless of where it started.

@export_group("Arc")
## Seconds spent crouching before the leap. The tell.
@export var windup: float = 0.45
## Upward speed of the leap.
@export var rise_speed: float = 9.0
## Seconds spent rising.
@export var rise_time: float = 0.35
## Seconds hanging at the top before the drop.
@export var hang_time: float = 0.18
## Downward speed of the slam. Faster than the rise, so it lands like a hammer.
@export var slam_speed: float = 22.0
## Safety ceiling on the fall, in case the ground is missing beneath it.
@export var slam_timeout: float = 1.0
## Seconds of recovery after landing, while it is vulnerable.
@export var recover: float = 0.7

@export_group("Impact")
## Explosion spawned at the feet on landing.
@export var blast_scene: PackedScene
@export var blast_radius: float = 4.0
@export var blast_damage: int = 20
@export var knockback_force: float = 14.0
@export var knockback_up: float = 6.0
@export var knockback_duration: float = 0.3

@export_group("Bomb")
## One bomb flung up as it leaps, to land and make a nuisance of itself. Empty =
## no bomb.
@export var bomb_scene: PackedScene
## Speed of that bomb.
@export var bomb_speed: float = 11.0
## How far off straight up the bomb is thrown, in degrees. "Vaguely upward".
@export_range(0.0, 60.0, 1.0) var bomb_tilt_deg: float = 25.0


func run(token: int) -> bool:
	if not await _hold(windup, token):
		return false

	# Up. The bomb goes with it, so the shockwave and the falling bomb arrive as
	# two separate problems rather than one.
	_throw_bomb()
	var elapsed: float = 0.0
	while elapsed < rise_time:
		if not still_running(token):
			return false
		drive(Vector3.UP * rise_speed)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame

	if not await _hold(hang_time, token):
		return false

	# Down, until it touches something or the safety timer trips.
	elapsed = 0.0
	while elapsed < slam_timeout:
		if not still_running(token):
			return false
		drive(Vector3.DOWN * slam_speed)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
		if body.is_on_floor():
			break

	_impact()
	return await _hold(recover, token)


## Plant the feet for `seconds` without drifting.
func _hold(seconds: float, token: int) -> bool:
	var elapsed: float = 0.0
	while elapsed < seconds:
		if not still_running(token):
			return false
		drive(Vector3.ZERO)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
	return still_running(token)


func _impact() -> void:
	if blast_scene == null:
		return
	var world: Node = get_tree().current_scene
	if world == null:
		return
	var blast := blast_scene.instantiate() as Node3D
	if blast == null:
		return
	blast.set("radius", blast_radius)
	blast.set("damage", blast_damage)
	blast.set("damages_player", true)
	blast.set("knockback_force", knockback_force)
	blast.set("knockback_up", knockback_up)
	blast.set("knockback_duration", knockback_duration)
	world.add_child(blast)
	blast.global_position = body.global_position


func _throw_bomb() -> void:
	if bomb_scene == null:
		return
	var world: Node = get_tree().current_scene
	if world == null:
		return
	var bomb := bomb_scene.instantiate() as Node3D
	if bomb == null:
		return
	world.add_child(bomb)
	bomb.global_position = body.global_position + Vector3.UP * 1.2

	# Mostly up, tilted a random way — it should land somewhere inconvenient, not
	# somewhere aimed.
	var tilt: float = deg_to_rad(randf_range(0.0, bomb_tilt_deg))
	var yaw: float = randf() * TAU
	var dir := Vector3(sin(tilt) * cos(yaw), cos(tilt), sin(tilt) * sin(yaw))
	if bomb.has_method("launch"):
		bomb.call("launch", dir * bomb_speed)
