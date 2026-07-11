extends Destructible
class_name Enemy

## Enemy specialization of Destructible. Adds:
##   - Distance-based activation (INACTIVE → ACTIVE when the player gets close)
##   - Component setup that passes the resolved player reference to
##     MovementComponent and WeaponComponent
##   - Enemy-flavored log labels (uses enemy_data.display_name) and a death
##     message that includes the score
##
## All HP/take_damage/death-VFX behavior lives in Destructible — this
## class only adds what is enemy-specific.

@export var enemy_data: EnemyData
## Player must get this close (world units) before the enemy activates.
@export var activation_distance: float = 45.0

# Component references kept here so we can call setup(player) on them. The base
# class handles broadcast set_active() via duck-typed dispatch, so it doesn't
# need these refs.
@onready var _movement: MovementComponent = get_node_or_null("MovementComponent")
@onready var _weapon: WeaponComponent = get_node_or_null("WeaponComponent")


func _ready() -> void:
	add_to_group("enemy")

	# Read HP from the data resource (if present) so the base's hp = max_hp
	# initialization picks up the right value when super._ready() runs.
	if enemy_data:
		max_hp = enemy_data.max_hp

	# Enemies wait to activate; obstacles/projectiles use the default ACTIVE.
	state = State.INACTIVE

	super._ready()

	# Components are reachable now; wire them with the resolved player ref.
	if _movement:
		_movement.setup(_player)
	if _weapon:
		_weapon.setup(_player)

	print("[%s] Spawned (HP %d/%d), waiting to activate within %.0fu." % [_label(), hp, max_hp, activation_distance])


func _physics_process(_delta: float) -> void:
	# The only work here is the INACTIVE → ACTIVE proximity check; once ACTIVE the
	# movement/weapon components run themselves.
	if state != State.INACTIVE:
		return
	if not _player:
		_player = _resolve_player()
		return
	if global_position.distance_to(_player.global_position) <= activation_distance:
		_activate()


func _activate() -> void:
	state = State.ACTIVE
	_dispatch_active(true)
	print("[%s] Activated." % _label())


# --- Log overrides ---------------------------------------------------------

func _label() -> String:
	var dn: String = String(enemy_data.display_name) if enemy_data else String(name)
	return "Enemy:" + dn


func _death_message() -> String:
	var score: int = enemy_data.score if enemy_data else 0
	return "Destroyed! (+%d score)" % score
