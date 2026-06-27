extends Node
class_name BlastComponent

## Spawns a blast sphere when the owning destructible dies — the "red" category.
##
## Unlike MovementComponent / WeaponComponent (which are driven each frame by the
## set_active() lifecycle), the blast is a *death event*: this connects to the
## parent FseDestructible's `died` signal and, when it fires, instantiates a Blast
## actor at the corpse and hands it this component's radius + damage. The Blast
## then damages nearby destructibles (is_blast=true), which can chain into more
## blasts. No set_active() needed.

## Blast actor to spawn (root must expose configure(radius, damage)).
@export var blast_scene: PackedScene
## Blast sphere DIAMETER in world units (spec is sized by diameter: small 3,
## medium 6, large 12). Halved to a radius for the spawned Blast.
@export var blast_diameter: float = 3.0
## Damage the blast deals to each destructible it catches (small 10, med 30,
## large 90).
@export var blast_damage: int = 10

var _body: Node3D = null


func _ready() -> void:
	_body = get_parent() as Node3D
	if _body and _body.has_signal("died"):
		_body.died.connect(_on_died)


func _on_died() -> void:
	if not blast_scene or not _body:
		return
	var world: Node = get_tree().current_scene
	if not world:
		return

	var inst: Node = blast_scene.instantiate()
	if not inst.has_method("configure"):
		push_error("[BlastComponent] blast_scene must expose configure(radius, damage).")
		inst.queue_free()
		return

	world.add_child(inst)
	(inst as Node3D).global_position = _body.global_position
	inst.configure(blast_diameter * 0.5, blast_damage)
