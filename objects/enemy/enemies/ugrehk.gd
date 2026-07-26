extends Enemy
class_name Ugrehk

## A mushroom that isn't one.
##
## It sits at ground level looking like the breakable Mushroom 1 — the whole point
## is that you cannot tell them apart, so harvesting a patch of mushrooms carries a
## risk. Bump it and instead of bursting it ERUPTS: a long stalk shoots up out of
## the ground carrying a mouth, and now you are in a fight.
##
## The disguise is `activation_mode = BUMP` on the base: while INACTIVE the first
## hit wakes it and deals no damage, so it cannot be quietly killed before it has
## revealed itself. That would defeat the trick entirely — a player who bumped
## every mushroom would never learn to fear one.
##
## The reveal is a position tween rather than an animation because the whole body
## is one rigid shape: the creature lives most of its length UNDERGROUND, sunk by
## `hidden_depth`, and rising to y=0 is the entire transformation. Nothing needs to
## be modelled twice.
##
## The HitBox rises with it. It has to be raised separately rather than parented to
## the model, because the bump system identifies an enemy as its HitBox's PARENT —
## reparenting the box under the model would break both the is_defeated() check and
## the DropComponent lookup.

## The visual, sunk while disguised.
@export var model_path: NodePath = ^"Model"
## The hurtbox, raised alongside the model so a revealed Ugrehk is struck along its
## stalk rather than at its base.
@export var hitbox_path: NodePath = ^"HitBox"
## How far underground it waits. The cap should sit at ground level at this depth.
@export var hidden_depth: float = -1.55
## Hurtbox height while disguised — low, covering only the visible cap.
@export var hidden_hitbox_y: float = 0.3
## Hurtbox height once revealed.
@export var revealed_hitbox_y: float = 1.2
## Seconds the eruption takes.
@export var reveal_time: float = 0.35

var _model: Node3D = null
var _hitbox: Node3D = null


func _ready() -> void:
	super._ready()
	_model = get_node_or_null(model_path) as Node3D
	_hitbox = get_node_or_null(hitbox_path) as Node3D
	# Only sink it if it is actually waiting. An Ugrehk placed pre-activated (or
	# woken by something else first) should already be standing.
	if state == State.INACTIVE:
		if _model:
			_model.position.y = hidden_depth
		if _hitbox:
			_hitbox.position.y = hidden_hitbox_y


## Erupt. Called by the base the moment activation happens, whatever triggered it.
func _on_activated() -> void:
	if _model == null and _hitbox == null:
		return
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	# BACK/EASE_OUT overshoots slightly at the top, so it reads as bursting out of
	# the ground rather than being raised on a lift.
	if _model:
		tween.tween_property(_model, "position:y", 0.0, reveal_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _hitbox:
		tween.tween_property(_hitbox, "position:y", revealed_hitbox_y, reveal_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _label() -> String:
	return "Ugrehk:" + String(name)


func _death_message() -> String:
	return "Uprooted!"
