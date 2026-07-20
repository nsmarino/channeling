extends MovementPattern
class_name NavWanderMovement

## Wanders the enemy around a baked navmesh using a NavigationAgent3D: pick a
## random reachable point nearby, walk the agent's path to it, pick another on
## arrival. Ignores the player entirely — this is idle ambient movement.
##
## Stateless by design, like the other patterns: the destination and the computed
## path live on the per-instance NavigationAgent3D node, not on this resource, so
## a single .tres can safely be shared by every enemy that wanders.
##
## Requires a NavigationAgent3D child on the enemy and a baked NavigationRegion3D
## in the level. Note the enemy body has no CollisionShape3D (only its HitBox
## area does), so it follows the path height directly rather than falling onto it.

## Movement speed (world units/sec).
@export var speed: float = 3.0
## Radius around its current spot within which new destinations are picked.
@export var wander_radius: float = 20.0
## Name of the NavigationAgent3D child on the enemy.
@export var agent_node_name: StringName = &"NavigationAgent3D"


func compute_velocity(enemy: Node3D, _player: Node3D, _time_active: float, _delta: float) -> Vector3:
	var agent := enemy.get_node_or_null(NodePath(String(agent_node_name))) as NavigationAgent3D
	if agent == null:
		return Vector3.ZERO

	var map: RID = agent.get_navigation_map()
	# The navigation map needs a sync pass before it can answer queries — until
	# then every point snaps to the origin, which would herd enemies to (0,0,0).
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.ZERO

	# Arrived (or no destination yet): roll a new one, start moving next frame.
	if agent.is_navigation_finished():
		_pick_destination(enemy, agent, map)
		return Vector3.ZERO

	var to_next: Vector3 = agent.get_next_path_position() - enemy.global_position
	if to_next.length_squared() < 0.0001:
		return Vector3.ZERO
	return to_next.normalized() * speed


## Random point in a disc around the enemy, snapped onto the navmesh so it's
## always reachable.
func _pick_destination(enemy: Node3D, agent: NavigationAgent3D, map: RID) -> void:
	var angle: float = randf() * TAU
	# sqrt keeps samples uniform across the disc instead of clumping at the centre.
	var dist: float = sqrt(randf()) * wander_radius
	var candidate: Vector3 = enemy.global_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	agent.target_position = NavigationServer3D.map_get_closest_point(map, candidate)
