extends EnemyAction
class_name StrikeAction

## Wind up, open the hitbox for a moment, recover.
##
## The plainest possible attack, and deliberately generic: a rooted mushroom
## slamming its stalk down and a blob jabbing a tentacle are the same three beats
## with different numbers and a different clip. Anything that telegraphs, connects
## in a window, and is punishable afterwards can be this action rather than a new
## script.
##
## Reach comes from the AttackBox's own shape, not from here — move and resize that
## collision shape per creature and this action follows it.
##
## Contrast AttackComboAction, which exists because a multi-swing combo has to lock
## in decisions across steps. Nothing here needs to remember anything, so it stays
## a flat sequence.

@export_group("Timing")
## Telegraph before the hitbox opens. The dodge window.
@export var windup: float = 0.5
## How long the hitbox stays live.
@export var hit_window: float = 0.22
## Vulnerable recovery afterwards. What makes a whiff punishable.
@export var recover: float = 0.7
## Keep facing the player through the windup. Off = commits to its starting aim,
## which makes the attack dodgeable by circling.
@export var track_during_windup: bool = true

@export_group("Damage")
@export var damage: int = 14
@export var knockback_force: float = 10.0
@export var knockback_up: float = 3.0
@export var knockback_duration: float = 0.2

@export_group("Animation")
## Clip played on the windup. Empty = none.
@export var animation: StringName = &""
@export var animation_speed: float = 1.0


func run(token: int) -> bool:
	if anim and animation != &"" and anim.has_animation(animation):
		anim.speed_scale = animation_speed
		anim.play(animation)

	if not await _hold(windup, token, track_during_windup):
		return false

	# One connection per strike: a cooldown longer than the window means a target
	# standing in it the whole time is still only hit once.
	open_hitbox(damage, knockback_force, knockback_up, knockback_duration, hit_window + 1.0)
	var connected: bool = await _hold(hit_window, token, false)
	close_hitbox()
	if not connected:
		return false

	return await _hold(recover, token, false)


func _hold(seconds: float, token: int, track: bool) -> bool:
	var elapsed: float = 0.0
	while elapsed < seconds:
		if not still_running(token):
			return false
		drive(Vector3.ZERO)
		if track:
			var target: Node3D = get_player()
			if is_instance_valid(target):
				face_toward(target.global_position)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
	return still_running(token)


func on_abort() -> void:
	super.on_abort()
	if anim and animation != &"" and anim.current_animation == String(animation):
		anim.stop()
