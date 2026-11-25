extends Node
class_name FlagDisableCollision

## Turns collision off while a GameManager flag is set: a body you can walk
## through once something has happened (a soldier fed a spore, a gate opened).
##
## State, like FlagSpawner: checked on load and on Events.flag_changed, so it
## holds after a restart or a portal trip, and clearing the flag turns the
## collision back on.
##
## `targets` can name CollisionShape3Ds (disabled one by one) or bodies/areas
## (every CollisionShape3D / CollisionPolygon3D directly under them). Empty =
## this node's parent. To stop an Interaction too, set its `unless_flag` to the
## same flag — this node only handles collision.

@export var flag: StringName = &""
## Shapes or bodies to switch off. Empty = the parent.
@export var targets: Array[NodePath] = []


func _ready() -> void:
	Events.flag_changed.connect(_on_flag_changed)
	_apply(GameManager.has_flag(flag))


func _on_flag_changed(changed: StringName, value: bool) -> void:
	if changed == flag:
		_apply(value)


func _apply(disabled: bool) -> void:
	if flag.is_empty():
		return
	var nodes: Array[Node] = []
	if targets.is_empty():
		nodes.append(get_parent())
	else:
		for path in targets:
			var n: Node = get_node_or_null(path)
			if n == null:
				push_warning("[FlagDisableCollision] No node at '%s'." % path)
			else:
				nodes.append(n)
	for n in nodes:
		if n is CollisionShape3D or n is CollisionPolygon3D:
			_set_disabled(n, disabled)
		else:
			for child in n.get_children():
				if child is CollisionShape3D or child is CollisionPolygon3D:
					_set_disabled(child, disabled)


# Deferred: flipping a shape mid physics callback (an interaction step setting
# the flag) errors otherwise.
func _set_disabled(shape: Node, disabled: bool) -> void:
	shape.set_deferred(&"disabled", disabled)
