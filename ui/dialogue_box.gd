extends Control

@export var characters_per_second: float = 45.0
@export var advance_action: StringName = &"MenuConfirm"
@export var fallback_advance_action: StringName = &"CombatAttack"
@export var fade_in_duration: float = 0.15
@export var fade_out_duration: float = 0.15
@export var fade_slide_offset: float = 18.0

@onready var panel_container: PanelContainer = $PanelContainer
@onready var speaker_label: Label = $PanelContainer/MarginContainer/VBoxContainer/Header/SpeakerLabel
@onready var body_label: RichTextLabel = $PanelContainer/MarginContainer/VBoxContainer/BodyRow/BodyText
@onready var portrait_rect: TextureRect = $PanelContainer/MarginContainer/VBoxContainer/BodyRow/Portrait
@onready var continue_hint: Label = $PanelContainer/MarginContainer/VBoxContainer/ContinueHint

var dialogue_nodes: Array[Dictionary] = []
var current_index: int = -1
var current_text: String = ""
var reveal_progress: float = 0.0
var is_typing: bool = false
var is_transitioning: bool = false
var panel_rest_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	hide()
	set_process(true)
	panel_rest_position = panel_container.position
	Events.dialogue_started.connect(_on_dialogue_started)


func _process(delta: float) -> void:
	if not visible or not is_typing:
		return
	
	reveal_progress += characters_per_second * delta
	var visible_chars: int = min(current_text.length(), int(floor(reveal_progress)))
	body_label.visible_characters = visible_chars
	
	if visible_chars >= current_text.length():
		_finish_typing()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if is_transitioning:
		return
	
	if not (event.is_action_pressed(advance_action) or event.is_action_pressed(fallback_advance_action)):
		return
	
	if is_typing:
		_skip_typewriter()
	else:
		_advance_or_finish()
	
	get_viewport().set_input_as_handled()


func _on_dialogue_started(dialogue_config: DialogueConfig) -> void:
	dialogue_nodes = dialogue_config.load_dialogue_nodes()
	current_index = -1
	
	if dialogue_nodes.is_empty():
		Events.end_dialogue()
		return
	
	show()
	await _play_intro_transition()
	_advance_or_finish()


func _advance_or_finish() -> void:
	current_index += 1
	if current_index >= dialogue_nodes.size():
		_close_dialogue()
		return
	
	var node := dialogue_nodes[current_index]
	var trigger_id := str(node.get("trigger_id", ""))
	if not trigger_id.is_empty():
		Events.emit_dialogue_trigger(trigger_id)
	
	speaker_label.text = str(node.get("speaker", ""))
	current_text = str(node.get("text_content", ""))
	body_label.text = current_text
	body_label.visible_characters = 0
	continue_hint.visible = false
	
	var portrait_path := str(node.get("portrait", ""))
	if portrait_path.is_empty():
		portrait_rect.texture = null
	else:
		var loaded_texture := load(portrait_path)
		if loaded_texture is Texture2D:
			portrait_rect.texture = loaded_texture
		else:
			portrait_rect.texture = null
	
	reveal_progress = 0.0
	is_typing = true


func _skip_typewriter() -> void:
	body_label.visible_characters = current_text.length()
	_finish_typing()


func _finish_typing() -> void:
	is_typing = false
	continue_hint.visible = true


func _close_dialogue() -> void:
	if is_transitioning:
		return
	
	is_typing = false
	continue_hint.visible = false
	await _play_outro_transition()
	hide()
	panel_container.modulate.a = 1.0
	panel_container.position = panel_rest_position
	dialogue_nodes.clear()
	current_index = -1
	current_text = ""
	portrait_rect.texture = null
	Events.end_dialogue()


func _play_intro_transition() -> void:
	is_transitioning = true
	panel_container.modulate.a = 0.0
	panel_container.position = panel_rest_position + Vector2(0, fade_slide_offset)
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel_container, "modulate:a", 1.0, fade_in_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel_container, "position", panel_rest_position, fade_in_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished
	is_transitioning = false


func _play_outro_transition() -> void:
	is_transitioning = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel_container, "modulate:a", 0.0, fade_out_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(panel_container, "position", panel_rest_position + Vector2(0, fade_slide_offset), fade_out_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	is_transitioning = false
