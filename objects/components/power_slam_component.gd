extends Component
class_name PowerSlamComponent

## Power move: spend collected PowerDrops to arc into the air and slam down in
## front of the player, damaging everything in the landing zone.
##
## The trajectory is NOT hardcoded — it samples the Curve3D of a Path3D child of
## the player (the NurbsPath3D authored with the editor gizmo). That path is the
## in-engine equivalent of a root-motion bake: drag its control points in the
## viewport and the move re-tunes on the next play, with no Blender round-trip.
##
## The curve is authored in player-local space (-Z forward) and re-anchored on
## every cast to the player's current position and the CAMERA's horizontal
## heading — you slam where you're looking, not where the model happens to be
## turned. The model snaps to that heading as the cast starts so the launch reads.
##
## While casting, the player hands its transform over via begin_scripted_move()
## so the controller's gravity and input steering don't fight the curve.

## Energy spent per cast. The move won't fire if the player has less.
@export var energy_cost: float = 35.0
## Testing toggle: cast for free, ignoring (and never spending) energy.
@export var free_cast: bool = false
## Input action that triggers the slam.
@export var action: StringName = &"power_slam"
## Path3D whose curve defines the trajectory, relative to this component.
@export var path_node: NodePath = ^"../NurbsPath3D"
## Camera whose horizontal heading aims the slam, relative to this component.
## Falls back to the Model's facing if it can't be resolved.
@export var camera_node: NodePath = ^"../CameraPivot/SpringArm3D/Camera3D"
## Model snapped to the aim heading on cast, relative to this component.
@export var model_node: NodePath = ^"../Model"
## Seconds the whole arc takes.
@export_range(0.1, 3.0, 0.05) var duration: float = 0.6
## Optional time warp along the arc (x = time 0-1, y = distance travelled 0-1).
## Empty = constant speed. Add an ease-in curve to hang at the apex then drop hard.
@export var time_curve: Curve
## Damage dealt to each destructible in the landing zone.
@export_range(0, 300, 1) var impact_damage: int = 40
## Radius of the landing zone (world units).
@export_range(0.5, 15.0, 0.5) var impact_radius: float = 3.5

@export_group("Impact Knockback")
## Shove given to the PLAYER when the landing catches at least one enemy, so a
## connected slam bounces you off them like a ground bump does.
@export_range(0.0, 40.0, 0.5) var player_knockback_force: float = 10.0
## Upward pop added to the player's bounce.
@export_range(0.0, 20.0, 0.5) var player_knockback_up: float = 4.0
## Seconds the player's bounce suppresses input.
@export_range(0.0, 1.0, 0.01) var player_knockback_duration: float = 0.25
## Shove given to each enemy caught in the landing, pushed away from the impact.
@export_range(0.0, 40.0, 0.5) var enemy_knockback_force: float = 9.0
## Seconds an enemy is shoved before its movement pattern takes back over.
@export_range(0.0, 2.0, 0.05) var enemy_knockback_duration: float = 0.35

@export_group("Misc")
## BumpCombatComponent switched into airborne mode for the flight, relative to
## this component. Leave empty to skip the handoff.
@export var bump_component_node: NodePath = ^"../BumpCombat"
## Print casts and impacts to the console.
@export var debug_log: bool = true

var _body: CharacterBody3D = null
var _path: Path3D = null
var _model: Node3D = null
var _camera: Node3D = null
var _bump: Node = null

var _casting: bool = false
var _elapsed: float = 0.0
## Distance travelled along the curve (0-1) as of the last frame.
var _travel: float = 0.0
# Where the cast started, and the facing it started with — the curve is replayed
# relative to these so it doesn't drift if the player was moving.
var _start_pos: Vector3 = Vector3.ZERO
var _start_basis: Basis = Basis.IDENTITY


func _setup() -> void:
	_body = host as CharacterBody3D
	_path = get_node_or_null(path_node) as Path3D
	_model = get_node_or_null(model_node) as Node3D
	_camera = get_node_or_null(camera_node) as Node3D
	_bump = get_node_or_null(bump_component_node)
	if _path == null or _path.curve == null:
		push_warning("[PowerSlam] No Path3D curve at '%s' — the slam is disabled." % path_node)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _casting:
		_advance(delta)
	elif Input.is_action_just_pressed(action):
		_try_cast()


## Spend the energy and take over the player's transform. Bails without spending
## if the player can't afford it (spend_energy is all-or-nothing).
func _try_cast() -> void:
	if _body == null or _path == null or _path.curve == null:
		return
	if not free_cast:
		if not _body.has_method("spend_energy") or not bool(_body.call("spend_energy", energy_cost)):
			return

	_casting = true
	_elapsed = 0.0
	_travel = 0.0
	_start_pos = _body.global_position
	var yaw: float = _aim_yaw()
	_start_basis = Basis(Vector3.UP, yaw)
	# Snap the player around to face the way they're about to launch.
	if _model:
		_model.rotation.y = yaw
	if _body.has_method("begin_scripted_move"):
		_body.call("begin_scripted_move")
	# Bumps during the flight are chip damage with no bounce — see BumpCombat.
	if _bump:
		_bump.set("airborne_mode", true)
	if debug_log:
		print("[PowerSlam] Cast (%s)" % ("free" if free_cast else "-%.0f energy" % energy_cost))


