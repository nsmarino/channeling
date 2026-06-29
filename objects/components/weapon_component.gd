extends Component
class_name WeaponComponent

## Fires an enemy projectile scene on a timed cadence while active. Projectiles
## spawn at a muzzle and travel either toward the player or along the muzzle's
## forward. Kept deliberately simple — cadence config lives here, not in a resource.

## Projectile scene to spawn (root must expose launch(transform, direction, owner)).
@export var projectile_scene: PackedScene
## Seconds between shots (or between bursts).
@export var fire_interval: float = 1.5
## Projectiles per burst.
@export var burst_count: int = 1
## Seconds between shots within a burst.
@export var burst_spacing: float = 0.12
## Projectile speed (world units/sec).
@export var projectile_speed: float = 24.0
## Damage per projectile.
@export var damage: int = 10
## Aim at the player; if false, fire along the muzzle's -Z.
@export var aim_at_player: bool = true
## Delay before the first shot after activation.
@export var initial_delay: float = 0.6
## Muzzle marker; defaults to a "Muzzle" sibling/child or the body origin.
@export var muzzle_path: NodePath

var _body: Node3D = null
var _player: Node3D = null
var _muzzle: Node3D = null
var _cooldown: float = 0.0


func _setup() -> void:
	_body = host as Node3D
	if muzzle_path != NodePath() and has_node(muzzle_path):
		_muzzle = get_node(muzzle_path) as Node3D
	elif _body and _body.has_node("Muzzle"):
		_muzzle = _body.get_node("Muzzle") as Node3D
	set_physics_process(false)


func setup(player: Node3D) -> void:
	_player = player


func on_activate() -> void:
	set_physics_process(true)
	_cooldown = initial_delay


func on_deactivate() -> void:
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not is_active or not projectile_scene:
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		_fire_burst()
		_cooldown = fire_interval


func _fire_burst() -> void:
	for i in maxi(burst_count, 1):
		if i == 0:
			_fire_one()
		else:
			get_tree().create_timer(burst_spacing * i).timeout.connect(_fire_one)


func _fire_one() -> void:
	if not projectile_scene:
		return
	var world: Node = get_tree().current_scene
	if not world:
		return

	var origin: Vector3 = _muzzle.global_position if _muzzle else _body.global_position
	var direction: Vector3
	if aim_at_player and _player:
		direction = (_player.global_position - origin)
		if direction.length_squared() < 0.0001:
			direction = -_body.global_transform.basis.z
		direction = direction.normalized()
	elif _muzzle:
		direction = -_muzzle.global_transform.basis.z
	else:
		direction = -_body.global_transform.basis.z

	var inst: Node = projectile_scene.instantiate()
	if not inst.has_method("launch"):
		push_error("[WeaponComponent] projectile_scene must expose launch().")
		inst.queue_free()
		return

	world.add_child(inst)
	if "speed" in inst:
		inst.speed = projectile_speed
	if "damage" in inst:
		inst.damage = float(damage)
	var xform := Transform3D(Basis.IDENTITY, origin)
	inst.launch(xform, direction, _body)
