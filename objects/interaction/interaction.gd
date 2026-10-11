extends Area3D
class_name Interaction

## Something the player can walk up to and interact with: talk to an NPC, read a
## sign, pull a lever. Ported and extended from Nightbloom v1's DialogueTrigger.
##
## While the player stands inside this volume a prompt shows ("[E] Talk").
## Pressing `interact_action` locks player control (Events.interaction_started —
## the same freeze a cutscene uses) and runs this node's InteractionStep children
## top to bottom — lines of dialogue, camera moves, sounds, flags — then closes
## the dialogue box, blends the camera back to the player and hands control back.
##
## WHY STEPS ARE NODES. Nightbloom kept the script in JSON with `trigger_id`
## strings for side effects, but nothing ever listened for those ids. Steps as
## children mean the camera a step cuts to, the sound it plays and the NPC it
## animates are real nodes in the level, picked in the Inspector — and the
## sequence is visible and reorderable in the scene tree.
##
## STATE. `once_flag` makes an interaction happen once per session (it survives
## restarts, unlike `one_shot`); `required_flag` gates it on earlier events. Two
## Interactions on one NPC — the first with once_flag "met_archivist", the second
## with required_flag "met_archivist" — give a first meeting and a follow-up.
##
## Only one interaction owns the prompt at a time; when several overlap, the one
## the player entered first keeps it until they leave.
##
## CUTSCENES are Interactions too: `start_on_enter` starts on walking in (no
## prompt, no button), `letterbox` slides the Cinematic bars in for the duration,
## and a TimelineStep plays an AnimationPlayer clip for anything that needs exact
## timing. See objects/cutscene/ExampleCutscene.tscn.
##
## Polled rather than signal-driven, matching TriggerRegion and Portal.

## Emitted after the last step, once control is back with the player. Connect it
## in the editor to react in the level (open a gate, spawn an enemy).
signal finished

## Prompt shown while the player is in range.
@export var prompt_text: String = "[E] Talk"
## Input that starts the interaction.
@export var interact_action: StringName = &"interact"
## Run at most once per load of this location (resets on restart). For once per
## session, use `once_flag` instead.
@export var one_shot: bool = false
## If set: unavailable once this GameManager flag is true, and sets it on finish.
@export var once_flag: StringName = &""
## If set: only available while this GameManager flag is true.
@export var required_flag: StringName = &""
## Group a body must belong to to use the interaction.
@export var target_group: StringName = &"player"

## How the view moves between the player's camera and the interaction's cameras.
##   BLEND — sweep around the player.
##   FADE  — fade to black, switch cameras while dark, fade back in.
##   CUT   — switch instantly.
enum CameraTransition { BLEND, FADE, CUT }

@export_group("Camera")
## INTO the interaction: the first switch away from the player's camera, whichever
## step makes it (a CameraStep, or a TimelineStep's clip). Later switches between
## level cameras use the CameraStep's own blend_time.
@export var camera_enter: CameraTransition = CameraTransition.BLEND
## Enter BLEND: seconds to sweep in.
@export var camera_enter_blend: float = 0.6
## Enter FADE: seconds each way, and how long to hold on black.
@export var camera_enter_fade: float = 0.35
@export var camera_enter_fade_hold: float = 0.1
## OUT of the interaction, back to the player's camera at the end.
@export var camera_return: CameraTransition = CameraTransition.BLEND
## Return BLEND: seconds to sweep back.
@export var camera_return_blend: float = 0.4
## Return FADE: seconds each way, and how long to hold on black.
@export var camera_return_fade: float = 0.35
@export var camera_return_fade_hold: float = 0.1

@export_group("Cutscene")
## Start as soon as the player walks in — no prompt, no button. Re-arms only once
## they've left, so a repeatable one doesn't loop while they stand there.
@export var start_on_enter: bool = false
## Slide the Cinematic letterbox bars in for the duration.
@export var letterbox: bool = false
## Bar height for this interaction (-1 = the Cinematic default).
@export var letterbox_height: float = -1.0
## Hand the player's body over for the duration (Player.begin_scripted_move), so
## an ActorDriver can walk it along a path like any other actor. Without this the
## frozen player still applies its own gravity and drift, and fights the driver.
@export var puppet_player: bool = false

