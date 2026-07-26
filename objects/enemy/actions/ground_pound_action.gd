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

@export_group("Ground")
## Physics layers that count as ground for the landing probe. Defaults to
## `environment` (layer 1), which is where CSG blockout collision lands.
@export_flags_3d_physics var ground_mask: int = 1
## How far below the creature to look for a floor.
@export var ground_probe_depth: float = 40.0

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
	# Remembered before leaving the ground, as the fallback landing height if the
	# probe finds nothing to land on later.
	var launch_y: float = body.global_position.y

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

	# Down, until it reaches the floor we found or the safety timer trips.
	var floor_y: float = _probe_ground(launch_y)
	elapsed = 0.0
	while elapsed < slam_timeout:
		if not still_running(token):
			return false
		var step: float = slam_speed * get_physics_process_delta_time()
		if body.global_position.y - step <= floor_y:
			# Land exactly rather than overshooting by up to a frame of travel.
			# Writing position directly is the same escape hatch MovementComponent
			# uses in _snap_to_navmesh(): it is a one-off correction at the end of a
			# scripted arc, not a per-frame velocity write, so the single-writer
			# rule for velocity/rotation still holds.
			body.global_position.y = floor_y
			break
		drive(Vector3.DOWN * slam_speed)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame

	_impact()
	return await _hold(recover, token)


## Height of the floor under the creature.
##
## Raycast rather than is_on_floor(), because enemy bodies carry NO collision
## shape and `collision_mask = 0` — move_and_slide() collides with nothing, so
## is_on_floor() is never true and the slam drove straight through the level until
## the safety timer tripped, detonating underground. That collision setup is
## deliberate (it is what lets the player run through an enemy so a bump lands
## cleanly), so the fix belongs here rather than in giving every enemy a body
## shape, which would change how all of them move and snag them on geometry.
##
## Falls back to the height it launched from, so a pound over a pit returns the
## creature to where it jumped rather than dropping it out of the level.
func _probe_ground(fallback_y: float) -> float:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var from: Vector3 = body.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * ground_probe_depth)
	query.collision_mask = ground_mask
	query.exclude = [body.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	return float((hit["position"] as Vector3).y) if hit.has("position") else fallback_y


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
