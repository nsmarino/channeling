extends Node3D
class_name FseBlast

## A one-shot blast sphere spawned at a destroyed enemy by its BlastComponent.
## After a short `detonation_delay` (the shockwave reaching its edge — gives a
## visible cascade ripple), it damages every `destructible` whose center is within
## `radius`, passing is_blast=true so it can also kill "blast only" (green)
## targets. Detached in the scene root, so it outlives the enemy that spawned it
## (like the death VFX). VFX can be added as children later.

## Blast sphere radius (world units). The spawner passes diameter / 2.
@export var radius: float = 1.5
## Damage dealt to each destructible inside the radius.
@export var damage: int = 10
## Seconds after spawn before the damage lands. >0 gives chained blasts a visible
## ripple instead of all resolving the same instant. 0 = immediate.
@export var detonation_delay: float = 0.06
## Seconds the node lingers after detonating before freeing (room for VFX).
@export var lifetime: float = 0.5

var _detonated: bool = false


## Configure from the spawner (BlastComponent passes radius + damage).
func configure(p_radius: float, p_damage: int) -> void:
	radius = p_radius
	damage = p_damage


func _ready() -> void:
	if detonation_delay <= 0.0:
		_detonate()
	else:
		get_tree().create_timer(detonation_delay).timeout.connect(_detonate)
	get_tree().create_timer(maxf(detonation_delay, 0.0) + lifetime).timeout.connect(queue_free)


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true

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
