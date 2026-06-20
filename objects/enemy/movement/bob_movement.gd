extends MovementPattern
class_name BobMovement

## Oscillates the body back and forth along a fixed axis (default: vertical) with
## a sine wave. Independent of the player — good for blocks that rise and fall or
## slide side to side as hazards.
##
## Returns a velocity so it composes with the CharacterBody3D.move_and_slide()
## path that MovementComponent uses. Velocity is the time-derivative of
## position = amplitude * sin(2π f t), i.e. amplitude * 2π f * cos(2π f t).

## Local axis to oscillate along (normalized). Default is straight up.
@export var axis: Vector3 = Vector3.UP
## Peak displacement from the rest position, in world units.
@export var amplitude: float = 3.0
## Oscillations per second.
@export var frequency: float = 0.5
## Phase offset in turns (0..1) so multiple blocks can desync.
@export var phase: float = 0.0


func compute_velocity(_enemy: Node3D, _player: Node3D, time_active: float, _delta: float) -> Vector3:
	var dir: Vector3 = axis.normalized() if axis.length_squared() > 0.0001 else Vector3.UP
	var omega: float = TAU * frequency
	var speed: float = amplitude * omega * cos(omega * time_active + TAU * phase)
	return dir * speed
