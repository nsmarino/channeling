extends TriggerState

## Idle state for overworld triggers
## The trigger stands still and waits


func on_enter() -> void:
	super.on_enter()
	_stop_movement()


func update(_delta: float) -> void:
	# Just stand still
	_stop_movement()


func check_transition(_delta: float) -> Array:
	# No automatic transitions from idle
	# Other states or external code can trigger transitions
	return [false, ""]
