extends Node3D

## Main scene controller — loads the active location, then registers the player and
## location root with GameManager. Also swaps locations when a Portal is used.
##
## Main holds what every location shares (player, HUD, environment, music); each
## location is its own .tscn, instanced here at startup.

## The location to play. Swap it in the Inspector to test a different place.
## Play From Here and portal trips override it (see GameManager.location_override).
@export var active_scene: PackedScene

## Spawn used when nothing names one: a node with this name anywhere in the
## location. If absent, the player starts where it sits in main.tscn. Play From
## Here still wins — GameManager applies its override after this.
@export var spawn_marker_name: StringName = &"PlayerSpawn"

var location: Node3D = null


func _ready() -> void:
	var scene: PackedScene = _override_scene()
	if not scene:
		scene = active_scene
	if scene:
		_add_location(scene)
	else:
		push_warning("[Main] No active_scene assigned — running with no location.")
	_register_with_game_manager()


## Replace the current location with `scene_path`, arriving at `spawn_name`.
## Called by Portal. Deferred because a portal fires from a physics callback, and
## freeing CollisionObjects mid-callback errors.
func travel(scene_path: String, spawn_name: StringName) -> void:
	_travel.call_deferred(scene_path, spawn_name)


func _travel(scene_path: String, spawn_name: StringName) -> void:
	var scene := load(scene_path) as PackedScene
	if not scene:
		push_error("[Main] Portal target %s is not a scene." % scene_path)
		return
	GameManager.record_travel(scene_path, spawn_name)

	if location:
		remove_child(location)
		location.queue_free()
		location = null
	_add_location(scene)

	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player:
		_place_at_spawn(player, spawn_name)
	if location:
		GameManager.register_overworld(location)


func _add_location(scene: PackedScene) -> void:
	location = scene.instantiate() as Node3D
	if not location:
		push_error("[Main] %s does not have a Node3D root." % scene.resource_path)
		return
	add_child(location)
	print("[Main] Loaded location: %s" % scene.resource_path)


## The location to load instead of `active_scene`, if Play From Here or a portal
## trip set one. Ignored when it is main.tscn itself.
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
		_place_at_spawn(player as CharacterBody3D, GameManager.spawn_name_override)
		GameManager.register_navigator(player)
	if location:
		GameManager.register_overworld(location)


## Move the player to the spawn called `spawn_name`, falling back to the default
## spawn. A named spawn that doesn't exist is a broken link, so it warns.
func _place_at_spawn(player: CharacterBody3D, spawn_name: StringName) -> void:
	if not location:
		return
	var spawn: Node3D = null
	if not spawn_name.is_empty():
		spawn = location.find_child(String(spawn_name), true, false) as Node3D
		if not spawn:
			push_warning("[Main] No spawn named '%s' in %s — using '%s'."
					% [spawn_name, location.name, spawn_marker_name])
	if not spawn:
		spawn = location.find_child(String(spawn_marker_name), true, false) as Node3D
	if not spawn:
		return
	if player.has_method("place_at"):
		player.call("place_at", spawn.global_transform)
	else:
		player.global_position = spawn.global_position
		player.velocity = Vector3.ZERO
