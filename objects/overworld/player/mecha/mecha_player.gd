extends CharacterBody3D

## Mecha pilot controller — Star Fox / Panzer Dragoon "aim-led" model.
##
## The reticle is the ONLY directly-driven element (right stick + mouse). The
## ship is a follower: each frame it eases toward a scaled-down version of the
## reticle position, so steering and aiming are one gesture. The camera reacts to
## where you're aiming — banking, pitching, and yawing slightly toward the aim,
## so the world leans as you sweep.
##
## Per-frame order matters: aim → camera → ship → combat. The ship is positioned
## relative to the (now-banked) camera transform, so the camera must rotate
## before the ship reads it. The camera reacts to the cursor *value* (camera-
## local x/y), not the reticle's world point, so there's no feedback loop and the
## on-screen crosshair stays where you left it even as the world banks under it.
##
## Gamepad only: left stick L/R flicks a barrel-roll evade; aim is right stick + mouse.

@export_category("Movement")
## Distance in front of the camera where the ship plane sits (its rail depth).
@export var player_plane_distance: float = 10.0
## Fraction of the visible view the ship may roam (1.0 = full screen edges).
@export var move_bounds_scale: float = 0.85

@export_category("Aiming")
## Reticle cursor speed across the aim plane, in world units per second.
@export var aim_speed: float = 18.0
## Distance in front of the camera where the aim plane sits.
@export var aim_plane_distance: float = 30.0
## Fraction of the visible view the reticle may roam (1.0 = full screen edges).
@export var aim_bounds_scale: float = 1.0
## Mouse aim sensitivity (world units of cursor movement per pixel of mouse motion).
@export var mouse_aim_sensitivity: float = 0.06
## Capture the mouse on ready; Escape toggles release.
@export var capture_mouse_on_ready: bool = true
## How fast the reticle eases back toward center when there's no input
## (per second). 0 = fully persistent (Panzer Dragoon); raise for a Star Fox
## springy return.
@export var recenter_rate: float = 0.0

@export_category("Ship Follow")
## The ship targets the reticle position scaled by this (0..1), so the reticle
## can reach the screen edge while the ship only drifts partway. This is the
## ship's reachable sub-box.
@export var ship_follow_fraction: float = 0.6
## How snappily the ship eases toward its follow target (higher = tighter).
@export var ship_follow_lerp: float = 18.0
## World units the ship sits *below* the reticle so it doesn't occlude the
## target. Fades out as the reticle drops into the lower screen half (otherwise
## aiming down would push the ship off the bottom edge).
@export var ship_below_offset: float = 1.0
## Max cosmetic roll (deg) of the ship mesh as it banks into a horizontal turn.
@export var ship_bank_max_deg: float = 20.0
## Max cosmetic pitch (deg) — the nose tilts up/down toward a vertical aim.
@export var ship_pitch_max_deg: float = 12.0
## Max cosmetic yaw (deg) — the nose turns left/right toward a horizontal aim.
@export var ship_yaw_max_deg: float = 12.0
## How fast the cosmetic ship lean eases toward its target.
@export var ship_visual_lerp: float = 10.0

@export_category("Camera React")
## Max camera roll (bank) in degrees from horizontal aim offset. Subtle by
## default (Star Fox); raise for Panzer Dragoon's dramatic horizon tilt.
@export var camera_roll_max_deg: float = 8.0
## Max camera pitch in degrees from vertical aim offset.
@export var camera_pitch_max_deg: float = 5.0
## Max camera yaw in degrees from horizontal aim offset.
@export var camera_yaw_max_deg: float = 3.0
## How fast the camera reaction eases toward its target angle.
@export var camera_react_lerp: float = 6.0

@export_category("Combat")
## Weapon instantiated and mounted to the WeaponSocket on ready.
@export var default_weapon_scene: PackedScene
## Player hit points (no UI yet — logged to console).
@export var max_hp: int = 100
## Lock-on radius around the reticle, as a fraction of screen height. A target
## must project within this many pixels of the crosshair to be homing-eligible;
## if nothing is inside it, shots fly straight (no distant lock). Small = tight,
## crosshair-accurate homing.
@export var homing_screen_radius: float = 0.12
## Max world distance a target can be to be eligible for homing lock-on.
@export var homing_max_range: float = 120.0

