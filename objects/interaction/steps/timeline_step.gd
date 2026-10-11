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

## To keep a camera aimed at something — a focus point, an actor — give the
## camera a LookAtTarget child. (This step used to offer a one-shot aim at clip
## start; LookAtTarget does it continuously, which is what "focus" implies.)


## Previewing a clip in the editor really sets the properties it animates, so a
## scene saved mid-preview can ship with a timeline camera stuck `current = true`
## — and that camera takes over the view as soon as the location loads. A RESET
## animation prevents it (the editor restores RESET values before saving); this
## catches a timeline without one.
func _ready() -> void:
	_check_saved_cameras.call_deferred()


func _check_saved_cameras() -> void:
	var ap := get_node_or_null(animation_player) as AnimationPlayer
	for cam: Camera3D in _keyed_cameras():
		if not cam.current:
			continue
		push_warning("[TimelineStep] %s: '%s' was saved as current, so it took over the view on load. Add a RESET animation to '%s' that keys it false." % [name, cam.name, ap.name])
		var player: Node = get_tree().get_first_node_in_group(&"player")
		var player_cam: Camera3D = player.call("get_camera") as Camera3D if player and player.has_method("get_camera") else null
		if player_cam:
			player_cam.make_current()
		else:
			cam.current = false


## Cameras the clip switches on and off (tracks keying `current`).
func _keyed_cameras() -> Array[Camera3D]:
	var cams: Array[Camera3D] = []
	var ap := get_node_or_null(animation_player) as AnimationPlayer
	if ap == null or not ap.has_animation(animation):
		return cams
	var anim: Animation = ap.get_animation(animation)
	var root: Node = ap.get_node_or_null(ap.root_node)
	if root == null:
		return cams
	for i: int in anim.get_track_count():
		var path: NodePath = anim.track_get_path(i)
		if path.get_concatenated_subnames() != "current":
			continue
		var cam := root.get_node_or_null(NodePath(path.get_concatenated_names())) as Camera3D
		if cam:
			cams.append(cam)
	return cams


func run(interaction: Interaction) -> void:
	var ap := get_node_or_null(animation_player) as AnimationPlayer
	if ap == null or not ap.has_animation(animation):
		push_warning("[TimelineStep] %s: no clip '%s' on '%s'." % [name, animation, animation_player])
		return
	if ap.get_animation(animation).loop_mode != Animation.LOOP_NONE:
		push_warning("[TimelineStep] %s: '%s' loops and would never end — not playing it." % [name, animation])
		return
	# If this clip takes the view off the player, the Interaction's camera_enter
	# shapes that first cut: a fade covers it, a blend sweeps the new camera in.
	var entering: bool = interaction.is_entering_camera() and not _keyed_cameras().is_empty()
	if entering:
		await interaction.begin_camera_switch()
	ap.play(animation)
	if entering:
		# Apply the clip's first keys NOW so its camera is current before we look.
		# (Waiting a process_frame isn't enough: that signal fires before nodes
		# process, so the AnimationPlayer hasn't applied anything yet.)
		ap.advance(0.0)
		# Not awaited: the clip keeps playing under the fade-in / blend. FOV is
		# left to the clip, which may be animating it.
		interaction.end_camera_switch(false)
	await ap.animation_finished
