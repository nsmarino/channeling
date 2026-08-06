extends Area3D
class_name BumpCombatComponent

## Ys-style "bump combat" for the player: run into an enemy to damage it.
##
## Damage depends on WHERE you hit them from, in two steps: a bump into an enemy's
## back deals `max_damage`, a bump into their front deals `min_damage`, and
## `back_threshold` is the line between. Two steps rather than a gradient because
## creatures now have single-digit health — every intermediate value rounded to
## one of the same two numbers regardless, so the curve bought nothing but made
## the outcome harder to predict. Every landed bump also kicks the player back
## along the reverse of the attack vector, so you bounce off instead of grinding
## into the body.
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
## Damage for a bump into the enemy's BACK. The reward for manoeuvring behind
## something rather than running at it.
@export_range(0, 200, 1) var max_damage: int = 3
## Damage for a bump into the enemy's FRONT.
@export_range(0, 200, 1) var min_damage: int = 1
## Where the back begins, as a fraction of the way around the enemy: 0 is nose-on,
## 1 is directly behind, 0.5 is exactly beside them.
##
## The split is a STEP, not a curve. With a health pool of 5 there is no room for
## gradations — every intermediate value rounds to one of two numbers anyway, so a
## smooth falloff only made the same two outcomes harder to predict. A hard line
## you can learn is worth more than a gradient you can't read.
##
## The comparison is strictly greater-than, so a hit exactly on the line counts as
## the FRONT. Ambiguity should never hand out the bonus.
@export_range(0.0, 1.0, 0.05) var back_threshold: float = 0.5
## Unused by the current two-step rule; kept for now at your request. It shaped the
## old continuous face→back falloff.
@export_range(0.1, 4.0, 0.05) var facing_falloff: float = 1.0

@export_group("Hit Callout")
## Pop a floating FRONT/BACK label on the target. Requires a FloatingTextComponent
## on it; without one this does nothing.
##
## The two-step rule is only worth learning if you can SEE which step you got —
## the raw back-factor lives in the console, but the console is not where you are
## looking while playing.
@export var show_hit_callout: bool = true
## Text popped for a back hit, and its colour. The caller picks the words because
## the caller is what knows the distinction; the label component just renders.
@export var back_callout: String = "BACK"
@export var back_callout_color: Color = Color(1.0, 0.85, 0.25)
@export var front_callout: String = "FRONT"
@export var front_callout_color: Color = Color(0.75, 0.8, 0.9)

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

## Set by an ability that owns the player's transform — the Power Dive's flight,
## the dash's burst — for its duration.
##
## It waives the ENERGY COST and the PLAYER BOUNCE, and nothing else. Damage is
## unaffected: a bump is a bump, and where you struck from is the only thing that
## decides what it does.
##
## Both waivers exist because the move already paid, and because a bounce would be
## thrown away regardless: a claimed transform ignores knockback, and releasing it
## clears the timer. Charging energy per bump on top of a 40-energy dive is just a
## second bill for one decision.
##
## (The name is a slight misnomer now — it means "mid-committed-move", not
## "off the ground".)
var airborne_mode: bool = false

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

	# WHERE you struck from is the only input to damage. Computed once, up front,
	# so every path below lands on the same number — a bump mid-dive and a bump on
	# foot hit for the same amount from the same angle, and the only thing being
	# mid-move changes is what it COSTS you.
	var back := _back_factor(enemy)
	# Strictly greater-than: a hit exactly on the line is a FRONT hit.
	var from_behind := back > back_threshold
	var damage := max_damage if from_behind else min_damage

	# Mid-committed-move: the ability already paid, so no energy and no bounce.
	if airborne_mode:
		hitbox.call("receive_hit", damage)
		_try_spawn_drop(enemy)
		_show_callout(enemy, from_behind)
		Events.attack_hit.emit(_host, enemy, damage)
		if debug_log:
			print("[BumpCombat] %s for %d (%s, mid-move)" % [
				String(enemy.name), damage, "BACK" if from_behind else "front"])
		return

	# A ground bump costs energy. Too little and it's a whiff — the player still
	# bounces off, but deals no damage and shakes loose no drop. (Placeholder for
	# the planned player-gets-knocked-down state.)
	if _host.has_method("spend_energy") and not bool(_host.call("spend_energy", energy_cost)):
		_apply_knockback(enemy)
		if debug_log:
			print("[BumpCombat] %s — not enough energy, bounced off" % String(enemy.name))
		return

	hitbox.call("receive_hit", damage)
	_apply_knockback(enemy)
	_try_spawn_drop(enemy)
	_show_callout(enemy, from_behind)
	Events.attack_hit.emit(_host, enemy, damage)

	if debug_log:
		# The raw factor stays in the log even though the damage is now a step —
		# it's what tells you whether a hit was a clear one or right on the line
		# when you're deciding where to put back_threshold.
		print("[BumpCombat] %s for %d (%s, back factor %.2f)" % [
			String(enemy.name), damage, "BACK" if from_behind else "front", back])


## How far behind the enemy we struck: 0 = straight into their face, 1 = straight
## into their back. Flattened to the ground plane so height doesn't skew it.
##
## Both degenerate cases — standing exactly on top of them, or a target with no
## meaningful facing — return 0, the FRONT. That is the safe direction to fail in:
## it withholds the bonus rather than awarding one nobody earned.
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


## Ask the thing we just hit to say which side it was hit on.
##
## Found the same way the drop is — by scanning the target's children for the
## method rather than by holding a reference. A target with no
## FloatingTextComponent simply gets no callout, so props and breakables cost
## nothing and nothing has to be wired per creature.
func _show_callout(enemy: Node3D, from_behind: bool) -> void:
	if not show_hit_callout:
		return
	for child in enemy.get_children():
		if child.has_method("show_text"):
			child.call("show_text",
				back_callout if from_behind else front_callout,
				back_callout_color if from_behind else front_callout_color)
			return


## Ask the thing we just hit to shake a pickup loose.
##
## WHAT drops is the target's business, not ours — it owns a DropComponent with
## its own odds and its own pickup. The player used to spawn the loot itself,
## which forced every enemy and prop in the game to share one drop table.
## Duck-typed, so a target with no DropComponent simply drops nothing.
func _try_spawn_drop(enemy: Node3D) -> void:
	for child in enemy.get_children():
		if child.has_method("shake_loose"):
			child.call("shake_loose")
			return


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
