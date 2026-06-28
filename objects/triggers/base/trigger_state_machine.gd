extends BaseStateMachine
class_name TriggerStateMachine

## State machine for overworld triggers
## Extends BaseStateMachine with trigger-specific functionality

# Convenience accessor for the trigger body
var trigger_body: CharacterBody3D:
	get:
		return owner_node as CharacterBody3D


## Override to collect TriggerState children specifically
func _collect_states() -> void:
	for child in get_children():
		if child is TriggerState:
			states[child.state_name] = child
			# Give state references
			child.state_machine = self
			child.owner_node = owner_node
