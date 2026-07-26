extends Node3D
class_name Blast

## A one-shot blast spawned at a destroyed enemy by its BlastComponent.
##
## This owns the blast LOGIC (radius, damage, detonation timing); the VISUAL is a
## separate burst scene parented under it (BurstVfx — vfx/particle-scenes/blast.tscn)
## so the two evolve independently. On detonation it damages every destructible
## whose center is within `radius` (is_blast=true, so it can also kill "green"
## targets) AND plays every GPUParticles3D in the burst as a one-shot. Detonation
## can be delayed so chained blasts ripple in both damage and visuals.
##
## Detached in the scene root by BlastComponent, so it outlives the enemy that
## spawned it; it frees itself once the burst's longest emitter finishes.

## Blast sphere radius (world units). The spawner passes diameter / 2.
@export var radius: float = 1.5
## Damage dealt to each destructible inside the radius.
@export var damage: int = 10
## Seconds after spawn before the blast detonates (damage + burst). >0 gives
## chained blasts a visible ripple. 0 = immediate.
@export var detonation_delay: float = 0.06
## Extra seconds the node lingers after the longest burst emitter finishes before
## freeing (covers fade-out / trailing particles).
@export var cleanup_margin: float = 0.3

@export_group("Player")
## Whether this blast also hurts the PLAYER, not just destructibles.
##
## Off by default on purpose. One explosion class now serves both enemy deaths and
## hostile ordnance, but flipping this globally would silently change every
## existing encounter — killing a red enemy at melee range would start hurting you.
## So the unification is in the CODE, and whether a given blast is dangerous to the
## player stays a per-blast decision. A Gevi-Dava bomb sets it true; an enemy's
## death blast can opt in whenever you want to tune that.
@export var damages_player: bool = false
## Damage to the player. 0 = use `damage`.
@export var player_damage: int = 0
## Horizontal shove away from the blast centre. 0 = no knockback.
@export var knockback_force: float = 0.0
## Upward pop added to the shove.
@export var knockback_up: float = 0.0
## Seconds the shove suppresses the player's input.
@export var knockback_duration: float = 0.25

var _detonated: bool = false
# Every GPUParticles3D in the burst, held quiet until detonation.
var _burst: Array[GPUParticles3D] = []


## Configure from the spawner (BlastComponent passes radius + damage).
func configure(p_radius: float, p_damage: int) -> void:
	radius = p_radius
	damage = p_damage


func _ready() -> void:
	# Gather the burst emitters and keep them from auto-playing on spawn; they
	# fire one-shot at detonation instead.
	_collect_burst(self)
	for p in _burst:
		p.emitting = false
		p.one_shot = true

	if detonation_delay <= 0.0:
		_detonate()
	else:
		get_tree().create_timer(detonation_delay).timeout.connect(_detonate)


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	_apply_damage()
	_play_burst()


func _apply_damage() -> void:
	var origin: Vector3 = global_position
	for node in get_tree().get_nodes_in_group("destructible"):
		var target := node as Node3D
		if target == null or not is_instance_valid(target):
			continue
		# Skip anything already dying/dead (incl. the enemy that spawned us).
		if target.has_method("is_defeated") and target.is_defeated():
			continue
		if origin.distance_to(target.global_position) > radius:
			continue
		if target.has_method("take_damage"):
			target.take_damage(damage, true)

	_apply_player_damage(origin)


## Catch the player in the blast, if this one is hostile to them. Separate from the
## destructible loop because the player is not a destructible: their take_damage()
## takes no is_blast flag, and they get knocked back rather than simply damaged.
func _apply_player_damage(origin: Vector3) -> void:
	if not damages_player:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(player):
		return
	if origin.distance_to(player.global_position) > radius:
		return

	if player.has_method("take_damage"):
		player.call("take_damage", player_damage if player_damage > 0 else damage)

	if knockback_force > 0.0 and player.has_method("apply_knockback"):
		var away: Vector3 = player.global_position - origin
		away.y = 0.0
		var dir: Vector3 = away.normalized() if away.length_squared() > 0.0001 \
			else Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized()
		player.call("apply_knockback",
			dir * knockback_force + Vector3.UP * knockback_up, knockback_duration)


## Fire every burst emitter one-shot, then free once the longest one finishes.
func _play_burst() -> void:
	var max_life: float = 0.0
	for p in _burst:
		p.restart()
		max_life = maxf(max_life, p.lifetime)
	get_tree().create_timer(max_life + cleanup_margin).timeout.connect(queue_free)


func _collect_burst(node: Node) -> void:
	for child in node.get_children():
		if child is GPUParticles3D:
			_burst.append(child as GPUParticles3D)
		_collect_burst(child)
