extends Area3D
class_name BouncePadComponent

## Launches whoever lands on it along the pad's own +Y.
##
## The first INTERACTABLE: a thing that acts on the player without being a
## creature or a target. Note that there is no `Interactable` base class and no
## HP here — an interactable is a CAPABILITY you bolt onto any body, not a kind of
## object. That is what lets the same component sit on a mushroom, a door, or one
## day an enemy's head, without any inheritance to negotiate.
##
## Launch direction is the pad's OWN +Y (`global_transform.basis.y`), not world
## up, so tilting the node in the editor fires the player off at an angle. Tuning
## is `launch_speed` plus the node's rotation — both draggable in the viewport.
##
## Landing only. The overlap must be a DESCENDING body, so running into the side
## of a mushroom does nothing and only coming down on top of it launches you.
##
## Sizes are one scene, not three: instance it and change `launch_speed` (and the
## node scale to match visually).
##
## PATH MODE. Assign `path_node` (a Path3D, e.g. a NurbsPath3D placed as a
## sibling under the mushroom) and the pad stops launching: it takes over the
## player's transform with begin_scripted_move() and flies them along the curve,
## like the Power Dive does. The curve is used as placed in the level (its global
## transform), so drag its control points in the viewport to reshape the jump.
## Speed along it follows the height: fast off the pad, slow over the apex, fast
## again on the way down (see `apex_speed`). Empty `path_node` = the launch above.
##
## Single-inheritance caveat: this must BE an Area3D, so like HitBox and
## MeleeHitbox it can't extend the Node-based Component.

signal launched(body: Node3D)

## Speed imparted along the pad's +Y. The player's launch() cancels their existing
## motion along that axis first, so this is the speed you actually get regardless
## of how hard you came down.
@export var launch_speed: float = 14.0
## Skip a body that is already travelling UP the axis — it has just been launched
## and is on its way out, so this stops a second launch on the way through.
##
## Note what this does NOT do: it does not try to prove the body arrived from
## above. GEOMETRY proves that — the trigger volume sits above the solid cap, so
## the only way into it is to come down onto it. An earlier version tested for
## downward velocity instead and almost never fired, because Godot reports area
## overlaps from the PREVIOUS physics step while move_and_slide has already zeroed
## the lander's velocity by the time this polls: the pad kept seeing a body that
## was, as far as it could tell, standing still.
@export var ignore_rising: bool = true
## How fast a body must be rising to count as "on its way out".
@export_range(0.0, 20.0, 0.1) var rising_threshold: float = 0.5
## Seconds before the same body can be launched again — stops a body that is still
## overlapping on the next frame from being fired twice.
@export_range(0.0, 2.0, 0.05) var retrigger_delay: float = 0.3
## Group a body must belong to to be launched.
@export var target_group: StringName = &"player"
## Optional SfxEmitter key played on launch. Empty = silent.
@export var sfx_key: StringName = &""
## Node holding the SFX. Empty = look for a sibling "SfxEmitter".
@export var sfx_path: NodePath

@export_group("Path")
## Path3D to fly the player along instead of launching them. Empty = launch mode.
@export var path_node: NodePath
## Seconds the whole flight takes.
@export_range(0.1, 5.0, 0.05) var path_duration: float = 1.2
## Speed over the highest point of the curve, as a fraction of the top speed.
## Low = a long hang at the apex; 1 = constant speed along the whole path. In
## between, speed follows the drop below the apex like a thrown body does.
@export_range(0.05, 1.0, 0.01) var apex_speed: float = 0.25
## Optional time warp (x = time 0-1, y = distance along the path 0-1). Set it to
## replace the height-based easing above with a hand-drawn one.
@export var path_time_curve: Curve
## The player rarely lands on the exact start of the curve. On: the flight starts
## where they are and blends onto the curve, landing exactly on its end point.
## Off: the whole curve is shifted to start where they landed.
@export var land_on_path_end: bool = true
## Turn the player's model to face along the path when the flight starts.
@export var face_path_direction: bool = true
## Hand the flight's final velocity back to the player, so a path that ends in
## mid-air carries on falling naturally instead of stopping dead.
@export var carry_exit_velocity: bool = true
## Metres the player's camera pulls back for the flight (and the fall after it,
## until they land). 0 = no change.
@export_range(0.0, 10.0, 0.1) var flight_camera_pull: float = 3.0
@export_group("")

