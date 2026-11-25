extends Node3D
class_name EnemyHealthPips

## A row of health pips floating above an enemy. Child of the enemy (any
## Destructible); the node's own position is where the row sits, so move the
## node to set the height per creature.
##
## Hidden until the creature first takes damage, then shown for the rest of its
## life; hidden again when it dies. It reads `hp` / `max_hp` from the host and
## listens to the host's `hit` and `died` signals.
##
## Each pip is a Sprite3D, all at this node's position: `billboard` turns them
## to the camera and each one's pixel `offset` spreads them sideways in that
## camera-facing plane, so the row stays level on screen from any angle.
## `fixed_size` keeps one screen size at any distance; `no_depth_test` draws it
## over the creature's own model.
##
## FEEL: the row pops in pip by pip on the first hit; every hit flashes all pips
## white; a pip that empties shrinks to `empty_scale`. All scales ease with
## TRANS_BACK, which overshoots slightly before settling.
##
## SCALING ABOUT THE CENTRE: a sprite's `offset` is multiplied by its scale, so
## scaling the node alone would also slide the pip toward the row's middle.
## _set_pip_scale() divides the offset by the scale to cancel that, so each pip
## stays where it is and grows/shrinks about its own centre.
##
## FLASH: each pip has a white twin drawn on top (same shape, built from the
## pip textures' alpha) whose opacity is tweened from 1 to 0. That keeps the
## sprites' built-in billboard / fixed-size, which a custom shader would have to
## reimplement.

@export var enabled: bool = true

@export_group("Pips")
## Texture for a point of HP still held.
@export var full_texture: Texture2D = preload("res://ui/hud/health_pip_full.png")
## Texture for a point of HP lost.
@export var empty_texture: Texture2D = preload("res://ui/hud/health_pip_empty.png")
## Gap between pips, in texture pixels.
@export var spacing_px: float = 12.0

@export_group("Appearance")
## On-screen size: world units per texture pixel (with `fixed_screen_size`, a
## screen-relative measure). The pip PNGs are 108 px.
@export_range(0.00005, 0.01, 0.00005) var pixel_size: float = 0.00025
## Same size on screen at any distance. Off = shrinks with distance.
@export var fixed_screen_size: bool = true
## Draw over geometry rather than being hidden by it.
@export var draw_through_walls: bool = true

@export_group("Reveal")
## Seconds for one pip to pop from zero to its size on the first hit.
@export_range(0.01, 1.0, 0.01) var reveal_time: float = 0.25
## Delay between one pip starting its pop and the next, left to right.
@export_range(0.0, 0.3, 0.005) var reveal_stagger: float = 0.04

@export_group("Damage")
## Seconds for the white flash on every pip to fade out after a hit.
@export_range(0.01, 1.0, 0.01) var flash_time: float = 0.18
## Scale an emptied pip settles at.
@export_range(0.1, 1.0, 0.05) var empty_scale: float = 0.8
## Seconds for an emptied pip to shrink to `empty_scale`.
@export_range(0.01, 1.0, 0.01) var shrink_time: float = 0.25

## One pip: its sprite, its white flash twin, and its unscaled offset.
class Pip:
	var sprite: Sprite3D
	var flash: Sprite3D
	var base_offset: Vector2
	var scale: float = 1.0
	var tween: Tween

var _host: Node = null
var _pips: Array[Pip] = []
var _shown_hp: int = 0
var _revealed: bool = false
var _flash_tween: Tween


func _ready() -> void:
	visible = false
	_host = get_parent()
	if not enabled or _host == null or not ("hp" in _host and "max_hp" in _host):
		return
	if _host.has_signal("hit"):
		_host.connect("hit", _on_host_hit)
	if _host.has_signal("died"):
		_host.connect("died", _on_host_died)
	# The host's max_hp is final once its own _ready ran (Enemy reads it from
	# enemy_data there), which is after this child's _ready — so build deferred.
	_build.call_deferred()


func _build() -> void:
	for pip in _pips:
		pip.sprite.queue_free()
		pip.flash.queue_free()
	_pips.clear()
	# One pip per point of HP. Enemies are meant to stay at 10 HP or less.
	var count: int = maxi(int(_host.get("max_hp")), 1)
	var width: float = float(full_texture.get_width()) if full_texture else 108.0
	var step: float = width + spacing_px
	for i in count:
		var pip := Pip.new()
		pip.base_offset = Vector2((float(i) - float(count - 1) * 0.5) * step, 0.0)
		pip.sprite = _make_sprite(0)
		pip.flash = _make_sprite(1)
		pip.flash.modulate.a = 0.0
		_pips.append(pip)
		_set_pip_scale(pip, 1.0)
	_shown_hp = int(_host.get("hp"))
	_refresh_textures()


func _make_sprite(priority: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.fixed_size = fixed_screen_size
	s.no_depth_test = draw_through_walls
	s.shaded = false
	s.double_sided = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.pixel_size = pixel_size
	# The flash twin draws after its pip.
	s.render_priority = priority
	add_child(s)
	return s


## Scale a pip about its own centre (see the class notes).
func _set_pip_scale(pip: Pip, s: float) -> void:
	pip.scale = s
	var safe: float = maxf(s, 0.001)
	for sprite: Sprite3D in [pip.sprite, pip.flash]:
		sprite.scale = Vector3.ONE * safe
		sprite.offset = pip.base_offset / safe
		sprite.visible = s > 0.001


func _refresh_textures() -> void:
	for i in _pips.size():
		var tex: Texture2D = full_texture if i < _shown_hp else empty_texture
		_pips[i].sprite.texture = tex
		_pips[i].flash.texture = Silhouette.of(tex)


## Tween a pip's scale from where it is now. `delay` waits first.
func _tween_pip(pip: Pip, to: float, time: float, delay: float = 0.0) -> void:
	if pip.tween:
		pip.tween.kill()
	pip.tween = create_tween()
	if delay > 0.0:
		pip.tween.tween_interval(delay)
	pip.tween.tween_method(func(s: float) -> void: _set_pip_scale(pip, s), pip.scale, to, time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_host_hit(_amount: int) -> void:
	if _pips.is_empty():
		return
	var hp: int = int(_host.get("hp"))
	var prev: int = _shown_hp
	_shown_hp = hp
	_refresh_textures()

	if not _revealed:
		# First hit: every pip pops in from nothing, left to right, landing at
		# its resting size (empties already small).
		_revealed = true
		visible = true
		for i in _pips.size():
			_set_pip_scale(_pips[i], 0.0)
			var target: float = 1.0 if i < hp else empty_scale
			_tween_pip(_pips[i], target, reveal_time, reveal_stagger * float(i))
	else:
		# Pips that just went full -> empty shrink.
		for i in range(hp, mini(prev, _pips.size())):
			_tween_pip(_pips[i], empty_scale, shrink_time)

	_flash()


func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween().set_parallel(true)
	for pip in _pips:
		pip.flash.modulate.a = 1.0
		_flash_tween.tween_property(pip.flash, "modulate:a", 0.0, flash_time)


func _on_host_died() -> void:
	visible = false

