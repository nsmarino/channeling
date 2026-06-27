extends PathFollow3D

## Drives the player rig forward along the rail by advancing `progress` each
## frame at a tweakable speed — replaces the old AnimationPlayer-driven
## progress_ratio sweep. The ToggleBrake action stops/resumes the advance.
##
## PathFollow3D.loop stays on, so progress wraps at the end of the curve just
## like the old looping animation did.

## Forward speed along the curve, in world units per second. (~20 ≈ the previous
## "1200u curve over 60s" feel.)
@export var speed: float = 20.0
## When true the rig holds position. Toggled by the ToggleBrake input.
@export var braked: bool = false


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("ToggleBrake"):
		braked = not braked
	if braked:
		return
	progress += speed * delta
