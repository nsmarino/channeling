extends PlayerAbility
class_name DashAbility

## A short committed burst in the direction you're holding — evasion that is also
## an attack, since dashing through a creature damages it.
##
## COMMITTED ON PURPOSE. It claims the player's transform for its whole duration,
## so the distance is fixed and input during the dash changes nothing. A dash you
## can steer is really just a temporary speed boost; one you cannot is a move with
## a reach you can learn, which is what makes it worth timing.
##
## Direction is the movement input mapped through the CAMERA, falling back to the
## model's current facing when nothing is held — so a standing dash goes where you
## are looking and a held dash goes where you asked, including sideways.
##
## THE ATTACK RIDES ON BumpCombat's AIRBORNE PATH rather than a second damage
## system. A dash is fast enough to trip `min_bump_speed` on its own, so without
## intervention dashing into a creature would fire an ordinary ground bump — which
## charges energy AND knocks the player back, and that bounce would then be
## swallowed anyway, because a claimed transform ignores knockback and
## end_scripted_move() clears the timer. Flipping `airborne_mode` for the dash (the
## same handoff the Power Dive uses) gives flat damage, no energy charge and no
## bounce: the dash carries you through, and the only thing it costs is the dash.
##
## Movement is by frame DELTA through move_and_slide, never by teleporting to the
## end point, so walls and ledges stop it. Chasing an absolute target would build a
## catch-up vector that eventually punches the player through geometry.

@export_group("Motion")
## How far the dash travels if nothing blocks it.
@export var distance: float = 5.0
## Seconds it takes. Short — this is a burst, not a sprint.
@export var duration: float = 0.18
## Optional easing (x = time 0-1, y = distance travelled 0-1). Empty = constant
## speed. A fast-out curve makes it feel snappier than it measures.
@export var speed_curve: Curve
## Turn the model to face the dash. OFF keeps a sideways dash reading as a
## sidestep instead of spinning you to face the way you slid.
@export var face_dash_direction: bool = false

@export_group("Attack")
## Flat damage a dash-through deals. Applied by borrowing BumpCombat's airborne
## damage for the duration and putting the old value back afterwards.
@export var bump_damage: int = 12
## BumpCombatComponent switched into airborne mode for the dash, relative to this
## component. Empty = the dash does no damage at all (pure evasion).
@export var bump_component_node: NodePath = ^"../BumpCombat"

@export_group("Aim")
## Camera the input direction is measured against.
@export var camera_node: NodePath = ^"../CameraPivot/SpringArm3D/Camera3D"
## Model turned to face the dash, if `face_dash_direction` is on.
@export var model_node: NodePath = ^"../Model"

var _camera: Node3D = null
var _model: Node3D = null
var _bump: Node = null

var _dashing: bool = false
var _elapsed: float = 0.0
## Fraction of `distance` covered as of last frame.
var _travel: float = 0.0
var _direction: Vector3 = Vector3.FORWARD
## BumpCombat's own airborne damage, restored when the dash ends.
var _restore_bump_damage: int = 0


func _setup() -> void:
	super._setup()
	_camera = get_node_or_null(camera_node) as Node3D
	_model = get_node_or_null(model_node) as Node3D
	_bump = get_node_or_null(bump_component_node)


func needs_body_claim() -> bool:
	return true


func is_busy() -> bool:
	return _dashing


func _activate() -> void:
	# can_activate() already established nothing else holds the transform, but the
	# claim is the authority — take it before committing to anything.
	if not claim_body():
		return

	_direction = _dash_direction()
	_dashing = true
	_elapsed = 0.0
	_travel = 0.0

	if face_dash_direction and _model:
		_model.rotation.y = atan2(-_direction.x, -_direction.z)

	if _bump:
		_restore_bump_damage = int(_bump.get("air_bump_damage"))
		_bump.set("air_bump_damage", bump_damage)
		_bump.set("airborne_mode", true)


func _tick(delta: float) -> void:
	if not _dashing:
		return

	_elapsed += delta
	var t: float = clampf(_elapsed / duration, 0.0, 1.0)
	var travel: float = clampf(speed_curve.sample(t), 0.0, 1.0) if speed_curve else t

	# This frame's slice of the dash, applied as velocity so collisions resolve.
	var step: Vector3 = _direction * distance * (travel - _travel)
	_travel = travel
	body.velocity = step / delta if delta > 0.0 else Vector3.ZERO
	body.move_and_slide()

	if t >= 1.0:
		_finish()


func _finish() -> void:
	_dashing = false
	if _bump:
		_bump.set("airborne_mode", false)
		_bump.set("air_bump_damage", _restore_bump_damage)
	release_body()


## Where the dash goes: the held movement direction mapped through the camera, or
## the model's facing if nothing is held.
##
## Measured off the camera's global basis rather than the pivot's rotation, for the
## same reason the Power Dive aims that way — it stays correct however the rig is
## nested, and while lock-on is steering the pivot.
func _dash_direction() -> Vector3:
	var input: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back")

	if input.length_squared() > 0.0001 and _camera:
		var forward: Vector3 = -_camera.global_transform.basis.z
		var right: Vector3 = _camera.global_transform.basis.x
		forward.y = 0.0
		right.y = 0.0
		# Same mapping as player.gd's _camera_relative_direction, so a dash goes
		# exactly where walking would.
		var dir: Vector3 = right * input.x + forward.normalized() * -input.y
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			return dir.normalized()

	# Nothing held: dash the way we're facing.
	var facing: Vector3 = -_model.global_transform.basis.z if _model \
		else -body.global_transform.basis.z
	facing.y = 0.0
	return facing.normalized() if facing.length_squared() > 0.0001 else Vector3.FORWARD


## Cut short — death, a cutscene. Put BumpCombat back before letting go, or the
## player keeps dealing airborne chip damage with no bounce forever.
func on_deactivate() -> void:
	if _dashing:
		_dashing = false
		if _bump:
			_bump.set("airborne_mode", false)
			_bump.set("air_bump_damage", _restore_bump_damage)
	super.on_deactivate()
