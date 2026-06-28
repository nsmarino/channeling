extends Node3D
class_name SfxEmitter

## Plays AudioStreamPlayer3D children by key (node name). On death, can detach a
## player so the sound finishes after the enemy is freed.

var _players: Dictionary = {}  # String -> AudioStreamPlayer3D


func _ready() -> void:
	for child in get_children():
		if child is AudioStreamPlayer3D:
			_players[child.name] = child


func play(key: String, detach: bool = false) -> void:
	if not _players.has(key):
		return
	var p: AudioStreamPlayer3D = _players[key]

	if detach:
		var gx: Transform3D = p.global_transform
		var stream_len: float = 2.0
		if p.stream:
			stream_len = p.stream.get_length() + 0.2
		remove_child(p)
		var scene: Node = get_tree().current_scene
		if scene:
			scene.add_child(p)
			p.global_transform = gx
			p.play()
			get_tree().create_timer(stream_len).timeout.connect(p.queue_free)
		return

	p.stop()
	p.play()
