extends Destructible
class_name Enemy

## Enemy specialization of Destructible. Adds:
##   - Activation: INACTIVE → ACTIVE by distance, by being hit, or on demand
##     (see `activation_mode`)
##   - Component setup that passes the resolved player reference to the
##     components that need one
##   - Enemy-flavored log labels (uses enemy_data.display_name) and a death
##     message that includes the score
##
## All HP/take_damage/death-VFX behavior lives in Destructible — this
## class only adds what is enemy-specific.
##
## BaseEnemy.tscn ships the AI stack — PerceptionComponent, EnemyBrain, an empty
## `Actions` container, a NavigationAgent3D and an AttackBox — so a new enemy
## gets a working brain for free and only has to fill in its own actions. An
## enemy with no actions is unaffected: the brain stays in WANDER and leaves the
## body to its MovementPattern.
##
## WeaponComponent is deliberately NOT on the base. Ranged fire is one enemy's
## choice, not a property of enemies, so an enemy that shoots adds the component
## itself — the lookup below stays so that still wires up when it does.

## How this enemy wakes up.
##   DISTANCE — the player gets within `activation_distance`. The default.
##   BUMP     — it stays dormant until something HITS it. The first hit wakes it
##              and deals no damage, so a creature disguised as scenery cannot be
##              killed before it has revealed itself.
##   MANUAL   — nothing wakes it automatically; a cutscene or another script calls
##              activate().
enum Activation { DISTANCE, BUMP, MANUAL }

@export var enemy_data: EnemyData
@export var activation_mode: Activation = Activation.DISTANCE
## Player must get this close (world units) before the enemy activates. DISTANCE
## mode only.
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

	if debug_log:
		print("[%s] Spawned (HP %d/%d), waiting to activate within %.0fu." % [_label(), hp, max_hp, activation_distance])


func _physics_process(_delta: float) -> void:
	# The only work here is the INACTIVE → ACTIVE proximity check; once ACTIVE the
	# components run themselves. Other modes wake on an event, not on a poll.
	if state != State.INACTIVE or activation_mode != Activation.DISTANCE:
		return
	if not _player:
		_player = _resolve_player()
		return
	if global_position.distance_to(_player.global_position) <= activation_distance:
		activate()


## Wake this enemy. Public so a cutscene, a trigger or another creature can do it
## (MANUAL mode), and idempotent.
func activate() -> void:
	if state != State.INACTIVE:
		return
	state = State.ACTIVE
	_dispatch_active(true)
	_on_activated()
	if debug_log:
		print("[%s] Activated." % _label())


## Override for what waking up LOOKS like — a mushroom springing up to reveal its
## stalk, a blob unfurling. Called after the components are live.
func _on_activated() -> void:
	pass


# --- Overrides -------------------------------------------------------------

## In BUMP mode the first hit is the wake-up call and deals nothing: a creature
## pretending to be scenery must not be killable before it has dropped the act.
## Every later hit goes through normally.
func take_damage(amount: int, is_blast: bool = false) -> void:
	if state == State.INACTIVE and activation_mode == Activation.BUMP:
		activate()
		return
	super.take_damage(amount, is_blast)

## Enemies (unlike bare Destructibles) feed the enemy hit-feedback channel.
func _report_damage(amount: int) -> void:
	Events.enemy_damaged.emit(amount)
	Events.enemy_hp_changed.emit(hp, max_hp)


func _label() -> String:
	var dn: String = String(enemy_data.display_name) if enemy_data else String(name)
	return "Enemy:" + dn


func _death_message() -> String:
	var score: int = enemy_data.score if enemy_data else 0
	return "Destroyed! (+%d score)" % score
