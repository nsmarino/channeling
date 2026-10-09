extends InteractionStep
class_name WaitStep

## A pause in the sequence — let a camera move breathe, or a sound land.

@export var seconds: float = 0.5


func run(_interaction: Interaction) -> void:
	await get_tree().create_timer(seconds).timeout
