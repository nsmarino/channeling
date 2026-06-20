extends CharacterBody3D

## Mecha pilot controller for the on-rails shooter prototype.
##
## Both the ship and the aim reticle are screen-space cursors: each is a point
## on a plane a fixed distance in front of the camera, steered in camera-local
## X/Y and clamped to the camera frustum at that depth (see _move_cursor /
## _frustum_extents). Because the camera rides PlayerRoot, banking and forward
## motion are inherited automatically — the cursors stay on-screen through it.
##
## - Left stick / IJKL moves the ship cursor (no gravity, no physics).
## - Right stick moves the aim cursor (the AimTarget node, a child of the camera).
## - CombatAttack fires the equipped weapon from the muzzle toward the AimTarget.
##
## The on-screen reticle (CombatUI) reads get_reticle_screen_position() each
## frame, so the crosshair and the world aim point can never desync.

@export_category("Movement")
## Movement speed in world units per second.
@export var move_speed: float = 12.0
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

@export_category("Combat")
## Weapon instantiated and mounted to the WeaponSocket on ready.
@export var default_weapon_scene: PackedScene
## Player hit points (no UI yet — logged to console).
@export var max_hp: int = 100
## Half-angle (degrees) of the aim cone around the reticle for homing lock-on.
@export var homing_cone_deg: float = 32.0
## Max world distance an enemy can be to be eligible for homing lock-on.
@export var homing_max_range: float = 120.0

@export_category("Evade")
## Initial impulse applied to the ship cursor in world units/second. The push
## decays linearly to zero over evade_duration. The standard frustum clamp
## still applies, so an evade can never carry the player past the play box.
@export var evade_strength: float = 40.0
## Seconds the impulse persists (linear decay).
@export var evade_duration: float = 0.22
## Minimum seconds between evades.
@export var evade_cooldown: float = 0.4

@export_category("References")
## Active camera used for aiming/reticle projection. Falls back to the
## viewport's current camera when left empty.
@export var camera_path: NodePath
## World-space aim target node (parenting it to the camera works best). One is
## created under the camera automatically if this is left empty.
@export var aim_target_path: NodePath

@onready var weapon_socket: Node3D = $WeaponSocket

var _camera: Camera3D = null
var _aim_target: Node3D = null
var _equipped_weapon: Node3D = null

# Cursor positions in camera-local X/Y (their plane depth is applied on use).
var _player_cursor: Vector2 = Vector2.ZERO
var _aim_cursor: Vector2 = Vector2.ZERO

var hp: int = 0

# Accumulated mouse motion since the last aim integration (cleared per frame).
var _pending_mouse_delta: Vector2 = Vector2.ZERO

# Evade impulse state. While _evade_timer > 0, _evade_velocity (world units/sec
# in the player plane) is added to the cursor each frame with linear decay.
var _evade_velocity: Vector2 = Vector2.ZERO
var _evade_timer: float = 0.0
var _evade_cooldown_timer: float = 0.0


func _ready() -> void:
	hp = max_hp
	_resolve_camera()
	_resolve_aim_target()
	_equip_default_weapon()
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
	_process_movement(delta)
	_process_aim(delta)
	_process_combat()


#region Shared cursor clamping

## Integrate input into a camera-local cursor and clamp it to the camera
## frustum at the given plane distance. Shared by the ship and the reticle.
func _move_cursor(cursor: Vector2, input: Vector2, speed: float, delta: float, distance: float, bounds_scale: float) -> Vector2:
	if input.length() > 1.0:
		input = input.normalized()
	cursor += input * speed * delta

	var extents := _frustum_extents(distance, bounds_scale)
	cursor.x = clampf(cursor.x, -extents.x, extents.x)
	cursor.y = clampf(cursor.y, -extents.y, extents.y)
	return cursor


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


#region Movement

func _process_movement(delta: float) -> void:
	if not _camera:
		return

	var input := Vector2(
		Input.get_axis("MoveLeft", "MoveRight"),
		Input.get_axis("MoveDown", "MoveUp")
	)
	_handle_evade_input(input)

	_player_cursor = _move_cursor(_player_cursor, input, move_speed, delta, player_plane_distance, move_bounds_scale)
	_apply_evade(delta)

	# Place the ship on its plane relative to the camera. Inheriting the camera's
	# basis makes the ship bank and advance with the rig.
	var cam_xform := _camera.global_transform
	var offset := Vector3(_player_cursor.x, _player_cursor.y, -player_plane_distance)
	global_transform = Transform3D(cam_xform.basis, cam_xform * offset)


