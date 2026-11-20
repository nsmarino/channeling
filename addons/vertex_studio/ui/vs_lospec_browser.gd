@tool
extends ConfirmationDialog
class_name VSLospecBrowser

## Browses the Lospec palette list and loads the swatches.

signal palette_chosen(colors: Array[Color])

const SIZE := Vector2i(800, 800)

var _scroll: ScrollContainer
var _list: VBoxContainer
var _count_spin: SpinBox
var _empty: Label
var _mode := VSLospec.Filter.ANY
var _hover: StyleBoxFlat
var _flat := StyleBoxEmpty.new()
var _scale := 1.0


func _init() -> void:
	title = "Lospec Palettes"
	ok_button_text = "Done"
	_scale = EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	_hover = StyleBoxFlat.new()
	_hover.bg_color = Color(1, 1, 1, 0.07)
	_hover.set_corner_radius_all(int(round(3 * _scale)))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", int(round(6 * _scale)))
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	root.add_child(_build_filter_row())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", int(round(2 * _scale)))
	_scroll.add_child(_list)
	root.add_child(_scroll)

	_empty = Label.new()
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.visible = false
	root.add_child(_empty)

	var more := add_button("See more in Lospec", true)
	more.pressed.connect(func(): OS.shell_open(VSLospec.URL))
	about_to_popup.connect(_refresh)


func _build_filter_row() -> Control:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Colors"
	row.add_child(lbl)
	var group := ButtonGroup.new()
	for mode in [VSLospec.Filter.ANY, VSLospec.Filter.MAX,
			VSLospec.Filter.MIN, VSLospec.Filter.EXACT]:
		var b := Button.new()
		b.text = ["Any", "Max", "Min", "Exact"][mode]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = mode == _mode
		b.pressed.connect(func(): _set_mode(mode))
		row.add_child(b)
	_count_spin = SpinBox.new()
	_count_spin.min_value = 2
	_count_spin.max_value = VSLospec.MAX_COLORS
	_count_spin.value = 16
	_count_spin.editable = false
	_count_spin.value_changed.connect(func(_v): _refresh())
	row.add_child(_count_spin)
	return row


func _set_mode(mode: VSLospec.Filter) -> void:
	_mode = mode
	_count_spin.editable = mode != VSLospec.Filter.ANY
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
		_list.remove_child(c)
	var shown := VSLospec.filtered(_mode, int(_count_spin.value))
	for p in shown:
		_list.add_child(_build_entry(p))
	if VSLospec.palettes().is_empty():
		_empty.text = "The palette list did not load (%s)." % VSLospec.PATH
	else:
		_empty.text = "No palette has that many colors."
	_empty.visible = shown.is_empty()


func _build_entry(palette: Dictionary) -> Control:
	var colors := VSLospec.colors_of(palette)
	var entry := PanelContainer.new()
	entry.tooltip_text = "Load this palette onto the swatches"
	entry.add_theme_stylebox_override("panel", _flat)
	entry.gui_input.connect(func(e: InputEvent): _on_entry_input(e, colors))
	entry.mouse_entered.connect(func(): entry.add_theme_stylebox_override("panel", _hover))
	entry.mouse_exited.connect(func(): entry.add_theme_stylebox_override("panel", _flat))

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", int(round(2 * _scale)))
	var title := Label.new()
	title.text = VSLospec.label_of(palette)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var ribbon := VSLospecRibbon.new()
	ribbon.setup(colors, _scale)
	box.add_child(ribbon)
	entry.add_child(box)
	return entry


func _on_entry_input(event: InputEvent, colors: Array[Color]) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		palette_chosen.emit(colors)