@export_category("Brake Bob")
## While braked (rail stopped), the ship mesh gently floats up/down. Vertical
## amplitude in world units.
@export var brake_bob_amplitude: float = 0.15
## Bob oscillation speed (radians/sec).
@export var brake_bob_speed: float = 2.5
## How fast the bob eases in when braking / out when resuming.
@export var brake_bob_ease: float = 3.0

@export_category("Evade")
## A left/right flick of the LEFT STICK triggers an evade: the ship slides
## laterally to a peak and springs back while spinning a full pirouette about its
## up axis (a "screw" spin, not a screen-plane cartwheel). Firing is
## disabled until it completes; aiming and the camera react keep running. An evade
## always runs to completion — the stick must re-center before another can fire.
## Total duration of one evade (seconds).
@export var evade_duration: float = 0.5
## Peak lateral slide distance (world units on the ship plane).
@export var evade_lateral_distance: float = 4.0
## Number of full barrel rolls performed over the evade.
@export var evade_spins: float = 1.0
## Degrees added to the camera FOV during the evade (pull-back cue); eased out as
## the evade starts and back in as it ends.
@export var evade_fov_pullback: float = 8.0
## Left-stick X magnitude that triggers an evade.
@export var evade_trigger_deadzone: float = 0.5
## The stick X must fall back below this before another evade can trigger (so a
## held stick doesn't re-fire).
@export var evade_rearm_threshold: float = 0.2

@export_category("References")
## Active camera used for aiming/reticle projection. Falls back to the
## viewport's current camera when left empty.
@export var camera_path: NodePath
## World-space aim target node (parenting it to the camera works best). One is
## created under the camera automatically if this is left empty.
@export var aim_target_path: NodePath
## PathFollow3D running rail_follower.gd, read for its `braked` flag (drives the
## idle bob). Empty = the nearest PathFollow3D ancestor.
@export var rail_follower_path: NodePath

@onready var weapon_socket: Node3D = $WeaponSocket

var _camera: Camera3D = null
var _aim_target: Node3D = null
var _equipped_weapon: Node3D = null
# The currently locked homing target (null = none). Read by CombatUI to place
# the lock-on indicator.
var _homing_target: Node3D = null

# Cursor positions in camera-local X/Y (their plane depth is applied on use).
# _aim_cursor is directly driven; _ship_cursor follows it.
var _aim_cursor: Vector2 = Vector2.ZERO
var _ship_cursor: Vector2 = Vector2.ZERO

# Eased camera reaction and cosmetic ship lean, both Euler radians
# (pitch=x, yaw=y, roll=z).
var _camera_react: Vector3 = Vector3.ZERO
var _ship_lean: Vector3 = Vector3.ZERO

var hp: int = 0

# Accumulated mouse motion since the last aim integration (cleared per frame).
var _pending_mouse_delta: Vector2 = Vector2.ZERO

# Barrel-roll evade state. _evade_dir is -1 (left) / +1 (right) / 0 (idle); while
# nonzero an evade is running. _evade_t counts up to evade_duration. _evade_armed
# gates re-triggering until the stick re-centers. _evade_frozen_lean is the ship
# lean captured at trigger time — the way OUT preserves it, the way BACK lerps to
# the live lean so the ship ends correctly oriented for the current aim.
var _evade_dir: float = 0.0
var _evade_t: float = 0.0
var _evade_armed: bool = true
var _evade_frozen_lean: Vector3 = Vector3.ZERO
var _base_fov: float = 70.0

# Hit-react (flash + shake) is delegated to a HitReactComponent child; the player
# feeds its brake bob in through that component's extra_offset. Duck-typed (Node)
# so this script doesn't depend on the component's class_name being registered.
var _hit_react: Node = null

# Idle-bob state. _bob_blend eases 0->1 as the rail brakes/resumes; _bob_phase is
# the running sine phase. _rail_follower is read for its `braked` flag.
var _rail_follower: Node = null
var _bob_phase: float = 0.0
var _bob_blend: float = 0.0


