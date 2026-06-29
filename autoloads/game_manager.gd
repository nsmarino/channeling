extends Node

## Holds scene references for active systems (the player navigator, level roots)
## and owns level restart — triggered by player death, falling off the map, or
## the `Restart` input action (R / gamepad Back).
##
## Lives in an autoload so it survives `reload_current_scene()`; the reloaded
## scene re-registers its navigator via `register_navigator`.

## Restart the current scene when the registered navigator drops below this Y.
@export var fall_limit_y: float = -50.0
## Disable to opt out of the fall-off-map check (e.g. for a flying player).
@export var fall_check_enabled: bool = true

var navigator: CharacterBody3D = null
var overworld_root: Node = null
var overworld_lighting: Node = null

# Guards against re-triggering a restart while the scene is reloading.
var _restart_pending: bool = false


func _ready() -> void:
	print("[GameManager] Initialized")
	Events.player_killed.connect(restart_level)


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
## the same frame — only the first call in a reload cycle takes effect.
func restart_level() -> void:
	if _restart_pending:
		return
	_restart_pending = true
	navigator = null
	get_tree().reload_current_scene()


func register_navigator(nav: CharacterBody3D) -> void:
	navigator = nav
	_restart_pending = false
	print("[GameManager] Navigator registered: %s" % nav.name)


func register_overworld(overworld: Node) -> void:
	overworld_root = overworld
	print("[GameManager] Overworld registered: %s" % overworld.name)
