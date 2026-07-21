extends Area3D
class_name BumpCombatComponent

## Ys-style "bump combat" for the player: run into an enemy to damage it.
##
## Damage scales with WHERE you hit them from — a bump into an enemy's back
## (they're facing away) deals `max_damage`, a head-on bump into their face deals
## `min_damage`, with a smooth falloff between. Every landed bump also kicks the
## player back along the reverse of the attack vector, so you bounce off instead
## of grinding into the body.
##
## Attach as an Area3D child of the player with a CollisionShape3D covering the
## body, masking the `enemy` layer (3). Enemy *bodies* are collision_layer = 0 in
## this project, so a bump can't be detected by move_and_slide — it's detected
## against their HitBox **areas** instead, and damage is routed through
## HitBox.receive_hit, the same path the player's projectiles use.
##
## Knockback is handed to the host through a duck-typed `apply_knockback(impulse,
## duration)` so this component never fights the controller for velocity.
##
## GDScript is single-inheritance, so this can't extend the Node-based Component
## base (it must BE an Area3D) — same caveat as HitBox / ContactDamage.

@export_group("Damage")
## Damage for a bump straight into the enemy's back (facing fully away from you).
@export_range(0, 200, 1) var max_damage: int = 30
## Damage for a head-on bump (enemy facing straight at you).
@export_range(0, 200, 1) var min_damage: int = 5
## Shapes the face→back falloff. 1 = linear; >1 means you must get well behind
## them to earn the bonus; <1 is more forgiving.
@export_range(0.1, 4.0, 0.05) var facing_falloff: float = 1.0

@export_group("Knockback")
## Horizontal impulse pushing the player back along the reverse attack vector.
@export_range(0.0, 40.0, 0.5) var knockback_force: float = 12.0
## Small upward pop added to the bounce, so it reads as an impact.
@export_range(0.0, 20.0, 0.5) var knockback_up: float = 3.0
## Seconds the impulse owns the player's movement before input resumes.
@export_range(0.0, 1.0, 0.01) var knockback_duration: float = 0.22

@export_group("Energy")
## Energy the player spends per landed ground bump. If they can't afford it the
## bump deals no damage — they just bounce off (a stub for a future knockdown).
@export_range(0.0, 100.0, 1.0) var energy_cost: float = 10.0

@export_group("Rules")
## Minimum horizontal speed required to register a bump — standing still and
## leaning on an enemy shouldn't damage it.
@export_range(0.0, 10.0, 0.1) var min_bump_speed: float = 1.5
## Seconds before the same enemy can be bumped again.
@export_range(0.0, 3.0, 0.05) var hit_cooldown: float = 0.45
## Flat damage for a bump landed mid-air during a scripted move (a PowerSlam
## flight). Facing is ignored — you're committed to an arc, not choosing an angle.
@export_range(0, 200, 1) var air_bump_damage: int = 12

## Set by PowerSlamComponent for the duration of a slam's flight. Bumps then deal
## `air_bump_damage` and apply NO knockback, since bouncing the player mid-flight
## would fight the trajectory they're locked into.
var airborne_mode: bool = false

@export_group("Power Drops")
## Physics pickup burst out of the enemy on a landed bump. Empty = no drops.
@export var power_drop_scene: PackedScene
## Odds a landed bump spawns a drop.
@export_range(0.0, 1.0, 0.05) var drop_chance: float = 0.5
## Upward speed of the pop.
@export_range(0.0, 20.0, 0.5) var drop_launch_up: float = 5.0
## Horizontal speed of the pop, fired in a random direction.
@export_range(0.0, 20.0, 0.5) var drop_launch_spread: float = 3.0
## Height above the enemy's origin the drop spawns at.
@export_range(0.0, 4.0, 0.1) var drop_spawn_height: float = 1.0
## Print the damage/angle of each bump, for tuning by feel.
@export var debug_log: bool = true

var _host: CharacterBody3D = null
# Per-enemy cooldown, seconds remaining.
var _cooldown_by_enemy: Dictionary = {}  # Node -> float


func _ready() -> void:
	_host = get_parent() as CharacterBody3D
	monitoring = true


