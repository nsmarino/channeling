extends EnemyAction
class_name AttackComboAction

## Close in, swing 1-3 times, then run any follow-ups, then reposition.
##
## The two "lock it in" rules that make the combo readable and dodgeable are plain
## local variables, captured once at the moment of the decision and immune to
## whatever the player does afterwards:
##   - the SWING COUNT is rolled when the action starts, not re-evaluated per swing;
##   - the FACING is locked as the first swing begins, so a combo commits to where
##     the player was standing rather than tracking them through it.
##
## FOLLOW-UPS ARE CHILD NODES. Every child EnemyAction is awaited in scene order
## after the swings, each gated by its own `chance`. That tree position IS the rule
## "this may only ever follow a swing" — a ZigzagTwirl parented here can never be
## picked cold by the brain. Reorder, add or delete children to reshape the combo;
## no code here changes.

@export_group("Swings")
## Swing count is rolled once, when the action starts.
@export var min_swings: int = 1
@export var max_swings: int = 3
## Clip played per swing.
@export var attack_animation: StringName = &"PracticeSwing"
## Playback rate for the swing (the raw clip is 2.25s, which is sluggish).
@export var attack_speed_scale: float = 1.4
## How far off-centre a swing may aim, in degrees. Each swing picks -this, 0, or
## +this, giving the front-left / front / front-right variation.
@export var aim_spread_deg: float = 28.0
## Normalized animation time by which the aim lerp completes ("first half").
@export_range(0.05, 1.0, 0.05) var aim_lerp_end: float = 0.5
## Extra beat between the 2nd and 3rd swing, so a triple reads differently.
@export var third_swing_delay: float = 0.45

@export_group("Damage")
## Normalized window during which the hitbox is live.
@export_range(0.0, 1.0, 0.01) var hit_window_start: float = 0.5
@export_range(0.0, 1.0, 0.01) var hit_window_end: float = 0.68
## Damage per connected swing.
@export var damage: int = 12
## Knockback a landed swing deals — deliberately gentler than a twirl's fling.
@export var knockback_force: float = 8.0
## Upward pop on a swing hit.
@export var knockback_up: float = 2.0
## Seconds a swing hit suppresses the player's input.
@export var knockback_duration: float = 0.18

@export_group("Approach")
## Distance it closes to before starting to swing. Must leave margin under the
## hitbox's actual reach, or an off-centre swing sails past — the enemy would
## windmill at thin air.
@export var attack_range: float = 1.6
## Speed while closing for an attack.
@export var approach_speed: float = 4.5
## Give up approaching after this long (blocked, or the player kited away).
@export var approach_timeout: float = 4.0


func run(token: int) -> bool:
	# Rolled NOW, at the moment of the decision — not re-evaluated per swing.
	var swings: int = randi_range(min_swings, maxi(min_swings, max_swings))

	if not await _approach(token):
		return false

	var target: Node3D = get_player()
	if not is_instance_valid(target):
		return false
	# 'Front' locks to where the player is standing as the first swing starts.
	var locked_yaw: float = yaw_toward(target.global_position)

	for i in swings:
		# A beat before the third swing, so a triple reads differently to a double.
		if i == 2 and not await wait(third_swing_delay, token):
			return false
		if not await _swing(token, locked_yaw):
			return false

	# Follow-ups, in scene order. Each child's position here is what makes it a
	# post-swing move rather than something the brain could open with.
	for child in get_children():
		if not (child is EnemyAction):
			continue
		var follow_up := child as EnemyAction
		if not follow_up.enabled or randf() >= follow_up.chance:
			continue
		if not await follow_up.run(token):
			return false

	return still_running(token)


## Close to `attack_range` through the navmesh, so walls and ledges are respected.
## False = gave up (blocked, kited, or cancelled), which ends the action before any
## swing happens.
func _approach(token: int) -> bool:
	var elapsed: float = 0.0
	while elapsed < approach_timeout:
		if not still_running(token):
			return false
		if flat_distance_to_player() <= attack_range:
			return true
		var target: Node3D = get_player()
		if agent and is_instance_valid(target):
			agent.target_position = target.global_position
			var to_next: Vector3 = agent.get_next_path_position() - body.global_position
			to_next.y = 0.0
			if to_next.length_squared() > 0.0001:
				drive(to_next.normalized() * approach_speed)
				face_toward(target.global_position)
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
	return false


## One swing: turn onto the aim during the first half of the clip, open the hitbox
## for the contact window, close it, done.
func _swing(token: int, base_yaw: float) -> bool:
	if anim == null or not anim.has_animation(attack_animation):
		return false

	# Front, front-left or front-right of the locked-in facing.
	var offsets: Array[float] = [0.0, -aim_spread_deg, aim_spread_deg]
	var target_yaw: float = base_yaw + deg_to_rad(offsets[randi() % offsets.size()])
	var start_yaw: float = body.rotation.y

	anim.speed_scale = attack_speed_scale
	anim.play(attack_animation)

	var open: bool = false

	while anim.is_playing() and anim.current_animation == String(attack_animation):
		if not still_running(token):
			return false

		# Progress is read off the ANIMATION's clock, not a wall timer, so retiming
		# the clip (attack_speed_scale) retimes the turn and the hit window with it —
		# they can never drift apart.
		var t: float = 0.0
		if anim.current_animation_length > 0.0:
			t = anim.current_animation_position / anim.current_animation_length

		if t <= aim_lerp_end:
			set_facing(lerp_angle(start_yaw, target_yaw, clampf(t / aim_lerp_end, 0.0, 1.0)))
		else:
			set_facing(target_yaw)
		drive(Vector3.ZERO)

		# A cooldown above the window length keeps a swing to one connection.
		var should_open: bool = t >= hit_window_start and t <= hit_window_end
		if should_open != open:
			open = should_open
			if open:
				open_hitbox(damage, knockback_force, knockback_up, knockback_duration, 1.0)
			else:
				close_hitbox()

		await get_tree().physics_frame

	close_hitbox()
	anim.speed_scale = 1.0
	return still_running(token)


func on_abort() -> void:
	super.on_abort()
	if anim and anim.current_animation == String(attack_animation):
		anim.stop()
