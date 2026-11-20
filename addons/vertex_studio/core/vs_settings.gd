@tool
extends RefCounted
class_name VSSettings

## Project Settings for Vertex Studio: Project Settings > General > Vertex Studio.
##
## Shortcuts live here instead of EditorSettings for two reasons: Godot gives plugins
## no API for the Shortcuts tab, and a project settings file can be committed.

const PREFIX := "Vertex_Studio"
const SETTINGS := "Settings"
const SHORTCUTS := "Shortcuts"
const EXTENSIONS := "Extensions"

#region Settings
# ----------------------------------------------------------------
# Settings
# ----------------------------------------------------------------

## Reopen the panel for any MeshInstance3D once it has been opened (see the plugin)
const AUTO_OPEN := "Auto_Open_When_Mesh_Selected"
## Turn Always Show Vertices off when the target is heavy
const AUTO_HIDE_DENSE := "Disable_Always_Show_Vertices_On_Dense_Meshes"
## Vertex count that counts as "dense" for the AUTO_HIDE_DENSE toggle
const DENSE_VERTEX_COUNT := "Dense_Mesh_Vertex_Count"
## Turn Show Vertices itself off when the target is heavier still
const AUTO_HIDE_VERY_DENSE := "Disable_Show_Vertices_On_Very_Dense_Meshes"
## Vertex count that counts as "very dense" for the AUTO_HIDE_VERY_DENSE toggle
const VERY_DENSE_VERTEX_COUNT := "Very_Dense_Mesh_Vertex_Count"
## Triangle count past which the per-dab rebuild waits for mouse up (see the plugin)
const REALTIME_TRI_LIMIT := "Realtime_Painting_Triangle_Limit"
## Show the panel's Targets section: mesh / vertex / triangle counts (and Include Children)
const SHOW_MESH_STATS := "Show_Mesh_Statistics_In_Panel"
## Vertex count at (or above) which Fill Hard / Fill Smooth runs asynchronously
## behind a blocking progress overlay instead of freezing the editor
const ASYNC_FILL_VERTEX_COUNT := "Async_Fill_Normals_Vertex_Count"

static var KNOWN_EXTENSIONS := [
	{
		"id": "vertex_studio_terrain3d",
		"name": "Vertex Studio Terrain3D",
		"search": "Vertex Studio Terrain3D",
		"require_gdextension": true,
		"url": "https://store.godotengine.org/asset/alfredbaudisch/vertex-studio-terrain3d/",
		"about": "Paint and manage vertices of Terrain3D terrains with the full Vertex Studio toolset: "
			+ "selection, brush, precision, blur, fills, replace, vertex groups and "
			+ "variations, alongside Terrain3D's tools.\n\n"
		    + "Requires Vertex Studio GDExtension (Free or Pro) and the Terrain3D addon.",
	},
]

const AUTO_OPEN_DEFAULT := true
const AUTO_HIDE_DENSE_DEFAULT := true
const DENSE_VERTEX_COUNT_DEFAULT := 1000
const AUTO_HIDE_VERY_DENSE_DEFAULT := true
## Default threshold to disable "Show vertices" for GDScript
const VERY_DENSE_VERTEX_COUNT_DEFAULT_SCRIPT := 20000
## Default threshold to disable "Show vertices" for GDExtension
const VERY_DENSE_VERTEX_COUNT_DEFAULT_NATIVE := 250000
const REALTIME_TRI_LIMIT_DEFAULT := 50000
const SHOW_MESH_STATS_DEFAULT := false
const ASYNC_FILL_VERTEX_COUNT_DEFAULT := 100000

#endregion Settings


#region Shortcuts
# ----------------------------------------------------------------
# Shortcuts
# ----------------------------------------------------------------

# A shortcut name carries a category, the setting path is: Vertex_Studio/Shortcuts/<Category>/<Name>.
# The dialog builds its tree from every path segment but the last,
# the bindings end up grouped the way the panel is bound.
const SC_BRUSH_INCREASE := "Brush/Increase_Size"
const SC_BRUSH_DECREASE := "Brush/Decrease_Size"
const SC_OPACITY_INCREASE := "Brush/Increase_Opacity"
const SC_OPACITY_DECREASE := "Brush/Decrease_Opacity"
const SC_BRUSH_SETTINGS := "Brush/Open_Tool_Popup"
const SC_CYCLE_SWATCH := "Brush/Cycle_Swatch_Color"

