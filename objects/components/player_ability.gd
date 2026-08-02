extends Component
class_name PlayerAbility

## Base for a player ability: one verb the player performs by pressing a button.
##
## Deliberately MUCH smaller than EnemyAction, and the difference is the point.
## Most of EnemyAction is selection — weights, range bands, regions, line of
## sight, and a scheduler that picks one behaviour and interrupts it. All of that
## answers "what should this creature do right now?", and the player never asks:
## they press a button. Porting that machinery here would be importing the answer
## to a problem this side doesn't have.
##
## What the two DO share is the awkward part — a thing that costs something, may
## not be available, takes time, and owns the body while it runs. That is all this
## class holds:
##
##   - GATING       `unlocked`, so an ability can be granted later rather than
##                  existing from the first frame.
##   - INPUT        one action, polled here instead of in every subclass.
##   - COST         energy, all-or-nothing, plus a `free_cast` testing toggle.
##   - COOLDOWN     ticked on the physics clock, so it respects pause/time_scale.
##   - THE CLAIM    exclusive ownership of the player's transform.
##
## THE CLAIM IS THE REASON THIS CLASS EXISTS. begin_scripted_move() suspends the
## player's movement, gravity and input; if two abilities take it at once they
## both drive one transform, and whichever finishes first hands control back while
## the other is still mid-move. With a single ability that could never happen, so
## it never showed. claim_body() refuses the second claimant, which turns a silent
## fight into an ability that simply doesn't fire — and anything that claims is
## responsible for releasing, including when it is cut short.
##
## SUBCLASSING. Override `_activate()` with what the ability does. If it lasts
## longer than a frame, also override `is_busy()` and do per-frame work in
## `_tick()` — the base owns `_physics_process` so it can run cooldowns and input
## without every subclass reimplementing them.

## Fires after the cost is paid and the ability actually starts. For SFX/VFX/UI
## that shouldn't have to know what the ability is.
signal activated

@export_group("Gating")
## Whether the player has this ability at all. Uncheck for something granted later
## — beating a boss, looting it, reaching somewhere. A locked ability ignores its
## input entirely; it is inert, not merely unaffordable.
@export var unlocked: bool = true

@export_group("Input")
## Input action that triggers it. Empty = never self-triggers, for an ability
## driven by something else calling try_activate().
@export var input_action: StringName = &""

@export_group("Cost")
## Energy spent per use. All-or-nothing: too little and nothing is spent and the
## ability doesn't fire.
@export var energy_cost: float = 0.0
## Testing toggle: fire for free, ignoring and never spending energy.
@export var free_cast: bool = false

@export_group("Rules")
## Whether it can be STARTED while airborne. Off = grounded only, and the ability
## simply won't fire mid-jump — nothing is spent and no cooldown begins.
##
## Only the start is gated. An ability that leaves the ground as part of what it
## does (the Power Dive does exactly that) keeps running once underway.
##
## Uses `is_on_floor()` with no coyote grace, matching how jump already reads the
## ground in player.gd — so walking off a ledge takes a grounded ability away at
## the same instant it takes the jump away.
@export var usable_in_air: bool = true

@export_group("Timing")
## Seconds before it can be used again, measured from ACTIVATION (not from the
## end), so a long ability with a short cooldown is usable again soon after it
## finishes.
@export var cooldown: float = 0.0

@export var debug_log: bool = false

## The player. Resolved in _setup().
var body: CharacterBody3D = null

var _cooldown_left: float = 0.0


func _setup() -> void:
	body = host as CharacterBody3D
	# Live from spawn. `is_active` is normally driven by Destructible's
	# _dispatch_active() broadcast, but the player is not a Destructible and
	# nothing dispatches to its components — so an ability left at the Component
	# default of false would be permanently unusable. Setting it here rather than
	# dropping the check keeps set_active(false) meaningful: if a cutscene or death
	# ever does switch abilities off, on_deactivate() still fires and still
	# releases the body.
	is_active = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)

	_tick(delta)

	if input_action != &"" and Input.is_action_just_pressed(input_action):
		try_activate()