var _sfx: Node = null
var _path: Path3D = null

# Path flight state. _rider is the body being flown, null when idle.
var _rider: CharacterBody3D = null
var _elapsed: float = 0.0
var _travel: float = 0.0  # distance along the curve, 0-1
var _start_offset: Vector3 = Vector3.ZERO
var _exit_velocity: Vector3 = Vector3.ZERO
# Timing table: _times[i] is the normalised time at which the flight reaches
# distance i / (n - 1) along the curve. Built per flight from the curve's heights.
var _times: PackedFloat32Array = PackedFloat32Array()
const _TIMING_SAMPLES: int = 48
# Per-body cooldown remaining (seconds).
var _cooldown_by_body: Dictionary = {}  # Node -> float


func _ready() -> void:
	_sfx = get_node_or_null(sfx_path)
	if _sfx == null and get_parent():
		_sfx = get_parent().get_node_or_null("SfxEmitter")
	monitoring = true
	if not path_node.is_empty():
		_path = get_node_or_null(path_node) as Path3D
		if _path == null or _path.curve == null:
			push_warning("[BouncePad] '%s' is not a Path3D with a curve — using launch mode." % path_node)
			_path = null


## Anything holding the player must let go when it leaves, or they stay frozen
## (a restart or portal trip can free the pad mid-flight).
func _exit_tree() -> void:
	if _rider != null:
		_end_ride(false)


func _physics_process(delta: float) -> void:
	# Tick cooldowns down; keys() is a copy, so erasing while iterating is safe.
	for body: Node in _cooldown_by_body.keys():
		_cooldown_by_body[body] -= delta
		if _cooldown_by_body[body] <= 0.0:
			_cooldown_by_body.erase(body)

	if _rider != null:
		_advance_ride(delta)

	for body: Node3D in get_overlapping_bodies():
		if not body.is_in_group(target_group):
			continue
		if _cooldown_by_body.has(body):
			continue
		if not body.has_method("launch"):
			continue
		if body == _rider:
			continue
		if ignore_rising and _is_rising(body):
			continue
		if _path != null and _rider == null and body is CharacterBody3D \
				and body.has_method("begin_scripted_move"):
			_start_ride(body as CharacterBody3D)
		else:
			_launch(body)


## Is this body already travelling up the pad's own axis? Measured against that
## axis rather than world Y, so a tilted pad judges it relative to its own face.
func _is_rising(body: Node3D) -> bool:
	var v: Variant = body.get("velocity")
	if not (v is Vector3):
		return false
	var axis: Vector3 = global_transform.basis.y.normalized()
	return (v as Vector3).dot(axis) > rising_threshold


func _launch(body: Node3D) -> void:
	_cooldown_by_body[body] = retrigger_delay
	var axis: Vector3 = global_transform.basis.y.normalized()
	body.call("launch", axis * launch_speed)
	if _sfx and sfx_key != &"" and _sfx.has_method("play"):
		_sfx.call("play", String(sfx_key))
	launched.emit(body)


# --- Path mode ----------------------------------------------------------------

func _start_ride(body: CharacterBody3D) -> void:
	_cooldown_by_body[body] = retrigger_delay
	# Exclusive claim: refused if a Power Dive or anything else owns the player.
	if not bool(body.call("begin_scripted_move", self)):
		return
	_rider = body
	_elapsed = 0.0
	_travel = 0.0
	_exit_velocity = Vector3.ZERO
	_start_offset = body.global_position - _curve_point(0.0)
	_build_timing()
	if flight_camera_pull > 0.0 and body.has_method("set_camera_pull"):
		body.call("set_camera_pull", flight_camera_pull)

	if face_path_direction and body.has_method("get_facing_node"):
		var model: Node3D = body.call("get_facing_node") as Node3D
		var dir: Vector3 = _curve_point(1.0) - _curve_point(0.0)
		dir.y = 0.0
		if model != null and dir.length_squared() > 0.0001:
			# -Z is forward, as in player.gd.
			model.rotation.y = atan2(-dir.x, -dir.z)

	if _sfx and sfx_key != &"" and _sfx.has_method("play"):
		_sfx.call("play", String(sfx_key))
	launched.emit(body)


