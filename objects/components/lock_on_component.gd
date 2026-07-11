extends Component

## Dark Souls-style lock-on, attached under the Player. Owns TARGETING only —
## which entity is locked and which are eligible — and deliberately does NOT
## touch the camera rig. player.gd reads this component (duck-typed) each frame
## and drives the auto-frame camera, tighter FOV, and orbit movement, so the
## SpringArm pivot stays single-writer.
##
## Eligibility is by group + viewport: a "lockable" marker (lock_on_target.gd) is
## eligible when it's alive, within `max_lock_distance`, in front of the camera,
## and its screen point falls inside the inner `inner_viewport_fraction` of the
## viewport. Pressing `lock_action` locks the most-centered eligible target;
## pressing again drops it; a look flick (right stick or mouse) switches targets.
##
## No class_name — player.gd and the HUD reference it by NodePath / group and
## call the public methods below, dodging the class-cache lag (per CLAUDE.md).

## Max distance (world units) an entity can be locked from.
@export var max_lock_distance: float = 35.0
## Centered fraction of the viewport an entity's screen point must fall within to
## be eligible (0.75 = 12.5% margin on every side).
@export var inner_viewport_fraction: float = 0.75
## Hysteresis: keep an existing lock until the target passes
## `max_lock_distance * unlock_distance_slack`, so it doesn't flicker at the edge.
@export var unlock_distance_slack: float = 1.25
## Right-stick X magnitude that counts as a target-switch flick.
@export var switch_stick_threshold: float = 0.6
## Mouse X pixels-per-frame magnitude that counts as a target-switch flick.
@export var switch_mouse_threshold: float = 400.0
## Seconds to ignore further flicks after a switch (debounce).
@export var switch_cooldown: float = 0.3
@export var lock_action: StringName = &"lock_on"

var _target: Node3D = null
var _eligible: Array[Node3D] = []
var _mouse_dx: float = 0.0
var _switch_timer: float = 0.0


func _unhandled_input(event: InputEvent) -> void:
	# Only accumulate while locked; the same look input drives target switching.
	if _target != null and event is InputEventMouseMotion:
		_mouse_dx += (event as InputEventMouseMotion).relative.x


func _physics_process(delta: float) -> void:
	_switch_timer = maxf(0.0, _switch_timer - delta)
	_eligible = _gather_eligible()

	if Input.is_action_just_pressed(lock_action):
		if _target != null:
			_target = null
		else:
			_target = _best_target()

	if _target != null:
		if not _is_valid(_target):
			_target = null
		else:
			_handle_switch()

	_mouse_dx = 0.0


# --- Public API (duck-typed; read by player.gd and combat_ui.gd) -----------

func is_locked() -> bool:
	_prune_freed()
	return _target != null


## The locked marker: aim point = `.global_position`, entity = `.get_parent()`.
func get_target() -> Node3D:
	_prune_freed()
	return _target


## Drop the target the instant its node is freed (e.g. the entity died and
## queue_free'd this frame) so the getters never hand a dangling reference to a
## caller that would cast/use it before our own _physics_process clears it.
func _prune_freed() -> void:
	if _target != null and not is_instance_valid(_target):
		_target = null


func get_eligible_targets() -> Array[Node3D]:
	return _eligible


# --- Targeting -------------------------------------------------------------

func _gather_eligible() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or host == null:
		return result
	var origin: Vector3 = (host as Node3D).global_position
	var rect: Rect2 = _inner_rect()
	for node in get_tree().get_nodes_in_group(&"lockable"):
		var marker := node as Node3D
		if marker == null or not _entity_alive(marker):
			continue
		var point: Vector3 = marker.global_position
		if origin.distance_to(point) > max_lock_distance:
			continue
		if cam.is_position_behind(point):
			continue
		if not rect.has_point(cam.unproject_position(point)):
			continue
		result.append(marker)
	return result


## The eligible marker whose screen point is nearest the viewport center.
func _best_target() -> Node3D:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return null
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var best: Node3D = null
	var best_d: float = INF
	for marker in _eligible:
		var d: float = cam.unproject_position(marker.global_position).distance_squared_to(center)
		if d < best_d:
			best_d = d
			best = marker
	return best


func _handle_switch() -> void:
	if _switch_timer > 0.0:
		return
	var dir: int = 0
	var stick_x: float = Input.get_axis(&"look_left", &"look_right")
	if absf(stick_x) >= switch_stick_threshold:
		dir = int(signf(stick_x))
	elif absf(_mouse_dx) >= switch_mouse_threshold:
		dir = int(signf(_mouse_dx))
	if dir == 0:
		return
	var next: Node3D = _neighbor_target(dir)
	if next != null:
		_target = next
		_switch_timer = switch_cooldown


## Nearest eligible target to one side (dir +1 = screen-right, -1 = left).
func _neighbor_target(dir: int) -> Node3D:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or _target == null:
		return null
	var cur_x: float = cam.unproject_position(_target.global_position).x
	var best: Node3D = null
	var best_dx: float = INF
	for marker in _eligible:
		if marker == _target:
			continue
		var offset: float = (cam.unproject_position(marker.global_position).x - cur_x) * float(dir)
		if offset > 0.0 and offset < best_dx:
			best_dx = offset
			best = marker
	return best


# --- Validity --------------------------------------------------------------

## Keep a lock while the target is alive and within (slack-expanded) range. We do
## NOT drop it just for being behind the camera — running past/through a target
## puts it behind for a few frames while the auto-frame swings back around, and a
## Dark Souls lock rides that out.
func _is_valid(marker: Node3D) -> bool:
	if not _entity_alive(marker):
		return false
	if host == null:
		return true
	var d: float = (host as Node3D).global_position.distance_to(marker.global_position)
	return d <= max_lock_distance * unlock_distance_slack


func _entity_alive(marker: Node3D) -> bool:
	if not is_instance_valid(marker) or not marker.is_in_group(&"lockable"):
		return false
	var entity: Node = marker.get_parent()
	if entity != null and entity.has_method("is_defeated") and entity.call("is_defeated"):
		return false
	return true


func _inner_rect() -> Rect2:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var margin: Vector2 = size * ((1.0 - inner_viewport_fraction) * 0.5)
	return Rect2(margin, size - margin * 2.0)