## Heading the slam launches along: the camera's forward, flattened to the ground
## so looking up or down only changes the view, never the aim. Read from the
## camera's global basis rather than the pivot's rotation.y so it stays correct
## regardless of how the rig is nested (and while lock-on is steering the pivot).
func _aim_yaw() -> float:
	if _camera:
		var forward: Vector3 = -_camera.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			# Same convention as player.gd's _face_point: -Z is forward.
			return atan2(-forward.x, -forward.z)
	return _model.rotation.y if _model else 0.0


func _advance(delta: float) -> void:
	var prev_travel: float = _travel
	_elapsed += delta
	var t: float = clampf(_elapsed / duration, 0.0, 1.0)
	_travel = clampf(time_curve.sample(t), 0.0, 1.0) if time_curve else t

	# Move by this frame's curve DELTA through move_and_slide, rather than
	# teleporting onto the absolute curve point — so walls, floors and ledges
	# actually stop us. Using the delta (not the absolute point) matters: if we
	# get blocked, the lost ground is simply lost. Chasing the absolute point
	# would build an ever-growing catch-up vector that eventually punches the
	# player straight through whatever is in the way.
	var step: Vector3 = _point_at(_travel) - _point_at(prev_travel)
	_body.velocity = step / delta if delta > 0.0 else Vector3.ZERO
	_body.move_and_slide()

	if t >= 1.0:
		_finish()


## World position at `travel` (0-1) along the curve, anchored to the cast's start.
## sample_baked works in arc length, so constant `travel` = constant speed.
func _point_at(travel: float) -> Vector3:
	var curve: Curve3D = _path.curve
	var local: Vector3 = curve.sample_baked(travel * curve.get_baked_length())
	# Respect the Path3D's own offset/rotation under the player.
	local = _path.transform * local
	return _start_pos + _start_basis * local


func _finish() -> void:
	_casting = false
	if _bump:
		_bump.set("airborne_mode", false)
	# Order matters: end_scripted_move() clears the knockback timer, so it has to
	# run BEFORE the impact hands out a fresh bounce.
	if _body.has_method("end_scripted_move"):
		_body.call("end_scripted_move")
	_impact(_body.global_position)


## Damage every destructible in the landing zone. Mirrors Blast._apply_damage,
## minus the is_blast flag — a slam shouldn't pop blast-only ("green") targets.
## Each victim is also shoved outward, and a connected slam bounces the player.
func _impact(origin: Vector3) -> void:
	var hits: int = 0
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for node in get_tree().get_nodes_in_group("destructible"):
		var target := node as Node3D
		if target == null or not is_instance_valid(target):
			continue
		if target.has_method("is_defeated") and bool(target.call("is_defeated")):
			continue
		var dist: float = origin.distance_to(target.global_position)
		if dist > impact_radius:
			continue
		if not target.has_method("take_damage"):
			continue
		target.call("take_damage", impact_damage)
		_shove_enemy(target, origin)
		hits += 1
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = target

	if hits > 0:
		_bounce_player_off(nearest, origin)
	if debug_log:
		print("[PowerSlam] Impact at %s — %d hit(s)" % [str(origin), hits])


## Shove a caught enemy outward from the impact. Routed through its
## MovementComponent rather than written onto the body: that component reassigns
## velocity from its MovementPattern every frame, so a velocity we set here would
## be overwritten before it ever moved. The component also snaps the body back
## onto the navmesh when the shove ends, so this can't strand a wanderer.
func _shove_enemy(target: Node3D, origin: Vector3) -> void:
	if enemy_knockback_force <= 0.0:
		return
	var mc := target.get_node_or_null(^"MovementComponent")
	if mc == null or not mc.has_method("apply_knockback"):
		return
	var away := target.global_position - origin
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	mc.call("apply_knockback", away.normalized() * enemy_knockback_force, enemy_knockback_duration)


## Bounce the player back off what they landed on, mirroring a ground bump.
func _bounce_player_off(nearest: Node3D, origin: Vector3) -> void:
	if not _body.has_method("apply_knockback"):
		return
	var back := Vector3.ZERO
	if nearest != null:
		back = origin - nearest.global_position
		back.y = 0.0
	if back.length_squared() < 0.0001:
		# Landed dead-centre on them: fall back to reversing the slam's heading.
		back = _start_basis * Vector3.BACK
		back.y = 0.0
	var impulse := back.normalized() * player_knockback_force + Vector3.UP * player_knockback_up
	_body.call("apply_knockback", impulse, player_knockback_duration)
