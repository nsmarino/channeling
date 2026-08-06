extends CanvasLayer

## Minimal HUD: a fixed center crosshair, three resource rows polled from the
## player (power pips, the energy bar, health pips), and the lock-on overlay.
##
## Everything is POLLED rather than signal-driven. The player owns its own numbers
## and broadcasts nothing about them, so the HUD stays a pure reader — it can be
## removed, duplicated or rebuilt without the player knowing it exists.
##
## The overlay reads the player's LockOnComponent (duck-typed) each frame and
## draws:
##   - the bold `LockOn` reticle on the actively locked target, and
##   - soft `◇` markers on every other eligible target (pooled),
## both projected to screen space via the active 3D camera.

@export_group("Resource Pips")
## How many power pips to draw. Keep equal to the player's `max_power` — any pip
## past it can never fill and just reads as broken.
@export var power_pips: int = 10
## How many health pips to draw. Should match the player's `max_hp`.
@export var health_pips: int = 6
## Size of a single pip. Width > height gives the ellipse its squash.
@export var pip_size: Vector2 = Vector2(20.0, 14.0)
@export var pip_spacing: int = 5
@export var power_color: Color = Color(1.0, 0.82, 0.25)
@export var health_color: Color = Color(1.0, 0.30, 0.36)
## Opacity of an empty pip. Drawn at reduced alpha rather than hidden, so the row
## always shows the CAPACITY as well as the amount — you can see what you're
## working toward, which is the whole reason it's pips and not a number.
@export_range(0.0, 1.0, 0.05) var empty_alpha: float = 0.5
@export_range(0.0, 1.0, 0.05) var filled_alpha: float = 1.0

@onready var crosshair: Control = $Crosshair
@onready var energy_bar: ProgressBar = $Resources/Energy
@onready var power_row: HBoxContainer = $Resources/PowerRow
@onready var health_row: HBoxContainer = $Resources/HealthRow
@onready var lock_on_reticle: Control = $LockOn
@onready var eligible_markers: Control = $EligibleMarkers

const MARKER_SIZE := Vector2(24, 24)

var _player: Node = null
var _lock_on: Node = null
var _marker_pool: Array[Label] = []
var _power_pool: Array[Panel] = []
var _health_pool: Array[Panel] = []


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	crosshair.visible = true
	lock_on_reticle.visible = false
	power_row.add_theme_constant_override(&"separation", pip_spacing)
	health_row.add_theme_constant_override(&"separation", pip_spacing)
	_build_pips(power_row, _power_pool, power_pips, power_color)
	_build_pips(health_row, _health_pool, health_pips, health_color)


## An "ellipse" is a Panel with a StyleBoxFlat whose corner radius exceeds half its
## height, which rounds it fully — no texture asset, and it stays crisp at any
## size. Colour lives in the stylebox; FILL is expressed through `modulate.a`, so
## updating a row every frame is one float per pip and no styleboxes are rebuilt.
func _build_pips(row: HBoxContainer, pool: Array[Panel], count: int, color: Color) -> void:
	for child in row.get_children():
		child.queue_free()
	pool.clear()

	var style := StyleBoxFlat.new()
	style.bg_color = color
	var r: int = int(maxf(pip_size.x, pip_size.y))
	style.corner_radius_top_left = r
	style.corner_radius_top_right = r
	style.corner_radius_bottom_right = r
	style.corner_radius_bottom_left = r

	for i in count:
		var pip := Panel.new()
		pip.custom_minimum_size = pip_size
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Shared, never mutated — every pip points at the same resource.
		pip.add_theme_stylebox_override(&"panel", style)
		pip.modulate.a = empty_alpha
		row.add_child(pip)
		pool.append(pip)


func _fill_pips(pool: Array[Panel], filled: int) -> void:
	for i in pool.size():
		pool[i].modulate.a = filled_alpha if i < filled else empty_alpha


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_resolve_lock_on()
	_update_health()
	_update_power()
	_update_energy()
	_update_lock_on()


func _update_health() -> void:
	if is_instance_valid(_player) and "hp" in _player:
		_fill_pips(_health_pool, int(_player.hp))


func _update_power() -> void:
	if is_instance_valid(_player) and "power" in _player:
		_fill_pips(_power_pool, int(_player.power))


func _update_energy() -> void:
	if is_instance_valid(_player) and "energy" in _player and "max_energy" in _player:
		energy_bar.max_value = _player.max_energy
		energy_bar.value = _player.energy


func _resolve_lock_on() -> void:
	if (_lock_on == null or not is_instance_valid(_lock_on)) and is_instance_valid(_player):
		_lock_on = _player.get_node_or_null(^"LockOnComponent")


func _update_lock_on() -> void:
	var cam := get_viewport().get_camera_3d()
	if _lock_on == null or cam == null:
		lock_on_reticle.visible = false
		_hide_markers_from(0)
		return

	var raw_target: Variant = _lock_on.call("get_target")
	var target: Node3D = null
	if is_instance_valid(raw_target):
		target = raw_target as Node3D

	# Bold reticle on the active target.
	if target != null and not cam.is_position_behind(target.global_position):
		lock_on_reticle.visible = true
		lock_on_reticle.position = cam.unproject_position(target.global_position)
	else:
		lock_on_reticle.visible = false

	# Soft markers on every other eligible target.
	var eligible: Array = _lock_on.call("get_eligible_targets")
	var shown := 0
	for i in eligible.size():
		var raw: Variant = eligible[i]
		if not is_instance_valid(raw):
			continue  # entity freed since the last physics gather; skip.
		var marker_target := raw as Node3D
		if marker_target == null or marker_target == target:
			continue
		if cam.is_position_behind(marker_target.global_position):
			continue
		var m := _get_marker(shown)
		m.visible = true
		m.position = cam.unproject_position(marker_target.global_position) - MARKER_SIZE * 0.5
		shown += 1
	_hide_markers_from(shown)


## Lazily grow the marker pool; each marker is a centered dim diamond glyph.
func _get_marker(index: int) -> Label:
	while _marker_pool.size() <= index:
		var lbl := Label.new()
		lbl.custom_minimum_size = MARKER_SIZE
		lbl.size = MARKER_SIZE
		lbl.text = "◇"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.1, 0.7))
		eligible_markers.add_child(lbl)
		_marker_pool.append(lbl)
	return _marker_pool[index]


func _hide_markers_from(index: int) -> void:
	for j in range(index, _marker_pool.size()):
		_marker_pool[j].visible = false
