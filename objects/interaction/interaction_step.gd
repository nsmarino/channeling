extends Node
class_name InteractionStep

## One beat of an Interaction: a line of dialogue, a camera move, a sound, a flag.
##
## Steps are children of an Interaction and run top to bottom; the Interaction
## awaits each one's `run()` before starting the next, so a step that should hold
## the sequence (a line waiting for the player, a camera blend) simply awaits
## inside `run()`, and one that shouldn't returns immediately.
##
## To add a new kind of beat, extend this and override `run()`.

## Untick to skip this step without deleting it — handy while iterating.
@export var enabled: bool = true


## Do the beat. Await inside to hold the sequence until it's done.
func run(_interaction: Interaction) -> void:
	pass
