extends CharacterBody3D
@onready var animation_tree: AnimationTree = $AnimationTree

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	animation_tree.active = true
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _physics_process(delta: float) -> void:
	# root_motion_position is a local-space delta for this frame
	# divide by delta to get m/s velocity, rotate into world space
	var root_motion: Vector3 = animation_tree.get_root_motion_position()
	velocity = global_transform.basis * root_motion / delta
	move_and_slide()
