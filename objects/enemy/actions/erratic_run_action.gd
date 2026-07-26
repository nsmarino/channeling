extends EnemyAction
class_name ErraticRunAction

## Careen around the navmesh on sharply changing headings for a while.
##
## This is the movement half of the Manicoppo's ZigzagTwirl, pulled out so a second
## creature can use it without the spin and the swinging arms. A Gevi-Dava having a
## panic attack and a Manicoppo whirling with its weapon out are the same PATH —
## bouncing off the level like a pool ball, rerolling to a sharply different
## heading every so often — wearing different costumes.
##
## Subclass hooks, all optional:
##   _begin(token) -> bool  : windup before the running starts. False aborts.
##   _step(delta)           : per-frame extra (spin the body, aim, whatever).
##   _cleanup()             : release anything _begin acquired.
##
## Used bare, it is exactly a headless-chicken run: nothing claims facing, so
## MovementComponent turns the body along its travel and the creature looks where
## it is going while going somewhere stupid.

## How long the run lasts.
@export var duration: float = 2.5
## Travel speed.
@export var speed: float = 5.0
## Seconds between heading changes — the "zig". Short = choppier.
@export var reroll_interval: float = 0.4
## Minimum turn (degrees) on each reroll, so the path reads as chaotic rather than
## as a lazy curve.
@export_range(0.0, 180.0, 5.0) var min_turn_deg: float = 100.0

var _heading: Vector3 = Vector3.FORWARD


func run(token: int) -> bool:
	if not await _begin(token):
		_cleanup()
		return false

	_heading = random_heading()
	var elapsed: float = 0.0
	var reroll: float = 0.0
	var delta: float = get_physics_process_delta_time()

	while elapsed < duration:
		if not still_running(token):
			_cleanup()
			return false

		_step(delta)

		# Zig: snap to a sharply different heading every so often.
		reroll -= delta
		if reroll <= 0.0:
			_heading = strong_turn(_heading, min_turn_deg)
			reroll = reroll_interval
		_move_step(delta)

		elapsed += delta
		await get_tree().physics_frame

	_cleanup()
	return still_running(token)


## Move along the current heading, bouncing off the navmesh edge like a pool ball.
## Enemy bodies carry no collision shape, so the mesh edge is the only thing
## keeping a blind sprint inside the level.
func _move_step(delta: float) -> void:
	var step: Vector3 = _heading * speed * delta
	if is_navigable(body.global_position + step):
		drive(_heading * speed)
		return

	# Blocked: reflect the heading across the mesh edge's inward normal.
	var normal: Vector3 = navmesh_normal(body.global_position + step)
	if normal.length_squared() > 0.0001:
		_heading = _heading.bounce(normal).normalized()
	else:
		_heading = -_heading  # degenerate corner: just reverse.

	# Only commit the bounced heading if it actually frees us; otherwise hold this
	# frame so we can't tunnel off the mesh.
	if is_navigable(body.global_position + _heading * speed * delta):
		drive(_heading * speed)
	else:
		drive(Vector3.ZERO)


# --- Hooks -------------------------------------------------------------------

## Windup before the run. Return false to abort. The await keeps this a coroutine
## so subclass overrides that genuinely wait don't change the call's nature — see
## EnemyAction.run() for why that matters.
func _begin(_token: int) -> bool:
	await get_tree().physics_frame
	return true


## Per-frame extra while running.
func _step(_delta: float) -> void:
	pass


## Release anything _begin acquired. Must be safe to call when _begin never ran.
func _cleanup() -> void:
	pass