const SC_TOGGLE_PAINT := "Tools/Toggle_Brush"
const SC_PAINT_ADD := "Tools/Paint_Add"
const SC_TOGGLE_ERASE := "Tools/Toggle_Eraser"
const SC_PAINT_PRECISION := "Tools/Paint_Precision"
const SC_PAINT_NORMALS := "Tools/Paint_Normals"
const SC_PAINT_BLUR := "Tools/Blur_Brush"
const SC_TOGGLE_LASSO := "Tools/Lasso_Selection"
const SC_SELECT_POINT := "Tools/Single_Selection"
const SC_SELECT_RECT := "Tools/Rectangle_Selection"
const SC_SELECT_ELLIPSE := "Tools/Ellipse_Selection"
const SC_SELECT_LINKED := "Tools/Select_Linked"
const SC_INVERT_SELECTION := "Tools/Invert_Selection"
const SC_DESELECT := "Tools/Deselect"

const SC_FILL := "Actions/Fill_All_Or_Selection"
const SC_ERASE_ALL := "Actions/Erase_All"

const SC_SHARED_VERTS := "View/Toggle_Merge_Or_Split_Shared_Vertices"
const SC_FRONT_VERTS := "View/Show_Front_Verts_Only"

const SC_RESTORE_MATERIAL := "Material/Restore_Material"

const SC_RESYNC_UVS := "Mesh_Tools/Resync_Uvs"
const SC_EXPORT_OBJ := "Mesh_Tools/Export_As_Obj"
const SC_EXPORT_GLTF := "Mesh_Tools/Export_As_Gltf"
const SC_REEXPORT := "Mesh_Tools/Re_Export"

## Default binding per shortcut: [keycode, cmd/ctrl, shift, alt].
## Ctrl flag uses `command_or_control_autoremap` (Mac == CMD).
## The ones that are empty have no default binding, but can be assigned in project settings.
## Developer's note: I kept the majority unbound by default to avoid conflicting with the Godot's viewport shortcuts, but do as you please :)
const SHORTCUT_DEFAULTS := {
	SC_TOGGLE_PAINT: [KEY_B, false, false, false],
	SC_PAINT_ADD: [],
	SC_TOGGLE_ERASE: [KEY_E, false, true, false],
	SC_PAINT_PRECISION: [],
	SC_PAINT_NORMALS: [],
	SC_PAINT_BLUR: [],
	SC_TOGGLE_LASSO: [KEY_L, false, false, false],
	SC_SELECT_POINT: [],
	SC_SELECT_RECT: [],
	SC_SELECT_ELLIPSE: [],
	SC_SELECT_LINKED: [],
	SC_INVERT_SELECTION: [],
	SC_DESELECT: [KEY_L, false, true, false],
	SC_FILL: [KEY_G, false, false, false],
	SC_ERASE_ALL: [],
	SC_SHARED_VERTS: [],
	SC_FRONT_VERTS: [],
	SC_RESTORE_MATERIAL: [],
	SC_RESYNC_UVS: [],
	SC_EXPORT_OBJ: [],
	SC_EXPORT_GLTF: [],
	SC_REEXPORT: [],
	SC_BRUSH_INCREASE: [KEY_BRACKETRIGHT, false, false, false],
	SC_BRUSH_DECREASE: [KEY_BRACKETLEFT, false, false, false],
	SC_OPACITY_INCREASE: [KEY_SLASH, false, false, false],
	SC_OPACITY_DECREASE: [KEY_BACKSLASH, false, false, false],
	SC_BRUSH_SETTINGS: [KEY_F, true, false, false],
	SC_CYCLE_SWATCH: [KEY_X, false, false, false],
}
#endregion Shortcuts


#region Registration
# ----------------------------------------------------------------
# Registration
# ----------------------------------------------------------------

