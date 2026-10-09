extends InteractionStep
class_name SayStep

## Lines of dialogue from one speaker, shown one at a time in the HUD's dialogue
## box; the player advances each. Several SaySteps in a row make a conversation —
## the box stays open between them.

@export var speaker: String = ""
## Optional face shown beside the text.
@export var portrait: Texture2D
## One entry per box of text.
@export_multiline var lines: Array[String] = []


func run(interaction: Interaction) -> void:
	var box: DialogueBox = interaction.get_dialogue_box()
	if box == null:
		push_warning("[SayStep] No DialogueBox in the HUD — run main.tscn.")
		return
	await box.say(speaker, portrait, lines)
