extends Node
class_name EnemyCoordinator

## Per-encounter blackboard + turn-taking for a group of enemies — the shared state
## individual EnemyBrains read and write so they coordinate instead of dogpiling.
##
## Entirely OPTIONAL: a brain that finds no coordinator behaves exactly like a solo
## enemy. Drop one node under the level; brains locate it via the
## "enemy_coordinator" group. It provides three things:
##
##   - Attack slots — at most `max_attackers` group members may be mid-attack at
##     once; the rest keep pressure by orbiting. This is what stops three enemies
##     swinging at the player simultaneously (unreadable) and makes group melee
##     feel fair (the Arkham/Assassin's-Creed "one or two attack at a time" rule).
##   - Shared perception — one member's sighting alerts the whole group, so an
##     enemy that spots the player can recruit its allies.
##   - Ring slots — engaged members get evenly-spread angles around the player, so
##     they surround it rather than stack. This is the cheap prototyping stand-in
##     for RVO avoidance: the enemy bodies don't physically collide (they're on
##     collision layer 0), so spacing is a coordination problem, not a physics one.
##
## It holds instance ids, not node refs, and prunes freed ones, so a dead enemy
## can't keep a slot forever.

## How many group members may attack simultaneously.
@export var max_attackers: int = 1
## Seconds a sighting stays "fresh" — how long the group stays alerted after the
## last member to see the player loses sight of them.
@export var sighting_memory: float = 4.0

var _attackers: Array[int] = []  # instance ids currently attacking
var _engaged: Array[int] = []    # instance ids in CHASE/COMBAT, ordered → ring slots
var _last_seen_pos: Vector3 = Vector3.ZERO
var _last_seen_msec: int = -100000


func _ready() -> void:
	add_to_group("enemy_coordinator")


# --- Attack slots ----------------------------------------------------------

## May this enemy attack right now? (Already holding a slot counts.) All-or-
## nothing: on false the caller should do something else, e.g. orbit.
func claim_attack_slot(enemy: Node) -> bool:
	_prune(_attackers)
	var id: int = enemy.get_instance_id()
	if _attackers.has(id):
		return true
	if _attackers.size() >= max_attackers:
		return false
	_attackers.append(id)
	return true


func release_attack_slot(enemy: Node) -> void:
	_attackers.erase(enemy.get_instance_id())


# --- Shared perception -----------------------------------------------------

func report_player_seen(pos: Vector3) -> void:
	_last_seen_pos = pos
	_last_seen_msec = Time.get_ticks_msec()


func has_fresh_sighting() -> bool:
	return Time.get_ticks_msec() - _last_seen_msec <= int(sighting_memory * 1000.0)


func get_last_seen_pos() -> Vector3:
	return _last_seen_pos


# --- Ring slots (spacing) --------------------------------------------------

## Reserve a ring slot (call on entering CHASE/COMBAT).
func engage(enemy: Node) -> void:
	var id: int = enemy.get_instance_id()
	if not _engaged.has(id):
		_engaged.append(id)


## Give up the ring slot and any attack slot (call on returning to WANDER / death).
func disengage(enemy: Node) -> void:
	_engaged.erase(enemy.get_instance_id())
	release_attack_slot(enemy)


## World-space angle (radians) assigned to this enemy: its slot on the ring around
## the player, spread evenly across everyone currently engaged.
func get_ring_angle(enemy: Node) -> float:
	_prune(_engaged)
	var i: int = _engaged.find(enemy.get_instance_id())
	if i < 0 or _engaged.is_empty():
		return 0.0
	return TAU * float(i) / float(_engaged.size())


## Drop instance ids whose nodes have been freed.
func _prune(ids: Array[int]) -> void:
	for i in range(ids.size() - 1, -1, -1):
		if instance_from_id(ids[i]) == null:
			ids.remove_at(i)
