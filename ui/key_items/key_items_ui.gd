extends CanvasLayer
class_name KeyItemsUI

## The player's key items on the HUD: a row of thumbnails in the lower left, and
## an inspect mode toggled by `inspect_action`.
##
## Inspecting darkens the screen edges, enlarges the selected thumbnail with a
## glow, and shows its description as a subtitle. The player keeps moving — this
## only reads its own actions (left/right to choose), and closes itself when an
## interaction or cutscene starts so it never sits on top of a conversation.
##
## Follows the Inventory autoload through Events.key_item_added / removed, and
## rebuilds from it on load, so the row survives restarts with the inventory.

@export var inspect_action: StringName = &"key_items_inspect"
@export var prev_action: StringName = &"key_item_prev"
@export var next_action: StringName = &"key_item_next"
## Subtitle shown when inspecting with nothing in the inventory.
@export var empty_text: String = "Nothing carried"

@export_group("Thumbnails")
## Square size of each thumbnail slot (px). The icon is inset inside it by the
## glow material's `padding`, to leave room for the glow.
@export var thumbnail_size: float = 84.0
## Seconds for a new thumbnail to pop in from nothing.
@export var appear_duration: float = 0.5
## Scale of the selected thumbnail while inspecting.
@export var selected_scale: float = 1.3
@export var select_duration: float = 0.25
## Template glow material; each thumbnail gets its own copy.
@export var glow_material: ShaderMaterial

@export_group("Inspect")
@export var vignette_fade: float = 0.35
@export var caption_fade: float = 0.2

@onready var _vignette: ColorRect = $Vignette
@onready var _strip: HBoxContainer = $Strip
@onready var _caption: Control = $Caption
@onready var _name_label: Label = $Caption/Name
@onready var _description_label: Label = $Caption/Description

var _inspecting: bool = false
var _selected: int = 0
# Parallel arrays: the held items and their thumbnails, in pickup order.
var _items: Array[KeyItem] = []
var _thumbs: Array[TextureRect] = []
var _thumb_tweens: Dictionary[TextureRect, Tween] = {}
var _vignette_tween: Tween
var _caption_tween: Tween


func _ready() -> void:
	_set_vignette(0.0)
	_caption.modulate.a = 0.0
	for item: KeyItem in Inventory.get_items():
		_add_thumb(item, false)
	Events.key_item_added.connect(_on_item_added)
	Events.key_item_removed.connect(_on_item_removed)
	Events.interaction_started.connect(func(_i: Node) -> void: close())
	Events.cutscene_started.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(inspect_action):
		# Only consume the press when it does something: d-pad up is also a
		# dialogue choice key while control is locked.
		if _inspecting:
			close()
			get_viewport().set_input_as_handled()
		elif _can_open():
			open()
			get_viewport().set_input_as_handled()
	elif _inspecting and event.is_action_pressed(prev_action):
		_step_selection(-1)
		get_viewport().set_input_as_handled()
	elif _inspecting and event.is_action_pressed(next_action):
		_step_selection(1)
		get_viewport().set_input_as_handled()


func is_inspecting() -> bool:
	return _inspecting


func open() -> void:
	if _inspecting:
		return
	_inspecting = true
	_fade_vignette(1.0)
	_selected = clampi(_selected, 0, maxi(_items.size() - 1, 0))
	if _items.is_empty():
		_show_caption("", empty_text)
	else:
		_select(_selected)


func close() -> void:
	if not _inspecting:
		return
	_inspecting = false
	_fade_vignette(0.0)
	_hide_caption()
	if _selected < _thumbs.size():
		_animate_thumb(_thumbs[_selected], 1.0, 0.0, select_duration)


## Not during a conversation, cutscene or anything else holding the player.
func _can_open() -> bool:
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player and player.has_method("is_control_enabled"):
		return bool(player.call("is_control_enabled"))
	return true


# --- selection ---------------------------------------------------------------

func _step_selection(dir: int) -> void:
	if _items.size() < 2:
		return
	_select(wrapi(_selected + dir, 0, _items.size()))