static func register_all() -> void:
	register_setting(SETTINGS, AUTO_OPEN, AUTO_OPEN_DEFAULT, TYPE_BOOL)
	register_setting(SETTINGS, AUTO_HIDE_DENSE, AUTO_HIDE_DENSE_DEFAULT, TYPE_BOOL)
	register_setting(SETTINGS, DENSE_VERTEX_COUNT, DENSE_VERTEX_COUNT_DEFAULT, TYPE_INT,
		PROPERTY_HINT_RANGE, "100,10000000,1,or_greater")
	register_setting(SETTINGS, AUTO_HIDE_VERY_DENSE, AUTO_HIDE_VERY_DENSE_DEFAULT, TYPE_BOOL)
	register_setting(SETTINGS, VERY_DENSE_VERTEX_COUNT, very_dense_vertex_count_default(),
		TYPE_INT, PROPERTY_HINT_RANGE, "1000,10000000,1000,or_greater")
	register_setting(SETTINGS, REALTIME_TRI_LIMIT, REALTIME_TRI_LIMIT_DEFAULT, TYPE_INT,
		PROPERTY_HINT_RANGE, "500,10000000,100,or_greater")
	register_setting(SETTINGS, SHOW_MESH_STATS, SHOW_MESH_STATS_DEFAULT, TYPE_BOOL)
	register_setting(SETTINGS, ASYNC_FILL_VERTEX_COUNT, ASYNC_FILL_VERTEX_COUNT_DEFAULT, TYPE_INT,
		PROPERTY_HINT_RANGE, "1000,10000000,1000,or_greater")
	for sc_name in SHORTCUT_DEFAULTS:
		register_shortcut(sc_name)


static func refresh_extensions(native_available: bool) -> void:
	for entry in KNOWN_EXTENSIONS:
		var id := str(entry["id"])
		var here := FileAccess.file_exists("res://addons/%s/plugin.cfg" % id)
		var needs_native := bool(entry.get("require_gdextension", false))
		var status := ""
		if here and needs_native and not native_available:
			status = "Installed, but needs a GDExtension edition of Vertex Studio"
		elif here:
			status = "Installed"
		elif needs_native and not native_available:
			status = "Not installed, and needs a GDExtension edition of Vertex Studio"
		else:
			status = "Not installed"
		var key := str(entry["name"]).replace(" ", "_")
		_report(setting_path(EXTENSIONS, key), status)
		var link := setting_path(EXTENSIONS, key + "_Download")
		if here:
			ProjectSettings.set_setting(link, null)
		else:
			_report(link, str(entry.get("url", "")))


static func _report(path: String, value: String) -> void:
	ProjectSettings.set_setting(path, value)
	ProjectSettings.set_initial_value(path, value)
	ProjectSettings.set_as_basic(path, true)
	ProjectSettings.add_property_info({
		"name": path,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY,
	})


static func setting_path(category: String, key: String) -> String:
	return "%s/%s/%s" % [PREFIX, category, key]


static func register_setting(category: String, key: String, default: Variant, type: int,
		hint := PROPERTY_HINT_NONE, hint_string := "") -> void:
	var path := setting_path(category, key)
	if not ProjectSettings.has_setting(path):
		ProjectSettings.set_setting(path, default)
	ProjectSettings.set_initial_value(path, default)
	ProjectSettings.set_as_basic(path, true)
	ProjectSettings.add_property_info({
		"name": path,
		"type": type,
		"hint": hint,
		"hint_string": hint_string,
	})


