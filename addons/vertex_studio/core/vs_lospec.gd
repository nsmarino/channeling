@tool
extends RefCounted
class_name VSLospec

## Lospec palette list, that reads palletes from disk (offline, no internet required).

const PATH := "res://addons/vertex_studio/palettes/lospec.json"
const URL := "https://lospec.com/palette-list"
## Swatch cap (same as PNG palette importer)
const MAX_COLORS := 256

## Color count filter. `ANY` ignores it
enum Filter { ANY, MAX, MIN, EXACT }

static var _palettes: Array = []
static var _loaded := false


static func palettes() -> Array:
	if _loaded:
		return _palettes
	_loaded = true
	var text := FileAccess.get_file_as_string(PATH)
	if text.is_empty():
		return _palettes
	var data: Variant = JSON.parse_string(text)
	if not (data is Array):
		return _palettes
	for p in data:
		if p is Dictionary and (p as Dictionary).get("colors", []) is Array \
				and not (p as Dictionary)["colors"].is_empty():
			_palettes.append(p)
	return _palettes


static func count_of(palette: Dictionary) -> int:
	var n := int(palette.get("numberOfColors", 0))
	return n if n > 0 else (palette.get("colors", []) as Array).size()


static func matches(palette: Dictionary, mode: Filter, count: int) -> bool:
	var have := count_of(palette)
	match mode:
		Filter.MAX: return have <= count
		Filter.MIN: return have >= count
		Filter.EXACT: return have == count
	return true


static func filtered(mode: Filter, count: int) -> Array:
	if mode == Filter.ANY:
		return palettes()
	var out: Array = []
	for p in palettes():
		if matches(p, mode, count):
			out.append(p)
	return out


static func colors_of(palette: Dictionary) -> Array[Color]:
	var out: Array[Color] = []
	for text in (palette.get("colors", []) as Array):
		out.append(Color(str(text)))
		if out.size() >= MAX_COLORS:
			break
	return out


static func label_of(palette: Dictionary) -> String:
	var author := str(palette.get("author", "")).strip_edges()
	var name := str(palette.get("name", "Untitled")).strip_edges()
	var n := count_of(palette)
	if author.is_empty():
		return "%s  -  %d colors" % [name, n]
	return "%s  -  %s  -  %d colors" % [name, author, n]
