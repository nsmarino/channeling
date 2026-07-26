# Enemy prototyping

How to go from "I want a creature that does X" to something you can play, in this
codebase. Written after building the Gevi-Dava, Ugrehk and Essurou.

---

## 1. What to tell me up front

The best briefs so far read like **encounter descriptions, not spec sheets**. You
don't need to know the implementation — describing what the fight *feels like*
gives me more to work with than a list of stats, because the numbers are Inspector
knobs you'll retune by playing anyway.

**Most useful, roughly in order:**

1. **What the player is doing while fighting it.** "Crossing a courtyard while
   bombs rain over a wall" told me more than any parameter would have. It's also
   how the design gets *corrected*: I initially proposed range bands for the
   Gevi-Dava, and your "no, it's a specific region, possibly behind a wall" is what
   produced `TriggerRegion` — a foundation piece I'd have otherwise skipped.
2. **Is it stationary or mobile?** This decides `can_chase` and half the structure.
   Three of four creatures so far are rooted.
3. **Phases or modes**, and *what switches between them* — distance, a region, HP,
   being hit.
4. **How you kill it.** Bump anywhere? One weak point? Only while it's doing
   something? The Essurou's "only one eye" was a one-line brief that turned into
   its entire fight.
5. **Anything that grabs, moves or disables the player.** Flag these loudly —
   they're the highest-risk mechanics (see §7).
6. **A reference.** The Kirby screenshot for the Ugrehk's inhale was worth
   paragraphs.
7. **Rough scale.** "About player height", "blocks a doorway". I can't infer this
   from the blockout and I will guess wrong.

**Not needed up front:** exact damage, cooldowns, speeds, HP. I'll pick plausible
starts and expose them; you'll change all of them.

**Worth saying if true:** "stub this if it's complex" — but note I'll usually push
back if the primitives already exist, as with suck/spit.

**A question I'll ask back:** whether a behaviour should be a *new action* or an
*existing one with different numbers*. `StrikeAction` covers a startling range of
attacks; say so if you specifically want something bespoke.

---

## 2. How the action system works

### The shape of it

```
Enemy (BaseEnemy.tscn)
├── PerceptionComponent    vision cone, sticky loss
├── EnemyBrain             FSM + scheduler — owns NO behaviour
├── Actions                ← the creature's repertoire
│   ├── SomeAction         an EnemyAction node
│   └── AnotherAction
│       └── FollowUp       nested: only runs after its parent's main beat
├── AttackBox              MeleeHitbox — reach comes from ITS shape
├── NavigationAgent3D
└── DropComponent
```

`EnemyBrain` gathers the `Actions` children, filters by eligibility,
weighted-picks one, and `await`s it. **It knows nothing about swings or bombs.**
Adding a behaviour is one script + one node; giving a second creature the same
behaviour is dropping the same node under it.

### The brain's FSM

| State | Meaning |
|---|---|
| `WANDER` | not alerted — hands off; the `MovementPattern` drives |
| `CHASE` | alerted, out of range — nav-paths to the player (skipped if `can_chase = false`) |
| `COMBAT` | picks an action, awaits it, re-picks |

**An empty `Actions` container pins the brain in `WANDER`.** That's what lets the
AI live on `BaseEnemy` without changing creatures that don't opt in.

### Why actions are coroutines

Most interesting attacks are *sequences* — close in, swing, pause, swing again,
back off. As per-frame state that smears across sub-states and counters; as
`await` it reads top to bottom, and "lock this in at the moment of the decision"
becomes a plain local variable captured once.

### The one rule

> **No `await` is ever followed by anything other than `still_running(token)`.**

A running coroutine can't be killed from outside. The brain bumps a token to
cancel; the action notices at its next await and returns. Follow this and
cancellation is handled. Break it and you get an action resuming three states
later, mid-swing, on a corpse.

`still_running()` also checks `is_inside_tree()`, because a **level restart
detaches nodes before freeing them** — for one frame `is_instance_valid()` still
says yes while `global_position` and `get_tree()` are already unusable. Being
killed by an enemy's own attack is exactly when that window is open.

### Writing one

```gdscript
extends EnemyAction
class_name MyAction

@export var duration: float = 1.0

func run(token: int) -> bool:
    var elapsed: float = 0.0
    while elapsed < duration:
        if not still_running(token):
            return false
        drive(some_velocity)          # steer via the helpers, never the body
        elapsed += get_physics_process_delta_time()
        await get_tree().physics_frame
    return still_running(token)
```

