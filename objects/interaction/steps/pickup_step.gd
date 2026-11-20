extends InteractionStep
class_name PickupStep

## Takes a key item: adds `item` to the Inventory, sets a flag, and removes the
## item's scene from the world.
##
## The scene is HIDDEN (and stops blocking) at once but only FREED once the
## Interaction finishes. The Interaction is a child of that scene; freeing it
## mid-sequence would skip any steps after this one ("It's warm in your hand…")
## and snap the camera back instead of blending.
##
## The flag (`got_<id>` by default) keeps it gone: on load, a PickupStep whose
## flag is already set frees its scene, so the item doesn't reappear after a
## restart or a portal round trip — even once it has been given away and is no
## longer in the inventory.

## The item to take.
@export var item: KeyItem
## The scene to remove ("" = the Interaction's parent, the item scene's root).
@export var item_root: NodePath
## Flag set on pickup and checked on load ("" = got_<item id>).
@export var got_flag: StringName = &""


func _ready() -> void:
	if GameManager.has_flag(_flag()):
		var root: Node = _root()
		if root:
			root.queue_free.call_deferred()


func run(interaction: Interaction) -> void:
	if item == null:
		push_warning("[PickupStep] %s: no KeyItem set." % get_path())
		return
	Inventory.add(item)
	GameManager.set_flag(_flag())
	var root: Node = _root()
	if root == null:
		return
	if root is Node3D:
		(root as Node3D).visible = false
	if root is CollisionObject3D:
		# Stop blocking now. Layer, not process_mode: disabling the root would
		# also pause the running Interaction's tweens (its camera blend back).
		(root as CollisionObject3D).set_deferred(&"collision_layer", 0)
	interaction.finished.connect(root.queue_free, CONNECT_ONE_SHOT)


func _flag() -> StringName:
	if not got_flag.is_empty():
		return got_flag
	if item and not item.id.is_empty():
		return StringName("got_%s" % item.id)
	return &""


func _root() -> Node:
	if not item_root.is_empty():
		return get_node_or_null(item_root)
	var interaction: Node = get_parent()
	return interaction.get_parent() if interaction else null
