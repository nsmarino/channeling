extends EnemyAction
class_name OrbitAction

## Circle the player at the brain's combat range while facing them, until the arc
## is covered. The bread-and-butter "keep pressure without committing" action.
##
## Steering is direct rather than navmesh-pathed — a path query per frame for a
## tight circle is both laggy and overkill — so the projected step is checked
## against the mesh and the circle reverses at its edge.

## Arc distance (world units) travelled before the action ends and the brain
## re-picks.
@export var arc_units: float = 6.0
## Speed while circling.
@export var speed: float = 2.6
## How hard it corrects back toward the combat range while circling.
@export_range(0.0, 3.0, 0.1) var radial_correction: float = 1.2


func run(token: int) -> bool:
	# Direction is rolled once, here — an orbit that changed its mind every frame
	# would just jitter in place.
	var direction: float = 1.0 if randf() < 0.5 else -1.0
	var travelled: float = 0.0
	var flipped: bool = false
	var radius: float = combat_range()

	while travelled < arc_units:
		if not still_running(token):
			return false
		var target: Node3D = get_player()
		if not is_instance_valid(target):
			return false

		var to_player: Vector3 = target.global_position - body.global_position
		to_player.y = 0.0
		var dist: float = to_player.length()
		if dist < 0.001:
			return true

		var radial: Vector3 = to_player / dist
		var tangent := Vector3(-radial.z, 0.0, radial.x) * direction
		# Pull back toward the preferred radius as we circle.
		var offset: float = clampf(dist - radius, -1.0, 1.0)
		var velocity: Vector3 = tangent * speed + radial * offset * radial_correction

		var delta: float = get_physics_process_delta_time()
		if not is_navigable(body.global_position + velocity * delta):
			if flipped:
				return true  # boxed in both ways — let the brain pick something else.
			flipped = true
			direction = -direction
			hold_still()
			await get_tree().physics_frame
			continue

		drive(velocity)
		face_toward(target.global_position)
		travelled += speed * delta
		await get_tree().physics_frame

	return still_running(token)
