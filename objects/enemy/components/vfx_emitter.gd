extends Node3D
class_name VfxEmitter

## Plays one-shot GPUParticles3D effects by key. Each child GPUParticles3D is
## registered under its node name (e.g. a child named "death" is played by
## emit("death")). On death we can reparent the effect so it survives the enemy.

var _effects: Dictionary = {}  # String -> GPUParticles3D


func _ready() -> void:
	for child in get_children():
		if child is GPUParticles3D:
			_effects[child.name] = child


## Fire a one-shot effect by key. If detach is true, the particle system is
## reparented to the current scene at its current global transform so it keeps
## emitting after the owning enemy is freed.
func emit(key: String, detach: bool = false) -> void:
	if not _effects.has(key):
		return
	var p: GPUParticles3D = _effects[key]

	if detach:
		var gx: Transform3D = p.global_transform
		var lifetime: float = p.lifetime
		remove_child(p)
		var scene: Node = get_tree().current_scene
		if scene:
			scene.add_child(p)
			p.global_transform = gx
			p.emitting = false
			p.restart()
			p.emitting = true
			# Free after it finishes emitting + one full lifetime.
			get_tree().create_timer(lifetime * 2.0 + 0.5).timeout.connect(p.queue_free)
		return

	p.emitting = false
	p.restart()
	p.emitting = true