func _ready() -> void:
	hp = max_hp
	_resolve_camera()
	_resolve_aim_target()
	_equip_default_weapon()
	_hit_react = get_node_or_null("HitReactComponent")
	_resolve_rail_follower()
	if _camera:
		_base_fov = _camera.fov
	if capture_mouse_on_ready:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Y is inverted: pushing the mouse up moves the reticle up (which is +Y locally).
		_pending_mouse_delta.x += event.relative.x * mouse_aim_sensitivity
		_pending_mouse_delta.y -= event.relative.y * mouse_aim_sensitivity

	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	# Order is load-bearing: the camera banks from the aim (step 2), then the
	# ship positions itself relative to the banked camera (step 3).
	_update_evade(delta)
	_process_aim(delta)
	_process_camera(delta)
	_process_ship(delta)
	_process_combat()
	_update_bob(delta)


## Edge-triggers a barrel-roll evade on a left/right flick of the left stick and
## advances any active evade timer. An evade always runs to completion (no hold,
## no cancel); the stick must relax below evade_rearm_threshold before another can
## fire. The motion itself (lateral slide + roll) is applied in _process_ship.
func _update_evade(delta: float) -> void:
	var x := Input.get_axis("MoveLeft", "MoveRight")

	if _evade_dir != 0.0:
		_evade_t += delta
		if _evade_t >= evade_duration:
			_evade_dir = 0.0
			_evade_t = 0.0
	elif _evade_armed and absf(x) > evade_trigger_deadzone:
		_evade_dir = signf(x)
		_evade_t = 0.0
		_evade_armed = false
		# Freeze the orientation at trigger time; the way back lerps off this.
		_evade_frozen_lean = _ship_lean

	# Re-arm only once the stick relaxes back toward center.
	if absf(x) < evade_rearm_threshold:
		_evade_armed = true


#region Frustum helper

## Frustum half-size (width, height) at a plane distance, scaled. Godot's
## Camera3D defaults to KEEP_HEIGHT, so fov is the vertical angle.
func _frustum_extents(distance: float, bounds_scale: float) -> Vector2:
	var fov_rad := deg_to_rad(_camera.fov)
	var half_h := tan(fov_rad * 0.5) * distance
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := 1.0 if viewport_size.y == 0.0 else viewport_size.x / viewport_size.y
	var half_w := half_h * aspect
	return Vector2(half_w, half_h) * bounds_scale

#endregion


#region Aiming (the directly-driven element)

func _process_aim(delta: float) -> void:
	if not _aim_target or not _camera:
		return

	var look := Vector2(
		Input.get_axis("LookLeft", "LookRight"),
		Input.get_axis("LookDown", "LookUp")
	)
	if look.length() > 1.0:
		look = look.normalized()

	var moved := look.length_squared() > 0.0001 or _pending_mouse_delta.length_squared() > 0.0001

	# Stick integrates by speed; mouse delta is already in world units.
	_aim_cursor += look * aim_speed * delta
	_aim_cursor += _pending_mouse_delta
	_pending_mouse_delta = Vector2.ZERO

	# Ease back toward center when idle (0 = fully persistent).
	if not moved and recenter_rate > 0.0:
		var t := clampf(recenter_rate * delta, 0.0, 1.0)
		_aim_cursor = _aim_cursor.lerp(Vector2.ZERO, t)

	var aim_extents := _frustum_extents(aim_plane_distance, aim_bounds_scale)
	_aim_cursor.x = clampf(_aim_cursor.x, -aim_extents.x, aim_extents.x)
	_aim_cursor.y = clampf(_aim_cursor.y, -aim_extents.y, aim_extents.y)

	# AimTarget is a child of the camera; its local position is the cursor. Its
	# world position is derived from the camera transform when read, so it tracks
	# the camera bank applied later this frame.
	_aim_target.position = Vector3(_aim_cursor.x, _aim_cursor.y, -aim_plane_distance)

#endregion


#region Camera reaction (reacts to aim)

