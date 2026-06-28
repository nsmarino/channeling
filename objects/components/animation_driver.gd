extends Node
class_name AnimationDriver

## Drives a keyframed AnimationPlayer through the same set_active(bool) lifecycle
## that FseDestructible broadcasts. Use this instead of a MovementComponent when
## an obstacle/enemy's motion is hand-keyframed (e.g. a one-off zig-zag) rather
## than procedural.
##
## On activate: plays `play_on_active` from the start.
## On deactivate (PASSED / DYING): pauses (or stops) so off-screen / dead bodies
## don't keep animating.
##
## NOTE: don't combine with a MovementComponent on the same body — both write the
## body transform and will fight. Pick one per destructible.

## AnimationPlayer to drive. If empty, the first AnimationPlayer found under the
## parent is used.
@export var animation_player_path: NodePath
## Animation played (from the start) when the parent becomes ACTIVE.
@export var play_on_active: StringName = &""
## Playback speed scale.
@export var speed_scale: float = 1.0
## When deactivated: pause (keep current pose) if true, else stop (reset).
@export var pause_on_inactive: bool = true

var _ap: AnimationPlayer = null
var _active: bool = false


func _ready() -> void:
	if animation_player_path != NodePath() and has_node(animation_player_path):
		_ap = get_node(animation_player_path) as AnimationPlayer
	else:
		_ap = _find_animation_player(get_parent())
	if not _ap:
		push_warning("[AnimationDriver] No AnimationPlayer found.")


func set_active(active: bool) -> void:
	_active = active
	if not _ap:
		return
	if active:
		_ap.speed_scale = speed_scale
		if play_on_active != &"":
			# A specific clip was requested; only play if it actually exists.
			if _ap.has_animation(play_on_active):
				_ap.play(play_on_active)
			else:
				push_warning("[AnimationDriver] Animation '%s' not found on %s." % [play_on_active, _ap.name])
		elif _ap.current_animation != "":
			# No clip named — resume whatever is current (autoplay/assigned).
			_ap.play()
	else:
		if pause_on_inactive:
			_ap.pause()
		else:
			_ap.stop()


## Depth-first search for the first AnimationPlayer under `node`.
func _find_animation_player(node: Node) -> AnimationPlayer:
	if not node:
		return null
	for child in node.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var found: AnimationPlayer = _find_animation_player(child)
		if found:
			return found
	return null
