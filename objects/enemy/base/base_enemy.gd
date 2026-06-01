extends CharacterBody3D
class_name FseEnemy

## Lean rails-shooter enemy. The visible body is a real child node (added by
## inherited scenes, so it's editor-visible) — no runtime PackedScene instancing.
## Behavior is assembled from component children the root coordinates:
##   HitBox · MovementComponent · WeaponComponent · VfxEmitter · SfxEmitter
##
## Lifecycle: INACTIVE (waiting) -> ACTIVE (moving/attacking once the advancing
## player gets within activation_distance) -> DYING (death VFX/SFX, then freed).
## ACTIVE enemies that get passed by the camera flip to PASSED — they stay in
## the scene but stop moving and attacking (no rear-firing harassment).

signal died

enum State { INACTIVE, ACTIVE, DYING, PASSED }

@export var enemy_data: FseEnemyData
## Player must get this close (world units) before the enemy activates.
@export var activation_distance: float = 45.0
## Seconds the death VFX/SFX play before the enemy frees itself.
@export var death_duration: float = 1.2

# Component references (optional — resolved if present).
@onready var _movement: MovementComponent = get_node_or_null("MovementComponent")
@onready var _weapon: WeaponComponent = get_node_or_null("WeaponComponent")
@onready var _vfx: VfxEmitter = get_node_or_null("VfxEmitter")
@onready var _sfx: SfxEmitter = get_node_or_null("SfxEmitter")

var state: State = State.INACTIVE
var hp: int = 0
var max_hp: int = 0
var _player: Node3D = null


func _ready() -> void:
	add_to_group("enemy")

	max_hp = enemy_data.max_hp if enemy_data else 100
	hp = max_hp

	_player = _resolve_player()
	if _movement:
		_movement.setup(_player)
	if _weapon:
		_weapon.setup(_player)

	var label: String = String(enemy_data.display_name) if enemy_data else String(name)
	print("[Enemy:%s] Spawned (HP %d/%d), waiting to activate within %.0fu." % [label, hp, max_hp, activation_distance])


func _physics_process(_delta: float) -> void:
	match state:
		State.INACTIVE:
			if not _player:
				_player = _resolve_player()
				return
			if global_position.distance_to(_player.global_position) <= activation_distance:
				_activate()
		State.ACTIVE:
			# Freeze once the rail has flown past us; the camera handles arbitrary
			# orientations so this still works when PlayerRoot banks on a curve.
			var cam: Camera3D = get_viewport().get_camera_3d()
			if cam and cam.is_position_behind(global_position):
				_freeze_passed()


func _activate() -> void:
	state = State.ACTIVE
	if _movement:
		_movement.set_active(true)
	if _weapon:
		_weapon.set_active(true)
	var label: String = String(enemy_data.display_name) if enemy_data else String(name)
	print("[Enemy:%s] Activated." % label)


func _freeze_passed() -> void:
	state = State.PASSED
	if _movement:
		_movement.set_active(false)
	if _weapon:
		_weapon.set_active(false)
	velocity = Vector3.ZERO
	var label: String = String(enemy_data.display_name) if enemy_data else String(name)
	print("[Enemy:%s] Passed by rail; frozen." % label)


func take_damage(amount: int) -> void:
	if state == State.DYING or hp <= 0:
		return
	var prev: int = hp
	hp = maxi(0, hp - amount)
	var label: String = String(enemy_data.display_name) if enemy_data else String(name)
	print("[Enemy:%s] Took %d damage. HP: %d -> %d / %d" % [label, amount, prev, hp, max_hp])

	if _sfx:
		_sfx.play("hit")
	Events.enemy_damaged.emit(amount)
	Events.enemy_hp_changed.emit(hp, max_hp)

	if hp <= 0:
		_die()


func _die() -> void:
	state = State.DYING
	var label: String = String(enemy_data.display_name) if enemy_data else String(name)
	var score: int = enemy_data.score if enemy_data else 0
	print("[Enemy:%s] Destroyed! (+%d score)" % [label, score])

	if _movement:
		_movement.set_active(false)
	if _weapon:
		_weapon.set_active(false)
	velocity = Vector3.ZERO

	# Hide the body but keep the node alive briefly so detached VFX/SFX play.
	for child in get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false

	if _vfx:
		_vfx.emit("death", true)
	if _sfx:
		_sfx.play("death", true)

	died.emit()
	get_tree().create_timer(death_duration).timeout.connect(queue_free)


func _resolve_player() -> Node3D:
	var node: Node = get_tree().get_first_node_in_group("player")
	return node as Node3D


func is_defeated() -> bool:
	return hp <= 0 or state == State.DYING
