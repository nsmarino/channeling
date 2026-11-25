@tool
class_name BlobShadow
extends Decal

## A soft oblong shadow projected onto whatever is under its parent — not from
## any light, just a "you are here" mark that wraps the ground, slopes and
## ledges. Add it as a child of a body (Player, an enemy) and tune it in the
## Inspector.
##
## Each physics frame it casts a ray straight down from the parent and moves
## itself to the hit, so it stays on the ground while the body jumps, and fades
## and shrinks with height. No hit within `max_height` = no shadow.
##
## It projects onto anything inside its box. `exclude_owner` keeps it off the
## owner: at runtime the owner's meshes move to `owner_layer` (a visual layer
## nothing else uses), which this decal's `cull_mask` leaves out. That is what
## lets the box be tall enough for uneven ground under a long or offset oval.
## Other creatures walking through it still get darkened.
##
## The parent's origin should be at its feet (true for the Player and
## BaseEnemy). If a body also casts a real shadow you may want `cast_shadow` off
## on its meshes, or it gets two.

@export_group("Shape")
## Width (X) and length (Z) in metres, at ground level. Length runs along the
## facing. Make it wider than the body, or the body hides it from behind — only
## the part outside the silhouette reads.
@export var shadow_size: Vector2 = Vector2(2.0, 2.4):
	set(v):
		shadow_size = v
		_apply_size(1.0)
## Extra turn in degrees, on top of the facing (or of world -Z when
## `follow_facing` is off).
@export_range(-180.0, 180.0, 1.0, "degrees") var angle: float = 0.0
## Shift in metres along the shadow's own axes, after `angle`: X = to its
## right, Y = along its length (positive = the way the length points, i.e. ahead
## of the facing). To put one end of an oval under the body, set Y to about
## half the length minus a little: length 2.4 → Y ≈ 0.9. Shrinks with height
## along with the size.
@export var offset: Vector2 = Vector2.ZERO
## Turn with the body's facing (the Player's Model, or the body itself).
@export var follow_facing: bool = true
## 0 = hard edge, 1 = soft all the way from the centre.
@export_range(0.0, 1.0, 0.01) var softness: float = 0.5:
	set(v):
		softness = v
		_build_texture()
## Darkness at ground level.
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.7:
	set(v):
		opacity = v
		modulate = Color(0, 0, 0, opacity)

@export_group("Height")
## Above this height the shadow is gone (and the ray stops looking).
@export var max_height: float = 6.0
## Size at `max_height`, as a fraction of the ground size.
@export_range(0.0, 1.0, 0.01) var min_scale: float = 0.45
## How opacity falls with height: 1 = linear, higher = holds longer, then drops.
@export_range(0.2, 4.0, 0.05) var fade_curve: float = 1.0

@export_group("Projection")
## How far above the ground under the body the box reaches, and below it.
## Ground anywhere under the oval must fall inside, or the shadow is cut off in
## a straight line — raise these for long or offset ovals on bumpy ground.
## With `exclude_owner` off, keep `reach_above` low or the owner's legs go dark.
@export var reach_above: float = 1.0
@export var reach_below: float = 1.0
## Keep the shadow off the owner's own meshes (see `owner_layer`).
@export var exclude_owner: bool = true
## The visual layer the owner's meshes move to. Pick one nothing else uses;
## cameras and lights see every layer by default, so nothing else changes.
@export_range(1, 20) var owner_layer: int = 20
## Physics layers the ray treats as ground. 1 = environment.
@export_flags_3d_physics var ground_mask: int = 1
## Start the ray this far above the parent's origin, so it can't start below a
## floor the body is sinking into.
@export var ray_start: float = 0.5


func _ready() -> void:
	modulate = Color(0, 0, 0, opacity)
	albedo_mix = 1.0
	normal_fade = 0.5
	# No fade through the box: the ground can sit anywhere in it.
	upper_fade = 0.0
	lower_fade = 0.0
	if texture_albedo == null:
		_build_texture()
	_apply_size(1.0)
	if exclude_owner and not Engine.is_editor_hint():
		cull_mask &= ~(1 << (owner_layer - 1))
		_exclude_owner.call_deferred()


## Move every mesh under the owner onto `owner_layer` only, so this decal (and
## any other BlobShadow using the same layer) skips it. Meshes added to the
## owner later (a picked-up weapon) are not caught.
func _exclude_owner() -> void:
	var body: Node = get_parent()
	if body == null:
		return
	var stack: Array[Node] = [body]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n != self and n is VisualInstance3D and not (n is Decal):
			(n as VisualInstance3D).layers = 1 << (owner_layer - 1)
		stack.append_array(n.get_children())


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var body: Node3D = get_parent() as Node3D
	if body == null:
		return

	var from: Vector3 = body.global_position + Vector3.UP * ray_start
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, from + Vector3.DOWN * (max_height + ray_start), ground_mask)
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		visible = false
		return

	var ground: Vector3 = hit["position"]
	var t: float = clampf((body.global_position.y - ground.y) / max_height, 0.0, 1.0)
	visible = t < 1.0
	modulate.a = opacity * (1.0 - pow(t, fade_curve))
	var scale_factor: float = lerpf(1.0, min_scale, t)
	_apply_size(scale_factor)

	var yaw: float = deg_to_rad(angle)
	if follow_facing:
		yaw += _facing_node(body).global_rotation.y
	var rot: Basis = Basis(Vector3.UP, yaw)
	# -Z is "ahead", so a positive length offset moves the oval forward.
	var shift: Vector3 = rot * Vector3(offset.x, 0.0, -offset.y) * scale_factor
	var centre: Vector3 = ground + shift + Vector3.UP * (reach_above - reach_below) * 0.5
	global_transform = Transform3D(rot, centre)


func _facing_node(body: Node3D) -> Node3D:
	if body.has_method(&"get_facing_node"):
		var n: Node3D = body.call(&"get_facing_node") as Node3D
		if n:
			return n
	return body


func _apply_size(scale_factor: float) -> void:
	size = Vector3(shadow_size.x * scale_factor, reach_above + reach_below,
			shadow_size.y * scale_factor)


## A radial black-to-clear gradient; stretched to the oblong by `size`.
func _build_texture() -> void:
	var g: Gradient = Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	var core: float = clampf(1.0 - softness, 0.0, 0.99)
	g.offsets = PackedFloat32Array([0.0, core, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	# Radius 0.45, not 0.5: clear texels all round the edge, or filtering
	# bleeds a faint square outline of the box onto the ground.
	tex.fill_to = Vector2(0.95, 0.5)
	tex.width = 64
	tex.height = 64
	texture_albedo = tex
