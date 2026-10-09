extends InteractionStep
class_name CameraStep

## Switch the view to a Camera3D placed in the level (usually a child of the
## Interaction, so it moves with it). The Interaction blends back to the player's
## camera when the whole sequence ends.

## The camera to look through.
@export var camera: NodePath
## Seconds to blend from the current view (0 = cut).
@export var blend_time: float = 0.6
## Hold the sequence until the blend finishes. Off = the next step (a line of
## dialogue, say) starts while the camera is still moving.
@export var wait_for_blend: bool = true
## Optional: aim the camera at this node before blending — place it by position
## only and it stays framed wherever the Interaction is moved.
@export var look_at_target: NodePath


func run(interaction: Interaction) -> void:
	var cam := get_node_or_null(camera) as Camera3D
	if cam == null:
		push_warning("[CameraStep] %s: no Camera3D at '%s'." % [name, camera])
		return
	var target := get_node_or_null(look_at_target) as Node3D
	if target and cam.global_position.distance_to(target.global_position) > 0.01:
		cam.look_at(target.global_position, Vector3.UP)
	if wait_for_blend:
		await interaction.blend_camera_to(cam, blend_time)
	else:
		interaction.blend_camera_to(cam, blend_time)
