extends CanvasLayer

## Minimal HUD: a fixed center crosshair plus a health readout polled from the
## player each frame. The Crosshair Control is center-anchored in the scene, so it
## stays put on its own — this script only keeps it visible and mirrors `hp`.

@onready var crosshair: Control = $Crosshair
@onready var health_label: Label = $Health

var _player: Node = null


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	crosshair.visible = true
	# Hide the legacy lock-on indicator if the scene still carries it.
	var lock_on: Control = get_node_or_null("LockOn")
	if lock_on:
		lock_on.visible = false


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(_player) and "hp" in _player:
		health_label.text = "HEALTH: %d" % int(_player.hp)
