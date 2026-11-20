extends Control
class_name DialogueBox

## The on-screen dialogue panel: speaker name, optional portrait, typewriter body
## text and a continue hint. Ported from Nightbloom v1.
##
## Driven by SayStep, not by the Events bus — a step calls `say()` and awaits it,
## so a conversation is just steps running in order. The box stays open between
## consecutive SaySteps (no flicker); the Interaction calls `close()` when its
## steps are done.
##
## Advancing: the first press while text is typing reveals the whole line; the
## next press moves on.
##
## Choices: `ask()` types a question, then lists options under it. Up/down (or
## left/right) moves the highlight; only `choice_confirm_actions` picks, so the
## jump/attack presses that skip through dialogue can't choose by accident.

## Typewriter speed.
@export var characters_per_second: float = 45.0
## Any of these advances a line. `attack` is LMB, so a mouse click works too.
@export var advance_actions: Array[StringName] = [&"interact", &"jump", &"attack"]
@export var fade_in_duration: float = 0.15
@export var fade_out_duration: float = 0.15
## How far the panel slides up as it fades in (px).
@export var fade_slide_offset: float = 18.0

@export_group("Choices")
## Picks the highlighted option.
@export var choice_confirm_actions: Array[StringName] = [&"interact"]
@export var choice_prev_actions: Array[StringName] = [&"ui_up", &"ui_left", &"move_forward", &"move_left"]
@export var choice_next_actions: Array[StringName] = [&"ui_down", &"ui_right", &"move_back", &"move_right"]
## Options ignore input for this long after appearing, so a press meant to
## reveal the question can't also pick an answer.
@export var choice_input_delay: float = 0.2
@export var choice_selected_color: Color = Color(1, 1, 1, 1)
@export var choice_unselected_color: Color = Color(1, 1, 1, 0.45)

signal _line_advanced
signal _choice_made(index: int)

@onready var panel_container: PanelContainer = $PanelContainer
@onready var speaker_label: Label = $PanelContainer/MarginContainer/VBoxContainer/Header/SpeakerLabel
@onready var body_label: RichTextLabel = $PanelContainer/MarginContainer/VBoxContainer/BodyRow/BodyText
@onready var portrait_rect: TextureRect = $PanelContainer/MarginContainer/VBoxContainer/BodyRow/Portrait
@onready var continue_hint: Label = $PanelContainer/MarginContainer/VBoxContainer/ContinueHint
@onready var choices_box: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/Choices

var _current_text: String = ""
var _reveal_progress: float = 0.0
var _is_typing: bool = false
var _waiting_for_advance: bool = false
var _is_transitioning: bool = false
var _panel_rest_position: Vector2 = Vector2.ZERO
# Options of the question being asked (empty when not asking).
var _options: Array[String] = []
var _choice: int = 0
# The options are listed and taking input (after choice_input_delay).
var _choosing: bool = false


func _ready() -> void:
	add_to_group("dialogue_box")
	hide()
	_panel_rest_position = panel_container.position


## Show `lines` one at a time under `speaker`, waiting for the player to advance
## each. Returns once the last line is dismissed; the box stays open.
func say(speaker: String, portrait: Texture2D, lines: Array[String]) -> void:
	if lines.is_empty():
		return
	await _open_for(speaker, portrait)
	for line: String in lines:
		_show_line(line)
		await _line_advanced


## Type `question`, then list `options` under it and wait for the player to pick
## one. Returns the chosen index (the first option starts highlighted). The box
## stays open afterwards, like say().
func ask(speaker: String, portrait: Texture2D, question: String, options: Array[String]) -> int:
	if options.is_empty():
		return -1
	await _open_for(speaker, portrait)
	_options = options
	_choice = 0
	_show_line(question)
	var index: int = await _choice_made
	_options = []
	_choosing = false
	_clear_choices()
	return index


# Load this speaker before the intro, so a reopened box doesn't fade in still
# showing the previous run's speaker and line.
func _open_for(speaker: String, portrait: Texture2D) -> void:
	speaker_label.text = speaker
	portrait_rect.texture = portrait
	portrait_rect.visible = portrait != null
	if not visible:
		body_label.text = ""
		continue_hint.visible = false
		_clear_choices()
		show()
		await _play_intro_transition()


