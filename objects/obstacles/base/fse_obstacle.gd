extends Destructible
class_name Obstacle

## Obstacle specialization of Destructible — a level hazard the player avoids.
## May be destructible or not, may move (MovementComponent / AnimationDriver) or
## be static. Contact damage is added via a ContactDamage child where desired.
##
## All HP / death-VFX / camera-passed-freeze / lifecycle-dispatch behavior comes
## from Destructible; this class only adds the destructible toggle and an
## optional proximity activation gate.

## If > 0, the obstacle waits in INACTIVE until the player gets this close, then
## activates (movement/animation start). If 0 or less, it is active on spawn.
@export var activation_distance: float = 0.0
## When false, take_damage is ignored — an indestructible block. Set
## homing_eligible = false on these too so the player can't lock onto them.
@export var is_destructible: bool = true


func _ready() -> void:
	add_to_group("obstacle")
	if activation_distance > 0.0:
		state = State.INACTIVE
	super._ready()
	# Hand the player ref to a movement component if present (patterns may use it).
	var mc: MovementComponent = get_node_or_null("MovementComponent")
	if mc:
		mc.setup(_player)


func _physics_process(delta: float) -> void:
	if state == State.INACTIVE:
		if not _player:
			_player = _resolve_player()
			return
		if global_position.distance_to(_player.global_position) <= activation_distance:
			_activate()
		return
	super._physics_process(delta)


func _activate() -> void:
	state = State.ACTIVE
	_dispatch_active(true)
	print("[%s] Activated." % _label())


func take_damage(amount: int, is_blast: bool = false) -> void:
	if not is_destructible:
		# Hit bounced off — give feedback but take no damage.
		if _sfx:
			_sfx.play("hit")
		return
	super.take_damage(amount, is_blast)


func _label() -> String:
	return "Obstacle:" + String(name)
