extends Control

## "Press [E] to talk" — shown while the player stands in an Interaction's range.
## Ported from Nightbloom v1. The Interaction decides when; this only listens.


@onready var prompt_label: Label = $PanelContainer/MarginContainer/PromptLabel


func _ready() -> void:
	hide()
	Events.interaction_prompt_shown.connect(_on_prompt_shown)
	Events.interaction_prompt_hidden.connect(hide)
	Events.interaction_started.connect(_on_interaction_started)


func _on_prompt_shown(text: String) -> void:
	prompt_label.text = text
	show()


func _on_interaction_started(_interaction: Node) -> void:
	hide()
