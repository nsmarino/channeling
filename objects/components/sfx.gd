class_name Sfx
extends RefCounted

## One-shot sound effects that clean up after themselves.
##
## Each call makes a throwaway AudioStreamPlayer3D that frees itself when the
## sound ends. Use it from scripts that make a noise without owning a player
## node: actions, components, and things about to be freed (a pickup being
## collected), since `play_at` parents the player to the scene rather than to
## the caller.


## Play `stream` at a world position. The player is parented to the current
## scene, so the sound keeps going if `context` is freed a moment later.
## `pitch_variation` 0.1 = a random pitch within ±10%.
static func play_at(context: Node, stream: AudioStream, position: Vector3,
		volume_db: float = 0.0, pitch_variation: float = 0.0) -> AudioStreamPlayer3D:
	if stream == null or context == null or not context.is_inside_tree():
		return null
	var tree: SceneTree = context.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	var player: AudioStreamPlayer3D = _make(stream, volume_db, pitch_variation)
	parent.add_child(player)
	player.global_position = position
	player.play()
	return player


## Play `stream` attached to `node`, so it follows a moving source (a spinning
## enemy). Cut short if `node` is freed.
static func play_on(node: Node3D, stream: AudioStream,
		volume_db: float = 0.0, pitch_variation: float = 0.0) -> AudioStreamPlayer3D:
	if stream == null or node == null or not node.is_inside_tree():
		return null
	var player: AudioStreamPlayer3D = _make(stream, volume_db, pitch_variation)
	node.add_child(player)
	player.play()
	return player


static func _make(stream: AudioStream, volume_db: float, pitch_variation: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.finished.connect(player.queue_free)
	return player
