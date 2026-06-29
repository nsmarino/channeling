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
