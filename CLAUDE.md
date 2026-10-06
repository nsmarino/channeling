# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

**channeling** is a 3D action game in Godot 4 (Forward+), built on a
character-controller foundation. The current phase is **encounter prototyping**: a
CSG blockout level dressed with enemies, breakables and interactables, tuned by
playing, ahead of any mise-en-scène work (textures, lighting, Blender models).

Combat is **bump-based** — you damage things by running into them — not shooting.
A player rifle/weapon system still exists in the tree but is not the direction;
treat it as legacy unless asked.

Main scene: `main.tscn` (project root), which loads one location scene from
`levels/` (see Locations). The project ships a Godot MCP server
(`mcp__godot__*`); prefer it (`run_project`, `game_eval`, `game_screenshot`) over
raw shell work for verification.

**For building new enemies, read [`docs/enemy-prototyping.md`](docs/enemy-prototyping.md).**
It covers the action system, the component map, testing practice and the traps.

## Project layout

- **`main.tscn`** — the harness: player, HUD, `WorldEnvironment`, music. It holds
  no level content; it instances a **location** scene at startup (see Locations).
- **`levels/`** — `main.gd` (loads the location, registers player + location with
  `GameManager`), `proto_scene.tscn` (the current prototype location),
  `overworld/`, `dungeon/`.
- **`placeholder/`** — untextured blockout geometry and placeholder creature
  models.
- **`objects/`**
  - `player/` — third-person player (`player.gd` + `Player.tscn`).
  - `components/` — reusable behaviour components + the `Component` base.
  - `enemy/` — `Destructible` / `Enemy` bases, `actions/` (the AI action library),
    concrete enemies, the blast system, movement patterns.
  - `breakables/` — `Breakable` base + Mushroom 1.
  - `interactables/` — bounce mushrooms (no base class; see below).
  - `level/` — `TriggerRegion`, `Portal`, level-authoring pieces.
  - `pickups/`, `weapons/`, `cutscene/`.
- **`autoloads/`** — `Events`, `GameManager`, `Cinematic`.
  `mcp_interaction_server.gd` is injected per-run by the MCP tool, not a project
  autoload; **treat its warnings as noise** when triaging.
- **`vfx/`**, **`ui/`**, **`assets/`**, **`addons/`**, **`explores/`** — as named.

## Running & Tooling

- **Run**: `mcp__godot__run_project`. **Editor**: `mcp__godot__launch_editor`.
- **Godot 4.6/4.7, Forward+.** GDScript with **typed declarations throughout**;
  untyped is a warning.
- `run_project` then `game_eval` in **separate turns** — the MCP server needs a
  moment to connect, so calls batched with `run_project` fail with "Not connected".
- Break-on-error is on; a parse error in eval-injected GDScript pauses the game.
  Keep eval snippets short and explicitly typed.

### Class-cache / `.uid` gotcha (read before adding a `class_name`)

A freshly written `.gd` with a new `class_name` will **not** register from a bare
`run_project` — `extends NewClass` fails with *"Could not find base class"*. Fix:

```bash
/Applications/Godot_4.7.app/Contents/MacOS/Godot --headless --editor --quit-after 400 --path .
```

This rebuilds `.godot/global_script_class_cache.cfg` and runs fine alongside an
open editor. Also write the script's `.uid` by hand (`uid://<token>`, checked for
collisions) so scenes can reference it stably.

## Architecture

### Autoloads

- **`Events`** — signal bus: `player_killed`, the cutscene bracket,
  `enemy_hp_changed` / `enemy_damaged` / `attack_hit`.
- **`GameManager`** — runtime refs + **level restart** (deferred
  `reload_current_scene()` behind a re-entrancy guard). Triggers: player death,
  falling below `fall_limit_y`, and the `restart` action. Also holds the Play
  From Here overrides (spawn point + `location_override`) for the whole session.
- **`Cinematic`** — brackets cutscenes with the `Events` signals.

### Locations (`levels/`)

`main.tscn` is a harness; each playable place is its own `.tscn`. `Main`'s
`active_scene` (`PackedScene`) names the location to play — swap it in the
Inspector. At startup `main.gd` instances it as a child of Main, moves the player
to its `PlayerSpawn` marker if it has one, and registers it with `GameManager`.
Restart reloads `main.tscn`, which re-instances the same location.

