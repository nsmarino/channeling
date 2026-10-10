extends InteractionStep
class_name TimelineStep

## Play an AnimationPlayer clip and hold the sequence until it ends — the step for
## choreography that needs exact timing: camera cuts and FOV pulls keyed on
## `current` / `fov`, an NPC walking, a stinger on an audio track. This is what a
## cutscene is made of.
##
## Unlike the old cutscene trigger, the clip needs no final "finish" key — the
## sequence moves on when the clip ends. Use AnimationStep instead for a clip you
## don't want to wait on (an NPC gesture under a line of dialogue).

@export var animation_player: NodePath
@export var animation: StringName = &""

@export_group("Aim (optional)")
## Point the cameras below at this node before playing. Pose cameras by position
## only and they stay framed wherever the instance is moved.
@export var focus: NodePath
@export var aim_cameras: Array[NodePath] = []


func run(_interaction: Interaction) -> void:
	var ap := get_node_or_null(animation_player) as AnimationPlayer
	if ap == null or not ap.has_animation(animation):
		push_warning("[TimelineStep] %s: no clip '%s' on '%s'." % [name, animation, animation_player])
		return
	if ap.get_animation(animation).loop_mode != Animation.LOOP_NONE:
		push_warning("[TimelineStep] %s: '%s' loops and would never end — not playing it." % [name, animation])
		return
	_aim_cameras()
	ap.play(animation)
	await ap.animation_finished


func _aim_cameras() -> void:
	var target := get_node_or_null(focus) as Node3D
	if target == null:
		return
	for path: NodePath in aim_cameras:
		var cam := get_node_or_null(path) as Node3D
		if cam and cam.global_position.distance_to(target.global_position) > 0.01:
			cam.look_at(target.global_position, Vector3.UP)
