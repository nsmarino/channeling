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
## THE ATTACK IS JUST A BUMP, and the dash has no damage number of its own. A dash
## is fast enough to trip `min_bump_speed` by itself, so dashing through a creature
## already lands an ordinary bump for ordinary front/back damage — you arrived
## faster, not differently, and where you struck from is still the only thing that
## decides what it did. `airborne_mode` (the same handoff the Power Dive uses)
## waives the energy and the bounce so the move isn't billed twice; it does not
## touch damage.
##
## THE REBOUND IS THE DASH'S OWN, and that is the point of doing it this way. A
## bump's bounce is sized for walking into something; a dash arrives far faster and
## should come off harder, so the knockback is a separate set of knobs that can be
## tuned well past the ordinary bump without touching how walking into a creature
## feels. On contact the dash cuts short, hands the body back, and bounces — in
## that order, because a claimed transform ignores knockback and
## end_scripted_move() clears the timer, so a bounce applied any earlier is thrown
## away. Cutting short is what makes the rebound read as an impact rather than as
## something that happens after you have already slid past.
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
## BumpCombatComponent switched into mid-move mode for the dash, relative to this
## component. Empty = a dash-through costs energy and bounces you like a walk-in.
##
## The dash has no damage number of its own: what a dash-through deals is decided
## by the same front/back rule as any other bump, because it IS one — you arrived
## faster, not differently.
@export var bump_component_node: NodePath = ^"../BumpCombat"

@export_group("Impact")
## Bounce given to the PLAYER when the dash connects, back along the way it came.
##
## Deliberately its own knob rather than reusing the bump's. BumpCombat's ordinary
## bounce (12 / 3 / 0.22 by default) is sized for walking into something; a dash
## hits far faster, and overshooting those numbers is how that speed reads on
## contact. Turn it down to the bump's values to make a dash-through feel the same
## as a walk-in, or up for a hard ricochet.
@export_range(0.0, 60.0, 0.5) var player_knockback_force: float = 20.0
## Upward pop added to the rebound.
@export_range(0.0, 30.0, 0.5) var player_knockback_up: float = 5.0
## Seconds the rebound suppresses input. Longer = less able to cancel the bounce.
@export_range(0.0, 1.0, 0.01) var player_knockback_duration: float = 0.28
## End the dash the instant it connects. Off = carry through the full distance and
## bounce only once the dash finishes.
@export var stop_on_hit: bool = true

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
## Whether this dash has struck anything, so the rebound only fires on a hit.
var _connected: bool = false


func _setup() -> void:
	super._setup()
	_camera = get_node_or_null(camera_node) as Node3D
	_model = get_node_or_null(model_node) as Node3D
	_bump = get_node_or_null(bump_component_node)
	# Connected once and gated on `_dashing` rather than hooked up per dash —
	# nothing to leave dangling if a dash ends by an unusual route.
	Events.attack_hit.connect(_on_attack_hit)


## BumpCombat landed a hit. Ours only if we are mid-dash and the attacker is us —
## the same signal carries every other bump in the game.
func _on_attack_hit(attacker: Node, _target: Node, _damage: int) -> void:
	if not _dashing or attacker != body:
		return
	_connected = true
	if stop_on_hit:
		_finish()


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
	_connected = false
	_elapsed = 0.0
	_travel = 0.0

	if face_dash_direction and _model:
		_model.rotation.y = atan2(-_direction.x, -_direction.z)

	if _bump:
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

	# Release BEFORE bouncing. end_scripted_move() zeroes velocity and clears the
	# knockback timer, so a rebound handed out any earlier is silently discarded —
	# the same ordering trap the Power Dive's impact has to respect.
	release_body()
	if _connected:
		_rebound()


## Throw the player back along the way they came.
func _rebound() -> void:
	if player_knockback_force <= 0.0 and player_knockback_up <= 0.0:
		return
	if body == null or not body.has_method("apply_knockback"):
		return
	var impulse: Vector3 = -_direction * player_knockback_force \
		+ Vector3.UP * player_knockback_up
	body.call("apply_knockback", impulse, player_knockback_duration)


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
## Deliberately does NOT rebound. Being cut short by death or a cutscene is not a
## connection, and flinging the player as the world is being taken away from them
## is the last thing anyone wants.
func on_deactivate() -> void:
	if _dashing:
		_dashing = false
		if _bump:
			_bump.set("airborne_mode", false)
	_connected = false
	super.on_deactivate()