## The interaction that currently shows the prompt, and the one running, if any.
## Static so overlapping interactions can arbitrate without a manager node.
static var _focused: Interaction = null
static var _running: Interaction = null

var _has_run: bool = false
# Wait for the interact button to be released before re-arming, so the press that
# dismissed the last line can't immediately start the conversation again.
var _await_release: bool = false
# start_on_enter: the player must leave before it can start again.
var _await_exit: bool = false
# Cameras a CameraStep moved for a blend, with their authored transforms, so they
# can be put back afterwards.
var _moved_cameras: Dictionary[Camera3D, Transform3D] = {}
# The first switch away from the player's camera has happened (camera_enter is spent).
var _entered_camera: bool = false
# The player whose scripted move we claimed for `puppet_player`, to release.
var _puppet: Node = null


func _ready() -> void:
	monitoring = true


func _physics_process(_delta: float) -> void:
	if _running == self:
		return
	var player: Node3D = _find_player()
	if start_on_enter:
		_poll_enter(player)
		return
	var available: bool = player != null and _is_available() and _player_controllable(player)

	if not available:
		if _focused == self:
			_release_focus()
		return

	if not _has_focus():
		if is_instance_valid(_focused) or is_instance_valid(_running):
			return  # someone else has the prompt (or is mid-conversation)
		_take_focus()

	if _await_release:
		if Input.is_action_pressed(interact_action):
			return
		_await_release = false
	if Input.is_action_just_pressed(interact_action):
		start()


func _poll_enter(player: Node3D) -> void:
	if player == null:
		_await_exit = false
		return
	if _await_exit or is_instance_valid(_running):
		return
	if _is_available() and _player_controllable(player):
		start()


## Run the interaction now, regardless of range (also callable from code or from
## another node's signal).
func start() -> void:
	if is_instance_valid(_running):
		return
	_running = self
	_has_run = true
	_await_release = true
	_entered_camera = false
	_await_exit = start_on_enter
	# Drop the prompt even if another interaction held it; it re-takes the prompt
	# once this one ends and the player is still in its range.
	_focused = null
	Events.interaction_prompt_hidden.emit()
	Events.interaction_started.emit(self)
	if letterbox:
		Cinematic.show_bars(letterbox_height)
	if puppet_player:
		_claim_puppet()

	for child: Node in get_children():
		var step := child as InteractionStep
		if step == null or not step.enabled:
			continue
		# Called dynamically: the base run() isn't a coroutine, so a static call
		# trips the "unnecessary await" warning, but overrides usually are.
		await step.call(&"run", self)
		if not is_inside_tree():
			return  # freed mid-sequence (restart, travel) — _exit_tree cleaned up

	var box: DialogueBox = get_dialogue_box()
	if box:
		await box.close()
	match camera_return:
		CameraTransition.FADE:
			await _fade_return()
		CameraTransition.CUT:
			await _return_camera(0.0)
		_:
			await _return_camera(camera_return_blend)
	if letterbox and camera_return != CameraTransition.FADE:
		await Cinematic.hide_bars().finished
	if not once_flag.is_empty():
		GameManager.set_flag(once_flag)
	_release_puppet()
	_end()
	finished.emit()


## The HUD's dialogue box, or null when running a scene without main.tscn's HUD.
func get_dialogue_box() -> DialogueBox:
	return get_tree().get_first_node_in_group(&"dialogue_box") as DialogueBox


## Blend the view from whatever camera is current to `cam` over `duration`.
## The target camera is animated FROM the current view TO its own authored pose,
## so nothing extra is spawned and it always ends exactly where it was placed.
func blend_camera_to(cam: Camera3D, duration: float) -> void:
	var from: Camera3D = get_viewport().get_camera_3d()
	if not _moved_cameras.has(cam):
		_moved_cameras[cam] = cam.global_transform
	if is_entering_camera():
		# First switch away from the player: camera_enter decides, not the step.
		await begin_camera_switch()
		cam.make_current()
		await end_camera_switch(true)
		return
	if duration <= 0.0 or from == null or from == cam:
		cam.make_current()
		return
	var target_xform: Transform3D = _moved_cameras[cam]
	var target_fov: float = cam.fov
	cam.global_transform = from.global_transform
	cam.fov = from.fov
	cam.make_current()
	await _arc_camera(cam, target_xform, target_fov, duration)