## Fade the box out. Safe to call when it's already hidden.
func close() -> void:
	if not visible:
		return
	_is_typing = false
	_waiting_for_advance = false
	_choosing = false
	continue_hint.visible = false
	await _play_outro_transition()
	_clear_choices()
	hide()
	panel_container.modulate.a = 1.0
	panel_container.position = _panel_rest_position
	_current_text = ""
	portrait_rect.texture = null


func is_open() -> bool:
	return visible


func _process(delta: float) -> void:
	if not visible or not _is_typing:
		return
	_reveal_progress += characters_per_second * delta
	var visible_chars: int = mini(_current_text.length(), int(floor(_reveal_progress)))
	body_label.visible_characters = visible_chars
	if visible_chars >= _current_text.length():
		_finish_typing()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _is_transitioning:
		return
	if _choosing:
		_handle_choice_input(event)
		return
	if not _is_advance(event):
		return
	get_viewport().set_input_as_handled()
	if _is_typing:
		body_label.visible_characters = _current_text.length()
		_finish_typing()
	elif _waiting_for_advance:
		_waiting_for_advance = false
		continue_hint.visible = false
		_line_advanced.emit()


func _is_advance(event: InputEvent) -> bool:
	return _pressed_any(event, advance_actions)


func _pressed_any(event: InputEvent, actions: Array[StringName]) -> bool:
	if event.is_echo():
		return false
	for action: StringName in actions:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			return true
	return false


func _handle_choice_input(event: InputEvent) -> void:
	if _pressed_any(event, choice_confirm_actions):
		get_viewport().set_input_as_handled()
		_choosing = false
		_choice_made.emit(_choice)
	elif _pressed_any(event, choice_prev_actions):
		get_viewport().set_input_as_handled()
		_set_choice(wrapi(_choice - 1, 0, _options.size()))
	elif _pressed_any(event, choice_next_actions):
		get_viewport().set_input_as_handled()
		_set_choice(wrapi(_choice + 1, 0, _options.size()))


# The question has finished typing: list the options, then take input shortly after.
func _show_choices() -> void:
	_clear_choices()
	for option: String in _options:
		var label := Label.new()
		label.text = option
		label.add_theme_font_size_override(&"font_size", 22)
		choices_box.add_child(label)
	choices_box.visible = true
	_set_choice(_choice)
	if choice_input_delay > 0.0:
		await get_tree().create_timer(choice_input_delay).timeout
	if not _options.is_empty() and visible:
		_choosing = true


func _set_choice(index: int) -> void:
	_choice = index
	for i: int in choices_box.get_child_count():
		var label := choices_box.get_child(i) as Label
		var selected: bool = i == index
		label.text = ("▸  " if selected else "    ") + _options[i]
		label.add_theme_color_override(&"font_color",
				choice_selected_color if selected else choice_unselected_color)


func _clear_choices() -> void:
	for child: Node in choices_box.get_children():
		child.queue_free()
	choices_box.visible = false


func _show_line(text: String) -> void:
	_current_text = text
	body_label.text = text
	body_label.visible_characters = 0
	continue_hint.visible = false
	_reveal_progress = 0.0
	_waiting_for_advance = false
	_is_typing = true


func _finish_typing() -> void:
	_is_typing = false
	if not _options.is_empty():
		_show_choices()  # a question: list the options instead of the ▼ hint
		return
	_waiting_for_advance = true
	continue_hint.visible = true


func _play_intro_transition() -> void:
	_is_transitioning = true
	panel_container.modulate.a = 0.0
	panel_container.position = _panel_rest_position + Vector2(0, fade_slide_offset)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel_container, ^"modulate:a", 1.0, fade_in_duration)
	tween.tween_property(panel_container, ^"position", _panel_rest_position, fade_in_duration)
	await tween.finished
	_is_transitioning = false


func _play_outro_transition() -> void:
	_is_transitioning = true
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(panel_container, ^"modulate:a", 0.0, fade_out_duration)
	tween.tween_property(panel_container, ^"position", _panel_rest_position + Vector2(0, fade_slide_offset), fade_out_duration)
	await tween.finished
	_is_transitioning = false
