extends ErraticRunAction
class_name ZigzagTwirlAction

## Freeze on an arms-out pose, then careen around the navmesh spinning, flinging
## whoever it catches.
##
## The roaming itself is ErraticRunAction; this adds the three things that make it
## a Manicoppo attack rather than a panic: the frozen pose, the body spin, and a
## live strike window for the whole run. `duration`, `speed`, `reroll_interval` and
## `min_turn_deg` are inherited.
##
## The spin is BLIND — it never aims at the player. Getting hit is about being in
## the wrong place, not about being targeted, which is what makes it feel like
## chaos rather than a homing attack.
##
## Ships as a child of AttackComboAction, which is what enforces "only ever follows
## a swing". Nothing stops you parenting it directly under `Actions` to let an
## enemy open with it — that is the whole point of the tree being the rule.

@export_group("Pose")
## Clip to freeze for the twirl, and the point in it (seconds) to hold — for the
## Manicoppo, the frame of PracticeSwing with arms out and weapon front.
@export var pose_animation: StringName = &"PracticeSwing"
@export var pose_time: float = 1.7
## Hold on the frozen pose before spinning up.
@export var windup: float = 0.25

@export_group("Spin")
## Body spin speed about Y, degrees/sec. High = frantic.
@export var spin_speed_deg: float = 540.0

@export_group("Damage")
## Damage on a twirl hit. 0 = pure knockback.
@export var damage: int = 15
## Horizontal fling force — set above a bump's knockback for more punch.
@export var fling_force: float = 16.0
## Upward pop on the fling.
@export var fling_up: float = 4.0
## Seconds the fling suppresses the player's input.
@export var fling_duration: float = 0.3
## Seconds before the twirl can fling the same target again.
@export var hit_cooldown: float = 0.5

@export_group("Sound")
## Played on each full turn of the spin, following the creature. Empty = silent.
@export var swing_sound: AudioStream = preload("res://assets/sounds/whoosh.wav")
@export var swing_sound_volume_db: float = 0.0
## Random pitch spread (0.1 = ±10%).
@export_range(0.0, 0.5, 0.01) var swing_pitch_variation: float = 0.1

var _yaw: float = 0.0
var _spun: float = 0.0  # radians turned since the last whoosh


func _begin(token: int) -> bool:
	# speed_scale = 0 (not pause) holds the pose while still reading as "playing",
	# so LocomotionAnimator keeps its hands off — pause() would blank
	# current_animation and let the idle clip stomp it.
	if anim and anim.has_animation(pose_animation):
		anim.play(pose_animation)
		anim.seek(pose_time, true)
		anim.speed_scale = 0.0

	# A held windup on the pose before the spin — plant, don't drift.
	if not await wait_still(windup, token):
		return false

	_yaw = body.rotation.y
	_spun = 0.0
	# The sweeping "hands": the hitbox flings whoever it catches on its own
	# per-target cooldown, so a spin is a series of impacts, not a per-frame barrage.
	open_hitbox(damage, fling_force, fling_up, fling_duration, hit_cooldown)
	Sfx.play_on(body, swing_sound, swing_sound_volume_db, swing_pitch_variation)
	return true


func _step(delta: float) -> void:
	var turn: float = deg_to_rad(spin_speed_deg) * delta
	_yaw = wrapf(_yaw + turn, -PI, PI)
	set_facing(_yaw)
	# One whoosh per full turn (the first played as the spin started).
	_spun += absf(turn)
	if _spun >= TAU:
		_spun = fmod(_spun, TAU)
		Sfx.play_on(body, swing_sound, swing_sound_volume_db, swing_pitch_variation)


func _cleanup() -> void:
	close_hitbox()
	if anim:
		anim.speed_scale = 1.0
		if anim.current_animation == String(pose_animation):
			anim.stop()


func on_abort() -> void:
	_cleanup()
