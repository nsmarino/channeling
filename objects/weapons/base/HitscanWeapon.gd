extends BaseWeapon
class_name HitscanWeapon

@export var hitscan_range: float = 120.0
@export var hitscan_collision_mask: int = 0
@export var collide_with_areas: bool = false
@export var trail_scene: PackedScene
@export var trail_lifetime: float = 0.06
@export var trail_width: float = 0.03
@export var debug_hitscan_logs: bool = true

var _shot_counter: int = 0

func can_fire() -> bool:
	return cooldown_timer.is_stopped() and data != null


func try_fire(aim_direction: Vector3 = Vector3.ZERO) -> bool:
	if not can_fire():
		_play_blocked_fire_attempt_sfx()
		return false

	if ammo_count == 0:
		return false

	if ammo_count > 0:
		ammo_count -= 1

	_shot_counter += 1
	var direction: Vector3 = -muzzle.global_transform.basis.z
	if aim_direction.length_squared() > 0.0001:
		direction = aim_direction.normalized()

	var origin: Vector3 = muzzle.global_position + direction * muzzle_spawn_offset
	var end_point: Vector3 = origin + direction * hitscan_range

	var query := PhysicsRayQueryParameters3D.create(origin, end_point)
	query.exclude = [owner_character]
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = true
	if hitscan_collision_mask != 0:
		query.collision_mask = hitscan_collision_mask

	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		end_point = result["position"]
		_apply_damage(result["collider"])
		_log_hitscan_hit(_shot_counter, origin, end_point, direction, result["collider"])
	else:
		_log_hitscan_miss(_shot_counter, origin, end_point, direction)

	_spawn_trail(origin, end_point)
	_play_shoot_sfx()
	cooldown_timer.start(maxf(float(data.get("fire_rate")), 0.01))
	return true


func _apply_damage(collider: Variant) -> void:
	if not collider is Node:
		return
	var target: Node = collider as Node
	var damage_amount: int = roundi(float(data.get("damage")))

	# Enemy hurtboxes (HitBox areas) forward damage to their owner via receive_hit.
	if target.has_method("receive_hit"):
		target.call("receive_hit", damage_amount)
		if Events:
			Events.attack_hit.emit(owner_character, target, damage_amount)
	elif target.has_method("take_damage"):
		target.call("take_damage", damage_amount)
		if Events:
			Events.attack_hit.emit(owner_character, target, damage_amount)
	elif target.has_method("on_damage"):
		target.call("on_damage", damage_amount)
		if Events:
			Events.attack_hit.emit(owner_character, target, damage_amount)


func _spawn_trail(start: Vector3, hit_point: Vector3) -> void:
	var world: Node = get_tree().current_scene
	if world == null:
		return

	if trail_scene:
		var inst: Node = trail_scene.instantiate()
		world.add_child(inst)
		if inst.has_method("configure"):
			inst.call("configure", start, hit_point, trail_lifetime, trail_width)
		return

	var segment: Vector3 = hit_point - start
	var length: float = segment.length()
	if length <= 0.001:
		return

	var mesh := CylinderMesh.new()
	mesh.top_radius = trail_width
	mesh.bottom_radius = trail_width
	mesh.height = length
	mesh.radial_segments = 6
	mesh.rings = 1

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.9, 0.5, 0.9)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.8, 0.3)
	mesh.material = material

	var trail := MeshInstance3D.new()
	trail.mesh = mesh
	world.add_child(trail)

	var midpoint: Vector3 = start + segment * 0.5
	var trail_basis := Basis.looking_at(segment.normalized(), Vector3.UP)
	trail.global_transform = Transform3D(trail_basis.rotated(trail_basis.x, deg_to_rad(90.0)), midpoint)

	get_tree().create_timer(trail_lifetime).timeout.connect(trail.queue_free)


func _log_hitscan_hit(
	shot_id: int,
	origin: Vector3,
	hit_point: Vector3,
	direction: Vector3,
	collider: Variant
) -> void:
	if not debug_hitscan_logs:
		return
	var collider_name: String = "unknown"
	var collider_type: String = "unknown"
	if collider is Node:
		var collider_node: Node = collider as Node
		collider_name = collider_node.name
		collider_type = collider_node.get_class()
	print(
		"[Hitscan:%s] shot=%d HIT collider=%s(%s) origin=%s hit=%s dir=%s dist=%.2f" %
		[
			name,
			shot_id,
			collider_name,
			collider_type,
			origin,
			hit_point,
			direction,
			origin.distance_to(hit_point)
		]
	)


func _log_hitscan_miss(shot_id: int, origin: Vector3, end_point: Vector3, direction: Vector3) -> void:
	if not debug_hitscan_logs:
		return
	print(
		"[Hitscan:%s] shot=%d MISS origin=%s end=%s dir=%s range=%.2f" %
		[
			name,
			shot_id,
			origin,
			end_point,
			direction,
			origin.distance_to(end_point)
		]
	)
