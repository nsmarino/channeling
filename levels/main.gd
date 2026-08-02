extends Node3D

## Main scene controller — registers the player and level root with GameManager.

## Optional. `get_node_or_null` rather than `$Level` because renaming or removing
## this node in the scene should not take the whole boot down — GameManager only
## stores the reference, nothing reads it.
@onready var level: Node3D = get_node_or_null(^"Level") as Node3D


func _ready() -> void:
	_register_with_game_manager()


func _register_with_game_manager() -> void:
	await get_tree().process_frame

	if not GameManager:
		push_error("[Main] GameManager autoload not found!")
		return

	var player: Node = get_tree().get_first_node_in_group("player")
	if player is CharacterBody3D:
		GameManager.register_navigator(player)
	if level:
		GameManager.register_overworld(level)
	print("[Main] Registered player and level with GameManager")
