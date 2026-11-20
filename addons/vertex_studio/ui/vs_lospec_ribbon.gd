@tool
extends Control
class_name VSLospecRibbon

## Palette's colors as a wrapped strip (tries to match the shape that it's shown in Lospec).

## Target cell size (strip made of blocks)
const CELL := 26.0
const MIN_COLS := 8

var _colors: Array[Color] = []
var _cell := CELL
var _rows := 0


func setup(colors: Array[Color], ui_scale: float) -> void:
	_colors = colors
	_cell = CELL * ui_scale
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = _cell
	queue_redraw()


func _layout() -> Vector2i:
	var cols := maxi(MIN_COLS, int(floor(size.x / _cell)))
	return Vector2i(cols, int(ceil(float(_colors.size()) / float(cols))))


func _draw() -> void:
	if _colors.is_empty():
		return
	var grid := _layout()
	var w := size.x / float(grid.x)
	for i in _colors.size():
		draw_rect(Rect2(float(i % grid.x) * w, float(i / grid.x) * _cell,
			w, _cell), _colors[i])
	if grid.y != _rows:
		_rows = grid.y
		set_deferred("custom_minimum_size", Vector2(0, float(grid.y) * _cell))