## Override for per-frame work while the ability runs. The base keeps
## `_physics_process` so cooldown and input don't have to be reimplemented.
func _tick(_delta: float) -> void:
	pass


## Override with what the ability actually does. Called only after every gate has
## passed and the cost is already spent.
func _activate() -> void:
	push_warning("[PlayerAbility] %s does not override _activate()." % String(name))


## Override if the ability lasts longer than the frame it starts on. While busy it
## won't retrigger.
func is_busy() -> bool:
	return false


## Override to add conditions beyond the standard ones (on the ground, has a
## target, holding something).
func _can_activate() -> bool:
	return true


## Override to true if the ability takes exclusive control of the player's
## transform, so availability is checked BEFORE the cost is charged.
##
## Without this the claim is discovered too late: try_activate() spends the energy
## and starts the cooldown, then _activate() finds the body already held — by
## another ability, or by an Ugrehk that swallowed the player — and bails. The
## player pays full price for nothing. A virtual rather than an @export because a
## subclass cannot change an inherited export's default, and this is a property of
## the ability's code, not something to tune per-scene.
func needs_body_claim() -> bool:
	return false


## Every standard gate, in the order that makes a refusal cheapest to diagnose.
## All of them run before anything is spent.
func can_activate() -> bool:
	if not (unlocked and is_active and _cooldown_left <= 0.0 and not is_busy()):
		return false
	if not usable_in_air and not is_grounded():
		return false
	if needs_body_claim() and body != null and body.has_method("is_scripted_move_claimed") \
			and bool(body.call("is_scripted_move_claimed")):
		return false
	return _can_activate()


## Feet on the ground right now.
##
## `is_on_floor()` is only meaningful after a move_and_slide, and it is here: the
## player's own _physics_process runs before its children's, so by the time an
## ability polls this, the player has already moved this frame.
func is_grounded() -> bool:
	return body != null and body.is_on_floor()


## Try to use the ability. Also the entry point for anything triggering it from
## outside — a combo, a cutscene, a test. Returns whether it fired.
func try_activate() -> bool:
	if not can_activate():
		return false
	if not try_spend():
		return false

	_cooldown_left = cooldown
	if debug_log:
		print("[%s] Activated (%s)" % [
			String(name), "free" if free_cast else "-%.0f energy" % energy_cost])
	_activate()
	activated.emit()
	return true


## Grant the ability at runtime. The hook a progression system calls.
func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	if debug_log:
		print("[%s] Unlocked" % String(name))


func is_on_cooldown() -> bool:
	return _cooldown_left > 0.0


## Pay the energy cost. All-or-nothing — false means nothing was spent.
func try_spend() -> bool:
	if free_cast or energy_cost <= 0.0:
		return true
	if body == null or not body.has_method("spend_energy"):
		return false
	return bool(body.call("spend_energy", energy_cost))


# --- The body claim ----------------------------------------------------------

## Take exclusive control of the player's transform, suspending their movement,
## gravity and input. FALSE MEANS SOMEONE ELSE HAS IT — another ability, or an
## enemy that swallowed the player — and the caller must abort rather than drive
## a transform it doesn't own.
func claim_body() -> bool:
	if body == null or not body.has_method("begin_scripted_move"):
		return false
	return bool(body.call("begin_scripted_move", self))


## Hand the transform back. Safe to call when we never claimed: the player ignores
## a release from anyone who isn't the current claimant.
func release_body() -> void:
	if body and body.has_method("end_scripted_move"):
		body.call("end_scripted_move", self)


## Called when the component is switched off (death, cutscene). Anything holding
## the body must let go here, or the player is frozen until a restart.
func on_deactivate() -> void:
	release_body()
