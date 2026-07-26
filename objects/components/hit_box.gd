extends Area3D
class_name HitBox

## Receives hits and forwards damage to the owning destructible. Lives on the
## `hurtbox` physics layer; the player's bump combat and projectiles scan for it.
## The owner must expose take_damage(amount: int).
##
## An owner can carry SEVERAL of these to make some parts count for more than
## others — a weak point, or armour that shrugs hits off (see `override_damage`).

## Node that takes the damage. Defaults to the parent if left empty.
@export var damage_receiver_path: NodePath
## When > 0, every hit deals exactly this much, ignoring what the attacker asked
## for. Turns the hitbox into a fixed-value weak point, which is what you want
## whenever the attacker's own damage model doesn't apply — bump damage scales by
## how far behind the target you struck, and "behind" is meaningless on something
## that spins, or on a single eye in a ring of them. Set the owner's max_hp to a
## multiple of this and the hit count becomes exact.
@export_range(0, 200, 1) var override_damage: int = 0

var _receiver: Node = null


func _ready() -> void:
	if damage_receiver_path != NodePath() and has_node(damage_receiver_path):
		_receiver = get_node(damage_receiver_path)
	else:
		_receiver = get_parent()


## Called by the player's bump combat and by projectiles overlapping this hitbox.
func receive_hit(amount: int) -> void:
	if _receiver and _receiver.has_method("take_damage"):
		_receiver.take_damage(override_damage if override_damage > 0 else amount)
