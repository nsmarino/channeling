@tool
extends RefCounted
class_name VSExtension

## Extension system that allows Vertex Studio to paint something other MeshInstance3Ds.
##
## An extension claims a node with [method handles] and returns MeshInstance3D
## paint targets for it. Every tool works on those as usual, and the extension
## writes the painted colors back into whatever the node really renders from.
##
## Register through Vertex Studio's Engine singleton:
## [codeblock]
## if Engine.has_singleton("VertexStudio"):
##     Engine.get_singleton("VertexStudio").call("register_extension", my_ext)
## [/codeblock]
## Call "unregister_extension" the same way when your plugin exits.
##
## It's not necessary to extend this class, every call is guarded by has_method.
## A plugin should use RefCounted with the same method names.

func requires_native() -> bool:
	return false


func handles(node: Node) -> bool:
	return false


func paint_meshes(node: Node) -> Array:
	return []


func setup_material(node: Node, lit: bool) -> bool:
	return false


func restore_material(node: Node, explicit: bool) -> void:
	pass


func scene_saving(node: Node) -> bool:
	return false


func snapshot_data(node: Node, options: Dictionary) -> Variant:
	return null


func restore_data(node: Node, data: Variant) -> void:
	pass


func snapshot_options(node: Node) -> Array:
	return []


func stored_options(data: Variant) -> Dictionary:
	return {}


func colors_changed(node: Node, targets: Array, live: bool) -> void:
	pass


func view_changed(node: Node, view: Dictionary) -> void:
	pass


func tool_active_changed(node: Node, active: bool) -> void:
	pass


func supports_wireframe(node: Node) -> bool:
	return true


func supports_normals(node: Node) -> bool:
	return true
