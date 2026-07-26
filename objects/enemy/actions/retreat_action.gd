extends EnemyAction
class_name RetreatAction

## Back off to the brain's combat range, straight or strafing.
##
## Bailing out is a legitimate resolution here rather than a failure: if the
## retreat would leave the navmesh it mirrors the strafe once and then gives up,
## because the brain simply picks again and an orbit re-establishes spacing from
## wherever it ended up.
##
## Ships as the last child of AttackComboAction — the reposition that ends a combo.

## Chance the retreat strafes sideways instead of backing straight up.
@export_range(0.0, 1.0, 0.05) var strafe_chance: float = 0.5
## Speed while retreating.
@export var speed: float = 3.2
## Give up retreating after this long.
@export var give_up_after: float = 3.0
## Sideways speed as a fraction of `speed`, when strafing.
@export_range(0.0, 2.0, 0.05) var strafe_ratio: float = 0.8


func run(token: int) -> bool:
	var strafe: bool = randf() < strafe_chance
	var direction: float = 1.0 if randf() < 0.5 else -1.0
	var flipped: bool = false
	var elapsed: float = 0.0
	var radius: float = combat_range()

	while elapsed < give_up_after:
		if not still_running(token):
			return false
		var target: Node3D = get_player()
		if not is_instance_valid(target):
			return false

		var to_player: Vector3 = target.global_position - body.global_position
		to_player.y = 0.0
		var dist: float = to_player.length()
		if dist >= radius or dist < 0.001:
			return true  # spacing restored.

		var radial: Vector3 = to_player / dist
		var velocity: Vector3 = -radial * speed
		if strafe:
			velocity += Vector3(-radial.z, 0.0, radial.x) * direction * speed * strafe_ratio

		if not is_navigable(body.global_position + velocity * get_physics_process_delta_time()):
			if flipped:
				return true
			flipped = true
			direction = -direction
			strafe = true
			hold_still()
			await get_tree().physics_frame
			continue

		drive(velocity)
		face_toward(target.global_position)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame

	return still_running(token)
