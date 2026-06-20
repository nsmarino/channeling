extends Node
class_name TurretEmitter

## Spawns FseTurretProjectiles on a cadence, handing each the emitter's Curve2D so
## every shot traces the same tweakable pattern (line / arc / sine sweep across
## the lane). Unlike WeaponComponent it does NOT aim at the player — the curve is
## the whole behavior. Supports an alternating list of projectile scenes so one
## turret can fire, e.g., a destructible bolt then a tougher one.
##
## Driven by the same set_active(bool) lifecycle the FseDestructible base
## broadcasts, so a passed/dead turret stops emitting automatically.

## Projectile scenes cycled through in order (each must expose launch_on_curve).
@export var projectile_scenes: Array[PackedScene] = []
## Curve traced by every projectile, in the muzzle's local XY plane. Tweak this
## one resource to reshape all shots at once.
@export var curve: Curve2D
## Seconds between shots.
@export var fire_interval: float = 1.2
## How fast each projectile advances along the curve (world units/sec of arc).
@export var advance_speed: float = 20.0
## Delay before the first shot after activation.
@export var initial_delay: float = 0.5
## Muzzle the curve is traced relative to. Defaults to a "Muzzle" child of the
## parent, else the parent itself.
@export var muzzle_path: NodePath

var _body: Node3D = null
var _muzzle: Node3D = null
var _active: bool = false
var _cooldown: float = 0.0
var _next_index: int = 0


func _ready() -> void:
	_body = get_parent() as Node3D
	if muzzle_path != NodePath() and has_node(muzzle_path):
		_muzzle = get_node(muzzle_path) as Node3D
	elif _body and _body.has_node("Muzzle"):
		_muzzle = _body.get_node("Muzzle") as Node3D
	else:
		_muzzle = _body
	set_physics_process(false)


func setup(_player: Node3D) -> void:
	# Accepts the player ref for parity with other components; unused (no aiming).
	pass


func set_active(active: bool) -> void:
	_active = active
	set_physics_process(active)
	if active:
		_cooldown = initial_delay


func _physics_process(delta: float) -> void:
	if not _active or projectile_scenes.is_empty() or not curve:
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		_fire_one()
		_cooldown = fire_interval


func _fire_one() -> void:
	var scene: PackedScene = projectile_scenes[_next_index % projectile_scenes.size()]
	_next_index += 1
	if not scene:
		return

	var world: Node = get_tree().current_scene
	if not world:
		return

	var inst: Node = scene.instantiate()
	if not inst.has_method("launch_on_curve"):
		push_error("[TurretEmitter] projectile must expose launch_on_curve().")
		inst.queue_free()
		return

	world.add_child(inst)
	var base: Transform3D = _muzzle.global_transform if _muzzle else _body.global_transform
	inst.call("launch_on_curve", curve, base, advance_speed)
