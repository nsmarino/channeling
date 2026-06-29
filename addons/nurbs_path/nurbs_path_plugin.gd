@tool
extends EditorPlugin

## Registers the NurbsPath3D viewport gizmo and adds Shift+Left-click in the 3D
## viewport to append a control point (raycast onto a horizontal plane at the
## last point's height). Drag existing points with their handles; remove points
## via the Inspector's `control_points` array for now.

const NurbsGizmo := preload("res://addons/nurbs_path/nurbs_path_gizmo.gd")
const NurbsScript := preload("res://addons/nurbs_path/nurbs_path_3d.gd")

var _gizmo_plugin: EditorNode3DGizmoPlugin
var _editing: Node3D = null


func _enter_tree() -> void:
	_gizmo_plugin = NurbsGizmo.new(self)
	add_node_3d_gizmo_plugin(_gizmo_plugin)


func _exit_tree() -> void:
	remove_node_3d_gizmo_plugin(_gizmo_plugin)
	_gizmo_plugin = null


func _handles(object: Object) -> bool:
	return _is_nurbs(object)


func _edit(object: Object) -> void:
	_editing = object as Node3D


func _make_visible(visible: bool) -> void:
	if not visible:
		_editing = null


static func _is_nurbs(object: Object) -> bool:
	return object is Node3D and object.get_script() == NurbsScript


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	var node: Variant = _editing
	if node == null or not _is_nurbs(node):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed:
		_add_point(node, camera, event.position)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Append a control point where the click ray meets a horizontal plane at the
## last point's height (node origin height when empty). Drag it afterward to
## raise/lower it.
func _add_point(node: Variant, camera: Camera3D, screen_pos: Vector2) -> void:
	var before: Array = node.control_points.duplicate()
	var gt: Transform3D = node.global_transform
	var height := gt.origin.y
	if before.size() > 0:
		height = (gt * (before[before.size() - 1] as Vector3)).y
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, height).intersects_ray(from, dir)
	if hit == null:
		return
	var after: Array = before.duplicate()
	after.append(gt.affine_inverse() * (hit as Vector3))
	var ur := get_undo_redo()
	ur.create_action("Add NURBS control point")
	ur.add_do_property(node, "control_points", after)
	ur.add_undo_property(node, "control_points", before)
	ur.commit_action()
