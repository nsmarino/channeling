extends Node

## Holds scene references for active systems (the player navigator, level roots)
## and owns level restart — triggered by player death, falling off the map, or
## the `Restart` input action (R / gamepad Back).
##
## Lives in an autoload so it survives `reload_current_scene()`; the reloaded
## scene re-registers its navigator via `register_navigator`.

## Written by the Play From Here editor plugin (addons/play_from_here) with a
## world position, immediately before it runs the scene. Consumed and deleted
## here on startup, so a normal run is never affected by a stale file.
const PLAY_FROM_HERE_FILE: String = "user://play_from_here.cfg"

## Restart the current scene when the registered navigator drops below this Y.
@export var fall_limit_y: float = -50.0
## Disable to opt out of the fall-off-map check (e.g. for a flying player).
@export var fall_check_enabled: bool = true

var navigator: CharacterBody3D = null
var overworld_root: Node = null
var overworld_lighting: Node = null

# Guards against re-triggering a restart while the scene is reloading.
var _restart_pending: bool = false

# Play From Here override, held for the whole session (see _consume_spawn_override).
var _spawn_override: Vector3 = Vector3.ZERO
var _has_spawn_override: bool = false


func _ready() -> void:
	print("[GameManager] Initialized")
	_consume_spawn_override()
	Events.player_killed.connect(restart_level)


## Pick up a Play From Here point, if the editor plugin left one.
##
## Deleted immediately but kept in memory for the rest of the process. Both halves
## of that matter: deleting means the next ordinary run spawns normally, and
## keeping it means DYING PUTS YOU BACK WHERE YOU WERE TESTING rather than at the
## level start — which is the whole point of playing from a spot.
func _consume_spawn_override() -> void:
	if not FileAccess.file_exists(PLAY_FROM_HERE_FILE):
		return

	var cfg := ConfigFile.new()
	if cfg.load(PLAY_FROM_HERE_FILE) == OK:
		_spawn_override = cfg.get_value("spawn", "position", Vector3.ZERO)
		_has_spawn_override = true
		print("[GameManager] Play From Here: spawning at %s" % str(_spawn_override))

	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(PLAY_FROM_HERE_FILE.get_file())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart"):
		restart_level()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not fall_check_enabled or _restart_pending:
		return
	if is_instance_valid(navigator) and navigator.global_position.y < fall_limit_y:
		restart_level()


## Reload the current scene from scratch. Safe to call from multiple sources in
## the same frame — only the first call in a reload cycle takes effect. The reload
## is deferred so it's safe to trigger from inside a physics callback (e.g. a
## projectile's body_entered killing the player), which otherwise errors on
## removing CollisionObject nodes mid-callback.
func restart_level() -> void:
	if _restart_pending:
		return
	_restart_pending = true
	navigator = null
	get_tree().call_deferred(&"reload_current_scene")


func register_navigator(nav: CharacterBody3D) -> void:
	navigator = nav
	_restart_pending = false
	# Applied on every registration, not just the first, so it survives restarts.
	if _has_spawn_override:
		nav.global_position = _spawn_override
		nav.velocity = Vector3.ZERO
	print("[GameManager] Navigator registered: %s" % nav.name)


func register_overworld(overworld: Node) -> void:
	overworld_root = overworld
	print("[GameManager] Overworld registered: %s" % overworld.name)
