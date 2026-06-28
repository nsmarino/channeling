extends Area3D
class_name ContactDamage

## Damages bodies that overlap this Area3D, on a per-body cooldown so a body
## sitting inside the area isn't damaged every physics frame. Built to cover
## three patterns:
##   - Enemy contact damage (Swooper diving into the player).
##   - Spike / hazard obstacles (persistent area).
##   - Turret-projectiles that consume themselves on hit (set consume_on_hit).
##
## Lifecycle-driven via the duck-typed set_active() the FseDestructible base
## broadcasts — inactive means monitoring is fully off, so PASSED/DYING parents
## stop dealing contact damage automatically.
##
## Collision layer/mask are configured on the Area3D in the scene, not here.
## For an enemy hitting the player: layer = enemy_projectile, mask = player.

## Damage dealt per hit.
@export var damage: int = 10
## Seconds before the same body can be damaged again while still overlapping.
@export var hit_cooldown: float = 0.6
## Group a body must belong to in order to be eligible for damage.
@export var damage_group: StringName = &"player"
## When true, queue_free the parent node after a successful hit. Use for
## turret-projectiles that should disappear on impact.
@export var consume_on_hit: bool = false
## When true, call destroy() on the parent after a successful hit so it runs its
## full death sequence (explosion VFX/SFX). Use for kamikaze enemies that blow
## up on contact. Takes precedence over consume_on_hit.
@export var destroy_self_on_hit: bool = false

var _active: bool = false
# Per-body cooldown in seconds remaining; cleared on deactivation.
var _cooldown_by_body: Dictionary = {}  # Node -> float


func _ready() -> void:
	monitoring = false
	set_physics_process(false)


func set_active(active: bool) -> void:
	_active = active
	monitoring = active
	set_physics_process(active)
	if not active:
		_cooldown_by_body.clear()


func _physics_process(delta: float) -> void:
	# Tick down per-body cooldowns; keys() is a copy, so erase is safe.
	for body: Node in _cooldown_by_body.keys():
		_cooldown_by_body[body] -= delta
		if _cooldown_by_body[body] <= 0.0:
			_cooldown_by_body.erase(body)

	# Poll overlapping bodies — handles initial overlap on activate, persistent
	# contact, and re-entry after cooldown with a single code path.
	for body: Node3D in get_overlapping_bodies():
		if not body.is_in_group(damage_group):
			continue
		if _cooldown_by_body.has(body):
			continue
		_deal_damage(body)


func _deal_damage(body: Node) -> void:
	_cooldown_by_body[body] = hit_cooldown
	if body.has_method("take_damage"):
		body.call("take_damage", damage)
	elif body.has_method("receive_attack"):
		body.call("receive_attack", damage)
	if Events:
		Events.attack_hit.emit(get_parent(), body, damage)

	var parent: Node = get_parent()
	if destroy_self_on_hit and parent and parent.has_method("destroy"):
		parent.call("destroy")
	elif consume_on_hit and parent:
		parent.queue_free()