static func register_shortcut(sc_name: String) -> void:
	var sc := Shortcut.new()
	sc.resource_name = shortcut_label(sc_name)
	var events: Array[InputEvent] = []
	var def: Array = SHORTCUT_DEFAULTS.get(sc_name, [])
	if def.size() == 4:
		events.append(_key_event(def[0], def[1], def[2], def[3]))
	sc.events = events
	register_setting(SHORTCUTS, sc_name, sc, TYPE_OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Shortcut")


static func _key_event(keycode: int, ctrl: bool, shift: bool, alt: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.command_or_control_autoremap = ctrl
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	return ev

#endregion Registration


#region Persistence
# ----------------------------------------------------------------
# Persistence
# ----------------------------------------------------------------

static func watch_shortcuts(handler: Callable) -> void:
	for sc_name in SHORTCUT_DEFAULTS:
		var sc := get_shortcut(sc_name)
		if sc == null:
			continue
		_watch(sc, handler)
		for e in sc.events:
			if e is Resource:
				_watch(e as Resource, handler)


static func unwatch_shortcuts(handler: Callable) -> void:
	for sc_name in SHORTCUT_DEFAULTS:
		var sc := get_shortcut(sc_name)
		if sc == null:
			continue
		_unwatch(sc, handler)
		for e in sc.events:
			if e is Resource:
				_unwatch(e as Resource, handler)


static func _watch(res: Resource, handler: Callable) -> void:
	if not res.changed.is_connected(handler):
		res.changed.connect(handler)


static func _unwatch(res: Resource, handler: Callable) -> void:
	if res.changed.is_connected(handler):
		res.changed.disconnect(handler)

#endregion Persistence


#region Reading
# ----------------------------------------------------------------
# Reading
# ----------------------------------------------------------------

static func get_setting(category: String, key: String, default: Variant) -> Variant:
	var path := setting_path(category, key)
	if not ProjectSettings.has_setting(path):
		return default
	return ProjectSettings.get_setting(path, default)


static func auto_open_when_mesh_selected() -> bool:
	return bool(get_setting(SETTINGS, AUTO_OPEN, AUTO_OPEN_DEFAULT))


static func auto_hide_dense_vertices() -> bool:
	return bool(get_setting(SETTINGS, AUTO_HIDE_DENSE, AUTO_HIDE_DENSE_DEFAULT))


static func dense_vertex_count() -> int:
	return maxi(1, int(get_setting(SETTINGS, DENSE_VERTEX_COUNT, DENSE_VERTEX_COUNT_DEFAULT)))


static func auto_hide_very_dense_vertices() -> bool:
	return bool(get_setting(SETTINGS, AUTO_HIDE_VERY_DENSE, AUTO_HIDE_VERY_DENSE_DEFAULT))


static func very_dense_vertex_count_default() -> int:
	if not VSMeshData.disable_native and ClassDB.class_exists("VSNativeMesh"):
		return VERY_DENSE_VERTEX_COUNT_DEFAULT_NATIVE
	return VERY_DENSE_VERTEX_COUNT_DEFAULT_SCRIPT


static func very_dense_vertex_count() -> int:
	return maxi(1, int(get_setting(SETTINGS, VERY_DENSE_VERTEX_COUNT, very_dense_vertex_count_default())))


static func realtime_triangle_limit() -> int:
	return maxi(1, int(get_setting(SETTINGS, REALTIME_TRI_LIMIT, REALTIME_TRI_LIMIT_DEFAULT)))


static func show_mesh_statistics() -> bool:
	return bool(get_setting(SETTINGS, SHOW_MESH_STATS, SHOW_MESH_STATS_DEFAULT))


static func async_fill_vertex_count() -> int:
	return maxi(1, int(get_setting(SETTINGS, ASYNC_FILL_VERTEX_COUNT, ASYNC_FILL_VERTEX_COUNT_DEFAULT)))


static func get_shortcut(sc_name: String) -> Shortcut:
	var v: Variant = get_setting(SHORTCUTS, sc_name, null)
	return v as Shortcut if v is Shortcut else null


static func matches(sc_name: String, event: InputEvent) -> bool:
	var sc := get_shortcut(sc_name)
	return sc != null and sc.matches_event(event)


static func keycode(sc_name: String) -> int:
	var sc := get_shortcut(sc_name)
	if sc != null:
		for e in sc.events:
			if e is InputEventKey:
				return (e as InputEventKey).keycode
	var def: Array = SHORTCUT_DEFAULTS.get(sc_name, [])
	return int(def[0]) if not def.is_empty() else KEY_NONE


static func shortcut_label(sc_name: String) -> String:
	return "Vertex Studio: " + sc_name.get_file().replace("_", " ")

#endregion Reading
