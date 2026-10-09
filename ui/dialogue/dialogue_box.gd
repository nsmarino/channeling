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

## Typewriter speed.
@export var characters_per_second: float = 45.0
## Any of these advances a line. `attack` is LMB, so a mouse click works too.
@export var advance_actions: Array[StringName] = [&"interact", &"jump", &"attack"]
@export var fade_in_duration: float = 0.15
@export var fade_out_duration: float = 0.15
## How far the panel slides up as it fades in (px).
@export var fade_slide_offset: float = 18.0

signal _line_advanced

@onready var panel_container: PanelContainer = $PanelContainer
@onready var speaker_label: Label = $PanelContainer/MarginContainer/VBoxContainer/Header/SpeakerLabel
@onready var body_label: RichTextLabel = $PanelContainer/MarginContainer/VBoxContainer/BodyRow/BodyText
@onready var portrait_rect: TextureRect = $PanelContainer/MarginContainer/VBoxContainer/BodyRow/Portrait
@onready var continue_hint: Label = $PanelContainer/MarginContainer/VBoxContainer/ContinueHint

var _current_text: String = ""
var _reveal_progress: float = 0.0
var _is_typing: bool = false
var _waiting_for_advance: bool = false
var _is_transitioning: bool = false
var _panel_rest_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("dialogue_box")
	hide()
	_panel_rest_position = panel_container.position


## Show `lines` one at a time under `speaker`, waiting for the player to advance
## each. Returns once the last line is dismissed; the box stays open.
func say(speaker: String, portrait: Texture2D, lines: Array[String]) -> void:
	if lines.is_empty():
		return
	if not visible:
		show()
		await _play_intro_transition()
	speaker_label.text = speaker
	portrait_rect.texture = portrait
	portrait_rect.visible = portrait != null
	for line: String in lines:
		_show_line(line)
		await _line_advanced


## Fade the box out. Safe to call when it's already hidden.
func close() -> void:
	if not visible:
		return
	_is_typing = false
	_waiting_for_advance = false
	continue_hint.visible = false
	await _play_outro_transition()
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
	if event.is_echo():
		return false
	for action: StringName in advance_actions:
		if event.is_action_pressed(action):
			return true
	return false


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
