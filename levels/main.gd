extends Node3D

## Main scene controller — registers navigator and overworld with GameManager.

@onready var navigator: CharacterBody3D = $Level/Rail/RailFollow/PlayerRoot/Navigator
@onready var level: Node3D = $Level


func _ready() -> void:
	Events.player_killed.connect(_on_player_killed)
	_register_with_game_manager()


func _register_with_game_manager() -> void:
	await get_tree().process_frame

	if GameManager:
		GameManager.register_navigator(navigator)
		GameManager.register_overworld(level)
		print("[Main] Registered navigator, overworld, and lighting with GameManager")
	else:
		push_error("[Main] GameManager autoload not found!")


func _on_player_killed() -> void:
	get_tree().quit()