A location owns everything that belongs to the place, so nothing leaks between
locations:

```
<Location> (Node3D root — required)
├── PlayerSpawn (Marker3D)     optional default spawn; else the player's spot in main.tscn
├── NavigationRegion3D         required if it has enemies — see below
│   └── geometry, Enemies, Items, …
├── EnemyCoordinator           optional; enemies opt in via coordinator_path
└── lights, LightmapGI, Cutscenes, TriggerRegions
```

Shared things (player, HUD, environment, music) stay in `main.tscn`.

**Starting a new location:** duplicate `levels/template_scene.tscn` (the tree
above, plus a 40×40 floor and a sun) with **Duplicate… in the FileSystem dock**,
not Finder — Godot gives the copy a fresh scene UID, a Finder copy shares the
template's and the two get confused. Then rename the root, bake the
NavigationRegion3D, and point `active_scene` at it. The template's navmesh ships
unbaked — every copy reshapes its geometry and must bake its own anyway. It is a
copy, not an inherited scene: changing the template later does not touch
locations already made from it.

**Portals** (`objects/level/Portal.tscn`) link locations. Each has a
`target_scene` (a file path — a `PackedScene` export would make two locations that
link to each other load each other forever) and a `target_spawn`, the **name** of
a node anywhere in the target location. So a location takes as many entry points
as it needs: a Marker3D per door, named for where it leads from (`FromCave`), and
the default `PlayerSpawn` for a fresh start. The spawn's -Z is the arrival facing;
aim it away from the return portal.

Walking in calls `Main.travel()`, which swaps the location in place — the player
node survives, so HP and energy carry over (`Player.place_at()` sets position and
facing). `GameManager.record_travel()` remembers the location and spawn, so dying
after a trip restarts at the door you came through, and clears any Play From Here
point (it belonged to the location you left). Guards: a portal ignores the player
until it has seen them outside it, so arriving inside a return portal can't
bounce; it won't fire during a scripted move, whose owner may be freed by the
swap; a spawn name that doesn't exist warns and falls back to `PlayerSpawn`.

**Enemies need a baked navmesh.** With no `NavigationRegion3D` the nav map is
still valid and synced but empty, so `map_get_closest_point` returns the world
origin: a knocked-back enemy is snapped to `(0,0,0)` by `MovementComponent`,
`NavWanderMovement` herds wanderers there, `is_navigable()` reports everything
off-mesh, and chase never moves. Breakables and interactables don't care.

**Play From Here** (`addons/play_from_here/`, hold J + left-click in the 3D view)
always launches `main.tscn`. It records the clicked point *and* the scene being
edited; Main loads that scene in place of `active_scene`. So J-click inside a
location file plays that location with the player and HUD — but J-clicking in a
non-location scene (e.g. `Player.tscn`) would try to load it as a location.

**LightmapGI bakes** write into the `LightmapGIData` already assigned. A location
saved from an existing branch inherits that file (`proto_scene` still bakes into
`main.lmbake`); clear `light_data` on a new location's LightmapGI before its first
bake or it will overwrite another location's lightmap.

### Player (`objects/player/`)

Third-person `CharacterBody3D`, mouse/keyboard and gamepad interchangeable. The
body never rotates: look lives on a `CameraPivot`, facing on a `Model` child.
Rig: `Player → CameraPivot → SpringArm3D → Camera3D`, plus `Model`, `BumpCombat`,
`PowerSlamComponent`, `LockOnComponent`.

**Three distinct ways to move the player from outside** — pick deliberately:

| Method | Overrides velocity | Suppresses input | Use for |
|---|---|---|---|
| `apply_knockback(impulse, duration)` | yes | **yes** | being hit; the impact must read |
| `launch(impulse)` | along the impulse axis only | no | bounce pads, traversal boosts |
| `apply_external_velocity(delta_v)` | adds only | no | sustained pull/push you can fight |

