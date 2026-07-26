@tool
extends EditorPlugin

## Run the scene with the player spawned wherever you point — Unreal's
## "Play From Here".
##
## **Ctrl+Shift+Right-click** anywhere in the 3D viewport. The plugin raycasts
## under the cursor, writes the hit point to a one-shot file, and plays the current
## scene; `GameManager` reads that file on startup and drops the player there.
##
## Why a modifier rather than a plain right-click: bare RMB is freelook in Godot's
## 3D viewport, and stealing it would break camera navigation.
##
## Why it REFUSES when the ray hits nothing: spawning in the void would put the
## player below `fall_limit_y`, and GameManager would restart the level instantly
## — you'd get a confusing respawn at the level start rather than an obvious
## failure. Better to say "no surface there" and not run.
##
## The point survives death. GameManager keeps it for the whole session, so dying
## respawns you at the spot you were testing instead of dumping you back at the
## level start — which is the entire reason the tool is worth having.

## Shared with GameManager, which reads and deletes it. `user://` because both the
## editor and the game resolve it to the same place, and it must not end up in the
## project or in version control.
const SPAWN_FILE: String = "user://play_from_here.cfg"

## Layers the placement ray tests against. Defaults to `environment` (layer 1),
## where CSG blockout collision lives.
const GROUND_MASK: int = 1

## How far the ray reaches.
const RAY_LENGTH: float = 4000.0

## Lifted above the surface so the player doesn't spawn embedded in the floor and
## get pushed out sideways.
const SPAWN_LIFT: float = 1.0


func _handles(object: Object) -> bool:
	# Must claim Node3D for _forward_3d_gui_input to be delivered at all. We add no
	# controls and no gizmos, so nothing about normal editing changes — but it does
	# mean a Node3D has to be SELECTED for the shortcut to reach us.
	return object is Node3D


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not (event is InputEventMouseButton):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var click := event as InputEventMouseButton
	if click.button_index != MOUSE_BUTTON_RIGHT or not click.pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not (click.ctrl_pressed and click.shift_pressed):
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	_play_from(viewport_camera, click.position)
	# Swallow it so the viewport doesn't also start a freelook drag.
	return EditorPlugin.AFTER_GUI_INPUT_STOP


func _play_from(camera: Camera3D, screen_pos: Vector2) -> void:
	var point: Variant = _surface_under(camera, screen_pos)
	if point == null:
		push_warning("[PlayFromHere] Nothing on the environment layer under the cursor — not playing. Aim at the floor.")
		return

	var spawn: Vector3 = (point as Vector3) + Vector3.UP * SPAWN_LIFT
	if not _write_spawn(spawn):
		push_warning("[PlayFromHere] Could not write %s — not playing." % SPAWN_FILE)
		return

	print("[PlayFromHere] Spawning player at %s" % str(spawn))
	EditorInterface.play_current_scene()


## World point under the cursor, or null if the ray hit nothing.
##
## Uses the EDITED scene's physics space, which the editor does populate — CSG
## nodes with `use_collision` generate their bodies at edit time, so the blockout
## is hittable without running the game.
func _surface_under(camera: Camera3D, screen_pos: Vector2) -> Variant:
	if camera == null:
		return null
	var world: World3D = camera.get_world_3d()
	if world == null:
		return null

	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = GROUND_MASK

	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	return hit["position"] if hit.has("position") else null


func _write_spawn(spawn: Vector3) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("spawn", "position", spawn)
	cfg.set_value("spawn", "scene", EditorInterface.get_edited_scene_root().scene_file_path)
	return cfg.save(SPAWN_FILE) == OK
