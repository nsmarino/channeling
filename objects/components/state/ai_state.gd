extends Node
class_name BaseAIState

## Base state for AI-controlled entities
## Provides timing utilities and state lifecycle hooks

@export var state_name: String = ""

# References set by state machine
var state_machine: Node = null  # BaseStateMachine
var owner_node: Node = null  # The node this state controls

# Timing
var enter_state_time: float = 0.0


#region Lifecycle Methods

## Called every physics frame while this state is active
## Override to implement state behavior
func update(_delta: float) -> void:
	pass


## Check if this state should transition to another
## Return [true, "state_name"] to transition, [false, ""] to stay
func check_transition(_delta: float) -> Array:
	return [false, ""]


## Called when entering this state
## Override to initialize state
func on_enter() -> void:
	pass


## Called when exiting this state
## Override to clean up state
func on_exit() -> void:
	pass

#endregion


#region Timing Utilities

## Mark the time when this state was entered (called by state machine)
func mark_enter_state() -> void:
	enter_state_time = Time.get_unix_time_from_system()


## Get how long we've been in this state (in seconds)
func get_progress() -> float:
	var now: float = Time.get_unix_time_from_system()
	return now - enter_state_time


## Check if we've been in this state longer than the given time
func duration_longer_than(time: float) -> bool:
	return get_progress() >= time


## Check if we've been in this state less than the given time
func duration_less_than(time: float) -> bool:
	return get_progress() < time


## Check if we've been in this state between start and finish times
func duration_between(start: float, finish: float) -> bool:
	var progress: float = get_progress()
	return progress >= start and progress <= finish

#endregion


#region Helper Methods

## Request transition to another state via the state machine
func transition_to(next_state: String) -> void:
	if state_machine:
		state_machine.switch_to(next_state)

#endregion
