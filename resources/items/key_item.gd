extends Resource
class_name KeyItem

## A story item the player carries: picked up by a PickupStep, shown in the HUD's
## KeyItemsUI, read in its inspect mode, and (later) handed over by a
## UseKeyItemStep. One .tres per item, kept in resources/items/.
##
## Items are compared by `id`, never by resource identity, so the inventory can be
## saved as a list of ids later.

## Unique, stable identifier ("smoldering_ember"). Also names the default pickup
## flag, `got_<id>`.
@export var id: StringName = &""
@export var display_name: String = ""
## Shown as a subtitle while the item is selected in the inspect mode.
@export_multiline var description: String = ""
## Thumbnail. A cut-out with transparency — the selection glow follows its alpha.
@export var icon: Texture2D
