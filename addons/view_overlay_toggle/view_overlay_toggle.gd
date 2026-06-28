@tool
extends EditorPlugin

## Blender-style "toggle viewport overlays" shortcut for the 3D editor.
##
## Godot lets you bind a shortcut to ONE built-in toggle, but not gang several
## together (or bind a key like Caps Lock at all). Each hotkey here fires its
## binding's menu items by emitting their `id_pressed` — the editor's own handler
## does the real toggle + checkmark. (There's no public API for grid/gizmo/etc.
## visibility, so driving the menus is the practical route.) Defaults:
##   - Option(Alt)+Shift+Z → View Grid + View Gizmos
##   - Period (.)          → Lock View Rotation (tap to toggle)
##
## Setup:
##   1. Project > Project Settings > Plugins → enable "View Overlay Toggle".
##   2. REMOVE any Editor Settings shortcut bound to the same keys, or it'll
##      double-fire and cancel itself out.
##   3. Project > Tools > "Print 3D View Menu Items" dumps the exact labels your
##      build uses to the Output panel — copy the ones you want into the label
##      lists below.

## Menu-item labels each hotkey toggles together. Must match exactly — use the
## Project > Tools command below to discover them. ("View Gizmos" also hides the
## transform manipulator.)
const OVERLAY_LABELS: Array[String] = ["View Grid", "View Gizmos"]
const LOCK_LABELS: Array[String] = ["Lock View Rotation"]

# Built in _enter_tree: [{ "shortcut": Shortcut, "labels": Array[String],
# "any_edge": bool }]. any_edge=false (normal) toggles on the press edge only. Set
# it true only for lock keys like Caps Lock, whose pressed-state mirrors the lock
# LED (there a press-only gate would fire on every other tap).
var _bindings: Array = []


func _enter_tree() -> void:
	_bindings = [
		# Option(Alt) + Shift + Z → grid + gizmos.
		{"shortcut": _make_shortcut(KEY_Z, true, true, false, false), "labels": OVERLAY_LABELS, "any_edge": false},
		# Period (.) → lock view rotation. any_edge=false → fires on the press edge
		# only, so each tap flips the state and it stays (a real toggle).
		{"shortcut": _make_shortcut(KEY_PERIOD, false, false, false, false), "labels": LOCK_LABELS, "any_edge": false},
	]
	add_tool_menu_item("Print 3D View Menu Items", _print_menu_items)


func _exit_tree() -> void:
	_bindings.clear()
	remove_tool_menu_item("Print 3D View Menu Items")


## Build a Shortcut from a physical key + modifiers (physical_keycode so macOS
## Option / keyboard-layout remapping doesn't break matching).
func _make_shortcut(keycode: Key, alt: bool, shift: bool, ctrl: bool, meta: bool) -> Shortcut:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.alt_pressed = alt
	ev.shift_pressed = shift
	ev.ctrl_pressed = ctrl
	ev.meta_pressed = meta
	var sc := Shortcut.new()
	sc.events = [ev]
	return sc


func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.is_echo():
		return
	for b: Dictionary in _bindings:
		# Normal keys fire on the press edge; any_edge keys (Caps Lock) fire on
		# either edge so every physical tap counts.
		if not bool(b["any_edge"]) and not event.is_pressed():
			continue
		var sc: Shortcut = b["shortcut"]
		if sc.matches_event(event):
			var base: Node = EditorInterface.get_base_control()
			var labels: Array[String] = b["labels"]
			for label in labels:
				_toggle_all_matching(base, label)
			get_viewport().set_input_as_handled()
			return


## Fire every PopupMenu item whose text == `label` (so a per-viewport item like
## "View Gizmos" flips in all open viewports at once). Returns how many fired.
func _toggle_all_matching(node: Node, label: String) -> int:
	var count := 0
	if node is PopupMenu:
		var pm: PopupMenu = node
		for i in pm.item_count:
			if pm.get_item_text(i) == label:
				pm.id_pressed.emit(pm.get_item_id(i))
				count += 1
	# include_internal = true: the editor builds its menus as INTERNAL children,
	# which a plain get_children() skips entirely.
	for child in node.get_children(true):
		count += _toggle_all_matching(child, label)
	return count


## Tools command: dump every non-empty editor PopupMenu and its items so you can
## copy the exact labels into the label lists above.
func _print_menu_items() -> void:
	print("--- Editor PopupMenu items (find your labels here) ---")
	_dump(EditorInterface.get_base_control())


func _dump(node: Node) -> void:
	if node is PopupMenu and (node as PopupMenu).item_count > 0:
		var pm: PopupMenu = node
		var items: Array[String] = []
		for i in pm.item_count:
			items.append(pm.get_item_text(i))
		print("%s: %s" % [pm.name, items])
	for child in node.get_children(true):
		_dump(child)