func _process_camera(delta: float) -> void:
	if not _camera:
		return

	var n := _normalized_aim()
	# Local rotation, so it composes additively on top of any rail orientation
	# the camera's parent (PlayerRoot) may have on curved rails later.
	var target := Vector3(
		n.y * deg_to_rad(camera_pitch_max_deg),   # pitch (X): aim up -> look up
		-n.x * deg_to_rad(camera_yaw_max_deg),    # yaw (Y): look toward aim
		-n.x * deg_to_rad(camera_roll_max_deg)    # roll (Z): bank into the turn
	)
	# The camera keeps reacting to aim through an evade (no neutral snap).
	var t := clampf(camera_react_lerp * delta, 0.0, 1.0)
	_camera_react = _camera_react.lerp(target, t)
	_camera.rotation = _camera_react

	# Pull the FOV back slightly during an evade as a "whoa, dodging" cue; eases
	# out as it starts and back to base as it ends.
	var fov_target := _base_fov + (evade_fov_pullback if _evade_dir != 0.0 else 0.0)
	_camera.fov = lerpf(_camera.fov, fov_target, clampf(camera_react_lerp * delta, 0.0, 1.0))

#endregion


#region Ship follow

func _process_ship(delta: float) -> void:
	if not _camera:
		return

	# Ease toward the reticle's screen position, scaled by ship_follow_fraction.
	# The cursors live on planes at different depths (aim_plane_distance vs.
	# player_plane_distance), so convert by the distance ratio — a cursor value
	# divided by its plane distance is the on-screen angle. Without this the ship
	# overshoots off-screen, since the same value spans a wider angle up close.
	var box := _frustum_extents(player_plane_distance, move_bounds_scale)
	var plane_ratio := player_plane_distance / maxf(aim_plane_distance, 0.001)
	var ship_target := _aim_cursor * plane_ratio * ship_follow_fraction

	# Drop the ship below the reticle so it doesn't occlude the target. The offset
	# is full when the reticle is centered or in the upper half, and fades to zero
	# as the reticle reaches the bottom edge — so aiming down doesn't shove the
	# ship off-screen or re-occlude the target.
	var aim_y := _normalized_aim().y  # +1 top, -1 bottom
	ship_target.y -= ship_below_offset * clampf(remap(aim_y, -1.0, 0.0, 0.0, 1.0), 0.0, 1.0)

	var t := clampf(ship_follow_lerp * delta, 0.0, 1.0)
	_ship_cursor = _ship_cursor.lerp(ship_target, t)

	# Evade progress 0..1 (only meaningful while _evade_dir != 0).
	var is_evade := _evade_dir != 0.0
	var p := clampf(_evade_t / maxf(evade_duration, 0.001), 0.0, 1.0)

	# The ship keeps following the reticle; the evade adds a lateral slide that
	# peaks mid-evade (sin) and returns to zero, so it lands back on the current
	# aim position with no snap.
	var final_cursor := _ship_cursor
	if is_evade:
		final_cursor.x += _evade_dir * evade_lateral_distance * sin(p * PI)
	final_cursor.x = clampf(final_cursor.x, -box.x, box.x)
	final_cursor.y = clampf(final_cursor.y, -box.y, box.y)

	# Cosmetic lean: the nose points toward the reticle (pitch + yaw) and the body
	# banks into a horizontal turn (roll). Keeps easing to live aim even mid-evade.
	var n := _normalized_aim()
	var lean_target := Vector3(
		n.y * deg_to_rad(ship_pitch_max_deg),    # pitch: aim up -> nose up
		-n.x * deg_to_rad(ship_yaw_max_deg),     # yaw: aim right -> nose right
		-n.x * deg_to_rad(ship_bank_max_deg)     # roll: bank into the turn
	)
	var vt := clampf(ship_visual_lerp * delta, 0.0, 1.0)
	_ship_lean = _ship_lean.lerp(lean_target, vt)

	# Base orientation: normally the live lean. During an evade the way OUT (p<=0.5)
	# preserves the lean captured at trigger time; the way BACK lerps to the
	# now-current live lean, so the ship ends correctly oriented with no snap. A
	# full spin about the ship's UP axis (a left/right "screw" pirouette, not a
	# screen-plane cartwheel) is composed on top.
	var base_lean := _ship_lean
	var spin := 0.0
	if is_evade:
		var back_blend := clampf((p - 0.5) / 0.5, 0.0, 1.0)
		base_lean = _evade_frozen_lean.lerp(_ship_lean, back_blend)
		spin = _evade_dir * TAU * evade_spins * p

	# Position the ship on its plane relative to the banked camera; the lean (and
	# any evade spin) is a local rotation composed onto the camera basis.
	var cam_xform := _camera.global_transform
	var lean := Basis.from_euler(base_lean)
	if is_evade:
		lean = lean * Basis(Vector3.UP, spin)
	var offset := Vector3(final_cursor.x, final_cursor.y, -player_plane_distance)
	global_transform = Transform3D(cam_xform.basis * lean, cam_xform * offset)


