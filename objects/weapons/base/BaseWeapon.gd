extends Node3D
class_name FseBaseWeapon

@export var data: Resource
@export var muzzle_spawn_offset: float = 0.3

@onready var muzzle: Marker3D = $Muzzle
@onready var cooldown_timer: Timer = $CooldownTimer
@onready var shoot_sfx: AudioStreamPlayer3D = get_node_or_null("SFX/Shoot") as AudioStreamPlayer3D
@onready var attempt_shot_sfx: AudioStreamPlayer3D = get_node_or_null("SFX/AttemptShot") as AudioStreamPlayer3D
@onready var ready_sfx: AudioStreamPlayer3D = get_node_or_null("SFX/Ready") as AudioStreamPlayer3D

var ammo_count: int = -1
var owner_character: CharacterBody3D = null
## Optional homing target assigned per-frame by the shooter; passed to each
## spawned projectile that supports it. Null = projectiles fly straight.
var homing_target: Node3D = null


func _ready() -> void:
	if data:
		ammo_count = int(data.get("ammo_count"))
	else:
		push_warning("[FseBaseWeapon:%s] Missing weapon data." % name)
	cooldown_timer.one_shot = true
	cooldown_timer.stop()
	if not cooldown_timer.timeout.is_connected(_on_cooldown_timer_timeout):
		cooldown_timer.timeout.connect(_on_cooldown_timer_timeout)


func can_fire() -> bool:
	return cooldown_timer.is_stopped() and data != null and data.get("projectile_scene") != null


func should_fire_for_input(trigger_pressed: bool, trigger_just_pressed: bool) -> bool:
	if not data:
		return false

	var is_automatic: bool = true
	var auto_value: Variant = data.get("is_automatic")
	if auto_value != null:
		is_automatic = bool(auto_value)

	if is_automatic:
		return trigger_pressed
	return trigger_just_pressed


func try_fire(aim_direction: Vector3 = Vector3.ZERO) -> bool:
	if not can_fire():
		_play_blocked_fire_attempt_sfx()
		return false

	if ammo_count == 0:
		return false

	if ammo_count > 0:
		ammo_count -= 1

	_spawn_projectiles(aim_direction)
	_play_shoot_sfx()
	cooldown_timer.start(maxf(float(data.get("fire_rate")), 0.01))
	return true


func _play_shoot_sfx() -> void:
	_play_sfx(shoot_sfx)


func _play_blocked_fire_attempt_sfx() -> void:
	if cooldown_timer.is_stopped():
		return

	_play_sfx(attempt_shot_sfx)


func _play_ready_sfx() -> void:
	if ammo_count == 0:
		return
	if not can_fire():
		return

	_play_sfx(ready_sfx)


func _play_sfx(player: AudioStreamPlayer3D) -> void:
	if not player:
		return

	player.stop()
	player.play()


func _on_cooldown_timer_timeout() -> void:
	_play_ready_sfx()


func _spawn_projectiles(aim_direction: Vector3) -> void:
	var world: Node = get_tree().current_scene
	if world == null:
		push_warning("[FseBaseWeapon:%s] Could not resolve current scene for projectile spawn." % name)
		return

	var direction: Vector3 = -muzzle.global_transform.basis.z
	if aim_direction.length_squared() > 0.0001:
		direction = aim_direction.normalized()
	var projectile_count: int = maxi(int(data.get("burst_count")), 1)

	for i in projectile_count:
		var projectile_scene: PackedScene = data.get("projectile_scene")
		if projectile_scene == null:
			continue
		var inst: Node = projectile_scene.instantiate()
		if not inst.has_method("launch"):
			push_error("[FseBaseWeapon:%s] projectile_scene root must expose launch()." % name)
			continue

		var projectile: Node = inst
		world.add_child(projectile)
		projectile.speed = float(data.get("muzzle_velocity"))
		projectile.damage = float(data.get("damage"))
		if homing_target and "homing_target" in projectile:
			projectile.homing_target = homing_target
		var spawn_transform: Transform3D = muzzle.global_transform
		spawn_transform.origin += direction * muzzle_spawn_offset
		projectile.launch(spawn_transform, direction, owner_character)
