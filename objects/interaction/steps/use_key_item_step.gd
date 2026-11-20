extends InteractionStep
class_name UseKeyItemStep

## Offers a key item: "Give the Smoldering Ember?" — Give / Keep.
##
## If the player holds `item`, the DialogueBox asks (with the item's icon as the
## portrait). Accepting removes it from the Inventory, sets `given_flag` and
## emits `given`; the steps after this one then run. Declining, or not holding
## the item, ends the interaction here unless told to continue.
##
## Make the outcome stick with flags rather than signals: `given_flag` drives
## a FlagSpawner (the ember appearing in the nest) and the follow-up Interaction
## (`required_flag`), and gates this one off (`unless_flag`), so it all survives
## restarts.

signal given
signal declined

@export var item: KeyItem
## "{item}" is replaced by the item's display name.
@export var question: String = "Give the {item}?"
@export var accept_label: String = "Give"
@export var decline_label: String = "Keep"
@export var speaker: String = ""
## GameManager flag set when the item is given ("" = none).
@export var given_flag: StringName = &""
## Run the following steps even when the player keeps the item.
@export var continue_if_declined: bool = false
## Run the following steps even when the player doesn't hold the item.
@export var continue_if_missing: bool = false


func uses_dialogue_box() -> bool:
	return true


func run(interaction: Interaction) -> void:
	if item == null:
		push_warning("[UseKeyItemStep] %s: no KeyItem set." % get_path())
		interaction.end_early()
		return
	if not Inventory.has(item.id):
		if not continue_if_missing:
			interaction.end_early()
		return
	var box: DialogueBox = interaction.get_dialogue_box()
	if box == null:
		push_warning("[UseKeyItemStep] No DialogueBox in the HUD — run main.tscn.")
		interaction.end_early()
		return

	var text: String = question.format({"item": item.display_name})
	var choice: int = await box.ask(speaker, item.icon, text, [accept_label, decline_label])
	if choice == 0:
		Inventory.remove(item.id)
		if not given_flag.is_empty():
			GameManager.set_flag(given_flag)
		given.emit()
	else:
		declined.emit()
		if not continue_if_declined:
			interaction.end_early()
