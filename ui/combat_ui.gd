extends CanvasLayer

## Minimal HUD: a fixed center crosshair and three resource rows polled from the
## player (power pips, the energy bar, health pips).
##
## Everything is POLLED rather than signal-driven. The player owns its own numbers
## and broadcasts nothing about them, so the HUD stays a pure reader — it can be
## removed, duplicated or rebuilt without the player knowing it exists.

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

var _player: Node = null
var _power_pool: Array[Panel] = []
var _health_pool: Array[Panel] = []


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	crosshair.visible = true
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
	_update_health()
	_update_power()
	_update_energy()


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

