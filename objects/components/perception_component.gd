extends Component
class_name PerceptionComponent

## Vision cone for an enemy: reports whether it has noticed the player.
##
## Sight requires all of — inside `view_distance`, within `view_angle_deg` of the
## body's forward (-Z), and (optionally) an unobstructed line of sight. Because the
## body turns to face its travel direction, the cone naturally sweeps where the
## enemy is walking.
##
## Losing the player is deliberately sticky: once alerted it stays alerted until
## the player has been out of sight for `lose_grace` seconds or has broken
## `lose_distance`. Without that hysteresis the alert would flicker every time the
## player clipped the edge of the cone, and the brain would stutter between states.
##
## Read by EnemyBrain via is_alerted(); also emits signals for one-shot reactions.

signal player_spotted
signal player_lost

## How far the enemy can see.
@export var view_distance: float = 18.0
## Full width of the vision cone, in degrees (so 110 = 55 either side of forward).
@export var view_angle_deg: float = 110.0
## Once alerted, give up if the player gets beyond this.
@export var lose_distance: float = 26.0
## Once alerted, seconds out of sight before giving up.
@export var lose_grace: float = 3.0
## Require an unobstructed ray to the player (walls block sight).
@export var require_line_of_sight: bool = true
## Eye height above the body origin, for the sight ray.
@export var eye_height: float = 1.0
## Height on the player the sight ray aims at.
@export var target_height: float = 1.0
## Layers that block sight. Defaults to `environment` (layer 1).
@export_flags_3d_physics var sight_blockers: int = 1
@export var debug_log: bool = false

var _body: Node3D = null
var _player: Node3D = null
var _alerted: bool = false
var _time_unseen: float = 0.0


func _setup() -> void:
	_body = host as Node3D
	_player = get_tree().get_first_node_in_group("player") as Node3D
	set_physics_process(false)


func on_activate() -> void:
	set_physics_process(true)


func on_deactivate() -> void:
	set_physics_process(false)
	_alerted = false
	_time_unseen = 0.0


## True while the enemy is actively aware of the player.
func is_alerted() -> bool:
	return _alerted and is_instance_valid(_player)


func get_player() -> Node3D:
	return _player if is_instance_valid(_player) else null


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	if _body == null:
		return

	var dist: float = _flat_distance_to_player()
	if _can_see(dist):
		_time_unseen = 0.0
		if not _alerted:
			_alerted = true
			if debug_log:
				print("[Perception] %s spotted the player" % String(host.name))
			player_spotted.emit()
		return

	if not _alerted:
		return
	_time_unseen += delta
	if dist > lose_distance or _time_unseen >= lose_grace:
		_alerted = false
		if debug_log:
			print("[Perception] %s lost the player" % String(host.name))
		player_lost.emit()


func _flat_distance_to_player() -> float:
	var to := _player.global_position - _body.global_position
	to.y = 0.0
	return to.length()


func _can_see(dist: float) -> bool:
	if dist > view_distance:
		return false

	var to := _player.global_position - _body.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return true  # standing on top of us; call that seen.

	# Standard convention: -Z is forward (see MovementComponent).
	var forward := -_body.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return false
	if rad_to_deg(forward.normalized().angle_to(to.normalized())) > view_angle_deg * 0.5:
		return false

	return not require_line_of_sight or _has_line_of_sight()


func _has_line_of_sight() -> bool:
	var space := _body.get_world_3d().direct_space_state
	var from: Vector3 = _body.global_position + Vector3.UP * eye_height
	var to: Vector3 = _player.global_position + Vector3.UP * target_height
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = sight_blockers
	if _body is CollisionObject3D:
		query.exclude = [(_body as CollisionObject3D).get_rid()]
	return space.intersect_ray(query).is_empty()
