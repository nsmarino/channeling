extends Control

@onready var prompt_label: Label = $PanelContainer/MarginContainer/PromptLabel


func _ready() -> void:
	hide()
	Events.dialogue_prompt_requested.connect(_on_dialogue_prompt_requested)
	Events.dialogue_prompt_cleared.connect(_on_dialogue_prompt_cleared)
	Events.dialogue_started.connect(_on_dialogue_started)
	Events.dialogue_ended.connect(_on_dialogue_ended)


func _on_dialogue_prompt_requested(content: String) -> void:
	prompt_label.text = content
	show()


func _on_dialogue_prompt_cleared() -> void:
	hide()


func _on_dialogue_started(_dialogue_config: DialogueConfig) -> void:
	hide()


func _on_dialogue_ended() -> void:
	# Prompt visibility is managed by triggers while the player is in range.
	pass
