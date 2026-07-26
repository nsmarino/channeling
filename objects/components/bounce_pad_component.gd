extends Area3D
class_name BouncePadComponent

## Launches whoever lands on it along the pad's own +Y.
##
## The first INTERACTABLE: a thing that acts on the player without being a
## creature or a target. Note that there is no `Interactable` base class and no
## HP here — an interactable is a CAPABILITY you bolt onto any body, not a kind of
## object. That is what lets the same component sit on a mushroom, a door, or one
## day an enemy's head, without any inheritance to negotiate.
##
## Launch direction is the pad's OWN +Y (`global_transform.basis.y`), not world
## up, so tilting the node in the editor fires the player off at an angle. Tuning
## is `launch_speed` plus the node's rotation — both draggable in the viewport.
##
## Landing only. The overlap must be a DESCENDING body, so running into the side
## of a mushroom does nothing and only coming down on top of it launches you.
##
## Sizes are one scene, not three: instance it and change `launch_speed` (and the
## node scale to match visually).
##
## Single-inheritance caveat: this must BE an Area3D, so like HitBox and
## MeleeHitbox it can't extend the Node-based Component.

signal launched(body: Node3D)

## Speed imparted along the pad's +Y. The player's launch() cancels their existing
## motion along that axis first, so this is the speed you actually get regardless
## of how hard you came down.
@export var launch_speed: float = 14.0
## Skip a body that is already travelling UP the axis — it has just been launched
## and is on its way out, so this stops a second launch on the way through.
##
## Note what this does NOT do: it does not try to prove the body arrived from
## above. GEOMETRY proves that — the trigger volume sits above the solid cap, so
## the only way into it is to come down onto it. An earlier version tested for
## downward velocity instead and almost never fired, because Godot reports area
## overlaps from the PREVIOUS physics step while move_and_slide has already zeroed
## the lander's velocity by the time this polls: the pad kept seeing a body that
## was, as far as it could tell, standing still.
@export var ignore_rising: bool = true
## How fast a body must be rising to count as "on its way out".
@export_range(0.0, 20.0, 0.1) var rising_threshold: float = 0.5
## Seconds before the same body can be launched again — stops a body that is still
## overlapping on the next frame from being fired twice.
@export_range(0.0, 2.0, 0.05) var retrigger_delay: float = 0.3
## Group a body must belong to to be launched.
@export var target_group: StringName = &"player"
## Optional SfxEmitter key played on launch. Empty = silent.
@export var sfx_key: StringName = &""
## Node holding the SFX. Empty = look for a sibling "SfxEmitter".
@export var sfx_path: NodePath

var _sfx: Node = null
# Per-body cooldown remaining (seconds).
var _cooldown_by_body: Dictionary = {}  # Node -> float


func _ready() -> void:
	_sfx = get_node_or_null(sfx_path)
	if _sfx == null and get_parent():
		_sfx = get_parent().get_node_or_null("SfxEmitter")
	monitoring = true


func _physics_process(delta: float) -> void:
	# Tick cooldowns down; keys() is a copy, so erasing while iterating is safe.
	for body: Node in _cooldown_by_body.keys():
		_cooldown_by_body[body] -= delta
		if _cooldown_by_body[body] <= 0.0:
			_cooldown_by_body.erase(body)

	for body: Node3D in get_overlapping_bodies():
		if not body.is_in_group(target_group):
			continue
		if _cooldown_by_body.has(body):
			continue
		if not body.has_method("launch"):
			continue
		if ignore_rising and _is_rising(body):
			continue
		_launch(body)


## Is this body already travelling up the pad's own axis? Measured against that
## axis rather than world Y, so a tilted pad judges it relative to its own face.
func _is_rising(body: Node3D) -> bool:
	var v: Variant = body.get("velocity")
	if not (v is Vector3):
		return false
	var axis: Vector3 = global_transform.basis.y.normalized()
	return (v as Vector3).dot(axis) > rising_threshold


func _launch(body: Node3D) -> void:
	_cooldown_by_body[body] = retrigger_delay
	var axis: Vector3 = global_transform.basis.y.normalized()
	body.call("launch", axis * launch_speed)
	if _sfx and sfx_key != &"" and _sfx.has_method("play"):
		_sfx.call("play", String(sfx_key))
	launched.emit(body)
