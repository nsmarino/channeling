extends RigidBody3D
class_name PowerDrop

## A small physics pickup that pops out of an enemy on a landed bump, bounces and
## rolls along the floor, and is collected by walking into it.
##
## Physics: a sphere collider plus a bouncy PhysicsMaterial, launched with an
## upward, randomly-angled impulse. It collides ONLY with the `environment` layer,
## so the player walks through it instead of kicking it away — collection is
## handled by the PickupArea child (which scans the `player` layer) rather than by
## physical contact.
##
## Collection routes through a duck-typed `collect_power(amount)` on the player.

## Power granted on pickup.
@export var power_value: int = 1
## Seconds before it despawns uncollected. This is the pickup window.
@export var lifetime: float = 12.0
## Seconds after spawning before it can be collected — without this it would be
## grabbed instantly, since the player is right on top of the enemy it burst from.
@export var arm_delay: float = 0.35
## Seconds after spawning before physics is frozen, so a drop doesn't keep
## drifting across the floor. Much shorter than `lifetime` — it settles early and
## then just sits there, collectable, until it despawns.
@export var settle_delay: float = 2.5
## Random tumble applied on launch (radians/sec).
@export var spin: float = 6.0

## Speed below which the drop counts as settled. Checked at `settle_delay` so a
## drop still mid-bounce isn't frozen in mid-air.
const SETTLE_SPEED: float = 0.6
## How often to re-check once `settle_delay` has passed but it's still moving.
const SETTLE_RETRY: float = 0.25

var _launched: bool = false
var _pending_impulse: Vector3 = Vector3.ZERO

@onready var _pickup_area: Area3D = $PickupArea


func _ready() -> void:
	# Poll for the player rather than connecting body_entered: the drop bursts out
	# right where the player is standing, so they're usually ALREADY inside the
	# pickup radius when the arm delay expires. body_entered is edge-triggered and
	# would have fired (and been discarded) during that delay, leaving the drop
	# uncollectable until the player walked away and back. Same reason
	# ContactDamage polls its overlaps.
	set_physics_process(false)
	get_tree().create_timer(arm_delay).timeout.connect(_arm)
	get_tree().create_timer(settle_delay).timeout.connect(_settle)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	# Spawner may have called launch() before we entered the tree.
	if _pending_impulse != Vector3.ZERO:
		_apply_launch(_pending_impulse)


## Pop the drop out with an impulse. Safe to call before or after the node is in
## the tree — if it's too early the impulse is stashed and applied on ready.
func launch(impulse: Vector3) -> void:
	if is_node_ready():
		_apply_launch(impulse)
	else:
		_pending_impulse = impulse


func _apply_launch(impulse: Vector3) -> void:
	if _launched:
		return
	_launched = true
	_pending_impulse = Vector3.ZERO
	linear_velocity = impulse
	angular_velocity = Vector3(
		randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
	) * spin


## Arm delay expired — start looking for the player.
func _arm() -> void:
	set_physics_process(true)


## Park the drop in place so it stops creeping around. Freezing only stops the
## body's simulation — the PickupArea keeps monitoring, so a settled drop is
## still collectable. If it's still bouncing, wait rather than freeze mid-air.
func _settle() -> void:
	if linear_velocity.length() > SETTLE_SPEED:
		get_tree().create_timer(SETTLE_RETRY).timeout.connect(_settle)
		return
	freeze = true


func _physics_process(_delta: float) -> void:
	for body: Node3D in _pickup_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			_collect(body)
			return


func _collect(player: Node) -> void:
	set_physics_process(false)
	if player.has_method("collect_power"):
		player.call("collect_power", power_value)
	queue_free()
