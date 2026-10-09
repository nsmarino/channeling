extends InteractionStep
class_name AnimationStep

## Play a clip on an AnimationPlayer — an NPC's gesture, a door swinging open.

@export var animation_player: NodePath
@export var animation: StringName = &""
## Hold the sequence until the clip ends. Looping clips never end — leave this off
## for them.
@export var wait_for_finish: bool = false


func run(_interaction: Interaction) -> void:
	var ap := get_node_or_null(animation_player) as AnimationPlayer
	if ap == null or not ap.has_animation(animation):
		push_warning("[AnimationStep] %s: no clip '%s' on '%s'." % [name, animation, animation_player])
		return
	ap.play(animation)
	if wait_for_finish:
		await ap.animation_finished
