extends Node
class_name BaseStateMachine

## Base state machine for AI-controlled entities
## Manages state transitions and delegates updates to the current state

@export var owner_node: Node  ## The node this state machine controls
@export var default_state: String = "idle"

var states: Dictionary = {}  # { String : BaseAIState }
var current_state: Node = null  # BaseAIState


func _ready() -> void:
	# Wait a frame for all nodes to be ready
	await get_tree().process_frame
	
	_collect_states()
	_enter_default_state()


func _physics_process(delta: float) -> void:
	if current_state == null:
		return
	
	# Check for state transitions
	var verdict: Array = current_state.check_transition(delta)
	if verdict[0]:
		switch_to(verdict[1])
	
	# Update current state
	current_state.update(delta)


## Switch to a new state by name
func switch_to(next_state_name: String) -> void:
	if not states.has(next_state_name):
		push_warning("[%s] State '%s' not found" % [get_class(), next_state_name])
		return
	
	if current_state:
		current_state.on_exit()
	
	current_state = states[next_state_name]
	current_state.mark_enter_state()
	current_state.on_enter()


## Get the name of the current state
func get_current_state_name() -> String:
	if current_state and "state_name" in current_state:
		return current_state.state_name
	return ""


## Check if currently in a specific state
func is_in_state(state_name: String) -> bool:
	return get_current_state_name() == state_name


## Collect all child states that extend BaseAIState
func _collect_states() -> void:
	for child in get_children():
		if child is BaseAIState:
			states[child.state_name] = child
			# Give state a reference to this machine and owner
			child.state_machine = self
			child.owner_node = owner_node


## Enter the default state
func _enter_default_state() -> void:
	if states.has(default_state):
		current_state = states[default_state]
		current_state.mark_enter_state()
		current_state.on_enter()
	else:
		push_warning("[%s] Default state '%s' not found" % [get_class(), default_state])
