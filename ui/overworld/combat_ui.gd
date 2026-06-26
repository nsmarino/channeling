extends CanvasLayer

## Combat HUD: the aim crosshair plus a lock-on indicator that tracks the homing
## target — a rotating, flashing square centered on the target's screen position.
##
## The indicator is a zero-size LockOn Control positioned exactly on the target;
## its Square child is offset to straddle that origin. The PARENT owns rotation +
## position (so the spin stays in place); the Square CHILD owns the pop-in scale,
## so the two never interfere.
##
## NOTE: distance scaling is temporarily disabled to focus on the entrance anim.

@onready var crosshair: Control = $Crosshair
@onready var lock_on: Control = $LockOn
@onready var lock_square: Control = $LockOn/Square

## Spin speed of the lock-on square (radians/sec).
@export var lockon_spin_speed: float = 3.0
## Flash (alpha pulse) frequency in Hz.
@export var lockon_flash_hz: float = 6.0
## Pop-in: scale the square starts at when a lock is acquired (eases to 1.0).
@export var lockon_pop_scale: float = 1.6
## Pop-in duration in seconds.
@export var lockon_pop_time: float = 0.28
## Overshoot strength of the Back ease (higher = more bounce past the end).
@export var lockon_pop_overshoot: float = 2.4
## Distances (camera units) mapping to the indicator's largest/smallest base
## size: at/under lockon_near_distance it's lockon_max_scale, at/over
## lockon_far_distance it's lockon_min_scale.
@export var lockon_near_distance: float = 20.0
@export var lockon_far_distance: float = 90.0
@export var lockon_min_scale: float = 0.7
@export var lockon_max_scale: float = 1.4

var _player: Node = null
var _locked_target: Object = null
var _spin: float = 0.0
var _flash_phase: float = 0.0
var _pop_t: float = 1.0  # 0..1 progress of the pop-in (1 = finished)


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	lock_on.visible = false
	# Pivot at the square's own center so the pop-in scale grows in place.
	lock_square.pivot_offset = lock_square.size * 0.5


func _process(delta: float) -> void:
	_update_crosshair()
	_update_lock_on(delta)


func _update_crosshair() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(_player):
			return

	if not _player.has_method("get_reticle_screen_position"):
		return
	if _player.has_method("is_aiming") and not _player.is_aiming():
		return

	# Hide the reticle while evading (aim is frozen).
	if _player.has_method("is_evading") and _player.is_evading():
		crosshair.visible = false
		return
	crosshair.visible = true

	var screen_pos: Vector2 = _player.get_reticle_screen_position()
	crosshair.global_position = screen_pos - crosshair.size * 0.5


func _update_lock_on(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.has_method("get_homing_target_screen_info"):
		_clear_lock()
		return

	var target: Object = null
	if _player.has_method("get_homing_target"):
		target = _player.get_homing_target()
	var info: Dictionary = _player.get_homing_target_screen_info()

	# No valid lock (none, destroyed, or behind camera) → vanish instantly.
	if target == null or info.is_empty():
		_clear_lock()
		return

	# A new / switched target restarts the entrance pop-in.
	if target != _locked_target:
		_locked_target = target
		_flash_phase = 0.0
		_pop_t = 0.0

	lock_on.visible = true

	# Spin + flash.
	_spin += lockon_spin_speed * delta
	_flash_phase += lockon_flash_hz * delta
	var flash: float = 0.55 + 0.45 * (0.5 + 0.5 * sin(_flash_phase * TAU))

	# Pop-in: scale the square from lockon_pop_scale → 1.0 with a Back ease (the
	# overshoot gives the bounce). Applied to the CHILD so it doesn't fight the
	# parent's rotation/position.
	_pop_t = minf(_pop_t + delta / maxf(lockon_pop_time, 0.001), 1.0)
	var pop: float = lerpf(lockon_pop_scale, 1.0, _ease_out_back(_pop_t))
	lock_square.scale = Vector2.ONE * pop

	# Distance base size: nearer targets get a bigger indicator. Applied to the
	# PARENT, so it composes with the child's pop-in (parent size × child pop)
	# while the spin/position stay on the parent. Since the parent is zero-size,
	# scaling it just multiplies the offset/size of the centered child in place.
	var dist: float = float(info["dist"])
	var dist_t: float = clampf(
		(lockon_far_distance - dist) / maxf(lockon_far_distance - lockon_near_distance, 0.001),
		0.0, 1.0)
	var base_scale: float = lerpf(lockon_min_scale, lockon_max_scale, dist_t)

	# LockOn is a zero-size Control: place its origin on the target and rotate it
	# about that origin, so the centered Square child spins in place.
	lock_on.global_position = info["pos"]
	lock_on.rotation = _spin
	lock_on.scale = Vector2.ONE * base_scale
	lock_on.modulate = Color(1, 1, 1, flash)


func _clear_lock() -> void:
	_locked_target = null
	lock_on.visible = false


## Overshoot ease (Back, out): quick approach then a spring past the end and
## settle. lockon_pop_overshoot controls how far past it bounces.
func _ease_out_back(x: float) -> float:
	var c1: float = lockon_pop_overshoot
	var c3: float = c1 + 1.0
	var t: float = x - 1.0
	return 1.0 + c3 * t * t * t + c1 * t * t
