extends Node

## Central signal bus. Cross-system communication (combat hits, player death)
## goes through here rather than direct node-to-node connections.

# Player lifecycle
signal player_killed

# Cutscene handoff — the Cinematic autoload brackets a cutscene with these, and
# the player suspends its own control while one is running (see player.gd).
signal cutscene_started
signal cutscene_finished

# Interactions (talk to an NPC, read a sign). An Interaction owns the prompt while
# the player is in range and runs its steps once triggered; the player suspends
# its own control for the duration, exactly as for a cutscene.
signal interaction_prompt_shown(text: String)
signal interaction_prompt_hidden
signal interaction_started(interaction: Node)
signal interaction_finished(interaction: Node)

# Enemy / hit feedback
signal enemy_hp_changed(current: int, max_val: int)
signal enemy_damaged(amount: int)
signal attack_hit(attacker: Node, target: Node, damage: int)


func _ready() -> void:
	print("Init autoload events")