func _select(index: int) -> void:
	if _selected != index and _selected < _thumbs.size():
		_animate_thumb(_thumbs[_selected], 1.0, 0.0, select_duration)
	_selected = index
	_animate_thumb(_thumbs[index], selected_scale, 1.0, select_duration)
	var item: KeyItem = _items[index]
	_show_caption(item.display_name, item.description)


# --- thumbnails --------------------------------------------------------------

func _on_item_added(item: KeyItem) -> void:
	_add_thumb(item, true)
	if _inspecting and _items.size() == 1:
		_select(0)  # was showing "Nothing carried"


func _on_item_removed(item: KeyItem) -> void:
	var index: int = -1
	for i: int in _items.size():
		if _items[i].id == item.id:
			index = i
			break
	if index < 0:
		return
	var thumb: TextureRect = _thumbs[index]
	_items.remove_at(index)
	_thumbs.remove_at(index)
	var tween: Tween = _new_thumb_tween(thumb)  # kills a pop-in still playing
	_thumb_tweens.erase(thumb)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(thumb, ^"scale", Vector2.ZERO, appear_duration * 0.6)
	tween.tween_callback(thumb.get_parent().queue_free)

	if index < _selected or _selected >= _items.size():
		_selected = maxi(_selected - 1, 0)
	if _inspecting:
		if _items.is_empty():
			_show_caption("", empty_text)
		else:
			_select(_selected)


func _add_thumb(item: KeyItem, animate: bool) -> void:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(thumbnail_size, thumbnail_size)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := TextureRect.new()
	rect.texture = item.icon
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Grow upward out of the row rather than off the bottom of the screen.
	rect.pivot_offset = Vector2(thumbnail_size * 0.5, thumbnail_size)
	if glow_material:
		rect.material = glow_material.duplicate()
	slot.add_child(rect)
	_strip.add_child(slot)
	_items.append(item)
	_thumbs.append(rect)
	if animate:
		rect.scale = Vector2.ZERO
		var tween: Tween = _new_thumb_tween(rect)
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(rect, ^"scale", Vector2.ONE, appear_duration)


## Tween a thumbnail to `to_scale` and its glow to `to_glow`.
func _animate_thumb(rect: TextureRect, to_scale: float, to_glow: float, duration: float) -> void:
	var tween: Tween = _new_thumb_tween(rect)
	tween.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(rect, ^"scale", Vector2.ONE * to_scale, duration)
	var mat := rect.material as ShaderMaterial
	if mat:
		var from_glow: float = float(mat.get_shader_parameter(&"glow_amount"))
		tween.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"glow_amount", v),
				from_glow, to_glow, duration).set_trans(Tween.TRANS_SINE)


func _new_thumb_tween(rect: TextureRect) -> Tween:
	var old: Tween = _thumb_tweens.get(rect)
	if old and old.is_valid():
		old.kill()
	var tween: Tween = rect.create_tween()
	_thumb_tweens[rect] = tween
	return tween


# --- vignette & caption ------------------------------------------------------

func _fade_vignette(to: float) -> void:
	if _vignette_tween and _vignette_tween.is_valid():
		_vignette_tween.kill()
	var mat := _vignette.material as ShaderMaterial
	var from: float = float(mat.get_shader_parameter(&"amount")) if mat else 0.0
	_vignette_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_vignette_tween.tween_method(_set_vignette, from, to, vignette_fade)


func _set_vignette(amount: float) -> void:
	var mat := _vignette.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter(&"amount", amount)


func _show_caption(title: String, text: String) -> void:
	_name_label.text = title
	_name_label.visible = not title.is_empty()
	_description_label.text = text
	if _caption_tween and _caption_tween.is_valid():
		_caption_tween.kill()
	_caption.modulate.a = 0.0
	_caption_tween = create_tween()
	_caption_tween.tween_property(_caption, ^"modulate:a", 1.0, caption_fade)


func _hide_caption() -> void:
	if _caption_tween and _caption_tween.is_valid():
		_caption_tween.kill()
	_caption_tween = create_tween()
	_caption_tween.tween_property(_caption, ^"modulate:a", 0.0, caption_fade)