Then drop it under `Actions` and set its knobs. The brain injects
`brain / body / move / agent / hitbox / anim` automatically — **no wiring.**

Base helpers: `drive()`, `face_toward()`, `set_facing()`, `hold_still()`,
`wait()`, `wait_still()`, `get_player()`, `flat_distance_to_player()`,
`yaw_toward()`, `is_navigable()`, `navmesh_normal()`, `random_heading()`,
`strong_turn()`, `open_hitbox()`, `close_hitbox()`, `combat_range()`.

Override `on_abort()` if your action *acquires* anything — an animation
`speed_scale`, an open hitbox, **the player's body**. It must be safe to call when
the action never ran.

### Selection knobs (on every action)

| Knob | Effect |
|---|---|
| `weight` | relative odds among eligible top-level actions |
| `chance` | probability when awaited as a nested follow-up |
| `enabled` | uncheck to A/B a behaviour while playing |
| `min_range` / `max_range` | distance band (`max_range = 0` means no limit) |
| `required_region` | only while the player is in that `TriggerRegion` |
| `los_requirement` | `ANY` / `REQUIRED` / `FORBIDDEN` |
| `cooldown` | seconds off the table after running |
| `committed` | suppresses **all** brain state transitions while running |
| `requires_attack_slot` | ask the `EnemyCoordinator` first, so a group doesn't all swing at once |
| `timeout` | hard ceiling; the brain aborts past it |