## Normalized aim cursor, each component in -1..1 (cursor / frustum extent).
func _normalized_aim() -> Vector2:
	var ext := _frustum_extents(aim_plane_distance, aim_bounds_scale)
	return Vector2(
		clampf(_aim_cursor.x / maxf(ext.x, 0.001), -1.0, 1.0),
		clampf(_aim_cursor.y / maxf(ext.y, 0.001), -1.0, 1.0)
	)


#endregion


#region Combat

func _process_combat() -> void:
	if not _equipped_weapon:
		return

	# Refresh the homing lock every frame so non-locked shots fly straight. Aim and
	# lock-on keep updating during an evade — only firing is gated below.
	_homing_target = _acquire_homing_target()
	if "homing_target" in _equipped_weapon:
		_equipped_weapon.homing_target = _homing_target

	# No shooting while evading.
	if _evade_dir != 0.0:
		return

	var pressed := Input.is_action_pressed("CombatAttack")
	var just := Input.is_action_just_pressed("CombatAttack")
	var wants_fire := pressed
	if _equipped_weapon.has_method("should_fire_for_input"):
		wants_fire = bool(_equipped_weapon.call("should_fire_for_input", pressed, just))

	if wants_fire:
		_equipped_weapon.try_fire(_get_aim_direction())


## Pick the homing-eligible target whose screen position is nearest the reticle,
## within a tight screen-space radius and within range. Returns null when nothing
## qualifies — shots then fly straight, so there's no distant snap lock-on.
##
## Iterates the "destructible" group (enemies, shootable obstacles, turret-bolts)
## and honors each target's homing_eligible flag, so props opt out cleanly.
func _acquire_homing_target() -> Node3D:
	if not _camera or not _aim_target:
		return null

	var reticle_screen: Vector2 = get_reticle_screen_position()
	var cam_origin: Vector3 = _camera.global_position
	var radius_px: float = homing_screen_radius * get_viewport().get_visible_rect().size.y

	var best: Node3D = null
	var best_screen_dist: float = radius_px  # only targets inside the radius qualify

	for node in get_tree().get_nodes_in_group("destructible"):
		var target := node as Node3D
		if not target:
			continue
		if "homing_eligible" in target and not target.homing_eligible:
			continue
		if target.has_method("is_defeated") and target.is_defeated():
			continue

		var dist: float = cam_origin.distance_to(target.global_position)
		if dist > homing_max_range or dist < 0.01:
			continue
		if _camera.is_position_behind(target.global_position):
			continue

		# Nearest to the crosshair on screen, and must be inside the lock radius.
		var screen_dist: float = reticle_screen.distance_to(_camera.unproject_position(target.global_position))
		if screen_dist < best_screen_dist:
			best_screen_dist = screen_dist
			best = target

	return best


func _get_aim_direction() -> Vector3:
	if not _aim_target:
		return -global_transform.basis.z

	var muzzle := _get_muzzle_position()
	var dir := _aim_target.global_position - muzzle
	if dir.length_squared() < 0.0001:
		return -global_transform.basis.z
	return dir.normalized()


func _get_muzzle_position() -> Vector3:
	if _equipped_weapon and _equipped_weapon.has_node("Muzzle"):
		var m: Node = _equipped_weapon.get_node("Muzzle")
		if m is Node3D:
			return (m as Node3D).global_position
	if weapon_socket:
		return weapon_socket.global_position
	return global_position


## Damage entry point used by enemy projectiles (body group "player") and contact.
func receive_attack(amount: int) -> void:
	take_damage(amount)


func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	var prev: int = hp
	hp = maxi(0, hp - amount)
	print("[Player] Took %d damage. HP: %d -> %d / %d" % [amount, prev, hp, max_hp])
	if _hit_react:
		_hit_react.call("trigger")
	if hp <= 0:
		print("[Player] Destroyed!")
		if Events:
			Events.player_killed.emit()


