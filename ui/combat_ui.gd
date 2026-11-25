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

@export_group("Health Pips")
## Health pips are images: one per point of max HP, showing `health_full_texture`
## while that point is held and `health_empty_texture` once it's lost. Leave
## either empty to fall back to the coloured ellipses above.
@export var health_full_texture: Texture2D = preload("res://ui/hud/health_pip_full.png")
@export var health_empty_texture: Texture2D = preload("res://ui/hud/health_pip_empty.png")
## On-screen size of one health pip. The PNGs are 108 px, so 36 stays crisp.
@export var health_pip_size: Vector2 = Vector2(36.0, 36.0)

@export_group("Health Damage")
## Seconds for the white flash on every health pip to fade after the player is
## hit. 0 = no flash. Image pips only, like the scale-down below.
@export_range(0.0, 1.0, 0.01) var hurt_flash_time: float = 0.18
## Scale a lost health pip settles at.
@export_range(0.1, 1.0, 0.05) var empty_pip_scale: float = 0.8
## Seconds for a lost pip to shrink to `empty_pip_scale` (and for a healed one
## to grow back). The scale overshoots slightly before settling.
@export_range(0.01, 1.0, 0.01) var pip_scale_time: float = 0.25

@export_group("Power Pips")
## Power pips as images, like the health pips: `power_full_texture` per point
## held, `power_empty_texture` for the rest. Leave either empty to fall back to
## the coloured ellipses above.
@export var power_full_texture: Texture2D = preload("res://ui/hud/power_pip_full.png")
@export var power_empty_texture: Texture2D = preload("res://ui/hud/health_pip_empty.png")
## On-screen size of one power pip.
@export var power_pip_size: Vector2 = Vector2(20.0, 20.0)

@onready var crosshair: Control = $Crosshair
@onready var energy_bar: Range = $Resources/Energy
@onready var power_row: HBoxContainer = $Resources/PowerRow
@onready var health_row: HBoxContainer = $Resources/HealthRow

var _player: Node = null
var _power_pool: Array[Panel] = []
var _health_pool: Array[Panel] = []
var _power_icons: Array[TextureRect] = []
var _health_icons: Array[TextureRect] = []
# White twin over each health icon, faded in and out for the hurt flash.
var _health_flashes: Array[TextureRect] = []
var _health_tweens: Array[Tween] = []
var _flash_tween: Tween
var _shown_hp: int = -1
var _hit_source: Node = null


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	crosshair.visible = true
	power_row.add_theme_constant_override(&"separation", pip_spacing)
	health_row.add_theme_constant_override(&"separation", pip_spacing)
	if _has_textures(power_full_texture, power_empty_texture):
		_build_icons(power_row, _power_icons, power_pips, power_pip_size, power_empty_texture)
	else:
		_build_pips(power_row, _power_pool, power_pips, power_color)
	if _has_textures(health_full_texture, health_empty_texture):
		_build_icons(health_row, _health_icons, health_pips, health_pip_size, health_empty_texture)
		_build_health_flashes()
	else:
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


func _has_textures(full: Texture2D, empty: Texture2D) -> bool:
	return full != null and empty != null


## Image pips: a TextureRect each, scaled to `size`; filling swaps the texture.
func _build_icons(row: HBoxContainer, pool: Array[TextureRect], count: int, size: Vector2, empty: Texture2D) -> void:
	for child in row.get_children():
		child.queue_free()
	pool.clear()
	for i in count:
		var icon := TextureRect.new()
		icon.custom_minimum_size = size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = empty
		row.add_child(icon)
		pool.append(icon)


## Each health icon gets a white silhouette child filling it (so it scales with
## the icon) and a pivot at its centre, so scale tweens grow and shrink in place.
func _build_health_flashes() -> void:
	_health_flashes.clear()
	_health_tweens.clear()
	for icon in _health_icons:
		icon.pivot_offset = health_pip_size * 0.5
		# The row may size the icon differently from its minimum; keep the pivot central.
		icon.resized.connect(func() -> void: icon.pivot_offset = icon.size * 0.5)
		var flash := TextureRect.new()
		flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash.modulate.a = 0.0
		icon.add_child(flash)
		_health_flashes.append(flash)
		_health_tweens.append(null)


func _fill_icons(pool: Array[TextureRect], filled: int, full: Texture2D, empty: Texture2D) -> void:
	for i in pool.size():
		pool[i].texture = full if i < filled else empty


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
		var hp: int = int(_player.hp)
		_fill_icons(_health_icons, hp, health_full_texture, health_empty_texture)
		_fill_pips(_health_pool, hp)
		_connect_hit()
		_update_health_scales(hp)


## Listen for the player's `hit` (the hurt flash). Re-run each frame since the
## player can be found late or replaced.
func _connect_hit() -> void:
	if _hit_source == _player or not _player.has_signal("hit"):
		return
	_hit_source = _player
	_player.connect("hit", _on_player_hit)


## Pips that just emptied shrink; pips that just refilled (a heal) grow back.
## The first reading only sets the scales, so loading in hurt doesn't animate.
func _update_health_scales(hp: int) -> void:
	if _health_icons.is_empty() or hp == _shown_hp:
		return
	var first: bool = _shown_hp < 0
	_shown_hp = hp
	for i in _health_icons.size():
		var target: float = 1.0 if i < hp else empty_pip_scale
		var icon: TextureRect = _health_icons[i]
		if is_equal_approx(icon.scale.x, target):
			continue
		if _health_tweens[i]:
			_health_tweens[i].kill()
		if first:
			icon.scale = Vector2.ONE * target
			continue
		var tween: Tween = create_tween()
		tween.tween_property(icon, "scale", Vector2.ONE * target, pip_scale_time) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_health_tweens[i] = tween


## Flash every health pip white, fading out over `hurt_flash_time`.
func _on_player_hit(_amount: int) -> void:
	if _health_flashes.is_empty() or hurt_flash_time <= 0.0:
		return
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween().set_parallel(true)
	# The HUD redraws in _process, so read hp now rather than the icons' textures.
	var hp: int = int(_player.hp) if is_instance_valid(_player) and "hp" in _player else 0
	for i in _health_flashes.size():
		var flash: TextureRect = _health_flashes[i]
		flash.texture = Silhouette.of(health_full_texture if i < hp else health_empty_texture)
		flash.modulate.a = 1.0
		_flash_tween.tween_property(flash, "modulate:a", 0.0, hurt_flash_time)


func _update_power() -> void:
	if is_instance_valid(_player) and "power" in _player:
		_fill_icons(_power_icons, int(_player.power), power_full_texture, power_empty_texture)
		_fill_pips(_power_pool, int(_player.power))


func _update_energy() -> void:
	if is_instance_valid(_player) and "energy" in _player and "max_energy" in _player:
		energy_bar.max_value = _player.max_energy
		energy_bar.value = _player.energy