## True until the first switch away from the player's camera has happened.
func is_entering_camera() -> bool:
	return not _entered_camera and get_viewport().get_camera_3d() == _player_camera()


## Steps call this BEFORE their first camera switch (await it): with an enter FADE
## it takes the screen to black, so the switch itself happens unseen.
func begin_camera_switch() -> void:
	if not is_entering_camera():
		return
	if camera_enter == CameraTransition.FADE:
		await Cinematic.fade_out(camera_enter_fade).finished


## Steps call this AFTER the new camera is current. Applies the rest of the enter
## transition: BLEND sweeps the new camera in from the player's view, FADE holds
## and fades back in, CUT does nothing. `include_fov` = false when something else
## (a timeline) animates the camera's FOV, so the two don't fight.
## Await it to hold the step until the transition is done; don't, to let the step
## carry on (a timeline should keep playing underneath).
func end_camera_switch(include_fov: bool) -> void:
	if _entered_camera:
		return
	var player_cam: Camera3D = _player_camera()
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or cam == player_cam:
		# Nothing switched after all — don't leave the screen black.
		if camera_enter == CameraTransition.FADE:
			await Cinematic.fade_in(camera_enter_fade).finished
		return
	_entered_camera = true
	if not _moved_cameras.has(cam):
		_moved_cameras[cam] = cam.global_transform
	match camera_enter:
		CameraTransition.FADE:
			if camera_enter_fade_hold > 0.0:
				await get_tree().create_timer(camera_enter_fade_hold).timeout
			await Cinematic.fade_in(camera_enter_fade).finished
		CameraTransition.BLEND:
			if player_cam == null or camera_enter_blend <= 0.0:
				return
			var target_xform: Transform3D = _moved_cameras[cam]
			var target_fov: float = cam.fov
			cam.global_transform = player_cam.global_transform
			if include_fov:
				cam.fov = player_cam.fov
			await _arc_camera(cam, target_xform, target_fov if include_fov else -1.0, camera_enter_blend)


func _return_camera(duration: float) -> void:
	var player_cam: Camera3D = _player_camera()
	var current: Camera3D = get_viewport().get_camera_3d()
	if player_cam and current and current != player_cam and duration > 0.0:
		# A timeline may have cut to a camera no CameraStep touched — remember its
		# pose too, so the blend doesn't leave it parked at the player's camera.
		if not _moved_cameras.has(current):
			_moved_cameras[current] = current.global_transform
		await _arc_camera(current, player_cam.global_transform, player_cam.fov, duration)
	# Hand the view over BEFORE putting borrowed cameras back. Restoring first snaps
	# the still-current camera to its authored shot, which then holds on screen
	# while the letterbox retracts — the blend appears to bounce back to a close-up.
	if player_cam:
		player_cam.make_current()
	_restore_cameras()


## Fade to black, swap to the player's camera (and drop the letterbox) while the
## screen is dark, then fade back in. Skips the fade if no other camera is active,
## so a plain conversation doesn't flash to black for nothing.
func _fade_return() -> void:
	var player_cam: Camera3D = _player_camera()
	var current: Camera3D = get_viewport().get_camera_3d()
	if current == null or current == player_cam:
		if letterbox:
			await Cinematic.hide_bars().finished
		return
	await Cinematic.fade_out(camera_return_fade).finished
	await _return_camera(0.0)
	if letterbox:
		Cinematic.hide_bars(0.0)
	if camera_return_fade_hold > 0.0:
		await get_tree().create_timer(camera_return_fade_hold).timeout
	await Cinematic.fade_in(camera_return_fade).finished


## Move `cam` to `to_xform` / `to_fov` along an ARC around the player rather than
## a straight line. Shots usually sit on different sides of the player, so a
## straight lerp swoops through (or right over) them; sweeping the direction from
## the player while easing the distance keeps the subject framed the whole way.
func _arc_camera(cam: Camera3D, to_xform: Transform3D, to_fov: float, duration: float) -> void:
	var from_xform: Transform3D = cam.global_transform
	var from_fov: float = cam.fov
	var pivot: Vector3 = _arc_pivot(from_xform.origin, to_xform.origin)
	var step := func(t: float) -> void:
		_apply_arc(cam, from_xform, to_xform, from_fov, to_fov, pivot, t)
	cam.set_meta(&"interaction_blending", true)
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(step, 0.0, 1.0, duration)
	await tween.finished
	if is_instance_valid(cam):
		cam.remove_meta(&"interaction_blending")


