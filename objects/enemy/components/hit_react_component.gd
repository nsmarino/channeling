extends Node
class_name HitReactComponent

## Flash + shake (and, later, a particle burst) reaction to taking damage —
## shared by enemies and the player.
##
##   - Flash: builds a ShaderMaterial from flash_shader and assigns it as a
##     material_overlay to every MeshInstance3D under mesh_root, then pulses
##     flash_modifier 1 -> 0 (the model's real materials show at rest).
##   - Shake: a decaying positional jitter on mesh_root. mesh_root is a visual
##     *child* (a mesh), so the offset composes with any body movement instead of
##     fighting it.
##   - extra_offset: an extra local offset the owner layers on each frame (e.g.
##     the player's brake bob), composed into the same single position write.
##
## Trigger: an FseDestructible parent that emits `hit` is auto-connected in
## _ready (enemies need zero wiring); anything else just calls trigger().

## Overlay shader for the flash (defaults to the shared blink shader).
@export var flash_shader: Shader = preload("res://vfx/shaders/blink.gdshader")
## Flash colour.
@export var flash_color: Color = Color(1.0, 0.05, 0.1, 1.0)
## Seconds the flash fades from full to none.
@export var flash_duration: float = 0.18
## Peak positional jitter (world units), decays to 0.
@export var shake_strength: float = 0.12
## Seconds the shake decays over.
@export var shake_duration: float = 0.25
## Visual node to flash + shake. Empty = the first MeshInstance3D under the
## parent (e.g. an enemy's "Body").
@export var mesh_root_path: NodePath

## Extra local offset layered onto mesh_root every frame. Owners that need it
## (e.g. the player's bob) set it; others leave it at zero.
var extra_offset: Vector3 = Vector3.ZERO

var _mesh_root: Node3D = null
var _mesh_rest: Vector3 = Vector3.ZERO
var _flash_material: ShaderMaterial = null
var _flash_timer: float = 0.0
var _shake_timer: float = 0.0


func _ready() -> void:
	_resolve_mesh_root()
	_setup_flash()
	var parent: Node = get_parent()
	if parent and parent.has_signal("hit"):
		parent.hit.connect(_on_parent_hit)


## Kick off a flash + shake.
func trigger() -> void:
	_flash_timer = flash_duration
	_shake_timer = shake_duration


func _on_parent_hit(_amount: int) -> void:
	trigger()


func _physics_process(delta: float) -> void:
	if _flash_material and _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		_flash_material.set_shader_parameter("flash_modifier", _flash_timer / maxf(flash_duration, 0.001))

	if not _mesh_root:
		return
	var shake := Vector3.ZERO
	if _shake_timer > 0.0:
		_shake_timer = maxf(_shake_timer - delta, 0.0)
		var decay := _shake_timer / maxf(shake_duration, 0.001)
		shake = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * shake_strength * decay
	_mesh_root.position = _mesh_rest + extra_offset + shake


func _resolve_mesh_root() -> void:
	if mesh_root_path != NodePath() and has_node(mesh_root_path):
		_mesh_root = get_node(mesh_root_path) as Node3D
	if not _mesh_root:
		_mesh_root = _find_first_mesh(get_parent())
	if _mesh_root:
		_mesh_rest = _mesh_root.position


## First MeshInstance3D under `node` (direct children first, then depth-first).
func _find_first_mesh(node: Node) -> Node3D:
	if node == null:
		return null
	for child in node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	for child in node.get_children():
		var found: Node3D = _find_first_mesh(child)
		if found:
			return found
	return null


func _setup_flash() -> void:
	if not flash_shader or not _mesh_root:
		return
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = flash_shader
	_flash_material.set_shader_parameter("flash_color", flash_color)
	_flash_material.set_shader_parameter("flash_modifier", 0.0)
	_assign_overlay_recursive(_mesh_root)


## Assign the shared overlay to every MeshInstance3D in the subtree, so the whole
## visual flashes off one material.
func _assign_overlay_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = _flash_material
	for child in node.get_children():
		_assign_overlay_recursive(child)