`launch()` cancels existing motion along its axis first, so height is what the pad
promises rather than a function of how hard you fell.
`begin_scripted_move()` / `end_scripted_move()` hand the transform over entirely
(Power Dive, being swallowed) — **anything that starts one is responsible for
ending it**, including on abort, or the player is frozen until a restart.

Also: `hp`, `energy` (regenerates every frame), `spend_energy()` (all-or-nothing),
`restore_energy()`, `take_damage()`.

Useful constants when tuning forces against the player: `move_speed` 6.0,
`ground_acceleration` 60.0, `air_acceleration` 6.0.

### Destructible family

```
Destructible (CharacterBody3D)        group: destructible
├── Enemy      — activation + brain    group: enemy
└── Breakable  — HP, no brain          group: breakable
TurretProjectile extends Destructible directly
```

**`Destructible`** (`objects/enemy/base/fse_destructible.gd`) — lifecycle
`{INACTIVE, ACTIVE, DYING}`, HP, `take_damage(amount, is_blast)`, `destroy()`,
`blast_only`, `hit`/`died` signals, `debug_log`, and the duck-typed
`_dispatch_active(bool)` broadcast to any child exposing `set_active(bool)`.
Virtuals: `_report_damage()` (base is a no-op; `Enemy` emits the `Events` signals,
so a breakable prop doesn't drive the enemy HUD channel), `_label()`,
`_death_message()`.

**`Enemy`** (`base_enemy.gd`) — `enemy_data`, `activation_mode`
(`DISTANCE` / `BUMP` / `MANUAL`), public `activate()`, and the `_on_activated()`
virtual for what waking up looks like. In `BUMP` mode the first hit wakes the
creature and **deals no damage** — that is what lets something disguise itself.

**`Breakable`** (`objects/breakables/breakable.gd`) — deliberately almost empty.
Its job is to exist as a *type* so a level can ask for breakables without also
getting enemies. Bump-destructible for free via its `hurtbox`-layer `HitBox`.

> **Naming note:** a few filenames still carry an old `Fse*` prefix
> (`fse_destructible.gd`, `fse_turret_projectile.gd`); class names don't.

### Enemy AI

`BaseEnemy.tscn` ships the whole stack — `PerceptionComponent`, `EnemyBrain`, an
empty `Actions` container, `NavigationAgent3D`, `AttackBox`, `DropComponent` — so
a new enemy inherits a working brain and only fills in its actions.
**`WeaponComponent` is deliberately NOT on the base**: ranged fire is one enemy's
choice, not a property of enemies.

Three ideas hold it together:

1. **Single-writer movement.** `MovementComponent` is the only thing that writes
   velocity/rotation and calls `move_and_slide`. Everything else routes intent
   through one-frame latches — `drive()`, `face_toward()`, `set_facing()` — plus
   `apply_knockback()`. Call them every frame you want control; *stop* calling to
   hand the body back. Precedence: `knockback > drive > pattern`.
2. **Perception** — vision cone with sticky loss (grace + hysteresis).
3. **Brain as scheduler** — a small FSM (`WANDER` / `CHASE` / `COMBAT`) that owns
   no behaviour. Behaviours are `EnemyAction` nodes it gathers, weighted-picks and
   awaits. `can_chase = false` for stationary creatures. **An empty `Actions`
   container keeps the brain in WANDER**, so the AI rides on the base without
   changing anything that doesn't opt in.

See [`docs/enemy-prototyping.md`](docs/enemy-prototyping.md) for the action
contract, the cancellation rule and the full action library.

### Interactables

**There is no `Interactable` base class, on purpose.** Being interactable is a
*capability* you bolt onto any body — so `BouncePadComponent` can sit on a
mushroom today and a door or an enemy's head tomorrow, with no inheritance to
negotiate. Interactables have no HP and are not destructibles.

`BouncePadComponent` proves "the player arrived from above" with **geometry** (its
volume sits above a solid cap) rather than by testing downward velocity — Godot
reports area overlaps from the previous physics step, by which time
`move_and_slide` has already zeroed the lander's velocity.

### Loot

`DropComponent` lives on the thing being broken, not on the player. Two separate
knobs because they're separate mechanics: **death loot** (`death_min`/`death_max`,
auto-connected to `died`) and **shake-loose** (`bump_chance`, called duck-typed by
`BumpCombatComponent` on a hit the target survived).

