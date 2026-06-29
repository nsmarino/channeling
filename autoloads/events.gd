extends Node

## Central signal bus. Cross-system communication (combat hits, player death)
## goes through here rather than direct node-to-node connections.

# Player lifecycle
signal player_killed

# Enemy / hit feedback
signal enemy_hp_changed(current: int, max_val: int)
signal enemy_damaged(amount: int)
signal attack_hit(attacker: Node, target: Node, damage: int)


func _ready() -> void:
	print("Init autoload events")
