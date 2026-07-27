extends EnemyAction
class_name SuckSpitAction

## Inhale, swallow, then spit the player back out.
##
## Three phases, each of which can fail into the next:
##   SUCK    — drag the player toward the mouth for a while. They can run.
##   HOLD    — if they were dragged close enough, they are swallowed and held.
##   SPIT    — fire them out of the mouth, still steering.
## Miss the capture and the whole thing is a whiff with a long recovery, which is
## what makes escaping worth attempting.
##
## THE SUCK IS A TUG OF WAR, NOT A CUTSCENE, and the counterplay is POSITIONAL.
## The pull falls off with distance: at the mouth it is overwhelming, at the edge
## of `suck_range` it is nothing. So escaping is not about mashing away from it —
## it is about noticing the windup and being far enough out before the inhale
## starts. React late and no amount of running saves you.
##
## Why falloff rather than a flat force: the player's own movement code drives
## their velocity toward their input every frame at `ground_acceleration`, which is
## an order of magnitude larger than any sane pull. A constant pull therefore
## resolves to a boolean — either it exceeds their acceleration and capture is
## certain regardless of what they do, or it doesn't and the inhale is decorative.
## Neither is a mechanic. Making the pull a target SPEED that decays with distance
## turns it into a comparison the player can act on: `pull_speed` against their own
## `move_speed`, at whatever range they happen to be standing.
##
## RELEASING THE PLAYER IS THIS CLASS'S MOST IMPORTANT JOB. A held player is inside
## begin_scripted_move(), which suspends their movement, gravity and input — if
## this action ends without calling end_scripted_move() they are frozen in place
## FOREVER, with no way out but a restart. The enemy dying mid-swallow is not an
## edge case, it is the most likely way this action ends. So every exit path goes
## through _release(), including on_abort().

@export_group("Mouth")
## Where the player is dragged to and held. Empty = the body's origin.
@export var mouth_path: NodePath = ^"../../Model/Mouth"
## How close to the mouth counts as swallowed.
@export var capture_radius: float = 1.4

@export_group("Suck")
## Telegraph before the inhale starts. The player's window to back off.
@export var windup: float = 0.6
## How long the inhale lasts.
@export var suck_duration: float = 1.8
## Drag speed the inhale tries to impose, AT THE MOUTH. Compare it against the
## player's `move_speed` (6.0): above that and someone standing close cannot walk
## out, below it and they can stroll away from point blank.
@export var pull_speed: float = 9.0
## How hard it accelerates them up to that speed. Must comfortably exceed the
## player's `ground_acceleration` (60), or their own braking cancels the pull
## before it ever moves them.
@export var pull_accel: float = 120.0
## Furthest the pull reaches, and the distance over which it decays to nothing.
@export var suck_range: float = 9.0

@export_group("Hold")
## Seconds the player is held in the mouth before being spat.
@export var hold_time: float = 0.9

@export_group("Spit")
## Speed the player is fired out at.
@export var spit_speed: float = 18.0
## Upward component of the spit, as a fraction of `spit_speed`.
@export_range(0.0, 2.0, 0.05) var spit_lift: float = 0.45
## Damage dealt on being spat out. 0 = purely humiliating.
@export var spit_damage: int = 10
## Recovery after spitting, or after a whiffed inhale.
@export var recover: float = 1.0

var _mouth: Node3D = null
## The player we are currently holding. Non-null means they are inside a scripted
## move that only we can end — see the class note.
var _held: Node3D = null


func _setup() -> void:
	_mouth = get_node_or_null(mouth_path) as Node3D


func run(token: int) -> bool:
	var target: Node3D = get_player()
	if not is_instance_valid(target):
		return false

	if not await _face_and_wait(windup, token):
		return false

	var captured: bool = await _suck(token)
	if not still_running(token):
		_release()
		return false

	if captured:
		if not await _hold(token):
			return false
		_spit()

	return await _face_and_wait(recover, token)


