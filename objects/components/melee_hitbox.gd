extends Area3D
class_name MeleeHitbox

## A melee strike region for enemy attacks. A brain opens it for a hit window and
## the hitbox owns everything that follows: while open it polls for targets and
## applies damage + optional knockback, at most once per target per `hit_cooldown`.
## It emits `hit(body)` so other systems (SFX, screen shake) can react without the
## brain plumbing it through.
##
## What a connection does is passed to open() per-attack, so one hitbox serves both
## the light swing (small knockback) and the ZigzagTwirl (a big fling) — the brain
## no longer contains any hit-detection code.
##
## Single-inheritance caveat: this must BE an Area3D, so like HitBox / ContactDamage
## it can't extend the Node-based Component; attach the script to the attack Area3D.
## Configure its collision mask (the target layer) on that Area3D in the scene.

signal hit(body: Node3D)

## Group a body must belong to to be struck.
@export var target_group: StringName = &"player"
## Body the knockback pushes away from. Empty = the nearest CharacterBody3D
## ancestor (the enemy this hitbox hangs off).
@export var source_path: NodePath

var _source: Node3D = null

# Current strike, set by open().
var _damage: int = 0
var _knockback: float = 0.0
var _knockback_up: float = 0.0
var _knockback_duration: float = 0.0
var _cooldown: float = 0.5

# Per-target cooldown remaining (seconds).
var _cooldown_by_body: Dictionary = {}  # Node -> float


func _ready() -> void:
	_source = get_node_or_null(source_path) as Node3D
	if _source == null:
		_source = _find_body_ancestor()
	monitoring = false
	set_physics_process(false)


## Begin a strike window. The params describe what a landed hit does; they hold
## until close(). `hit_cooldown` is the minimum gap before the same target can be
## struck again — set it above the window length for "once per swing", or to the
## desired cadence for a sustained attack like the twirl.
func open(damage: int, knockback: float = 0.0, knockback_up: float = 0.0,
		knockback_duration: float = 0.0, hit_cooldown: float = 0.5) -> void:
	_damage = damage
	_knockback = knockback
	_knockback_up = knockback_up
	_knockback_duration = knockback_duration
	_cooldown = hit_cooldown
	_cooldown_by_body.clear()
	monitoring = true
	set_physics_process(true)


func close() -> void:
	monitoring = false
	set_physics_process(false)
	_cooldown_by_body.clear()


func _physics_process(delta: float) -> void:
	# Tick down per-target cooldowns; keys() is a copy, so erasing is safe.
	for body: Node in _cooldown_by_body.keys():
		_cooldown_by_body[body] -= delta
		if _cooldown_by_body[body] <= 0.0:
			_cooldown_by_body.erase(body)

	for body: Node3D in get_overlapping_bodies():
		if not body.is_in_group(target_group):
			continue
		if _cooldown_by_body.has(body):
			continue
		_strike(body)


func _strike(body: Node3D) -> void:
	_cooldown_by_body[body] = _cooldown

	if _damage > 0 and body.has_method("take_damage"):
		body.call("take_damage", _damage)

	if _knockback > 0.0 and body.has_method("apply_knockback"):
		var origin: Vector3 = _source.global_position if _source else global_position
		var away: Vector3 = body.global_position - origin
		away.y = 0.0
		var dir: Vector3 = away.normalized() if away.length_squared() > 0.0001 \
			else -global_transform.basis.z
		body.call("apply_knockback", dir * _knockback + Vector3.UP * _knockback_up, _knockback_duration)

	hit.emit(body)


## Nearest CharacterBody3D up the tree — the enemy this strike belongs to.
func _find_body_ancestor() -> Node3D:
	var node: Node = get_parent()
	while node != null:
		if node is CharacterBody3D:
			return node as Node3D
		node = node.get_parent()
	return null
