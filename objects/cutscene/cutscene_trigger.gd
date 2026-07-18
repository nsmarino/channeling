extends Area3D

## Reusable cutscene trigger. When the player walks into this Area3D it raises the
## letterbox (Cinematic.begin) and plays a local AnimationPlayer timeline — the
## spine of the cutscene: camera cuts/moves on property tracks, story beats on
## Call-Method tracks, stingers on audio tracks.
##
## Wire the timeline's *final* Call-Method key to this node's `finish()` (or call
## `Cinematic.end()` directly) so control returns when the beats are done.
##
## The Area3D masks the player layer (2) so only the player fires it. Authoring the
## cameras + animation is done in the level (see ExampleCutscene.tscn); this script
## is just the reusable start/stop plumbing.

## Animation to play on the referenced AnimationPlayer.
@export var animation_name: StringName = &"intro"
## AnimationPlayer holding the cutscene timeline.
@export var animation_player_path: NodePath = ^"AnimationPlayer"
## Letterbox bar height for this cutscene (-1 = the Cinematic autoload default).
@export var letterbox_height: float = -1.0
## Play at most once. Off = re-triggers every time the player enters.
@export var one_shot: bool = true

@export_group("Aim (optional)")
## Point of interest the cutscene cameras look at. Leave empty to pose cameras
## by hand in the editor instead.
@export var focus_path: NodePath
## Cameras aimed at `focus_path` on ready. Placement-robust — pose only position;
## the aim is computed at runtime, so moving the whole instance keeps it framed.
@export var aim_cameras: Array[NodePath] = []

var _anim: AnimationPlayer = null
var _played: bool = false


func _ready() -> void:
	_anim = get_node_or_null(animation_player_path) as AnimationPlayer
	_aim_cameras_at_focus()
	body_entered.connect(_on_body_entered)


## Orient each listed camera at the focus point (once, on ready).
func _aim_cameras_at_focus() -> void:
	var focus := get_node_or_null(focus_path) as Node3D
	if focus == null:
		return
	for cam_path in aim_cameras:
		var cam := get_node_or_null(cam_path) as Node3D
		if cam != null and cam.global_position.distance_to(focus.global_position) > 0.01:
			cam.look_at(focus.global_position, Vector3.UP)


func _on_body_entered(body: Node) -> void:
	if _played and one_shot:
		return
	if not body.is_in_group("player"):
		return
	play()


## Start the cutscene now (also callable directly, without the trigger volume).
func play() -> void:
	_played = true
	Cinematic.begin(letterbox_height)
	if _anim != null and _anim.has_animation(animation_name):
		_anim.play(animation_name)
	else:
		push_warning("[CutsceneTrigger] No animation '%s'; ending immediately." % animation_name)
		finish()


## Drop the letterbox and hand control back. Call this from the timeline's final
## Call-Method key (or let a bare AnimationPlayer's `animation_finished` do it).
func finish() -> void:
	Cinematic.end()