## Inhale. Returns true if the player ended up close enough to swallow.
func _suck(token: int) -> bool:
	var elapsed: float = 0.0
	while elapsed < suck_duration:
		if not still_running(token):
			return false
		var target: Node3D = get_player()
		if not is_instance_valid(target):
			return false

		var origin: Vector3 = _mouth_position()
		var to_mouth: Vector3 = origin - target.global_position
		var dist: float = to_mouth.length()

		if dist <= capture_radius:
			return true
		_pull(target, to_mouth, dist)

		drive(Vector3.ZERO)
		face_toward(target.global_position)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame

	# Last chance: they may have been dragged in on the final frame.
	var final_target: Node3D = get_player()
	if is_instance_valid(final_target):
		return _mouth_position().distance_to(final_target.global_position) <= capture_radius
	return false


## Drag `target` one frame's worth toward the mouth.
##
## Works in terms of the speed the target is ALREADY closing at, and only tops it
## up to the distance-scaled goal — so the inhale converges on a drag speed instead
## of accelerating without limit, and a target already moving in fast is not shoved
## faster still.
func _pull(target: Node3D, to_mouth: Vector3, dist: float) -> void:
	if dist > suck_range or not target.has_method("apply_external_velocity"):
		return
	var v: Variant = target.get("velocity")
	if not (v is Vector3):
		return

	var dir: Vector3 = to_mouth / dist
	var falloff: float = clampf(1.0 - dist / suck_range, 0.0, 1.0)
	var goal: float = pull_speed * falloff
	var closing: float = (v as Vector3).dot(dir)
	if closing >= goal:
		return

	var add: float = minf(pull_accel * get_physics_process_delta_time(), goal - closing)
	target.call("apply_external_velocity", dir * add)


## Swallow and hold. The player's transform is ours for the duration.
func _hold(token: int) -> bool:
	var target: Node3D = get_player()
	if not is_instance_valid(target) or not target.has_method("begin_scripted_move"):
		return still_running(token)

	# The claim can be refused — the player may already be inside a Power Dive or
	# another creature's mouth. Swallowing them anyway would mean two things
	# driving one transform, and whichever released first would hand control back
	# mid-move. A refused swallow is just a whiff.
	if not bool(target.call("begin_scripted_move", self)):
		return still_running(token)
	_held = target

	var elapsed: float = 0.0
	while elapsed < hold_time:
		if not still_running(token):
			_release()
			return false
		# Park them in the mouth. Re-applied every frame rather than once, so
		# nothing else can drift them out of it.
		if is_instance_valid(_held):
			_held.global_position = _mouth_position()
		drive(Vector3.ZERO)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
	return still_running(token)


## Fire the held player out along the mouth's forward, and hand control back.
func _spit() -> void:
	var victim: Node3D = _held
	_release()
	if not is_instance_valid(victim):
		return

	var forward: Vector3 = -body.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	var impulse: Vector3 = forward.normalized() * spit_speed + Vector3.UP * spit_speed * spit_lift

	if victim.has_method("launch"):
		victim.call("launch", impulse)
	if spit_damage > 0 and victim.has_method("take_damage"):
		victim.call("take_damage", spit_damage)


## Hand the player back their own body. Safe to call when holding nobody, and
## safe to call twice — which is what lets every exit path call it blindly.
func _release() -> void:
	if _held == null:
		return
	var victim: Node3D = _held
	_held = null
	if is_instance_valid(victim) and victim.has_method("end_scripted_move"):
		victim.call("end_scripted_move", self)


func _mouth_position() -> Vector3:
	return _mouth.global_position if is_instance_valid(_mouth) else body.global_position


## Hold still facing the player for `seconds`.
func _face_and_wait(seconds: float, token: int) -> bool:
	var elapsed: float = 0.0
	while elapsed < seconds:
		if not still_running(token):
			_release()
			return false
		drive(Vector3.ZERO)
		var target: Node3D = get_player()
		if is_instance_valid(target):
			face_toward(target.global_position)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
	return still_running(token)


## The enemy died, changed state, or was otherwise interrupted. Whatever else
## happens, the player gets their body back.
func on_abort() -> void:
	super.on_abort()
	_release()
