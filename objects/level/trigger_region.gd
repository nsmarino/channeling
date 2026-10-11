extends Area3D
class_name TriggerRegion

## A level-authored volume that reports whether the player is inside it.
##
## WHY THIS EXISTS RATHER THAN A RADIUS. An EnemyAction can already gate itself on
## distance to the player, and for a creature that fights at arm's length that is
## enough. But a bombardment zone is a piece of LEVEL DESIGN, not a circle around a
## creature: "cross this courtyard while the Gevi-Dava lobs bombs from behind that
## wall" cannot be expressed as a range band, because the dangerous space and the
## creature are in different places — possibly not even in line of sight of each
## other. Same for bounding where a panicked creature is allowed to rampage.
##
## So a region is placed, shaped and sized in the editor independently of any
## creature, and creatures REFER to it. One region can drive several creatures, and
## one creature can care about several regions.
##
## It also feeds ALERTNESS, which is the part that is easy to miss: perception
## needs line of sight, so a creature behind a wall would never notice the player
## and never fire. EnemyBrain treats an occupied region as an alert source in its
## own right — see EnemyBrain._is_alerted().
##
## Polled rather than signal-driven, matching MeleeHitbox / BouncePad / BumpCombat:
## a handful of area queries per frame is nothing, and polling cannot desync the
## way a missed enter/exit pair can.

signal player_entered
signal player_exited

## Group a body must belong to to count as occupying the region.
@export var target_group: StringName = &"player"
@export var debug_log: bool = false

var _occupied: bool = false


## Collision layer the player body is on (project layer 2, "player").
const PLAYER_LAYER_BIT: int = 1 << 1


## Default to "detect the player, be detected by nothing". Area3D's own default
## (layer 1, mask 1) never sees the player, so one made from a bare Area3D with
## this script attached would silently never fire. Runs before the scene's saved
## properties are applied, so a mask set in the Inspector still wins.
func _init() -> void:
	collision_layer = 0
	collision_mask = PLAYER_LAYER_BIT


func _ready() -> void:
	add_to_group("trigger_region")
	monitoring = true
	if collision_mask & PLAYER_LAYER_BIT == 0:
		push_warning("[TriggerRegion] %s: collision_mask doesn't include the player layer (2), so the player can never trigger it." % get_path())


## True while a member of `target_group` is inside.
func is_occupied() -> bool:
	return _occupied


func _physics_process(_delta: float) -> void:
	var now: bool = _find_target() != null
	if now == _occupied:
		return
	_occupied = now
	if debug_log:
		print("[TriggerRegion] %s %s" % [String(name), "entered" if now else "exited"])
	if now:
		player_entered.emit()
	else:
		player_exited.emit()


## The occupying body, or null. Exposed so an action can aim at where the player
## actually is even when the creature cannot see them.
func get_target() -> Node3D:
	return _find_target()


func _find_target() -> Node3D:
	for body: Node3D in get_overlapping_bodies():
		if body.is_in_group(target_group):
			return body
	return null
