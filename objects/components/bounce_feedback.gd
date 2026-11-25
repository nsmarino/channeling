extends Node

## Game-feel for a bounce pad's body (the mushroom), so it reads as interactive:
##  - WIGGLE: a short, decaying tilt toward the player when they first come
##    near. Not a loop — it fires once, and re-arms only after they've walked
##    back out past `wiggle_rearm_radius`.
##  - BOUNCE: when the pad fires, a squash-and-stretch on the model (down first,
##    overshoot up, settle) and a one-shot burst effect.
##
## Both are procedural, on the model node's transform, so a proper animation
## made in Blender can replace them later by just removing this node.
##
## Plain Node with the duck-typed contract used across components: it finds its
## siblings by path in _ready and needs nothing else.

## BouncePadComponent whose `launched` signal triggers the bounce.
@export var pad_path: NodePath = ^"../BouncePad"
## Visual model to wiggle and squash. Scaled about its own origin, so that
## should be at the base.
@export var model_path: NodePath = ^"../mushroom"
## Optional burst effect played on launch (anything with a play() method,
## e.g. vfx/particles/bounce-shockwave.tscn).
@export var effect_path: NodePath = ^"../BounceShockwave"
## Optional sound played when the wiggle starts (an AudioStreamPlayer3D, or any
## player with play()). Nothing there = silent wiggle.
@export var wiggle_sound_path: NodePath = ^"../WiggleSound"

@export_group("Wiggle")
@export var wiggle_enabled: bool = true
## Horizontal distance (m) at which an approaching player sets off the wiggle.
@export_range(0.5, 15.0, 0.1) var wiggle_radius: float = 4.0
## The player must walk back out past this before it can wiggle again.
@export_range(0.5, 20.0, 0.1) var wiggle_rearm_radius: float = 6.0
## Peak tilt in degrees.
@export_range(0.0, 30.0, 0.5) var wiggle_angle: float = 7.0
## Back-and-forth swings per second.
@export_range(0.5, 15.0, 0.1) var wiggle_frequency: float = 4.5
## Seconds until it settles.
@export_range(0.1, 3.0, 0.05) var wiggle_duration: float = 0.8
## Random pitch spread on the wiggle sound (0.1 = ±10%), so repeats don't
## sound identical.
@export_range(0.0, 0.5, 0.01) var wiggle_pitch_variation: float = 0.1

@export_group("Bounce")
@export var bounce_enabled: bool = true
## How far it squashes on the first dip (0.25 = to 75% height).
@export_range(0.0, 0.8, 0.01) var squash_amount: float = 0.28
## How much it bulges sideways for each unit it squashes (keeps the volume).
@export_range(0.0, 2.0, 0.05) var squash_bulge: float = 0.6
## Down-up cycles per second.
@export_range(0.5, 10.0, 0.1) var bounce_frequency: float = 3.2
## Seconds until it settles.
@export_range(0.1, 3.0, 0.05) var bounce_duration: float = 0.9

var _model: Node3D = null
var _effect: Node = null
var _wiggle_sound: Node = null
var _wiggle_sound_pitch: float = 1.0
var _body: Node3D = null  # the mushroom root, used for distances
var _rest: Transform3D = Transform3D.IDENTITY

var _wiggle_t: float = -1.0  # < 0 = idle
var _wiggle_axis: Vector3 = Vector3.RIGHT  # in the model's parent space
var _wiggle_armed: bool = true
var _bounce_t: float = -1.0


func _ready() -> void:
	_body = get_parent() as Node3D
	_model = get_node_or_null(model_path) as Node3D
	_effect = get_node_or_null(effect_path)
	_wiggle_sound = get_node_or_null(wiggle_sound_path)
	if _wiggle_sound and "pitch_scale" in _wiggle_sound:
		_wiggle_sound_pitch = _wiggle_sound.get("pitch_scale")
	if _model:
		_rest = _model.transform
	else:
		push_warning("[BounceFeedback] No model at '%s'." % model_path)
	var pad: Node = get_node_or_null(pad_path)
	if pad and pad.has_signal("launched"):
		pad.connect("launched", _on_launched)
	else:
		push_warning("[BounceFeedback] No bounce pad at '%s'." % pad_path)


func _process(delta: float) -> void:
	if _model == null:
		return
	_check_approach()

	var angle: float = 0.0
	if _wiggle_t >= 0.0:
		_wiggle_t += delta
		var k: float = 1.0 - _wiggle_t / wiggle_duration
		if k <= 0.0:
			_wiggle_t = -1.0
		else:
			angle = deg_to_rad(wiggle_angle) * sin(TAU * wiggle_frequency * _wiggle_t) * k * k

	var squash: float = 0.0
	if _bounce_t >= 0.0:
		_bounce_t += delta
		if _bounce_t >= bounce_duration:
			_bounce_t = -1.0
		else:
			# Starts at rest, dips first (sin > 0), overshoots, dies away.
			var decay: float = exp(-4.0 * _bounce_t / bounce_duration)
			squash = squash_amount * sin(TAU * bounce_frequency * _bounce_t) * decay

	var scale: Vector3 = Vector3(1.0 + squash * squash_bulge, 1.0 - squash, 1.0 + squash * squash_bulge)
	var basis: Basis = _rest.basis * Basis.from_scale(scale)
	if angle != 0.0:
		basis = Basis(_wiggle_axis, angle) * basis
	_model.transform = Transform3D(basis, _rest.origin)


func _check_approach() -> void:
	if not wiggle_enabled or _body == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return
	var to_player: Vector3 = player.global_position - _body.global_position
	to_player.y = 0.0
	var dist: float = to_player.length()
	if dist > wiggle_rearm_radius:
		_wiggle_armed = true
	elif _wiggle_armed and dist < wiggle_radius:
		_wiggle_armed = false
		_start_wiggle(to_player)


## Tilt toward the player first: rotate about the horizontal axis at right
## angles to the direction they're coming from.
func _start_wiggle(to_player: Vector3) -> void:
	if _bounce_t >= 0.0:
		return  # mid-bounce: the squash already says plenty
	var axis_world: Vector3 = Vector3.UP.cross(to_player.normalized())
	if axis_world.length_squared() < 0.0001:
		axis_world = Vector3.RIGHT
	var parent: Node3D = _model.get_parent() as Node3D
	var axis_local: Vector3 = parent.global_basis.inverse() * axis_world if parent else axis_world
	_wiggle_axis = axis_local.normalized()
	_wiggle_t = 0.0
	_play_wiggle_sound()


func _play_wiggle_sound() -> void:
	if _wiggle_sound == null or not _wiggle_sound.has_method("play"):
		return
	if "pitch_scale" in _wiggle_sound:
		_wiggle_sound.set("pitch_scale",
				_wiggle_sound_pitch * (1.0 + randf_range(-wiggle_pitch_variation, wiggle_pitch_variation)))
	_wiggle_sound.call("play")


func _on_launched(_launched_body: Node3D) -> void:
	_wiggle_armed = false  # standing on it: don't wiggle as they come back down
	if bounce_enabled:
		_wiggle_t = -1.0
		_bounce_t = 0.0
	if _effect and _effect.has_method("play"):
		_effect.call("play")