func _advance_ride(delta: float) -> void:
	if not is_instance_valid(_rider):
		_rider = null
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / path_duration, 0.0, 1.0)
	var prev: float = _travel
	_travel = clampf(path_time_curve.sample(t), 0.0, 1.0) if path_time_curve else _travel_at(t)

	# Move by this frame's step through move_and_slide (as the Power Dive does)
	# rather than teleporting, so walls and ledges still stop the player.
	var step: Vector3 = _target(_travel) - _target(prev)
	_exit_velocity = step / delta if delta > 0.0 else Vector3.ZERO
	_rider.velocity = _exit_velocity
	_rider.move_and_slide()

	if t >= 1.0:
		_end_ride(true)


func _end_ride(completed: bool) -> void:
	var rider: CharacterBody3D = _rider
	_rider = null
	if not is_instance_valid(rider):
		return
	rider.call("end_scripted_move", self)  # this zeroes the player's velocity
	if completed and carry_exit_velocity:
		rider.velocity = _exit_velocity
	if flight_camera_pull > 0.0:
		if completed and rider.has_method("clear_camera_pull_on_landing"):
			rider.call("clear_camera_pull_on_landing")
		elif rider.has_method("set_camera_pull"):
			rider.call("set_camera_pull", 0.0)
	_cooldown_by_body[rider] = retrigger_delay


## World point at distance `s` (0-1) along the curve, as placed in the level.
func _curve_point(s: float) -> Vector3:
	var curve: Curve3D = _path.curve
	return _path.global_transform * curve.sample_baked(s * curve.get_baked_length())


## Where the player should be at distance `s`: the curve, plus the gap between
## where they landed and the curve's start, faded out by the end (or kept, if
## land_on_path_end is off).
func _target(s: float) -> Vector3:
	var keep: float = 1.0 - smoothstep(0.0, 1.0, s) if land_on_path_end else 1.0
	return _curve_point(s) + _start_offset * keep


## Precompute when the flight reaches each point along the curve. Speed at a
## point is set from how far it sits below the curve's apex: a thrown body's
## speed goes as the square root of its drop from the top, so this gives a quick
## rise, a hang at the apex and an accelerating fall. apex_speed keeps it from
## stopping dead at the very top. Times are normalised so the flight always lasts
## path_duration.
func _build_timing() -> void:
	var n: int = _TIMING_SAMPLES
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(n)
	var top: float = -INF
	var bottom: float = INF
	for i: int in n:
		var y: float = _curve_point(float(i) / float(n - 1)).y
		heights[i] = y
		top = maxf(top, y)
		bottom = minf(bottom, y)
	var span: float = maxf(top - bottom, 0.001)

	_times.resize(n)
	_times[0] = 0.0
	var prev_speed: float = _speed_at(heights[0], top, span)
	for i: int in range(1, n):
		var speed: float = _speed_at(heights[i], top, span)
		# Time across one segment = its length / its average speed.
		_times[i] = _times[i - 1] + (1.0 / float(n - 1)) / ((prev_speed + speed) * 0.5)
		prev_speed = speed
	var total: float = _times[n - 1]
	for i: int in n:
		_times[i] /= total


func _speed_at(y: float, top: float, span: float) -> float:
	return lerpf(apex_speed, 1.0, sqrt(clampf((top - y) / span, 0.0, 1.0)))


## Invert the timing table: distance along the curve (0-1) at time t (0-1).
func _travel_at(t: float) -> float:
	var n: int = _times.size()
	for i: int in range(1, n):
		if t <= _times[i]:
			var span: float = _times[i] - _times[i - 1]
			var f: float = (t - _times[i - 1]) / span if span > 0.0 else 1.0
			return (float(i - 1) + f) / float(n - 1)
	return 1.0
