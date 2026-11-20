@tool
extends RefCounted
class_name VSGltfExport

## glTF writer for the painted meshes (`.glb` or `.gltf`)

static func write(_targets: Array, _path: String, _material_for := Callable()) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


static func _node_xform(mi: MeshInstance3D) -> Transform3D:
	if mi == null:
		return Transform3D.IDENTITY
	return mi.global_transform if mi.is_inside_tree() else mi.transform
