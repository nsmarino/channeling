extends Node

## Central signal bus. Cross-system communication (combat hits, player death)
## goes through here rather than direct node-to-node connections.

# Player lifecycle
signal player_killed

# Cutscene handoff — the Cinematic autoload brackets a cutscene with these, and
# the player suspends its own control while one is running (see player.gd).
signal cutscene_started
signal cutscene_finished

# Enemy / hit feedback
signal enemy_hp_changed(current: int, max_val: int)
signal enemy_damaged(amount: int)
signal attack_hit(attacker: Node, target: Node, damage: int)


func _ready() -> void:
	print("Init autoload events")
