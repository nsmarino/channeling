extends CanvasLayer

## Minimal HUD: a fixed center crosshair, a health readout polled from the player,
## and the lock-on overlay. The overlay reads the player's LockOnComponent
## (duck-typed) each frame and draws:
##   - the bold `LockOn` reticle on the actively locked target, and
##   - soft `◇` markers on every other eligible target (pooled),
## both projected to screen space via the active 3D camera.

@onready var crosshair: Control = $Crosshair
@onready var health_label: Label = $Health
@onready var lock_on_reticle: Control = $LockOn
@onready var eligible_markers: Control = $EligibleMarkers

const MARKER_SIZE := Vector2(24, 24)

var _player: Node = null
var _lock_on: Node = null
var _marker_pool: Array[Label] = []


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	crosshair.visible = true
	lock_on_reticle.visible = false


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_resolve_lock_on()
	_update_health()
	_update_lock_on()


func _update_health() -> void:
	if is_instance_valid(_player) and "hp" in _player:
		health_label.text = "HEALTH: %d" % int(_player.hp)


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
