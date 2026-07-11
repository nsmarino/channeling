extends Node3D
class_name LockOnTargetComponent

## Opt-in lock-on marker. Add as a child of any entity (enemy, prop, boss) and
## place it at the point the camera should aim at when locked — usually chest or
## head height. Its `global_position` is that aim point; `get_parent()` is the
## entity the LockOnComponent treats as the target.
##
## Eligibility is by GROUP, not class: the marker simply registers itself in the
## "lockable" group so the LockOnComponent can find it via
## get_nodes_in_group("lockable") without a class_name (dodging the class-cache
## lag, matching the nurbs plugin's duck-typed style).

## Whether this target can currently be locked. Turn off for props you don't want
## stealing the lock, or flip at runtime via set_lockable().
@export var enabled: bool = true:
	set(value):
		enabled = value
		if is_inside_tree():
			set_lockable(value)


func _ready() -> void:
	if enabled:
		add_to_group(&"lockable")


## Add/remove this marker from the "lockable" group at runtime.
func set_lockable(value: bool) -> void:
	enabled = value
	if value:
		if not is_in_group(&"lockable"):
			add_to_group(&"lockable")
	elif is_in_group(&"lockable"):
		remove_from_group(&"lockable")
