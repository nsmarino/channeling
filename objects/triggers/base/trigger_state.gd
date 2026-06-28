extends BaseAIState
class_name TriggerState

## Base state for overworld triggers
## Extends BaseAIState with trigger-specific helpers

# Convenience accessor for the trigger body
var trigger_body: CharacterBody3D:
	get:
		return owner_node as CharacterBody3D

# Navigation agent reference (if present on trigger)
var nav_agent: NavigationAgent3D


#region Lifecycle

func on_enter() -> void:
	# Cache navigation agent reference
	if owner_node:
		nav_agent = owner_node.get_node_or_null("NavigationAgent3D")

#endregion


#region Movement Helpers

## Navigate toward a target position
func navigate_to(target: Vector3, speed: float, delta: float) -> void:
	if not trigger_body:
		return
	
	var ground_target: Vector3 = Vector3(target.x, trigger_body.global_position.y, target.z)
	var current_pos: Vector3 = trigger_body.global_position
	var direct_distance: float = current_pos.distance_to(ground_target)
	
	if direct_distance < 0.5:
		_stop_movement()
		return
	
	var direction: Vector3
	
	# Use navigation if available
	if nav_agent:
		nav_agent.target_position = ground_target
		if nav_agent.is_target_reachable() and not nav_agent.is_navigation_finished():
			var next_pos: Vector3 = nav_agent.get_next_path_position()
			direction = (next_pos - current_pos)
			direction.y = 0
			if direction.length() > 0.1:
				direction = direction.normalized()
			else:
				direction = (ground_target - current_pos).normalized()
		else:
			direction = (ground_target - current_pos).normalized()
	else:
		direction = (ground_target - current_pos).normalized()
	
	direction.y = 0
	
	# Rotate to face movement direction
	if direction.length() > 0.1:
		var target_rotation: float = atan2(direction.x, direction.z)
		trigger_body.rotation.y = lerp_angle(trigger_body.rotation.y, target_rotation, delta * 10.0)
	
	# Apply movement
	trigger_body.velocity = direction * speed
	trigger_body.move_and_slide()


## Stop all movement
func _stop_movement() -> void:
	if trigger_body:
		trigger_body.velocity = Vector3.ZERO
		trigger_body.move_and_slide()

#endregion
