extends Node3D
class_name FlagSpawner

## Instances `scene` as a child while a GameManager flag is true — the ember in
## the nest once it's been given, a gate standing open, a sign that's been fixed.
##
## State, not an event: it checks on load as well as when the flag changes
## (Events.flag_changed), so what appeared is still there after a restart or a
## portal round trip. Clearing the flag removes it again.

@export var scene: PackedScene
@export var flag: StringName = &""

var _spawned: Node = null


func _ready() -> void:
	Events.flag_changed.connect(_on_flag_changed)
	_sync(GameManager.has_flag(flag))


func _on_flag_changed(changed: StringName, value: bool) -> void:
	if changed == flag:
		_sync(value)


func _sync(present: bool) -> void:
	if flag.is_empty() or scene == null:
		return
	if present and not is_instance_valid(_spawned):
		_spawned = scene.instantiate()
		add_child(_spawned)
	elif not present and is_instance_valid(_spawned):
		_spawned.queue_free()
		_spawned = null
