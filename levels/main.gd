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

@export_group("Portal transition")
## Seconds to fade to black before a portal swaps the location (0 = cut).
@export var travel_fade_out: float = 0.3
## Seconds to hold on black after the swap — lets the new location settle.
@export var travel_hold: float = 0.15
## Seconds to fade back in on the new location.
@export var travel_fade_in: float = 0.4

var location: Node3D = null
# A portal trip is in progress (fading / swapping). Ignores further travel calls.
var _traveling: bool = false

# Harness defaults, restored when a location doesn't override them.
@onready var _world_environment: WorldEnvironment = get_node_or_null(^"WorldEnvironment") as WorldEnvironment
@onready var _music_player: AudioStreamPlayer = get_node_or_null(^"AudioStreamPlayer") as AudioStreamPlayer
var _default_environment: Environment = null
var _default_music: AudioStream = null


func _ready() -> void:
	if _world_environment:
		_default_environment = _world_environment.environment
	if _music_player:
		_default_music = _music_player.stream
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


## Fade to black, swap the location while the screen is dark, fade back in. The
## player is held (a scripted move, so no input, gravity or drift) from the first
## frame of the fade until the new location is showing, so it can't walk off or
## fall while nothing is visible.
func _travel(scene_path: String, spawn_name: StringName) -> void:
	if _traveling:
		return
	var scene := load(scene_path) as PackedScene
	if not scene:
		push_error("[Main] Portal target %s is not a scene." % scene_path)
		return
	_traveling = true
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	var held: bool = player != null and bool(player.call("begin_scripted_move", self))

	if travel_fade_out > 0.0:
		await Cinematic.fade_out(travel_fade_out).finished
	GameManager.record_travel(scene_path, spawn_name)

	if location:
		remove_child(location)
		location.queue_free()
		location = null
	_add_location(scene)

	if is_instance_valid(player):
		_place_at_spawn(player, spawn_name)
	if location:
		GameManager.register_overworld(location)

	if travel_hold > 0.0:
		await get_tree().create_timer(travel_hold).timeout
	if held and is_instance_valid(player):
		player.call("end_scripted_move", self)
	if travel_fade_in > 0.0:
		await Cinematic.fade_in(travel_fade_in).finished
	else:
		Cinematic.clear_fade()
	_traveling = false


## A restart mid-trip frees Main while the screen is black; Cinematic outlives it,
## so clear the fade or the reloaded scene starts in darkness.
func _exit_tree() -> void:
	if _traveling:
		Cinematic.clear_fade()


func _add_location(scene: PackedScene) -> void:
	location = scene.instantiate() as Node3D
	if not location:
		push_error("[Main] %s does not have a Node3D root." % scene.resource_path)
		return
	add_child(location)
	_apply_location_overrides()
	print("[Main] Loaded location: %s" % scene.resource_path)


## Apply the loaded location's overrides (see Location), or restore the harness
## defaults where it sets none — a plain Node3D root gets all defaults.
func _apply_location_overrides() -> void:
	var loc := location as Location
	if _world_environment:
		_world_environment.environment = loc.environment if loc and loc.environment else _default_environment
	if _music_player:
		var track: AudioStream = loc.music if loc and loc.music else _default_music
		if _music_player.stream != track:
			_music_player.stream = track
			if track:
				_music_player.play()
	if GameManager:
		GameManager.fall_limit_y = loc.fall_limit_y if loc and loc.override_fall_limit else GameManager.default_fall_limit_y


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
