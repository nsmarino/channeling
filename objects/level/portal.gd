extends Area3D
class_name Portal

## A doorway to another location. Walk into it and Main swaps the active location
## for `target_scene`, arriving at the spawn named `target_spawn`.
##
## WHY A FILE PATH, NOT A PackedScene. Two locations that link to each other would
## each hold a PackedScene of the other, and loading either would load both,
## forever — a cyclic resource load. A path is resolved only when the player
## actually walks through.
##
## SPAWNS ARE LOOKED UP BY NAME, anywhere in the target location, so a location can
## have as many entry points as it has portals: name a Marker3D "FromCave" and
## point the cave's portal at "FromCave". The marker's -Z is the way the player
## faces on arrival — aim it AWAY from the return portal.
##
## ARMING. A portal ignores the player until it has seen them OUTSIDE it, so a
## spawn placed inside (or overlapping) a return portal can't bounce you straight
## back. Area overlaps are only populated after the first physics step, so "outside"
## means absent for a couple of consecutive frames, not merely on the first one.
##
## Polled rather than signal-driven, matching TriggerRegion.

## The location this portal leads to.
@export_file("*.tscn") var target_scene: String = ""
## Name of the node in the target location to arrive at (a Marker3D, by convention).
@export var target_spawn: StringName = &"PlayerSpawn"
## Group a body must belong to to use the portal.
@export var target_group: StringName = &"player"

## Consecutive frames the player must be absent before the portal arms.
const ARM_FRAMES: int = 2

var _armed: bool = false
var _absent_frames: int = 0


func _ready() -> void:
	monitoring = true
	var label := get_node_or_null(^"Label3D") as Label3D
	if label:
		label.text = "→ %s\n%s" % [target_scene.get_file().get_basename(), target_spawn]


func _physics_process(_delta: float) -> void:
	var player: Node3D = _find_target()
	if player == null:
		_absent_frames += 1
		if _absent_frames >= ARM_FRAMES:
			_armed = true
		return
	_absent_frames = 0
	if not _armed:
		return
	# Something owns the player's transform (a Power Dive, being swallowed). Its
	# owner may live in THIS location and be freed by the swap, leaving the player
	# frozen with nobody to release them — so don't travel mid-move.
	if player.has_method("is_scripted_move_claimed") and bool(player.call("is_scripted_move_claimed")):
		return
	_travel()


func _travel() -> void:
	if target_scene.is_empty():
		push_warning("[Portal] %s has no target_scene." % name)
		_armed = false
		return
	var main: Node = get_tree().current_scene
	if not main.has_method("travel"):
		push_warning("[Portal] Current scene can't travel — run main.tscn.")
		_armed = false
		return
	_armed = false
	main.call("travel", target_scene, target_spawn)


func _find_target() -> Node3D:
	for body: Node3D in get_overlapping_bodies():
		if body.is_in_group(target_group):
			return body
	return null
