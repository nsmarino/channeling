extends CharacterBody3D
class_name Destructible

## Base class for anything in the level that the player can shoot: enemies,
## obstacles, turret-projectiles, etc. Provides HP / take_damage / death-with-VFX
## and a simple lifecycle: ACTIVE → DYING (subclasses may add an INACTIVE wait).
##
## Subclasses add their own activation model on top (e.g. Enemy waits in
## INACTIVE until the player gets within range; obstacles & turret-projectiles
## start ACTIVE on spawn).
##
## Component children are coordinated by duck-typed dispatch: any child that
## exposes `set_active(bool)` is called on lifecycle transitions. That covers
## MovementComponent, WeaponComponent, AnimationDriver, ContactDamage, etc.
## without the base needing to know about each one specifically.

signal died
## Emitted when damage actually lands (after the blast_only / dying guards), with
## the amount. Drives per-instance reactions like HitReactComponent.
signal hit(amount: int)

enum State { INACTIVE, ACTIVE, DYING }

@export var max_hp: int = 100
## Seconds the death VFX/SFX play before the body is freed.
@export var death_duration: float = 1.2
## When true, this destructible ignores all non-blast damage — it can ONLY be
## destroyed by a blast (the "green" category). Normal hits play a cue but deal
## no damage; a BlastComponent's blast passes is_blast=true and gets through.
@export var blast_only: bool = false
## Print each hit and the death line. Off by default: a level dressed with dozens
## of bump-destructible props would otherwise flood the console.
@export var debug_log: bool = false

# Resolved component children (optional — missing ones are simply skipped).
@onready var _vfx: VfxEmitter = get_node_or_null("VfxEmitter")
@onready var _sfx: SfxEmitter = get_node_or_null("SfxEmitter")

var state: State = State.ACTIVE
var hp: int = 0
var _player: Node3D = null


func _ready() -> void:
	add_to_group("destructible")
	hp = max_hp
	_player = _resolve_player()
	# Dispatch the initial lifecycle so children (movement, animation, etc.)
	# start in the correct enabled/disabled state.
	_dispatch_active(state == State.ACTIVE)


## Apply damage. `is_blast` marks damage coming from a blast radius — the only
## kind that can hurt a `blast_only` ("green") destructible.
func take_damage(amount: int, is_blast: bool = false) -> void:
	if state == State.DYING or hp <= 0:
		return
	# Green shrugs off everything but blast damage (still gives a hit cue).
	if blast_only and not is_blast:
		if _sfx:
			_sfx.play("hit")
		return
	var prev: int = hp
	hp = maxi(0, hp - amount)
	if debug_log:
		print("[%s] Took %d damage. HP: %d -> %d / %d" % [_label(), amount, prev, hp, max_hp])

	if _sfx:
		_sfx.play("hit")
	_report_damage(amount)
	hit.emit(amount)

	if hp <= 0:
		_die()


## Public way to trigger the death sequence without going through HP (e.g. a
## kamikaze enemy that explodes on contact). No-op if already dying/dead.
func destroy() -> void:
	if state == State.DYING or hp <= 0:
		return
	hp = 0
	_die()


func _die() -> void:
	state = State.DYING
	_dispatch_active(false)
	velocity = Vector3.ZERO
	if debug_log:
		print("[%s] %s" % [_label(), _death_message()])

	# Hide the body but keep the node alive briefly so detached VFX/SFX play.
	_hide_meshes(self)

	if _vfx:
		_vfx.emit("death", true)
	if _sfx:
		_sfx.play("death", true)

	died.emit()
	get_tree().create_timer(death_duration).timeout.connect(queue_free)


## Hide every mesh in the subtree so the corpse vanishes while the node lingers
## for its detached VFX/SFX.
##
## Recursive on purpose: an imported .glb parks its MeshInstance3Ds several levels
## down (under the model root and its Skeleton3D), so the old top-level-only scan
## missed them entirely and modelled enemies stayed fully visible until the
## death_duration timer freed them.
##
## VfxEmitter is skipped — its subtree is the death burst we're about to play.
func _hide_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is VfxEmitter:
			continue
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false
		_hide_meshes(child)


## Iterate component children with a `set_active(bool)` method and call them.
## This is the single lifecycle hook the base broadcasts; new drivers
## (AnimationDriver, ContactDamage, etc.) plug in just by exposing the method.
func _dispatch_active(active: bool) -> void:
	for child in get_children():
		if child.has_method("set_active"):
			child.call("set_active", active)


func _resolve_player() -> Node3D:
	var node: Node = get_tree().get_first_node_in_group("player")
	return node as Node3D


func is_defeated() -> bool:
	return hp <= 0 or state == State.DYING


# --- Virtual hooks ---------------------------------------------------------
#
# Subclasses override these to customize reporting and log lines without
# overriding the whole _die/take_damage flow.

## Broadcast a landed hit to the rest of the game. A bare Destructible reports
## nothing: a bump-destructible mushroom is scenery, and it has no business
## driving the enemy HUD channel. `Enemy` overrides this to emit the
## Events.enemy_* signals.
func _report_damage(_amount: int) -> void:
	pass


## Used in console logs as "[<label>] ...". Override to use a display_name etc.
func _label() -> String:
	return "Destructible:" + String(name)

## Message printed when the body dies. Override to add score / extras.
func _death_message() -> String:
	return "Destroyed!"
