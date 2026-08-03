extends Component
class_name ModelSwayComponent

## Leans a character's model into its movement, wobbles very slightly while doing
## it, and breathes gently when standing still. Pure garnish — it never moves the
## body, only the visual child, so it cannot affect collision, aim or hit
## detection.
##
## WHO OWNS WHAT. Two other things already write this node's transform every
## frame, and this component is built to touch neither:
##
##   - `Model.rotation.y` is FACING, owned by player.gd and snapped by the Power
##     Dive and the dash. This writes ONLY `.x` and `.z`. Because each writer
##     reads the current Vector3 and replaces one component, the two compose
##     without either knowing about the other.
##
##   - `Model.position` is owned by HitReactComponent, which reassigns it every
##     frame as `rest + extra_offset + shake`. A position written here would be
##     silently discarded on the next frame — so the bob is published through that
##     component's `extra_offset`, which is precisely what it exists for. Bob and
##     hit-shake then ADD instead of fighting, and a hit still reads while idling.
##
## The lean is computed in the MODEL'S LOCAL FRAME rather than in world space. That
## matters because the model usually turns to face where it is going, which would
## make every lean a forward lean — but while locked on it faces the target and
## strafes sideways, and that is exactly when a roll into the turn is worth seeing.

@export_group("Lean")
## Tilt at full speed, in degrees. Small is convincing; this is a weeble, not a
## motorcycle.
@export_range(0.0, 45.0, 0.5) var lean_degrees: float = 7.0
## Speed counted as "full tilt". Defaults to the player's `move_speed`.
@export_range(0.5, 30.0, 0.5) var reference_speed: float = 6.0
## How quickly the tilt chases its target. Higher = snappier, less floaty.
@export_range(0.5, 40.0, 0.5) var lean_response: float = 9.0

@export_group("Wobble")
## Very slight oscillation layered on top of the lean while moving, so the tilt
## breathes instead of sitting at a dead angle.
@export_range(0.0, 10.0, 0.1) var wobble_degrees: float = 0.9
## Oscillations per second. The pitch axis runs at a deliberately unrelated
## fraction of this, so the two never line up into an obvious metronome.
@export_range(0.0, 8.0, 0.05) var wobble_hz: float = 1.5

@export_group("Dash")
## Tilt while dashing — much steeper, to sell the speed.
@export_range(0.0, 60.0, 0.5) var dash_lean_degrees: float = 20.0
## How quickly the tilt reaches the dash angle and recovers out of it.
@export_range(0.5, 60.0, 0.5) var dash_response: float = 26.0
## DashAbility to watch, relative to this component. Empty = no dash lean.
@export var dash_path: NodePath = ^"../DashAbility"

@export_group("Idle Bob")
## Height of the resting bob. Deliberately tiny — it should read as breathing.
@export_range(0.0, 0.5, 0.005) var bob_height: float = 0.025
## Bobs per second.
@export_range(0.0, 5.0, 0.05) var bob_hz: float = 0.8
## Below this speed the character counts as at rest. The bob fades in across it
## rather than snapping on, so slowing to a halt doesn't pop.
@export_range(0.05, 5.0, 0.05) var idle_speed: float = 0.6

@export_group("Nodes")
## The visual to sway. Must NOT be the body itself.
@export var model_path: NodePath = ^"../Model"
## HitReactComponent to publish the bob through, so shake and bob compose. Empty
## or missing = the bob writes the model's position directly.
@export var hit_react_path: NodePath = ^"../HitReactComponent"

var _body: CharacterBody3D = null
var _model: Node3D = null
var _hit_react: Node = null
var _dash: Node = null

var _time: float = 0.0
## Current smoothed tilt, radians. Chased toward the target rather than assigned,
## so direction changes ease instead of snapping.
var _pitch: float = 0.0
var _roll: float = 0.0
## The model's authored resting height, for the fallback path only.
var _rest_y: float = 0.0


func _setup() -> void:
	_body = host as CharacterBody3D
	_model = get_node_or_null(model_path) as Node3D
	_hit_react = get_node_or_null(hit_react_path)
	_dash = get_node_or_null(dash_path)
	if _model:
		_rest_y = _model.position.y
	set_physics_process(_model != null and _body != null)


func _physics_process(delta: float) -> void:
	_time += delta

	var flat: Vector3 = Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	var speed: float = flat.length()
	var dashing: bool = _dash != null and _dash.has_method("is_busy") \
		and bool(_dash.call("is_busy"))

	_apply_lean(flat, speed, dashing, delta)
	_apply_bob(speed)


func _apply_lean(flat: Vector3, speed: float, dashing: bool, delta: float) -> void:
	var target_pitch: float = 0.0
	var target_roll: float = 0.0

	if speed > 0.001:
		# Movement direction expressed in the model's own frame, so "forward" means
		# the way the model is facing rather than the way the world is pointing.
		var local: Vector3 = _model.global_transform.basis.inverse() * (flat / speed)
		var lean: float = deg_to_rad(dash_lean_degrees if dashing else lean_degrees)
		# A dash is always full tilt; walking scales with how fast you're going.
		var amount: float = 1.0 if dashing else clampf(speed / reference_speed, 0.0, 1.0)

		# -Z is forward, and leaning INTO travel tips the model's top toward it,
		# which is negative rotation on both axes. Expressed via local.z/.x the
		# forward case folds into a single sign.
		target_pitch = local.z * lean * amount
		target_roll = -local.x * lean * amount

		if wobble_degrees > 0.0:
			var w: float = deg_to_rad(wobble_degrees) * amount
			target_roll += sin(_time * TAU * wobble_hz) * w
			# Off-frequency and phase-shifted so the two axes never sync up.
			target_pitch += sin(_time * TAU * wobble_hz * 0.73 + 1.3) * w * 0.6

	var response: float = dash_response if dashing else lean_response
	var t: float = clampf(response * delta, 0.0, 1.0)
	_pitch = lerpf(_pitch, target_pitch, t)
	_roll = lerpf(_roll, target_roll, t)

	# Only these two axes, ever. `.y` belongs to facing.
	_model.rotation.x = _pitch
	_model.rotation.z = _roll


func _apply_bob(speed: float) -> void:
	# Fades out as you pick up speed rather than switching off at a threshold.
	var rest: float = clampf(1.0 - speed / idle_speed, 0.0, 1.0)
	var bob: float = sin(_time * TAU * bob_hz) * bob_height * rest

	if _hit_react:
		# Additive channel — HitReactComponent folds this into its own write, so a
		# hit-shake while standing still still reads on top of the bob.
		_hit_react.set("extra_offset", Vector3(0.0, bob, 0.0))
	else:
		_model.position.y = _rest_y + bob
