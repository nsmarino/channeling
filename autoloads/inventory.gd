extends Node

## The player's key items (KeyItem resources), held for the whole session.
##
## An autoload rather than a field on the player for the same reason
## GameManager.flags is: the player is rebuilt on every restart, and a key item is
## story state — dying must not lose the Ember (and the Ember must not respawn
## while you still hold it; PickupStep's flag handles that half).
##
## Items are unique: adding one you already hold does nothing. Changes are
## announced on Events.key_item_added / key_item_removed; the HUD's KeyItemsUI
## listens.

var _items: Array[KeyItem] = []


## Add `item`. Returns false if it was null or already held.
func add(item: KeyItem) -> bool:
	if item == null or item.id.is_empty():
		push_warning("[Inventory] Ignoring a KeyItem with no id.")
		return false
	if has(item.id):
		return false
	_items.append(item)
	Events.key_item_added.emit(item)
	return true


## Remove the item with `id`. Returns false if it wasn't held.
func remove(id: StringName) -> bool:
	for i: int in _items.size():
		if _items[i].id == id:
			var item: KeyItem = _items[i]
			_items.remove_at(i)
			Events.key_item_removed.emit(item)
			return true
	return false


func has(id: StringName) -> bool:
	for item: KeyItem in _items:
		if item.id == id:
			return true
	return false


## The held items in pickup order (a copy — change the inventory through add/remove).
func get_items() -> Array[KeyItem]:
	return _items.duplicate()


func is_empty() -> bool:
	return _items.is_empty()
