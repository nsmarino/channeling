@tool
extends EditorNode3DGizmoPlugin

## Viewport gizmo for NurbsPath3D: draws the control polygon + a draggable handle
## per control point. Dragging moves a point on a plane facing the camera, which
## triggers the node's rebuild so the rail updates live. Undo/redo is wired
## through the owning EditorPlugin's UndoRedo.
##
## The node is held as Variant and accessed dynamically so this script never
## depends on the NurbsPath3D class_name being registered at parse time (the
## class-cache lag noted in CLAUDE.md). Identity is matched by script resource.

const NurbsScript := preload("res://addons/nurbs_path/nurbs_path_3d.gd")

var _plugin: EditorPlugin


func _init(plugin: EditorPlugin = null) -> void:
	_plugin = plugin
	create_material("polygon", Color(0.35, 0.8, 1.0))
	create_handle_material("handles")


func _get_gizmo_name() -> String:
	return "NurbsPath3D"


func _has_gizmo(node: Node3D) -> bool:
	return node.get_script() == NurbsScript


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node: Variant = gizmo.get_node_3d()
	var pts: Array = node.control_points

	if pts.size() >= 2:
		var lines := PackedVector3Array()
		for i in range(pts.size() - 1):
			lines.append(pts[i])
			lines.append(pts[i + 1])
		if node.closed:
			lines.append(pts[pts.size() - 1])
			lines.append(pts[0])
		gizmo.add_lines(lines, get_material("polygon", gizmo))

	if pts.size() > 0:
		var handles := PackedVector3Array()
		var ids := PackedInt32Array()
		for i in range(pts.size()):
			handles.append(pts[i])
			ids.append(i)
		gizmo.add_handles(handles, get_material("handles", gizmo), ids)


func _get_handle_name(_gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	return "Control point %d" % id


func _get_handle_value(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> Variant:
	var node: Variant = gizmo.get_node_3d()
	return node.control_points[id]


func _set_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, camera: Camera3D, point: Vector2) -> void:
	var node: Variant = gizmo.get_node_3d()
	var gt: Transform3D = node.global_transform
	var from := camera.project_ray_origin(point)
	var dir := camera.project_ray_normal(point)
	# Drag on a plane through the point, facing the camera (free screen-plane move).
	var cp_world: Vector3 = gt * node.control_points[id]
	var plane := Plane(-camera.global_transform.basis.z, cp_world)
	var hit: Variant = plane.intersects_ray(from, dir)
	if hit == null:
		return
	var pts: Array = node.control_points.duplicate()
	pts[id] = gt.affine_inverse() * (hit as Vector3)
	node.control_points = pts  # setter rebuilds the curve + redraws the gizmo


func _commit_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var node: Variant = gizmo.get_node_3d()
	if cancel:
		var reverted: Array = node.control_points.duplicate()
		reverted[id] = restore
		node.control_points = reverted
		return
	# Current value was applied live during the drag; record it for undo/redo.
	var after: Array = node.control_points.duplicate()
	var before: Array = after.duplicate()
	before[id] = restore
	var ur := _plugin.get_undo_redo()
	ur.create_action("Move NURBS control point")
	ur.add_do_property(node, "control_points", after)
	ur.add_undo_property(node, "control_points", before)
	ur.commit_action()