## Trigger an evade on CombatEvade press if cooldown is ready. The impulse
## direction matches the player's current steering; if stationary, it punches
## straight upward as a fallback.
func _handle_evade_input(input_dir: Vector2) -> void:
	if not Input.is_action_just_pressed("CombatEvade"):
		return
	if _evade_cooldown_timer > 0.0:
		return

	var dir: Vector2 = input_dir.normalized() if input_dir.length_squared() >= 0.04 else Vector2.UP
	_evade_velocity = dir * evade_strength
	_evade_timer = evade_duration
	_evade_cooldown_timer = evade_cooldown


## Integrate the decaying impulse into the cursor and re-clamp it to the play
## box (since this displacement bypasses _move_cursor's clamp).
func _apply_evade(delta: float) -> void:
	_evade_cooldown_timer = maxf(_evade_cooldown_timer - delta, 0.0)
	if _evade_timer <= 0.0:
		return

	var decay: float = clampf(_evade_timer / evade_duration, 0.0, 1.0)
	_player_cursor += _evade_velocity * decay * delta
	_evade_timer = maxf(_evade_timer - delta, 0.0)

	var extents := _frustum_extents(player_plane_distance, move_bounds_scale)
	_player_cursor.x = clampf(_player_cursor.x, -extents.x, extents.x)
	_player_cursor.y = clampf(_player_cursor.y, -extents.y, extents.y)

#endregion


#region Aiming

func _process_aim(delta: float) -> void:
	if not _aim_target or not _camera:
		return

	var look := Vector2(
		Input.get_axis("LookLeft", "LookRight"),
		Input.get_axis("LookDown", "LookUp")
	)
	# Stick + mouse share the same cursor; mouse delta is already in world units so
	# it's applied directly instead of being integrated by aim_speed * delta.
	_aim_cursor = _move_cursor(_aim_cursor, look, aim_speed, delta, aim_plane_distance, aim_bounds_scale)
	_aim_cursor += _pending_mouse_delta
	_pending_mouse_delta = Vector2.ZERO
	var aim_extents := _frustum_extents(aim_plane_distance, aim_bounds_scale)
	_aim_cursor.x = clampf(_aim_cursor.x, -aim_extents.x, aim_extents.x)
	_aim_cursor.y = clampf(_aim_cursor.y, -aim_extents.y, aim_extents.y)

	# AimTarget is a child of the camera, so its local position is the cursor.
	_aim_target.position = Vector3(_aim_cursor.x, _aim_cursor.y, -aim_plane_distance)

#endregion


#region Combat

func _process_combat() -> void:
	if not _equipped_weapon:
		return

	# Refresh the homing lock every frame so non-locked shots fly straight.
	if "homing_target" in _equipped_weapon:
		_equipped_weapon.homing_target = _acquire_homing_target()

	var pressed := Input.is_action_pressed("CombatAttack")
	var just := Input.is_action_just_pressed("CombatAttack")
	var wants_fire := pressed
	if _equipped_weapon.has_method("should_fire_for_input"):
		wants_fire = bool(_equipped_weapon.call("should_fire_for_input", pressed, just))

	if wants_fire:
		_equipped_weapon.try_fire(_get_aim_direction())


## Pick the enemy nearest the reticle, within an aim cone and range, in front of
## the camera. Returns null when nothing qualifies (shots then fly straight).
func _acquire_homing_target() -> Node3D:
	if not _camera or not _aim_target:
		return null

	var reticle_screen: Vector2 = get_reticle_screen_position()
	var cam_origin: Vector3 = _camera.global_position
	var cone_cos: float = cos(deg_to_rad(homing_cone_deg))
	var aim_dir: Vector3 = (_aim_target.global_position - cam_origin).normalized()

	var best: Node3D = null
	var best_screen_dist: float = INF

	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Node3D
		if not enemy:
			continue
		if enemy.has_method("is_defeated") and enemy.is_defeated():
			continue

		var to_enemy: Vector3 = enemy.global_position - cam_origin
		var dist: float = to_enemy.length()
		if dist > homing_max_range or dist < 0.01:
			continue
		# Must be within the aim cone and in front of the camera.
		if aim_dir.dot(to_enemy / dist) < cone_cos:
			continue
		if _camera.is_position_behind(enemy.global_position):
			continue

		var screen_dist: float = reticle_screen.distance_to(_camera.unproject_position(enemy.global_position))
		if screen_dist < best_screen_dist:
			best_screen_dist = screen_dist
			best = enemy

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
	if hp <= 0:
		print("[Player] Destroyed!")
		if Events:
			Events.player_killed.emit()

#endregion


#region Reticle hookup (read by CombatUI)

func is_aiming() -> bool:
	return _camera != null and _aim_target != null


func get_reticle_screen_position() -> Vector2:
	if not is_aiming():
		return Vector2.ZERO
	return _camera.unproject_position(_aim_target.global_position)

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
