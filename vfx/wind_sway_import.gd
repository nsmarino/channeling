@tool
extends EditorScenePostImport

## Makes an imported model sway in the wind.
##
## Turn it on per model: select the .glb, Import dock › Import Script › this
## file, then Reimport. Every material in the model becomes a wind_sway
## ShaderMaterial saved NEXT TO THE MODEL, and the model uses it:
##   - one material:  <model>_wind.tres
##   - several:       <model>_<material>_wind.tres
##
## Copied from the original material on EVERY reimport (edit them in Blender,
## not here): albedo texture and colour, roughness, emission (colour, energy,
## texture), plus the mesh's lowest and highest point (the shader's bounds).
##
## Kept across reimports (tune these in the .tres): the Shape group —
## anchor_at_top, falloff_power, flutter_scale, strength_scale,
## turbulence_scale, seed_from_position — and alpha_scissor.
##
## The wind itself is global: Project Settings › Shader Globals › wind_*.
##
## Only the albedo, roughness and emission carry over; a normal map etc. is
## dropped, as the wind shader doesn't have them.

const SHADER: Shader = preload("res://vfx/shaders/wind_sway.gdshader")

## The knobs kept across reimports, with the values a new material starts on.
## Keep in step with the shader's own defaults.
const TUNING_DEFAULTS: Dictionary[StringName, Variant] = {
	&"anchor_at_top": false,
	&"falloff_power": 1.6,
	&"flutter_scale": 0.6,
	&"strength_scale": 1.0,
	&"turbulence_scale": 1.0,
	&"seed_from_position": true,
	&"alpha_scissor": 0.5,
}


func _post_import(scene: Node) -> Object:
	var source_path: String = get_source_file()

	# A shader that didn't compile reports no uniforms, and a material saved then
	# keeps none of its settings (a plain white mesh). The usual cause is the
	# editor having started before the wind_* Shader Globals existed: restart it.
	if SHADER.get_shader_uniform_list().is_empty():
		push_error("WindSway import (%s): wind_sway.gdshader did not compile, so no wind materials were written. If the wind_* Shader Globals were just added to project.godot, restart the editor and reimport." % source_path)
		return scene
	var dir: String = source_path.get_base_dir()
	var model: String = source_path.get_file().get_basename()

	# Pass 1: every distinct source material, and the height range of all the
	# meshes that use it.
	var sources: Array[Material] = []
	var bounds: Dictionary[Material, Vector2] = {}
	var meshes: Array[MeshInstance3D] = _mesh_instances(scene)
	for mi: MeshInstance3D in meshes:
		var aabb: AABB = mi.mesh.get_aabb()
		for i: int in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			if src == null:
				continue
			if not bounds.has(src):
				sources.append(src)
				bounds[src] = Vector2(aabb.position.y, aabb.end.y)
			else:
				var b: Vector2 = bounds[src]
				bounds[src] = Vector2(minf(b.x, aabb.position.y), maxf(b.y, aabb.end.y))

	# Pass 2: build or refresh one wind material per source material.
	var made: Dictionary[Material, ShaderMaterial] = {}
	for src: Material in sources:
		var path: String = "%s/%s_wind.tres" % [dir, model] if sources.size() == 1 \
			else "%s/%s_%s_wind.tres" % [dir, model, _slug(src.resource_name)]
		var mat: ShaderMaterial = _build(src, bounds[src], path)
		if mat:
			made[src] = mat

	# Pass 3: point the meshes at them.
	for mi: MeshInstance3D in meshes:
		for i: int in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			if made.has(src):
				mi.mesh.surface_set_material(i, made[src])

	return scene


func _build(src: Material, height: Vector2, path: String) -> ShaderMaterial:
	var mat: ShaderMaterial = null
	if ResourceLoader.exists(path):
		mat = load(path) as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
	mat.shader = SHADER

	var base: BaseMaterial3D = src as BaseMaterial3D
	if base:
		mat.set_shader_parameter(&"albedo_texture", base.albedo_texture)
		mat.set_shader_parameter(&"albedo_color", base.albedo_color)
		mat.set_shader_parameter(&"roughness", base.roughness)
		var glow: bool = base.emission_enabled
		mat.set_shader_parameter(&"emission_color", base.emission if glow else Color.BLACK)
		mat.set_shader_parameter(&"emission_energy", base.emission_energy_multiplier if glow else 1.0)
		mat.set_shader_parameter(&"emission_texture", base.emission_texture if glow else null)
	mat.set_shader_parameter(&"bounds_bottom", height.x)
	mat.set_shader_parameter(&"bounds_top", height.y)

	# Fill any tuning knob not set yet, so a new (or older) .tres shows real
	# values rather than nulls. Spelled out here because the shader can't report
	# its defaults when importing headless.
	for knob: StringName in TUNING_DEFAULTS:
		if mat.get_shader_parameter(knob) == null:
			mat.set_shader_parameter(knob, TUNING_DEFAULTS[knob])

	var err: Error = ResourceSaver.save(mat, path, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		push_error("WindSway import: could not save %s (error %d)" % [path, err])
		return null
	return mat


func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D and (root as MeshInstance3D).mesh:
		out.append(root as MeshInstance3D)
	for child: Node in root.get_children():
		out.append_array(_mesh_instances(child))
	return out


## "Ucupaint button-mushrooms" -> "ucupaint-button-mushrooms"
func _slug(text: String) -> String:
	var s: String = text.strip_edges().to_lower().replace(" ", "-")
	for bad: String in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "."]:
		s = s.replace(bad, "-")
	return s if not s.is_empty() else "material"
