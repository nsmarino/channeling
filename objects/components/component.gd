extends Node
class_name Component

## Base class for behavior components — small Nodes you attach to a host body
## (enemy, obstacle, player) to add one slice of behavior. The host coordinates
## its components through `set_active(bool)`: the Destructible base broadcasts its
## lifecycle (ACTIVE / DYING / PASSED) to every child exposing that method
## (duck-typed dispatch, so the host needs no per-component knowledge).
##
## Two flavors of component, both subclass this:
##   - Lifecycle-driven (movement, weapon, turret, animation): override
##     on_activate() / on_deactivate() to start and stop per-frame work.
##   - Event-driven (hit-react, blast): ignore activation entirely and instead
##     connect to host signals (`hit` / `died`) in _setup().
##
## GDScript is single-inheritance, so components that must BE a spatial node can't
## extend this Node-based class — HitBox / ContactDamage are Area3D, and the
## Sfx/VfxEmitter are Node3D. Those implement the same `set_active` contract by
## hand and are recognised by the host through the same duck-typed dispatch.

## Host to augment. Leave empty for the parent node (the usual case).
@export var host_path: NodePath

## The body this component is attached to. Resolved in _ready, before _setup().
var host: Node = null

## True between an on_activate() and the next on_deactivate().
var is_active: bool = false


func _ready() -> void:
	if host_path != NodePath() and has_node(host_path):
		host = get_node(host_path)
	else:
		host = get_parent()
	_setup()


## Override for one-time wiring that needs `host`: cache sibling nodes, connect to
## host signals, put the component in its dormant state. Called once, right after
## the host is resolved.
func _setup() -> void:
	pass


## Lifecycle broadcast from the host. Routes to on_activate / on_deactivate and
## guards against redundant repeat calls so each transition fires exactly once.
func set_active(active: bool) -> void:
	if active == is_active:
		return
	is_active = active
	if active:
		on_activate()
	else:
		on_deactivate()


## Override: begin per-frame work (enable processing, reset cooldowns/timers).
func on_activate() -> void:
	pass


## Override: stop per-frame work and clear transient state.
func on_deactivate() -> void:
	pass
