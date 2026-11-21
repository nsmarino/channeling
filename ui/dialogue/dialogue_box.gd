extends Control
class_name DialogueBox

## The on-screen dialogue, styled like film subtitles to match the key-item
## inspect mode: a vignette darkens the screen edges while it's open, and the
## speaker name and typewriter body text sit centred near the bottom in the shared
## serif italic. The portrait is pinned to the lower-left corner and the ▼
## continue hint to the lower-right, both outside the text's layout, so neither
## shifts it; the text's width is capped to stay clear of the portrait.
## Ported from Nightbloom v1.
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
@export var fade_in_duration: float = 0.25
@export var fade_out_duration: float = 0.25
## Widest the text may get (px). It also always stops short of the portrait's
## corner, on both sides so it stays centred.
@export var text_max_width: float = 720.0
## Space kept between the text and the portrait (px).
@export var text_portrait_gap: float = 24.0
## Seconds for one blink of the ▼ continue hint (0 = steady).
@export var hint_blink_period: float = 1.0
## How far the hint dims at the bottom of a blink.
@export_range(0.0, 1.0) var hint_min_alpha: float = 0.1

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
@onready var vignette: ColorRect = $Vignette
@onready var speaker_label: Label = $PanelContainer/VBoxContainer/SpeakerLabel
@onready var body_label: RichTextLabel = $PanelContainer/VBoxContainer/BodyText
@onready var portrait_rect: TextureRect = $Portrait
@onready var continue_hint: Label = $ContinueHint
@onready var choices_box: VBoxContainer = $PanelContainer/VBoxContainer/Choices

var _current_text: String = ""
var _reveal_progress: float = 0.0
var _is_typing: bool = false
var _waiting_for_advance: bool = false
var _is_transitioning: bool = false
var _hint_time: float = 0.0
# Options of the question being asked (empty when not asking).
var _options: Array[String] = []
var _choice: int = 0
# The options are listed and taking input (after choice_input_delay).
var _choosing: bool = false


func _ready() -> void:
	add_to_group("dialogue_box")
	hide()
	_set_vignette(0.0)
	resized.connect(_update_text_width)
	_update_text_width()


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
	# Lay the options out (invisible) before typing, so the question doesn't jump
	# up when they appear.
	_build_choices()
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
	speaker_label.visible = not speaker.is_empty()
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
	_current_text = ""
	portrait_rect.texture = null


# Centre the text and cap its width: no wider than text_max_width, and clear of
# the portrait's corner on both sides (whether or not a portrait is showing, so
# the text never changes width between speakers).
func _update_text_width() -> void:
	var side: float = portrait_rect.offset_right + text_portrait_gap
	var width: float = maxf(minf(text_max_width, size.x - 2.0 * side), 120.0)
	panel_container.offset_left = -width * 0.5
	panel_container.offset_right = width * 0.5


func is_open() -> bool:
	return visible


func _process(delta: float) -> void:
	if not visible:
		return
	if continue_hint.visible:
		_blink_hint(delta)
	if not _is_typing:
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


# Lay the options out under the question, invisible until it has typed out.
func _build_choices() -> void:
	_clear_choices()
	var font: Font = body_label.get_theme_font(&"normal_font")
	for option: String in _options:
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override(&"font", font)
		label.add_theme_font_size_override(&"font_size", 22)
		label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.6))
		label.add_theme_constant_override(&"outline_size", 4)
		choices_box.add_child(label)
	choices_box.modulate.a = 0.0
	choices_box.visible = true
	_set_choice(_choice)


# The question has finished typing: show the options, then take input shortly after.
func _reveal_choices() -> void:
	var tween := create_tween()
	tween.tween_property(choices_box, ^"modulate:a", 1.0, 0.15)
	if choice_input_delay > 0.0:
		await get_tree().create_timer(choice_input_delay).timeout
	if not _options.is_empty() and visible:
		_choosing = true


func _set_choice(index: int) -> void:
	_choice = index
	for i: int in choices_box.get_child_count():
		var label := choices_box.get_child(i) as Label
		var selected: bool = i == index
		# Marks on both sides keep the centred word where it was.
		label.text = ("›  %s  ‹" if selected else "%s") % _options[i]
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
		_reveal_choices()  # a question: show the options instead of the ▼ hint
		return
	_waiting_for_advance = true
	_hint_time = 0.0  # each line's hint starts fully lit
	continue_hint.modulate.a = 1.0
	continue_hint.visible = true


# Fade the ▼ hint in and out: lit for the first half of each period, dim for
# the second, with soft edges.
func _blink_hint(delta: float) -> void:
	_hint_time += delta
	if hint_blink_period <= 0.0:
		continue_hint.modulate.a = 1.0
		return
	var wave: float = 0.5 + 0.5 * cos(TAU * _hint_time / hint_blink_period)
	continue_hint.modulate.a = lerpf(hint_min_alpha, 1.0, smoothstep(0.2, 0.8, wave))


func _play_intro_transition() -> void:
	_is_transitioning = true
	panel_container.modulate.a = 0.0
	portrait_rect.modulate.a = 0.0
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel_container, ^"modulate:a", 1.0, fade_in_duration)
	tween.tween_property(portrait_rect, ^"modulate:a", 1.0, fade_in_duration)
	tween.tween_method(_set_vignette, _vignette_amount(), 1.0, fade_in_duration)
	await tween.finished
	_is_transitioning = false


func _play_outro_transition() -> void:
	_is_transitioning = true
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(panel_container, ^"modulate:a", 0.0, fade_out_duration)
	tween.tween_property(portrait_rect, ^"modulate:a", 0.0, fade_out_duration)
	tween.tween_method(_set_vignette, _vignette_amount(), 0.0, fade_out_duration)
	await tween.finished
	_is_transitioning = false


func _set_vignette(amount: float) -> void:
	var mat := vignette.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter(&"amount", amount)


func _vignette_amount() -> float:
	var mat := vignette.material as ShaderMaterial
	return float(mat.get_shader_parameter(&"amount")) if mat else 0.0