func _physics_process(delta: float) -> void:
	# Tick cooldowns down; keys() is a copy, so erasing while iterating is safe.
	for enemy: Node in _cooldown_by_enemy.keys():
		_cooldown_by_enemy[enemy] -= delta
		if _cooldown_by_enemy[enemy] <= 0.0:
			_cooldown_by_enemy.erase(enemy)

	if _host == null or not _is_moving_fast_enough():
		return

	for area: Area3D in get_overlapping_areas():
		if not area.has_method("receive_hit"):
			continue
		var enemy := area.get_parent() as Node3D
		if enemy == null or _cooldown_by_enemy.has(enemy):
			continue
		# Don't waste a bump (or its cooldown) on something already dying.
		if enemy.has_method("is_defeated") and bool(enemy.call("is_defeated")):
			continue
		_bump(area, enemy)


func _is_moving_fast_enough() -> bool:
	var flat := Vector3(_host.velocity.x, 0.0, _host.velocity.z)
	return flat.length() >= min_bump_speed


func _bump(hitbox: Area3D, enemy: Node3D) -> void:
	_cooldown_by_enemy[enemy] = hit_cooldown

	# Mid-dive bumps are part of the already-paid Power Dive: flat damage, no
	# energy cost, no knockback (bouncing mid-flight fights the locked-in arc).
	if airborne_mode:
		hitbox.call("receive_hit", air_bump_damage)
		_try_spawn_drop(enemy)
		Events.attack_hit.emit(_host, enemy, air_bump_damage)
		if debug_log:
			print("[BumpCombat] %s for %d (air)" % [String(enemy.name), air_bump_damage])
		return

	# A ground bump costs energy. Too little and it's a whiff — the player still
	# bounces off, but deals no damage and shakes loose no drop. (Placeholder for
	# the planned player-gets-knocked-down state.)
	if _host.has_method("spend_energy") and not bool(_host.call("spend_energy", energy_cost)):
		_apply_knockback(enemy)
		if debug_log:
			print("[BumpCombat] %s — not enough energy, bounced off" % String(enemy.name))
		return

	var back := _back_factor(enemy)
	var damage := int(roundf(lerpf(float(min_damage), float(max_damage), pow(back, facing_falloff))))
	hitbox.call("receive_hit", damage)
	_apply_knockback(enemy)
	_try_spawn_drop(enemy)
	Events.attack_hit.emit(_host, enemy, damage)

	if debug_log:
		print("[BumpCombat] %s for %d (back factor %.2f)" % [String(enemy.name), damage, back])


## How far behind the enemy we struck: 0 = straight into their face, 1 = straight
## into their back. Flattened to the ground plane so height doesn't skew it.
func _back_factor(enemy: Node3D) -> float:
	var to_player := _host.global_position - enemy.global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.0001:
		return 0.0

	# Standard Godot convention: -Z is forward (see MovementComponent).
	var facing := -enemy.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return 0.0

	# dot = +1 → they're looking right at us (worst), -1 → facing away (best).
	var dot := facing.normalized().dot(to_player.normalized())
	return clampf((1.0 - dot) * 0.5, 0.0, 1.0)


## Roll for a PowerDrop and burst it out of the enemy in a random direction.
## Parented to the scene root, not the enemy, so it survives the enemy's death.
func _try_spawn_drop(enemy: Node3D) -> void:
	if power_drop_scene == null or randf() > drop_chance:
		return
	var world: Node = get_tree().current_scene
	if world == null:
		return

	var drop := power_drop_scene.instantiate() as Node3D
	if drop == null:
		return
	world.add_child(drop)
	drop.global_position = enemy.global_position + Vector3.UP * drop_spawn_height

	var angle := randf() * TAU
	var impulse := Vector3(
		cos(angle) * drop_launch_spread, drop_launch_up, sin(angle) * drop_launch_spread
	)
	if drop.has_method("launch"):
		drop.call("launch", impulse)


## Bounce the player back along the reverse of the attack vector.
func _apply_knockback(enemy: Node3D) -> void:
	if not _host.has_method("apply_knockback"):
		return

	var attack := enemy.global_position - _host.global_position
	attack.y = 0.0
	var back_dir: Vector3
	if attack.length_squared() > 0.0001:
		back_dir = -attack.normalized()
	else:
		# Dead-centre overlap: fall back to reversing our own travel.
		var flat := Vector3(_host.velocity.x, 0.0, _host.velocity.z)
		back_dir = -flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO

	var impulse := back_dir * knockback_force + Vector3.UP * knockback_up
	_host.call("apply_knockback", impulse, knockback_duration)
