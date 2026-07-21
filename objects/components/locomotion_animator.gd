extends Component
class_name LocomotionAnimator

## Switches an AnimationPlayer between an idle clip and a moving clip based on how
## fast the host body is actually travelling.
##
## Pairs with a MovementComponent rather than replacing it: that component owns
## the velocity, this one only *reads* it and picks a clip, so the two never fight
## over the body transform. (Contrast AnimationDriver, which fires one clip on the
## ACTIVE lifecycle edge and is meant for hand-keyframed body motion — that one
## genuinely can't share a body with a MovementComponent.)
##
## Drives the model's own skeletal loops, so it expects the AnimationPlayer that
## ships inside an imported character scene.

## AnimationPlayer to drive, relative to this component (e.g.
## "../model/AnimationPlayer"). Leave empty to auto-find the first one under the host.
@export var animation_player_path: NodePath
## Clip looped while the body is moving.
@export var move_animation: StringName = &""
## Clip looped while the body is stationary. Empty = just keep the move clip.
@export var idle_animation: StringName = &""
## Horizontal speed (units/sec) above which the body counts as moving.
@export var move_speed_threshold: float = 0.35
## Crossfade between the two clips (seconds).
@export var blend_time: float = 0.2
## Seconds the body must stay slow before idle takes over. Debounces single-frame
## stalls — e.g. the nav wander pattern pausing for a frame to re-roll its target.
@export var idle_delay: float = 0.15
## Playback speed scale.
@export var speed_scale: float = 1.0

var _ap: AnimationPlayer = null
var _body: CharacterBody3D = null
var _slow_time: float = 0.0


func _setup() -> void:
	if animation_player_path != NodePath() and has_node(animation_player_path):
		_ap = get_node(animation_player_path) as AnimationPlayer
	else:
		_ap = _find_animation_player(host)
	_body = host as CharacterBody3D
	if _ap == null:
		push_warning("[LocomotionAnimator] No AnimationPlayer found under %s." % String(host.name))
	set_physics_process(false)


func on_activate() -> void:
	if _ap:
		_ap.speed_scale = speed_scale
	_slow_time = 0.0
	set_physics_process(true)


func on_deactivate() -> void:
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _ap == null or _body == null:
		return

	# Never fight a clip we don't own — e.g. an attack the brain is playing. Backing
	# off on our own means there's no explicit "release" call for a caller to
	# forget, and nothing leaks if their coroutine is aborted mid-swing.
	if _ap.is_playing() and not _owns_clip(_ap.current_animation):
		_slow_time = 0.0
		return

	var flat := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	var moving := flat.length() >= move_speed_threshold
	_slow_time = 0.0 if moving else _slow_time + delta

	# Hold the move clip through brief stalls so it doesn't flicker to idle.
	var want: StringName = move_animation if (moving or _slow_time < idle_delay) else idle_animation
	if want == &"" or not _ap.has_animation(want):
		return
	if _ap.current_animation != String(want):
		_ap.play(want, blend_time)


## Is this one of the two locomotion clips we're responsible for?
func _owns_clip(anim: String) -> bool:
	return anim == "" or anim == String(move_animation) or anim == String(idle_animation)


## Depth-first search for the first AnimationPlayer under `node`.
func _find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	for child in node.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var found: AnimationPlayer = _find_animation_player(child)
		if found:
			return found
	return null
