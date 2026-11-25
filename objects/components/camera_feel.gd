extends Node
class_name CameraFeel

## Camera game-feel for the player: a shake when hurt, a push-in punch on a
## landed bump. Child of the Player; it finds the camera by path.
##
## SHAKE is trauma-based. Events add "trauma" (0..1, stacking, capped at 1),
## which drains at `trauma_decay` per second. The shake each frame is
## trauma ^ `trauma_power`, so a small hit barely trembles and big hits in a row
## shake hard, and every shake dies away smoothly rather than stopping dead.
## The jitter comes from smooth noise rather than randf(), so it wobbles instead
## of teleporting between random points.
##
## The shake moves the camera's LENS (Camera3D h_offset / v_offset), not the
## camera node: the SpringArm3D rewrites the camera's transform every physics
## frame, so position or rotation set from here would be overwritten. A lens
## offset slides the picture without moving the camera, which reads as a shake.
##
## PUNCH shortens the spring arm briefly: in fast over `punch_in_time`, eased
## back over `punch_out_time`. The Player owns the spring length and subtracts
## get_dolly() from it each frame.
##
## Triggers: the host's `hit` signal (player took damage) and Events.attack_hit
## with the host as attacker (a landed bump). Call add_trauma() / punch() for
## anything else.

## The camera whose lens is shaken.
@export var camera_path: NodePath = ^"../CameraPivot/SpringArm3D/Camera3D"

@export_group("Hurt Shake")
@export var shake_enabled: bool = true
## Trauma added when the player takes damage (0..1). 0.45 is slight; 1 is the max.
@export_range(0.0, 1.0, 0.01) var hurt_trauma: float = 0.45
## Lens offset at full trauma, in metres (x = sideways, y = up/down).
@export var max_offset: Vector2 = Vector2(0.6, 0.4)
## Trauma lost per second. 0.45 trauma at 1.5/s shakes for 0.3 s.
@export_range(0.1, 10.0, 0.05) var trauma_decay: float = 1.5
## How fast it jitters. Higher = buzzier, lower = a slow wobble.
@export_range(1.0, 60.0, 0.5) var shake_frequency: float = 22.0
## Shake = trauma ^ this. 2 keeps small hits subtle; 1 makes them linear.
@export_range(1.0, 3.0, 0.1) var trauma_power: float = 2.0

@export_group("Hit Punch")
@export var punch_enabled: bool = true
## How far the camera pushes toward the player on a landed bump (m).
@export_range(0.0, 3.0, 0.05) var punch_distance: float = 0.5
## Seconds to push in. Short: the push is the impact.
@export_range(0.01, 0.5, 0.01) var punch_in_time: float = 0.05
## Seconds to ease back out.
@export_range(0.05, 1.5, 0.01) var punch_out_time: float = 0.3
## How far it swings past rest on the way back, as a fraction of
## `punch_distance`. 0 = settles straight back; 0.3 = a little bounce.
@export_range(0.0, 1.0, 0.05) var punch_overshoot: float = 0.0

var _camera: Camera3D = null
var _noise := FastNoiseLite.new()
var _trauma: float = 0.0
var _time: float = 0.0
var _punch_t: float = -1.0  # < 0 = idle
var _punch_scale: float = 1.0
var _dolly: float = 0.0


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null:
		push_warning("[CameraFeel] No camera at '%s'." % camera_path)
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()
	var host: Node = get_parent()
	if host and host.has_signal("hit"):
		host.connect("hit", _on_host_hit)
	Events.attack_hit.connect(_on_attack_hit)


## Add shake. Stacks with any shake already running, capped at 1.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Start a push-in punch (restarts one in progress). `scale` multiplies
## `punch_distance`, for a bigger hit.
func punch(scale: float = 1.0) -> void:
	_punch_t = 0.0
	_punch_scale = scale


## How far (m) the camera should currently be pushed in. Read by the Player.
func get_dolly() -> float:
	return _dolly


func _process(delta: float) -> void:
	_time += delta
	_update_shake(delta)
	_update_punch(delta)


func _update_shake(delta: float) -> void:
	if _camera == null:
		return
	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	var amount: float = pow(_trauma, trauma_power)
	var t: float = _time * shake_frequency
	# Two noise rows far apart = two unrelated wobbles for x and y. Simplex noise
	# peaks around ±0.7, hence the 1.4 to reach max_offset.
	_camera.h_offset = max_offset.x * amount * _noise.get_noise_2d(t, 0.0) * 1.4
	_camera.v_offset = max_offset.y * amount * _noise.get_noise_2d(t, 100.0) * 1.4


func _update_punch(delta: float) -> void:
	if _punch_t < 0.0:
		_dolly = 0.0
		return
	_punch_t += delta
	var distance: float = punch_distance * _punch_scale
	if _punch_t < punch_in_time:
		# Ease out on the way in: fast start, so it lands on the hit frame.
		_dolly = distance * sin(_punch_t / punch_in_time * PI * 0.5)
		return
	var u: float = (_punch_t - punch_in_time) / punch_out_time
	if u >= 1.0:
		_punch_t = -1.0
		_dolly = 0.0
		return
	_dolly = distance * (1.0 - smoothstep(0.0, 1.0, u)) \
			- distance * punch_overshoot * sin(u * PI)


func _on_host_hit(_amount: int) -> void:
	if shake_enabled:
		add_trauma(hurt_trauma)


func _on_attack_hit(attacker: Node, _target: Node, _damage: int) -> void:
	if punch_enabled and attacker == get_parent():
		punch()
