extends Node3D
class_name ActorDriver

## Puppets an actor — an enemy, an NPC, the player — by copying this node's
## position and/or facing onto it while `driving` is on. Parent it to a
## PathFollow3D and key the follower's progress in a timeline to walk the actor
## along a path; key `driving` on at the start and off at the end.
##
## WHY NOT A RemoteTransform3D. A RemoteTransform pushes for as long as it exists,
## so it pins its target to the path before the cutscene and after it — an awake
## enemy gets dragged back. `driving` is off by default and only the timeline
## turns it on. It also knows the player's rule that the BODY never rotates:
## facing goes to whatever the actor reports from `get_facing_node()` (the
## player's Model), and to the actor itself otherwise.
##
## The actor must not be moving itself meanwhile: an enemy asleep in MANUAL
## activation, or the player held by `Interaction.puppet_player`.

## Copy position and facing while on. Key this in the timeline.
@export var driving: bool = false:
	set(value):
		driving = value
		if driving and is_inside_tree():
			_apply()
## The actor to drive.
@export var actor: NodePath
## Or: drive the first node in this group (e.g. "player") — for actors a
## cutscene scene can't reach by path. Used when `actor` is empty.
@export var actor_group: StringName = &""
## Copy this node's position onto the actor.
@export var drive_position: bool = true
## Turn the actor (yaw only) to face along this node's -Z.
@export var drive_facing: bool = true


func _ready() -> void:
	# Fires whenever our GLOBAL transform changes — including when the parent
	# PathFollow3D moves — so the actor follows in the same frame.
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and driving:
		_apply()


func get_actor() -> Node3D:
	if not actor.is_empty():
		return get_node_or_null(actor) as Node3D
	if not actor_group.is_empty():
		return get_tree().get_first_node_in_group(actor_group) as Node3D
	return null


func _apply() -> void:
	var target: Node3D = get_actor()
	if target == null:
		return
	if drive_position:
		target.global_position = global_position
	if drive_facing:
		var forward: Vector3 = -global_basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			return
		var facing: Node3D = target
		if target.has_method("get_facing_node"):
			facing = target.call("get_facing_node") as Node3D
		if facing:
			var rot: Vector3 = facing.global_rotation
			facing.global_rotation = Vector3(rot.x, atan2(-forward.x, -forward.z), rot.z)