func _apply_arc(cam: Camera3D, from_xform: Transform3D, to_xform: Transform3D,
		from_fov: float, to_fov: float, pivot: Vector3, t: float) -> void:
	if not is_instance_valid(cam):
		return
	var a: Vector3 = from_xform.origin - pivot
	var b: Vector3 = to_xform.origin - pivot
	var origin: Vector3
	if a.length() < 0.01 or b.length() < 0.01:
		origin = from_xform.origin.lerp(to_xform.origin, t)
	else:
		origin = pivot + a.normalized().slerp(b.normalized(), t) * lerpf(a.length(), b.length(), t)
	var rot: Quaternion = from_xform.basis.get_rotation_quaternion().slerp(
			to_xform.basis.get_rotation_quaternion(), t)
	cam.global_transform = Transform3D(Basis(rot), origin)
	if to_fov >= 0.0:  # < 0 = something else (a timeline) owns the FOV
		cam.fov = lerpf(from_fov, to_fov, t)


## What the arc swings around: the player's chest, or the midpoint if no player.
func _arc_pivot(a: Vector3, b: Vector3) -> Vector3:
	var player := get_tree().get_first_node_in_group(target_group) as Node3D
	if player:
		return player.global_position + Vector3.UP * 1.5
	return (a + b) * 0.5


## Put borrowed cameras back where they were authored. The player reclaims its own
## camera when control returns (Player._unlock_control).
func _restore_cameras() -> void:
	for cam: Camera3D in _moved_cameras:
		if is_instance_valid(cam):
			cam.global_transform = _moved_cameras[cam]
	_moved_cameras.clear()


## Take over the player's transform. Whoever claims a scripted move must release
## it — on the normal path and when freed mid-run — or the player stays frozen.
func _claim_puppet() -> void:
	var player: Node = get_tree().get_first_node_in_group(target_group)
	if player and player.has_method("begin_scripted_move") \
			and bool(player.call("begin_scripted_move", self)):
		_puppet = player


func _release_puppet() -> void:
	if is_instance_valid(_puppet):
		_puppet.call("end_scripted_move", self)
	_puppet = null


func _end() -> void:
	if _running == self:
		_running = null
	Events.interaction_finished.emit(self)


## Freed while running — a restart, or a step that traveled to another location.
## The player may survive (travel), so control must still come back.
func _exit_tree() -> void:
	if _focused == self:
		_release_focus()
	if _running != self:
		return
	_restore_cameras()
	var box: DialogueBox = get_dialogue_box()
	if box:
		box.close()
	if letterbox:
		Cinematic.hide_bars()
	Cinematic.clear_fade()  # an enter or return fade may be mid-way
	_release_puppet()
	_end()


func _take_focus() -> void:
	_focused = self
	Events.interaction_prompt_shown.emit(prompt_text)


func _release_focus() -> void:
	_focused = null
	Events.interaction_prompt_hidden.emit()


func _has_focus() -> bool:
	return _focused == self


func _is_available() -> bool:
	if one_shot and _has_run:
		return false
	if not once_flag.is_empty() and GameManager.has_flag(once_flag):
		return false
	if not required_flag.is_empty() and not GameManager.has_flag(required_flag):
		return false
	return true


## Not mid-cutscene, not mid-Power-Dive: the player could actually start talking.
func _player_controllable(player: Node3D) -> bool:
	if player.has_method("is_control_enabled") and not bool(player.call("is_control_enabled")):
		return false
	if player.has_method("is_scripted_move_claimed") and bool(player.call("is_scripted_move_claimed")):
		return false
	return true


func _player_camera() -> Camera3D:
	var player: Node = get_tree().get_first_node_in_group(target_group)
	if player and player.has_method("get_camera"):
		return player.call("get_camera") as Camera3D
	return null


func _find_player() -> Node3D:
	for body: Node3D in get_overlapping_bodies():
		if body.is_in_group(target_group):
			return body
	return null