## Compute the idle bob (vertical float while braked) and feed it to the hit-react
## component as extra_offset — the component composes it with the shake into one
## mesh position write. Mesh-only, so the camera/reticle don't bob with it.
func _update_bob(delta: float) -> void:
	var bob_target := 1.0 if _is_braked() else 0.0
	_bob_blend = lerpf(_bob_blend, bob_target, clampf(brake_bob_ease * delta, 0.0, 1.0))
	var bob_y := 0.0
	if _bob_blend > 0.001:
		_bob_phase += brake_bob_speed * delta
		bob_y = sin(_bob_phase) * brake_bob_amplitude * _bob_blend
	if _hit_react:
		_hit_react.set("extra_offset", Vector3(0.0, bob_y, 0.0))

#endregion


#region Reticle hookup (read by CombatUI)

func is_aiming() -> bool:
	return _camera != null and _aim_target != null


## True while a barrel-roll evade is running. CombatUI reads this only as a
## fire-gate now (the reticle stays visible — aiming continues through the evade).
func is_evading() -> bool:
	return _evade_dir != 0.0


func get_reticle_screen_position() -> Vector2:
	if not is_aiming():
		return Vector2.ZERO
	return _camera.unproject_position(_aim_target.global_position)


## The currently locked homing target, or null. CombatUI reads this to show the
## lock-on indicator at the target's screen position.
func get_homing_target() -> Node3D:
	if _homing_target and is_instance_valid(_homing_target):
		return _homing_target
	return null


## Screen position + camera distance of the locked target, for the lock-on
## indicator. Returns {"pos": Vector2, "dist": float} or an empty dict when there
## is no lock / it's behind the camera.
func get_homing_target_screen_info() -> Dictionary:
	var t := get_homing_target()
	if not t or not _camera:
		return {}
	if _camera.is_position_behind(t.global_position):
		return {}
	return {
		"pos": _camera.unproject_position(t.global_position),
		"dist": _camera.global_position.distance_to(t.global_position),
	}

#endregion


#region Setup helpers

func _resolve_camera() -> void:
	if camera_path != NodePath() and has_node(camera_path):
		var node: Node = get_node(camera_path)
		if node is Camera3D:
			_camera = node as Camera3D
	if not _camera:
		_camera = get_viewport().get_camera_3d()
	if not _camera:
		push_error("[MechaPlayer] No camera found for aiming.")


func _resolve_aim_target() -> void:
	if aim_target_path != NodePath() and has_node(aim_target_path):
		var node: Node = get_node(aim_target_path)
		if node is Node3D:
			_aim_target = node as Node3D
	if not _aim_target and _camera:
		var t := Node3D.new()
		t.name = "AimTarget"
		_camera.add_child(t)
		_aim_target = t
	if _aim_target:
		_aim_target.position = Vector3(0.0, 0.0, -aim_plane_distance)


## Cache the rail follower (PathFollow3D running rail_follower.gd) whose `braked`
## flag drives the idle bob. Falls back to the nearest PathFollow3D ancestor.
func _resolve_rail_follower() -> void:
	if rail_follower_path != NodePath() and has_node(rail_follower_path):
		_rail_follower = get_node(rail_follower_path)
		return
	var n: Node = get_parent()
	while n:
		if n is PathFollow3D:
			_rail_follower = n
			return
		n = n.get_parent()


func _is_braked() -> bool:
	return _rail_follower != null and "braked" in _rail_follower and _rail_follower.braked


func _equip_default_weapon() -> void:
	if not default_weapon_scene:
		push_warning("[MechaPlayer] No default_weapon_scene assigned.")
		return
	if not weapon_socket:
		push_error("[MechaPlayer] WeaponSocket node missing.")
		return

	var inst: Node = default_weapon_scene.instantiate()
	if not (inst is Node3D) or not inst.has_method("try_fire"):
		push_error("[MechaPlayer] default_weapon_scene must be a Node3D exposing try_fire().")
		if inst:
			inst.queue_free()
		return

	_equipped_weapon = inst as Node3D
	weapon_socket.add_child(_equipped_weapon)
	if "owner_character" in _equipped_weapon:
		_equipped_weapon.owner_character = self

#endregion
