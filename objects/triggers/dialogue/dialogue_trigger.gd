extends CharacterBody3D

@export var dialogue_config: DialogueConfig  ## Configuration for the dialogue encounter
@export var one_shot: bool = true  ## If true, trigger can only activate once
@export var trigger_delay: float = 0.0  ## Optional delay before dialogue starts
@export var interact_action: StringName = &"MenuConfirm"
@export var fallback_interact_action: StringName = &"CombatAttack"

@onready var interaction_area: Area3D = $InteractionArea
@onready var overworld_mesh: MeshInstance3D = $OverworldMesh

var has_triggered: bool = false
var player_in_range: bool = false
var waiting_for_interact_release: bool = false


func _ready() -> void:
	if not interaction_area:
		push_error("[DialogueTrigger] InteractionArea not found!")
		return
	
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	Events.dialogue_ended.connect(_on_dialogue_ended)
	_apply_config_visuals()


func _process(_delta: float) -> void:
	if not player_in_range:
		return
	if one_shot and has_triggered:
		return
	if Events.is_dialogue_active:
		return
	if waiting_for_interact_release:
		if _is_interact_held():
			return
		waiting_for_interact_release = false
	
	var wants_interact := Input.is_action_just_pressed(interact_action) \
		or Input.is_action_just_pressed(fallback_interact_action)
	if not wants_interact:
		return
	
	_start_dialogue()


func _on_body_entered(body: Node3D) -> void:
	if one_shot and has_triggered:
		return
	if not _is_navigator(body):
		return
	
	player_in_range = true
	var prompt_text := "Press [A] to talk"
	if dialogue_config and not dialogue_config.prompt_content.is_empty():
		prompt_text = dialogue_config.prompt_content
	Events.request_dialogue_prompt(self, prompt_text)


func _on_body_exited(body: Node3D) -> void:
	if not _is_navigator(body):
		return
	player_in_range = false
	Events.clear_dialogue_prompt(self)


func _is_navigator(body: Node3D) -> bool:
	if body is CharacterBody3D:
		if body.has_node("SpringArm3D") and body.has_node("SpringArm3D/Camera3D"):
			return true
		if body.get_script() and "navigator" in body.get_script().resource_path.to_lower():
			return true
	return false


func _start_dialogue() -> void:
	if not dialogue_config:
		push_warning("[DialogueTrigger] No dialogue_config set.")
		return
	
	if trigger_delay > 0.0:
		await get_tree().create_timer(trigger_delay).timeout
	
	if not Events.begin_dialogue(self, dialogue_config):
		return
	waiting_for_interact_release = true
	
	if one_shot:
		has_triggered = true
		player_in_range = false


func _on_dialogue_ended() -> void:
	if one_shot and has_triggered:
		return
	if not player_in_range:
		return
	
	var prompt_text := "Press [A] to talk"
	if dialogue_config and not dialogue_config.prompt_content.is_empty():
		prompt_text = dialogue_config.prompt_content
	Events.request_dialogue_prompt(self, prompt_text)


func _is_interact_held() -> bool:
	return Input.is_action_pressed(interact_action) or Input.is_action_pressed(fallback_interact_action)


func _apply_config_visuals() -> void:
	if not overworld_mesh:
		return
	if not dialogue_config:
		overworld_mesh.mesh = null
		return
	overworld_mesh.mesh = dialogue_config.overworld_mesh


func reset_trigger() -> void:
	has_triggered = false


func is_triggered() -> bool:
	return has_triggered
