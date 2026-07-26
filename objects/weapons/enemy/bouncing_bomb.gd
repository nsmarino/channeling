extends RigidBody3D
class_name BouncingBomb

## A lobbed explosive that bounces off the level and detonates on the player.
##
## The point of it being a real RigidBody3D rather than a straight-line projectile
## is that it stays dangerous after it misses. A bolt that whiffs is gone; a bomb
## that whiffs is now loose in the room, ricocheting somewhere you have to account
## for. That is what makes crossing a bombarded space interesting rather than a
## timing puzzle — the hazard accumulates.
##
## It collides ONLY with the `environment` layer, exactly like PowerDrop, so the
## player cannot bat it around by walking into it. Contact with the player is
## detected by the PlayerSensor area instead, which keeps "what it bounces off"
## and "what sets it off" as separate, independently tunable things.
##
## Uncollected it simply expires — it does NOT explode by default. A fuse that
## always detonates would make the safe move "wait", which is the opposite of the
## intended pressure; set `explode_on_expire` if you want the other feel.

## Explosion spawned on detonation. Configured at runtime, so one blast scene
## serves every size of bang.
@export var blast_scene: PackedScene
@export var blast_radius: float = 3.0
@export var blast_damage: int = 18
@export var knockback_force: float = 12.0
@export var knockback_up: float = 5.0
@export var knockback_duration: float = 0.25

@export_group("Lifetime")
## Seconds before it gives up and despawns.
@export var fuse: float = 5.0
## Detonate when the fuse runs out instead of quietly vanishing.
@export var explode_on_expire: bool = false
## Seconds before it can hurt anyone. Without this a bomb spawned at a creature's
## muzzle could detonate on a player already standing next to that creature.
@export var arm_delay: float = 0.15
## Random tumble applied on launch (radians/sec).
@export var spin: float = 8.0

var _launched: bool = false
var _armed: bool = false
var _spent: bool = false
var _pending_impulse: Vector3 = Vector3.ZERO

@onready var _sensor: Area3D = $PlayerSensor


func _ready() -> void:
	set_physics_process(false)
	get_tree().create_timer(arm_delay).timeout.connect(_arm)
	get_tree().create_timer(fuse).timeout.connect(_expire)
	# The launcher may have called launch() before we entered the tree.
	if _pending_impulse != Vector3.ZERO:
		_apply_launch(_pending_impulse)


## Fire the bomb. Safe before or after the node enters the tree — too early and the
## impulse is stashed and applied on ready (same contract as PowerDrop.launch).
func launch(impulse: Vector3) -> void:
	if is_node_ready():
		_apply_launch(impulse)
	else:
		_pending_impulse = impulse


func _apply_launch(impulse: Vector3) -> void:
	if _launched:
		return
	_launched = true
	_pending_impulse = Vector3.ZERO
	linear_velocity = impulse
	angular_velocity = Vector3(
		randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
	) * spin


func _arm() -> void:
	_armed = true
	set_physics_process(true)


## Polled rather than signal-driven, for the same reason PowerDrop polls: the
## player can already be overlapping when the arm delay expires, and an
## edge-triggered body_entered would have fired and been discarded during it.
func _physics_process(_delta: float) -> void:
	if not _armed or _spent:
		return
	for body: Node3D in _sensor.get_overlapping_bodies():
		if body.is_in_group("player"):
			_detonate()
			return


func _expire() -> void:
	if _spent:
		return
	if explode_on_expire:
		_detonate()
	else:
		queue_free()


func _detonate() -> void:
	if _spent:
		return
	_spent = true
	set_physics_process(false)
	_spawn_blast()
	queue_free()


## Parented to the scene rather than to this bomb, so the explosion outlives the
## body that carried it.
func _spawn_blast() -> void:
	if blast_scene == null:
		return
	var world: Node = get_tree().current_scene
	if world == null:
		return
	var blast := blast_scene.instantiate() as Node3D
	if blast == null:
		return
	blast.set("radius", blast_radius)
	blast.set("damage", blast_damage)
	blast.set("damages_player", true)
	blast.set("knockback_force", knockback_force)
	blast.set("knockback_up", knockback_up)
	blast.set("knockback_duration", knockback_duration)
	world.add_child(blast)
	blast.global_position = global_position