**`los_requirement = FORBIDDEN`** is the lob-over-a-wall case: it knows roughly
where you are (you're in its region) but can't see you, so it arcs something over.

### Nesting: the tree *is* the rule

A child action is awaited by its parent. `ZigzagTwirl` sits under `AttackCombo`,
so it is **structurally incapable** of being picked cold — that used to be a
comment, now it's the scene tree. Reorder or delete children to reshape a combo
without touching a script.

### The action library

| Action | What it does | Used by |
|---|---|---|
| `OrbitAction` | circle at combat range, reversing at the navmesh edge | Manicoppo |
| `AttackComboAction` | approach → 1–3 swings → follow-ups → reposition | Manicoppo |
| `ZigzagTwirlAction` | frozen pose, spin, roam, fling on contact | Manicoppo (nested) |
| `RetreatAction` | back off to combat range, straight or strafing | Manicoppo (nested) |
| `ErraticRunAction` | **base**: careen around the navmesh on chaotic headings | Gevi-Dava panic |
| `LaunchBombAction` | ballistic volley from a muzzle marker | Gevi-Dava |
| `GroundPoundAction` | leap, slam, radial blast, flings a bomb up | Gevi-Dava |
| `SuckSpitAction` | inhale → swallow → spit the player out | Ugrehk |
| `StrikeAction` | **generic**: windup → hit window → punishable recovery | Ugrehk, Essurou ×2 |

Two of these were extractions, not new work: `ErraticRunAction` is the Manicoppo's
twirl movement pulled out (a panicking bird and a whirling Manicoppo are the same
*path* in different costumes), and `StrikeAction` was written for one creature and
reused unchanged by the next. **Look for this before writing a new action.**

`EnemyAction extends Node3D` so an action can own spatial markers — a muzzle, a
slam epicentre — as children you drag in the viewport.

---

## 3. Component map (`objects/components/`)

### Heavy use by enemies — you'll touch these constantly

| Component | Role | Watch out for |
|---|---|---|
| **`MovementComponent`** | **single writer** of velocity + rotation | `spin_speed_deg` only applies on frames where nothing else claimed facing — an aiming action pauses the spin. `face_player` beats `face_travel_direction`. A null `pattern` = stationary but still aiming. |
| **`EnemyBrain`** | FSM + action scheduler | `can_chase`, `combat_range`, `range_hysteresis`. `debug_log` defaults **on** — that's the state/action trace you'll read while testing. |
| **`PerceptionComponent`** | vision cone, sticky loss | `require_line_of_sight` is why a creature behind a wall never wakes; pair with a `TriggerRegion`. `view_angle_deg` is the **full** cone, not half. |
| **`MeleeHitbox`** (`AttackBox`) | brain-opened strike window | **Reach lives in the CollisionShape3D**, not in any script. Set `hit_cooldown` above the window length for "once per swing". Detects **bodies**. |
| **`HitBox`** | receives hits → host `take_damage` | `override_damage` makes a fixed-value weak point. An enemy can carry **several** for weak points/armour. Must sit on layer 3 `hurtbox`. |
| **`DropComponent`** | loot | `death_min/max` vs `bump_chance` are different mechanics — death loot vs shaken loose off a survived hit. |
| **`HitReactComponent`** | flash + shake + bursts | Auto-connects to the host's `hit`; **zero wiring**. Needs `mesh_root_path` if the first `MeshInstance3D` isn't the right one. |

### Moderate use

| Component | Role | Watch out for |
|---|---|---|
| **`LocomotionAnimator`** | swaps idle/move clips by speed | Backs off clips it doesn't own, so attack animations aren't stomped. An action that freezes a clip must use `speed_scale = 0`, **not** `pause()` — pause blanks `current_animation` and the idle clip takes over. |
| **`BlastComponent`** | spawns a `Blast` on death | Event-driven; ignores activation. |
| **`SfxEmitter` / `VfxEmitter`** | keyed one-shots | Children are keyed **by node name**. `VfxEmitter.emit(key, true)` detaches so it outlives the corpse. |
| **`LockOnTargetComponent`** | opt into the lock-on system | Position it at the aim point (chest height). On `BaseEnemy` already. |

### Player-side (don't put these on enemies)

`BumpCombatComponent`, `PowerSlamComponent`, `LockOnComponent`,
`BouncePadComponent` (interactables).

### Legacy / unused — check before reaching for them

`WeaponComponent` (removed from `BaseEnemy`; no current user), `TurretEmitter`,
`AnimationDriver`, `ContactDamage`, `BobMovement`, `CurveFollowMovement`,
`WeaveMovement`, `SwoopMovement`, `StrafeMovement`. Kept because the *concepts*
are reusable; none is on a live creature.

### The ones with the most edge cases

1. **`MovementComponent`** — the facing-precedence interaction bites every time.
   If a creature won't turn, or won't stop turning, it's this.
2. **`MeleeHitbox`** — reach is in the scene, not the script. "The attack whiffs"
   is nearly always a shape that's too small or badly offset.
3. **`LocomotionAnimator`** — the pause-vs-speed_scale trap above.
4. **`HitReactComponent`** — `mesh_root_path` guesses wrong on multi-mesh models.

---

## 4. Interactables and breakables

**Breakable** = HP, no brain. `BaseBreakable.tscn` + `max_hp` ≤ 5 makes it die to
one bump from any angle (bump damage is 5–30 depending on how far behind you
struck). Add a `DropComponent` for loot. Mushroom 1 is exactly this and needed
**no code**.

**Interactable** = no HP, no base class. A capability component on any body. The
bounce mushroom is a `StaticBody3D` on the `environment` layer with a
`BouncePadComponent` area above its cap.

### When enemy work should spawn one of these instead

- **The creature is scenery that fights back** → it's an `Enemy` in `BUMP`
  activation mode wearing a breakable's clothes (the Ugrehk). *Not* a breakable.
- **You want a hazard with no decisions** → interactable component, not an enemy
  with one action.
- **A creature should launch/grab/redirect the player** → build it as a
  **component** even if only one creature uses it. `BouncePadComponent` was built
  for a mushroom and can be strapped to an enemy's head later.
- **A creature drops something on death** → `DropComponent`, never bespoke code.

**Rule of thumb:** if it makes a *decision*, it's an enemy. If it just *responds*,
it's an interactable. If it only *breaks*, it's a breakable.

---

## 5. Best practices for in-game testing

The loop is `run_project` → `game_eval` → `game_wait` → `game_eval`. Several
non-obvious traps, all learned the hard way:

### The game keeps running between calls

Elapsed real time between two evals is **unpredictable and often seconds**. This
silently invalidated several of my tests:

- Objects with lifetimes (PowerDrops at 12s) expired mid-test.
- A level restarted between setup and assertion, resetting everything I'd staged.
- `game_wait(60)` is *not* one second of game time by the time the next eval lands.

**Do:** measure against `Engine.get_physics_frames()`, not wall clock. Compute
expected values from the actual frame delta:

```gdscript
var secs: float = float(frames_elapsed) / float(Engine.physics_ticks_per_second)
var expected: float = deg_to_rad(spin_speed) * secs
```

That's how I confirmed a spin was exact rather than "roughly right".

**Do:** assert in the *same eval* that sets up, whenever possible.

### Physics needs a frame

A body added this frame is **not in the physics space yet**. A raycast in the same
eval that spawned it finds nothing. Wait a frame before any physics query.

### Don't teleport the player

Moving the player often drops them off the blockout, past `fall_limit_y`, and
GameManager restarts the level — destroying everything you spawned. **Move the
enemy to the player instead.** Enemies don't trigger fall-restarts.

### Verify state, don't infer it

"HP went down by 20, so two spits must have happened" is a guess. Prefer reading
the actual flag (`_held`, `_scripted_move`, `monitoring`). Where a window is too
short to catch across round-trips, **reproduce the state directly** rather than
racing the scheduler — that's how the swallow-release safety got tested.

### Check real numbers before trusting a design

The suck was inert because I guessed `pull_strength = 34` against the player's
actual `ground_acceleration = 60`. One eval reading the real value exposed both
the wrong constant *and* the wrong model.

### Reading the log

`EnemyBrain.debug_log` prints every transition and pick:

```
[EnemyBrain] GeviDava -> COMBAT
[EnemyBrain] GeviDava action: LaunchBomb
[EnemyBrain] GeviDava action: PanicRun
```

That trace is usually enough to tell whether a problem is *selection* (wrong
action chosen) or *execution* (right action, wrong behaviour). Note the brain logs
the **top-level** action — a nested follow-up runs silently under its parent's
name.

### Forcing a specific action

Set `enabled = false` on the others at runtime, and widen perception so the
creature engages:

```gdscript
perc.set("view_angle_deg", 360.0)
perc.set("require_line_of_sight", false)
```

### Triage noise

Every run prints ~150 warnings from `mcp_interaction_server.gd`, `events.gd`
("signal never explicitly used" — normal for a signal bus) and the eval wrappers.
**Filter for your own file paths.** A clean run has zero entries mentioning
`objects/`.

---

## 6. A working order that has held up

1. **Foundations first** if the brief needs them (a new activation mode, a new
   player-facing verb). Getting these wrong is expensive later.
2. **Build the creature's scene from `BaseEnemy`**, actions with fallback range
   bands so it works the moment it's dropped in.
3. **Verify structure** — actions present, context injected, overrides survived.
4. **Verify each action fires** via the debug log.
5. **Verify the dangerous paths** — anything touching the player's body,
   anything that can be interrupted.
6. **Regression-check an older creature.** Shared-base changes reach everything.
7. **Commit, then tune by playing.**

Scene structure over scripts, wherever possible: the Essurou needed **zero** new
code. If a creature needs a script, it's usually because it has a *visual* state
change (the Ugrehk's eruption), not because of its combat.

---

## 7. Traps worth knowing about

- **Never leave the player in `begin_scripted_move()`.** Any action that grabs
  them must release on *every* exit path including `on_abort()`, and the enemy
  dying mid-grab is the likeliest ending. The symptom is a frozen player with no
  recovery but a restart.
- **A flat force against the player is a boolean.** Their movement drives velocity
  toward input at `ground_acceleration = 60`, far above any sane pull, so a
  constant force either always wins or never does. Express pulls as a **target
  speed with distance falloff** to get counterplay.
- **Godot decides coroutine-ness statically, per function.** A base method with no
  `await` makes every `await base_typed_ref.method()` warn. `EnemyAction.run()`
  and `ErraticRunAction._begin()` both carry a deliberate one-frame await for this.
- **Inherited scenes resolve overrides by NAME, not index.** Stale `index=` values
  affect sibling order, not correctness — but keep them right anyway.
- **Adding a `class_name` needs the headless rescan** (see CLAUDE.md).
- **Enemy bodies have no gravity.** A `MovementPattern` assigns velocity outright,
  so a jump arc is driven frame by frame in the action. That's a feature for a
  telegraphed attack — the hang time is authored, not simulated.
- **Moving a property to a parent class is safe for existing scenes.** A scene
  override on an inherited property still applies, as long as the parent's default
  matches what the child had.

---

## 8. Things not yet built

Worth knowing before designing around them:

- **No enemy hit-reaction/stagger state.** Bumping an enemy mid-action doesn't
  interrupt it. The `_committed` flag exists but nothing drives stagger.
- **No enemy knockdown.** `BumpCombatComponent` has a stub where an
  out-of-energy bump would knock the *player* down.
- **`EnemyCoordinator` is only used by the Manicoppo** (shared sighting, ring
  slots, attack slots). New creatures don't opt in unless you add
  `requires_attack_slot`.
- **No spawner/wave system.** Enemies are placed by hand in the scene.
- **Nested action timeouts are ignored** — a follow-up runs inside its parent's
  ceiling.
