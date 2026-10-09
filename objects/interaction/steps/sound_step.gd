extends InteractionStep
class_name SoundStep

## Play a sound. Either point at an AudioStreamPlayer / AudioStreamPlayer3D in the
## level (for positional sound, or a player you've tuned), or just give a stream
## and it plays non-positionally.

## An AudioStreamPlayer or AudioStreamPlayer3D to play. Takes precedence.
@export var player: NodePath
## Played on a throwaway non-positional player if `player` is empty.
@export var stream: AudioStream
@export var volume_db: float = 0.0
## Hold the sequence until the sound ends.
@export var wait_for_finish: bool = false


func run(_interaction: Interaction) -> void:
	var node: Node = get_node_or_null(player)
	if node == null and stream:
		var one_shot := AudioStreamPlayer.new()
		one_shot.stream = stream
		one_shot.volume_db = volume_db
		add_child(one_shot)
		one_shot.finished.connect(one_shot.queue_free)
		node = one_shot
	if node == null:
		push_warning("[SoundStep] %s: set `player` or `stream`." % name)
		return
	node.call("play")
	if wait_for_finish and node.has_signal("finished"):
		await Signal(node, &"finished")