### Blast / explosions

One `Blast` class serves enemy deaths and hostile ordnance. `damages_player` is
**off by default** — the unification is in the code, but whether a given blast
hurts the player stays per-blast, so enabling it globally can't silently change
every existing encounter. Bombs and ground pounds set it true.

### Trigger regions

`TriggerRegion` is a level-authored volume, placed independently of any creature.
It gates actions (`EnemyAction.required_region`) **and feeds alertness** — the
latter is the part that's easy to miss: perception needs line of sight, so a
creature shelling a courtyard from behind a wall would otherwise never notice the
player. The brain collects regions from the actions that reference them.

### Input map (`project.godot`)

Keyboard + gamepad throughout. `move_*` (WASD **and** IJKL), `jump`, `look_*`,
`lock_on` (O / R3), `attack` (LMB / R2), `power_slam` (`;` / X), `restart`
(R / Back).

### Collision layers

| # | Name | Used by |
|---|---|---|
| 1 | `environment` | static world, **and solid enemies/interactables that block** |
| 2 | `player` | the player body |
| 3 | `hurtbox` | `HitBox` areas on enemies **and breakables** |
| 4 | `player_projectile` | player projectile areas |
| 5 | `enemy_projectile` | enemy projectile areas |
| 6 | `pickup` | PowerDrops |

Layer 3 is `hurtbox`, not `enemy` — breakables and props need it too. Enemy
*bodies* are `collision_layer = 0` (the player runs through them, which is what
makes a bump land cleanly); set layer 1 only when something should physically
block, like the Essurou.

### Curved-path authoring (`addons/nurbs_path/`)

`NurbsPath3D` (a `Path3D` subclass) authored as a control polygon rather than
Bézier tangents; rebuilds its `Curve3D` as a uniform cubic B-spline.
Shift+Left-click appends a point. Used for the Power Dive trajectory.

## Groups

Registered in code (`_ready`) and looked up with
`get_tree().get_first_node_in_group(...)` / `get_nodes_in_group(...)`:

`player`, `enemy`, `breakable`, `destructible`, `lockable`, `trigger_region`,
`enemy_coordinator`.

`project.godot` also declares `level` as a global group, but nothing joins it —
`GameManager` holds the level by direct reference instead. Don't write lookups
against it without registering it first.

## Conventions

- **Static typing throughout.** Untyped declarations warn.
- **Facing is Godot-standard `-Z` forward**, everywhere. Markers like `Muzzle` sit
  at negative Z. Rotate the *model* child if imported art faces wrong.
- Cross-system signals go through `Events`.
- Components attach by `script` on a child node, resolve siblings in `_setup()`,
  and are coordinated by the duck-typed `set_active(bool)` broadcast.
- Components that must *be* a spatial node (`HitBox`, `MeleeHitbox`,
  `ContactDamage`, `BouncePadComponent`, `BumpCombatComponent`, the emitters)
  can't extend the `Node`-based `Component`; they implement the same contract by
  hand.
- Avoid concurrent edits to the same file in one batch — the second one's "file has
  been modified" error can leave half-applied changes.

## Working style notes

- Tuning happens in the **Inspector**, not in code — keep `@export` knobs
  front-and-center. The user iterates by playing, tweaking, replaying.
- Prefer **small, reviewable changes**. Show a diff before committing when in doubt.
- **Never commit without explicit permission.**
- **Git remote:** `origin` is `https://github.com/nsmarino/channeling.git`.
  `main` tracks `origin/main`.
- Deleting superseded prototype content is welcome — verify nothing references it
  first, keep the reusable *scripts*, delete the scenes and their tuning `.tres`.

## Current direction

Landed: the bump-combat + energy loop, Power Dive, the node-based `EnemyAction`
system, the AI stack on `BaseEnemy`, the Enemy / Breakable / Interactable split,
trigger regions, and four prototype creatures (Manicoppo, Gevi-Dava, Ugrehk,
Essurou).

Next: **tuning the creatures by playing**, wiring `TriggerRegion`s into real
encounters, filling the CSG blockout, and only then mise-en-scène in Blender.
