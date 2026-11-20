@tool
extends Node
class_name VSBlendCycler

## Drop-on ready to use componente/node for runtime variation blending. Add it under a MeshInstance3D
## that has a [VSRuntime] (or under the VSRuntime itself) and press play: it
## finds the mesh's variations on its own and keeps blending between them.[br]
## [br]
## It's also a reference for driving the runtime from your own scripts:
## everything it does goes through the public [VSRuntime] API
## ([method VSRuntime.set_active_snapshot], [method VSRuntime.tween_to_snapshot],
## [method VSRuntime.tween_to_snapshot_cpu], [signal VSRuntime.snapshot_blend_finished]).[br]
## [br]
## Blending is EXPERIMENTAL.

## What the cycle does: walk every variation in order, looping (CYCLE_ALL), or
## bounce between two of them (PING_PONG, endpoints in the Ping Pong group).
enum Mode {
	CYCLE_ALL,
	PING_PONG,
}

enum BlendEngine {
	GPU,
	CPU,
}

## The runtime to drive. When empty it takes the [VSRuntime] beside this node
## (a sibling under the mesh, this node's parent, or a child of this node)
@export var runtime: VSRuntime = null:
	set(value):
		runtime = value
		update_configuration_warnings()

## Cycle all variations or bounce between two
@export var mode: Mode = Mode.CYCLE_ALL

## Duration in seconds for one blend
@export_range(0.01, 30.0, 0.01, "or_greater") var blend_duration := 1.5

## Duration in seconds to wait on a variation before blending onto another
@export_range(0.0, 30.0, 0.01, "or_greater") var hold_time := 0.75

## Include the unpainted baseline ("None") as a step of the cycle
@export var include_baseline := false

## Start blending automatically on play
@export var play_on_start := true

## Blending engine:
## - GPU: much cheaper per frame but renders the mesh with Vertex Studio's blend shader
## - CPU: preserves the mesh's own material
@export var blend_engine: BlendEngine = BlendEngine.GPU

## Print every transition
@export var verbose := false

@export_group("Ping Pong")
## Ping Pong only: the two endpoints. Left empty they are the mesh's first two
## variations (empty means the baseline/base mesh)
@export_file("*.tres", "*.res") var ping_pong_a := ""
@export_file("*.tres", "*.res") var ping_pong_b := ""

var _runtime: VSRuntime = null
## Variation paths in cycle order (empty string "" == baseline/basemesh)
var _steps: PackedStringArray = PackedStringArray()
var _step := -1
var _hold_left := 0.0
var _running := false


#region Lifecycle


func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint():
		return
	_runtime = _find_runtime()
	if _runtime == null:
		push_warning("VSBlendCycler: no VSRuntime on '%s'. Tick 'Add runtime node' in the Vertex Studio panel." % _owner_name())
		return
	_runtime.snapshot_blend_finished.connect(_on_blend_finished)
	if play_on_start:
		start_blending()


func _exit_tree() -> void:
	_running = false
	if _runtime != null and is_instance_valid(_runtime) \
			and _runtime.snapshot_blend_finished.is_connected(_on_blend_finished):
		_runtime.snapshot_blend_finished.disconnect(_on_blend_finished)


func _get_configuration_warnings() -> PackedStringArray:
	if _find_runtime() == null:
		return PackedStringArray([
			"No VSRuntime found. Add this node under a MeshInstance3D that has one"
			+ " (Vertex Studio panel > Runtime > Add runtime node), or set Runtime by hand."])
	return PackedStringArray()


#endregion Lifecycle


#region Public controls


## Finds the variations and begins the cycle. Safe to call again after
## [method stop_blending], or after the variation list changed.
func start_blending() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func stop_blending() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


## Blends to one variation from wherever the mesh is now, and leaves the cycle
## stopped ("" is baseline/base mesh)
func blend_to(_path: String) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


#endregion Public controls


#region Cycle driving


func _build_steps() -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _process(_delta: float) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


# The only difference between the two blend paths, from a caller  side
func _tween(_path: String) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


func _on_blend_finished(_reached_path: String) -> void:
	if _running:
		_hold_left = hold_time


# Variations the runtime will SWITCH to: the mesh's own history, plus the base mesh ("").
# Anything else can still be blended to. Blending loads the file straight from disk, just not set as the active variation.
func _is_known(_path: String) -> bool:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return false


#endregion Cycle driving


#region Wiring


# Beside this node: a sibling under the mesh (where the panel puts VSRuntime),
# this node's parent (dropped under the runtime itself), or a child of it.
func _find_runtime() -> VSRuntime:
	if runtime != null and is_instance_valid(runtime):
		return runtime
	var p := get_parent()
	if p is VSRuntime:
		return p as VSRuntime
	if p != null:
		for c in p.get_children():
			if c is VSRuntime:
				return c as VSRuntime
	for c in get_children():
		if c is VSRuntime:
			return c as VSRuntime
	return null


# Mesh name this cycler belongs to
func _owner_name() -> String:
	var p := get_parent()
	if p is VSRuntime:
		p = p.get_parent()
	return p.name if p != null else name


#endregion Wiring
