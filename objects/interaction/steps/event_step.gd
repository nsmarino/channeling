extends InteractionStep
class_name EventStep

## The hook for state changes. Sets a GameManager flag and/or emits `fired`, which
## you connect in the editor to anything in the level — open a gate, wake an
## enemy, enable a Portal. Runs instantly.

signal fired

## GameManager flag to set true ("" = none).
@export var set_flag: StringName = &""


func run(_interaction: Interaction) -> void:
	if not set_flag.is_empty():
		GameManager.set_flag(set_flag)
	fired.emit()
