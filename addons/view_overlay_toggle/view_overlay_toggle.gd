@tool
extends EditorPlugin

## Blender-style "toggle viewport overlays" shortcut for the 3D editor.
##
## Godot lets you bind a shortcut to ONE built-in toggle, but not gang several
## together. This plugin catches a single hotkey and fires each toggle in
## TOGGLE_LABELS by emitting that menu item's `id_pressed` — the editor's own
## handler then does the real toggle + checkmark. (There's no public API for
## grid/gizmo visibility, so driving the menus is the practical route.)
##
## Setup:
##   1. Project > Project Settings > Plugins → enable "View Overlay Toggle".
##   2. REMOVE any Editor Settings shortcut you bound to "View Gizmos" (etc.) on
##      this same key, or it'll double-fire and cancel itself out.
##   3. Project > Tools > "Print 3D View Menu Items" dumps the exact labels your
##      build uses to the Output panel — copy the ones you want into TOGGLE_LABELS.

## Exact 3D-editor menu-item labels to toggle together. "View Grid" lives in the
## toolbar View menu; "View Gizmos" is per-viewport (and also hides the transform
## manipulator). Use the Tools command above to discover / confirm labels.
const TOGGLE_LABELS: Array[String] = ["View Grid", "View Gizmos"]

## Hotkey = Option(Alt) + Shift + Z. Tweak here.
const HOTKEY_KEYCODE := KEY_Z
const HOTKEY_ALT := true   # Option on macOS
const HOTKEY_SHIFT := true
const HOTKEY_CTRL := false
const HOTKEY_META := false # Command on macOS

var _shortcut: Shortcut


func _enter_tree() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = HOTKEY_KEYCODE  # physical key — survives macOS Option remapping
	ev.alt_pressed = HOTKEY_ALT
	ev.shift_pressed = HOTKEY_SHIFT
	ev.ctrl_pressed = HOTKEY_CTRL
	ev.meta_pressed = HOTKEY_META
	_shortcut = Shortcut.new()
	_shortcut.events = [ev]

	add_tool_menu_item("Print 3D View Menu Items", _print_menu_items)


func _exit_tree() -> void:
	remove_tool_menu_item("Print 3D View Menu Items")


func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.is_echo() or not event.is_pressed():
		return
	if not _shortcut.matches_event(event):
		return
	# Reaching here means the HOTKEY actually matched (not just any keypress).
	var base: Node = EditorInterface.get_base_control()
	var toggled := 0
	for label in TOGGLE_LABELS:
		toggled += _toggle_all_matching(base, label)
	get_viewport().set_input_as_handled()


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
## copy the exact labels into TOGGLE_LABELS.
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
