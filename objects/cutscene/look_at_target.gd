extends Node
class_name LookAtTarget

## Child of a Camera3D: keeps the camera aimed at a node every frame while it is
## the active camera — for framing something that moves (an actor walking a
## path, or a player whose position you don't control). Moving the camera itself
## is up to its parent (parent it to a PathFollow3D for a tracking dolly).
##
## It stands aside while an Interaction is blending the camera (the camera
## carries the "interaction_blending" meta), so the blend's own rotation wins and
## the hand-back to the player's view stays smooth.

## The node to look at.
@export var target: NodePath
## Or: the first node in this group (e.g. "player"). Used when `target` is empty.
@export var target_group: StringName = &""
## Added to the target's position — aim at the chest rather than the feet.
@export var offset: Vector3 = Vector3(0.0, 1.2, 0.0)
## 0 = locked on. Higher = the camera catches up over time (a rate per second;
## ~4 is a gentle lag). The first frame the camera goes live always snaps.
@export var smoothing: float = 0.0
## Only aim while this camera is the active one.
@export var only_when_current: bool = true

var _was_live: bool = false


func _ready() -> void:
	# After AnimationPlayers and movers have placed things this frame.
	process_priority = 100


func _process(delta: float) -> void:
	var cam := get_parent() as Camera3D
	if cam == null:
		return
	if only_when_current and not cam.current:
		_was_live = false
		return
	if cam.has_meta(&"interaction_blending"):
		return
	var node: Node3D = _get_target()
	if node == null:
		return
	var point: Vector3 = node.global_position + offset
	var to_point: Vector3 = point - cam.global_position
	if to_point.length_squared() < 0.0001 or absf(to_point.normalized().y) > 0.999:
		return
	var desired: Basis = Basis.looking_at(to_point, Vector3.UP)
	if smoothing <= 0.0 or not _was_live:
		cam.global_basis = desired
	else:
		var weight: float = 1.0 - exp(-smoothing * delta)
		var from: Quaternion = cam.global_basis.get_rotation_quaternion()
		cam.global_basis = Basis(from.slerp(desired.get_rotation_quaternion(), weight))
	_was_live = true


func _get_target() -> Node3D:
	if not target.is_empty():
		return get_node_or_null(target) as Node3D
	if not target_group.is_empty():
		return get_tree().get_first_node_in_group(target_group) as Node3D
	return null
