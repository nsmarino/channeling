extends Area3D
class_name HitBox

## Receives player projectiles and forwards damage to the owning enemy. Lives on
## the "enemy" physics layer; projectiles scan for it. The owner must expose
## take_damage(amount: int).

## Node that takes the damage. Defaults to the parent if left empty.
@export var damage_receiver_path: NodePath

var _receiver: Node = null


func _ready() -> void:
	if damage_receiver_path != NodePath() and has_node(damage_receiver_path):
		_receiver = get_node(damage_receiver_path)
	else:
		_receiver = get_parent()


## Called by player projectiles when they overlap this hitbox.
func receive_hit(amount: int) -> void:
	if _receiver and _receiver.has_method("take_damage"):
		_receiver.take_damage(amount)
