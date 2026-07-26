extends Component
class_name DropComponent

## Spawns pickups out of the host — on death, and when a hit shakes some loose.
##
## WHY THIS EXISTS. The loot used to be spawned by the PLAYER's
## BumpCombatComponent, which meant the player carried one `drop_chance` and one
## drop scene for the whole game: every enemy and every prop necessarily dropped
## the same thing at the same odds. "Mushrooms burst into three, Manicoppos
## sometimes cough up one" was not expressible. Loot belongs to the thing being
## broken, so it lives here, and the bump asks the target what it drops.
##
## Two distinct events, deliberately kept apart:
##   - DEATH loot (`death_min`/`death_max`) — the reward for destroying something.
##     Auto-connected to the host's `died` signal.
##   - SHAKE-LOOSE (`bump_chance`) — a chance for a single pickup to pop out of
##     something that SURVIVED the hit. Driven by BumpCombatComponent calling
##     shake_loose() duck-typed.
## A mushroom wants the first, the Manicoppo wants the second, and something can
## want both.
##
## Event-driven like BlastComponent: it ignores the activation lifecycle and just
## connects to a host signal in _setup().

## Pickup to spawn. Empty = this component does nothing.
@export var drop_scene: PackedScene

@export_group("On Death")
## Inclusive range rolled when the host dies. Leave at 0 for no death loot.
@export_range(0, 20, 1) var death_min: int = 0
@export_range(0, 20, 1) var death_max: int = 0

@export_group("On Bump")
## Odds a landed bump that the host SURVIVES shakes one pickup loose.
@export_range(0.0, 1.0, 0.05) var bump_chance: float = 0.0

@export_group("Burst")
## Upward speed of the pop.
@export_range(0.0, 20.0, 0.5) var launch_up: float = 5.0
## Horizontal speed of the pop, fired in a random direction.
@export_range(0.0, 20.0, 0.5) var launch_spread: float = 3.0
## Height above the host's origin the pickups spawn at.
@export_range(0.0, 4.0, 0.1) var spawn_height: float = 1.0


func _setup() -> void:
	if host and host.has_signal("died"):
		host.died.connect(_on_died)


func _on_died() -> void:
	if death_max <= 0:
		return
	spawn_burst(randi_range(mini(death_min, death_max), death_max))


## Roll for a single pickup off a hit the host survived. Called duck-typed by
## BumpCombatComponent, so nothing needs a reference to this type.
func shake_loose() -> void:
	if bump_chance > 0.0 and randf() < bump_chance:
		spawn_burst(1)


## Burst `count` pickups out of the host in random directions.
##
## Parented to the current scene rather than the host, so they survive the host's
## death — which is the entire point for death loot, since the host is freed a
## moment later.
func spawn_burst(count: int) -> void:
	if drop_scene == null or count <= 0:
		return
	var world: Node = get_tree().current_scene
	if world == null or not (host is Node3D):
		return
	var origin: Vector3 = (host as Node3D).global_position + Vector3.UP * spawn_height

	for _i in count:
		var drop := drop_scene.instantiate() as Node3D
		if drop == null:
			return
		world.add_child(drop)
		drop.global_position = origin

		var angle: float = randf() * TAU
		var impulse := Vector3(
			cos(angle) * launch_spread, launch_up, sin(angle) * launch_spread
		)
		if drop.has_method("launch"):
			drop.call("launch", impulse)
