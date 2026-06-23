extends CanvasLayer

@onready var crosshair: Control = $Crosshair

var _player: Node = null

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")


func _process(_delta: float) -> void:
	_update_crosshair()


func _update_crosshair() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(_player):
			return

	if not _player.has_method("get_reticle_screen_position"):
		return
	if _player.has_method("is_aiming") and not _player.is_aiming():
		return

	# Hide the reticle while evading (aim is frozen).
	var evading: bool = _player.has_method("is_evading") and _player.is_evading()
	crosshair.visible = not evading
	if evading:
		return

	var screen_pos: Vector2 = _player.get_reticle_screen_position()
	crosshair.global_position = screen_pos - crosshair.size * 0.5
