extends Node3D

## Main scene controller — loads the active location, then registers the player and
## location root with GameManager.
##
## Main holds what every location shares (player, HUD, environment, music); each
## location is its own .tscn, instanced here at startup.

## The location to play. Swap it in the Inspector to test a different place.
## Play From Here overrides it with whichever location you clicked in.
@export var active_scene: PackedScene

## Name of an optional Marker3D directly under the location root. If present, the
## player starts there instead of where it sits in main.tscn. Play From Here still
## wins — GameManager applies its override after this.
@export var spawn_marker_name: StringName = &"PlayerSpawn"

var location: Node3D = null


func _ready() -> void:
	_load_location()
	_register_with_game_manager()


func _load_location() -> void:
	var scene: PackedScene = _override_scene()
	if not scene:
		scene = active_scene
	if not scene:
		push_warning("[Main] No active_scene assigned — running with no location.")
		return

	location = scene.instantiate() as Node3D
	if not location:
		push_error("[Main] %s does not have a Node3D root." % scene.resource_path)
		return
	add_child(location)
	print("[Main] Loaded location: %s" % scene.resource_path)


## The location Play From Here was launched from, if any. Ignored when it was
## launched from main.tscn itself — then the Inspector choice stands.
func _override_scene() -> PackedScene:
	var path: String = GameManager.location_override if GameManager else ""
	if path.is_empty() or path == scene_file_path:
		return null
	return load(path) as PackedScene


func _register_with_game_manager() -> void:
	await get_tree().process_frame

	if not GameManager:
		push_error("[Main] GameManager autoload not found!")
		return

	var player: Node = get_tree().get_first_node_in_group("player")
	if player is CharacterBody3D:
		_place_at_spawn(player as CharacterBody3D)
		GameManager.register_navigator(player)
	if location:
		GameManager.register_overworld(location)


func _place_at_spawn(player: CharacterBody3D) -> void:
	if not location:
		return
	var marker := location.get_node_or_null(NodePath(spawn_marker_name)) as Marker3D
	if marker:
		player.global_position = marker.global_position
		player.velocity = Vector3.ZERO
