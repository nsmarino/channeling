# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

**starter-4.7** is a clean **3D character-controller starter template** for Godot 4
(Forward+ renderer), carved out of an earlier rail-shooter prototype. The goal is a
small, legible base you can clone for new 3D game prototypes and hit the ground
running: a working third-person player (with a SpringArm camera and Dark
Souls-style lock-on), a reusable component system, a restart loop, and a
curved-path authoring tool — without the prototype-specific cruft.

Assume games built from this template are **3D and character-controller based**.

Main scene: `main.tscn` (project root) — a third-person player on a ground plane.
The project ships a Godot MCP server (`mcp__godot__*`) for AI-assisted iteration —
prefer MCP tools (`run_project`, `game_eval`, `game_screenshot`) for verification
over raw shell work.

## Project layout

- **`main.tscn`** — the playable starter scene, at the **project root**: a
  `WorldEnvironment`, a ground plane (`StaticBody3D` + collision + mesh), the
  player, the HUD, and empty `Enemies` / `Obstacles` containers under `Level`.
- **`levels/`** — `main.gd` (scene controller; registers the player + level with
  `GameManager`) and `overworld/` scene scaffolding.
- **`objects/`** — game objects:
  - `objects/player/` — the **third-person player** (`player.gd` + `Player.tscn`).
  - `objects/components/` — shared behavior components + the base `Component` class.
  - `objects/enemy/` — `Destructible` / `Enemy` bases, concrete enemies, the blast
    system (`enemy/blast/`), movement patterns, and `*Data` resources.
  - `objects/obstacles/` — `Obstacle` base + concrete obstacles.
  - `objects/weapons/` — data-driven weapon / projectile bases + variants.
- **`autoloads/`** — `Events` (signal bus) and `GameManager` (scene refs + restart).
  `mcp_interaction_server.gd` also lives here and is loaded by the MCP tool at runtime.
- **`resources/`** — shared `Resource` data types (e.g. `WeaponData`).
- **`vfx/`** — `vfx/shaders/` (e.g. `blink.gdshader`) and `vfx/particles/` (e.g.
  the `blast.tscn` burst).
- **`ui/`** — the HUD (`CombatUI.tscn` / `combat_ui.gd`): a center crosshair +
  health readout.
- **`assets/`** — imported content (`models/`, `sounds/`, `sprites/`, `fonts/`,
  `hdr/`, vendored texture/vfx packs).
- **`addons/`** — editor plugins: `nurbs_path/` (curved-path authoring gizmo),
  `view_overlay_toggle/`, `GPUTrail/`, `brackeys_particle_controls/`.
- **`explores/`** — standalone R&D sandboxes (`explore-shaders/`, `explore-vfx/`,
  `explore-animation/`); not loaded by `main.tscn`.

Rule of thumb: new content assets go under `assets/`; new game logic/scenes under
`objects/`; shaders/particles under `vfx/`; editor plugins under `addons/`.

## Running & Tooling

- **Open in editor**: launch Godot 4, or `mcp__godot__launch_editor`. Run with
  `mcp__godot__run_project`.
- **Godot version**: developed against Godot 4.6/4.7 (Forward+). GDScript with
  **typed declarations throughout** — untyped is treated as a warning.
- Verify with MCP: `run_project` then `game_eval` in **separate turns** (the MCP
  server takes a moment to connect after launch — eval calls batched with
  `run_project` fail with "Not connected").
- The debugger break-on-error is enabled; a single parse error in eval-injected
  GDScript pauses the running game. Keep eval snippets short, **explicitly typed**
  (untyped `:=` on a dynamic member trips a parser break), and avoid mixing
  tabs/spaces.

### Class-cache / `.uid` gotcha (read before adding a `class_name`)

A freshly-written `.gd` with a new `class_name` (or a renamed one) won't register
in Godot's global class cache from a bare `run_project` — `extends NewClass` then
fails at a debugger break with *"Could not find base class"*. Fixes:
- Write the script's `.uid` directly (`uid://<unique-token>`, check for collisions).
- Force a one-shot rescan that rebuilds `.godot/global_script_class_cache.cfg`:
  `Godot --headless --editor --quit-after 300 --path .` (this also refreshes UIDs).
- Duck-typing a reference (`var x: Node` + `.call()/.set()`) sidesteps the lag when
  you can't rescan.

## Architecture

### Autoloads
- **`Events`** (`autoloads/events.gd`) — central signal bus. Holds `player_killed`
  and the enemy/hit feedback signals (`enemy_hp_changed`, `enemy_damaged`,
  `attack_hit`). Cross-system communication should go through here.
- **`GameManager`** (`autoloads/game_manager.gd`) — holds runtime refs (the player
  `navigator`, the level root) **and owns level restart** (see below).
- **`McpInteractionServer`** — TCP server for the Godot MCP tool. Lives at
  `autoloads/mcp_interaction_server.gd` and is injected as an autoload by the MCP
  `run_project` tool per-run (it is not a persistent project autoload). Many style
  warnings emanate from this file; **treat its warnings as noise** when triaging.

### Player (`objects/player/`) — third-person controller + lock-on

A **third-person `CharacterBody3D`** (`player.gd` + `Player.tscn`) that works with
**mouse/keyboard and gamepad interchangeably**. The body never rotates: look lives
on a `CameraPivot`, facing on a `Model` child. Scene rig:
`Player → CameraPivot → SpringArm3D → Camera3D` (the spring arm pulls the camera
in on walls) plus a visible `Model` (capsule + front indicator) and the
`LockOnComponent`. The capsule renders slightly left of center via the camera's
**`h_offset`** (not a transform offset — the SpringArm overwrites its child's
transform each frame; `camera_h_offset` / `locked_h_offset` are `@export` knobs).

**Free (unlocked)** — camera-relative:
- **Look** — mouse motion or the right stick (`look_*`) orbits the pivot (yaw +
  clamped pitch).
- **Move** — `WASD`/`IJKL` or the left stick (`move_*`), relative to the camera's
  facing; the `Model` turns toward the direction of travel.
- **Jump** — `Space` or the gamepad A button (`jump`).
- **Escape** toggles mouse capture (so you can reach the editor / OS).

**Locked** (LockOnComponent reports a target) — Dark Souls-style: free look is
suppressed and the camera auto-frames the target (FOV punches in to `locked_fov`);
forward/back approaches/retreats along the player→target line, left/right strafes
tangentially to orbit, and the `Model` faces the target the whole time.

**Weapon** — a `weapon_scene` (`@export`, default `PlayerRifle.tscn`) is instanced
under a `WeaponSocket` (a child of `Model`, so it swings with the body's facing) on
ready, with `owner_character` set to the player so its hitscan excludes us. The
`attack` action fires it, **but only while locked on** — you shoot the thing you're
locked to, and aim runs straight from the muzzle to the lock target. The weapon's
own `should_fire_for_input()` decides semi vs auto from its `WeaponData`.

It registers into the **`player`** group, exposes `hp` (read by the HUD), and on
death calls `Events.player_killed.emit()` (which `GameManager` turns into a
restart). Tuning lives in Inspector `@export` blocks (Movement / Look / Lock-On /
Weapon / Health / References), matching the iterate-by-playing workflow.

### Lock-on (`objects/components/lock_on_component.gd`, `lock_on_target.gd`)

A `LockOnComponent` (`extends Component`) attached under the player owns
**targeting only** — it never touches the camera rig (player.gd reads it
duck-typed via `is_locked()` / `get_target()` / `get_eligible_targets()` so the
pivot stays single-writer). Eligible entities are **opt-in by group**: add a
`LockOnTargetComponent` (`lock_on_target.gd`, a `Node3D`) as a child at the aim
point (e.g. chest height) — it registers itself in the **`lockable`** group (toggle
via its `enabled` flag / `set_lockable()`); its `global_position` is the aim point
and `get_parent()` is the entity. `BaseEnemy.tscn` ships with one, so every enemy is
lockable out of the box. Each
frame the component gathers markers that are alive, within `max_lock_distance`, in
front of the camera, and inside the inner `inner_viewport_fraction` of the
viewport. Pressing `lock_on` locks the most-centered one; pressing again drops it;
a look flick (right stick / mouse) switches targets; the lock also drops when the
target dies (`is_defeated()`), is freed, or leaves range. The HUD draws a reticle
on the active target and soft markers on the rest (see below).

### Restart system (`GameManager`)

`GameManager.restart_level()` reloads the current scene (a **deferred**
`reload_current_scene()`) behind a re-entrancy guard, so multiple triggers in one
frame collapse to one reload. Deferring matters: death often fires from inside a
physics callback (a projectile's `body_entered`), and a synchronous reload there
errors on removing collider nodes mid-callback. It survives the reload because it's
an autoload; the fresh scene re-registers its player via `register_navigator`.
Three triggers are wired:
- **Player death** — connected to `Events.player_killed` in `_ready`.
- **Fall off map** — `_process` watches the registered navigator's `global_position.y`
  against `fall_limit_y` (default −50), toggleable via `fall_check_enabled`. It is
  controller-agnostic (it watches the navigator, not a specific script).
- **Input** — the `restart` action (R / gamepad Back), handled in `_unhandled_input`.

### HUD (`ui/CombatUI.tscn`, `ui/combat_ui.gd`)

A `CanvasLayer` with a **center-anchored crosshair** (it stays put on its own
anchors; the script just keeps it visible) and a `HEALTH: ###` label polled from
the player's `hp` each frame. It also drives the **lock-on overlay**: it finds the
player's `LockOnComponent` (duck-typed) and each frame `unproject_position`s the
targets — repurposing the `LockOn` square as the **active reticle** and pooling
soft `◇` markers (`EligibleMarkers`) on every other eligible target.

### Components (`objects/components/`)

Small Nodes you attach to a host body (enemy, obstacle, player) to add one slice of
behavior. The host coordinates them through **`set_active(bool)`**: `Destructible`
broadcasts its lifecycle (`ACTIVE` / `DYING`) to every child exposing
that method (duck-typed dispatch — the host needs no per-component knowledge).

- **`Component`** (`component.gd`, `class_name Component`, `extends Node`) — the
  base. Resolves `host` in `_ready` (the parent, or `host_path`), calls a `_setup()`
  hook, and routes `set_active(bool)` through an `is_active` guard into
  `on_activate()` / `on_deactivate()`. Two flavors both subclass it:
  - **Lifecycle-driven** (`MovementComponent`, `WeaponComponent`, `TurretEmitter`,
    `AnimationDriver`) — override `on_activate` / `on_deactivate` to start/stop
    per-frame work.
  - **Event-driven** (`HitReactComponent`, `BlastComponent`) — ignore activation
    and connect to host signals (`hit` / `died`) in `_setup()`.
- **Single-inheritance caveat**: components that must *be* a spatial node can't
  extend the `Node`-based `Component` — `HitBox` and `ContactDamage` are `Area3D`;
  `SfxEmitter` / `VfxEmitter` are `Node3D`. They implement the same `set_active`
  contract by hand and are recognised through the same duck-typed dispatch.

Component roster: `HitBox` (routes `receive_hit` → host `take_damage`),
`MovementComponent` (drives the body via a `MovementPattern`, and turns it to face
travel or — with `face_player` — the player; a null pattern = a stationary sentry
that still aims), `WeaponComponent`
(fires a projectile on a cadence), `ContactDamage` (damages overlapping bodies on a
per-body cooldown), `AnimationDriver` (plays a keyframed `AnimationPlayer`),
`TurretEmitter` (spawns curve-following projectiles), `HitReactComponent` (flash +
shake + optional particle bursts; on enemies **and** the player),
`BlastComponent` (spawns a blast on death), `SfxEmitter` / `VfxEmitter` (keyed
one-shot players), `LockOnComponent` (player-only; poll/input-driven targeting for
the lock-on system — see the Player section).

### Destructibles: enemies, obstacles, turret-projectiles

A **component-assembled** system. Everything shootable shares one base,
`Destructible`, built as an **inherited scene** so the visible body is a real
editor-visible child node.

> **Naming note:** the `class_name`s dropped the old `Fse*` prefix (now
> `Destructible`, `Enemy`, `Obstacle`, `Blast`, `EnemyData`, `WeaponData`,
> `BaseWeapon`, `BaseProjectile`, `HitscanWeapon`, `TurretProjectile`). A few
> **filenames** still carry the old prefix (`fse_destructible.gd`,
> `fse_obstacle.gd`, `fse_turret_projectile.gd`) — class names and file names
> intentionally differ there for now.

- **`Destructible`** (`objects/enemy/base/fse_destructible.gd`, extends
  `CharacterBody3D`) — the shared spine: lifecycle states
  `{ INACTIVE, ACTIVE, DYING }`, HP / `take_damage(amount, is_blast := false)`,
  a public `destroy()`, a `blast_only` flag, `homing_eligible`, the `hit` / `died`
  signals that `HitReactComponent` / `BlastComponent` hook, and the duck-typed
  `_dispatch_active(bool)` broadcast. Registers into the **`destructible`** group.
- **`Enemy`** (`objects/enemy/base/base_enemy.gd`) — adds `enemy_data`, distance
  activation, and `setup(player)` wiring. Group `enemy`.
- **`Obstacle`** (`objects/obstacles/base/fse_obstacle.gd`) — adds `is_destructible`
  and optional proximity activation. Group `obstacle`.
- **`TurretProjectile`** (`objects/weapons/enemy/fse_turret_projectile.gd`) — a
  destructible projectile that follows a curve from its emitter.

Movement patterns (`objects/enemy/movement/`): `MovementPattern` base +
`WeaveMovement`, `SwoopMovement`, `StrafeMovement`, `BobMovement`,
`CurveFollowMovement`. Concrete enemies (`objects/enemy/enemies/`): **Weaver**,
**Swooper**, **Turret** (a stationary sentry — no movement pattern, `face_player`
on — that looks at and shoots the player), each with an `*.tres` `EnemyData`. Obstacles
(`objects/obstacles/`): **BobBlock**, **AnimObstacle**, **StationaryTurret**.

> These enemies/weapons/obstacles ship as a **reusable library** but are **not
> instanced in `main.tscn`** — the starter scene is just the player + ground. Drop
> them under `Level/Enemies` or `Level/Obstacles` to use them.

### Weapons (`objects/weapons/`)

- **`BaseWeapon`** (`base/BaseWeapon.gd`) — data-driven via a `WeaponData`
  (`resources/WeaponData.gd`). `try_fire(aim_direction)`, plus an optional per-frame
  `homing_target` passed to spawned projectiles.
- **`BaseProjectile`** (`base/BaseProjectile.gd`) — straight-flying; dispatches
  damage both via `area_entered` (enemy `HitBox.receive_hit`) and `body_entered`
  (bodies exposing `take_damage` / `receive_attack` / `on_damage`).
- **`HomingProjectile`** (`player/homing_projectile.gd`) — curves toward a target at
  a capped turn rate. Enemy bolt variants live under `objects/weapons/enemy/`.
- **`HitscanWeapon`** (`base/HitscanWeapon.gd`) — instant raycast instead of a
  projectile; used by the player's `PlayerRifle.tscn`. To damage enemies it needs
  `collide_with_areas = true` and a `hitscan_collision_mask` covering the `enemy`
  layer, because the hurtbox is a `HitBox` **Area3D**, not a body. `_apply_damage`
  routes through `receive_hit` → `take_damage` → `on_damage` (first match wins), so
  it feeds the same `HitBox.receive_hit` path the projectiles use.

### Blast radius & chain reactions (`objects/enemy/blast/`, `blast_component.gd`)

Three blast categories: **Yellow** (destructible, no blast), **Red** (destructible
+ spawns a blast on death via `BlastComponent`), **Green** (`blast_only = true`:
immune to normal fire, dies only to a blast). `BlastComponent` spawns a transient
**`Blast`** (`Blast.tscn` + `blast.gd`, `class_name Blast`) at the corpse; after a
small delay it damages every `destructible` within `radius` via
`take_damage(dmg, is_blast = true)`, cascading through reds/greens. Sizes scale
together (small Ø3 / 10 dmg … large Ø12 / 90 dmg). Prototypes live in
`objects/enemy/enemies/blast-radius/`.

### Input map (`project.godot`)

A clean snake_case FPS action set, each bound for **keyboard and gamepad**:

| Action | Keyboard | Gamepad |
|---|---|---|
| `move_forward` / `move_back` | W / S (also I / K) | left stick Y |
| `move_left` / `move_right` | A / D (also J / L) | left stick X |
| `jump` | Space | A button |
| `look_left/right/up/down` | (mouse motion, in code) | right stick |
| `lock_on` | O | right-stick click (R3) |
| `attack` | left mouse | R2 trigger |
| `restart` | R | Back button |

(Movement is dual-bound to WASD **and** the right-hand IJKL cluster for
left-handed play; `lock_on` sits on `O` beside IJKL.)

### Combat collision layers

| # | Name | Used by |
|---|---|---|
| 1 | `environment` | static world / the ground plane |
| 2 | `player` | the player body |
| 3 | `enemy` | enemy `HitBox` areas |
| 4 | `player_projectile` | player projectile areas (mask scans `enemy`) |
| 5 | `enemy_projectile` | enemy projectile areas (mask scans `player`) |

### Curved-path authoring (`addons/nurbs_path/`)

An in-editor `@tool` plugin for composing curved paths (e.g. patrol routes, camera
rails, projectile arcs). Add a **`NurbsPath3D`** node (a `Path3D` subclass) and
author its curve as a **control polygon** instead of hand-tuning Bézier tangents.
It holds an `Array[Vector3] control_points` + a `closed` flag and rebuilds its own
`Curve3D` as a **uniform cubic B-spline**, which converts *exactly* into the cubic
Bézier `Curve3D` stores (no sampling error). Editing is a viewport gizmo (drag a
handle per point, with undo/redo; **Shift+Left-click** appends a point). Open curves
are clamped to start/end on the first/last point; `closed` wraps into a seamless
loop. The plugin/gizmo reference the node **duck-typed** (matched by script
resource, not `class_name`) to dodge class-cache lag.

### Exploration prototypes (`explores/`)

Standalone sandboxes, not loaded by `main.tscn`: `explore-shaders/`
(`outline-posterize-color-dither.gdshader` — Sobel + posterize + Bayer dither;
conflicts with Volumetric Fog unless `fog_disabled` is added to `render_mode`; plus
`simple-water.gdshader`, `grass.gdshader`), `explore-vfx/`, `explore-animation/`.

## Global groups

`"player"`, `"enemy"`, `"obstacle"`, `"destructible"`, `"level"`, `"lockable"` —
registered automatically (player in its scene + `_ready`; `destructible` in
`Destructible._ready`; `enemy`/`obstacle` in the respective subclass; `lockable`
in `lock_on_target.gd._ready`). Lookups use
`get_tree().get_first_node_in_group(...)` / `get_nodes_in_group(...)`.

## Conventions

- GDScript with **static typing** throughout. Untyped declarations warn.
- Cross-system signals go through `Events` rather than direct node-to-node connections.
- Components attach by `script` on a child node and resolve `host`/siblings in
  `_setup()`; the `Destructible` parent coordinates them via the duck-typed
  `set_active(bool)` broadcast — a new lifecycle driver only needs `on_activate` /
  `on_deactivate` (or, for an event-driven one, host-signal connections in `_setup`).
- Imported content lives under `assets/`; editor plugins under `addons/`.

## Working style notes

- Tuning happens in the **Inspector**, not in code — keep `@export` knobs
  front-and-center for new behavior. The user iterates by playing, tweaking, replaying.
- The user prefers **small, reviewable changes** over big batches. Show a diff
  before committing when in doubt.
- **Never commit without explicit permission.** The user reviews changes manually.
- **Git remote:** `origin` is `https://github.com/nsmarino/starter-4.7.git` (this
  template's own repo). `main` tracks `origin/main`.
- Avoid concurrent edits to the same file in one batch — they race and the second
  one's "file has been modified since read" error can leave half-applied changes.

## Current direction

This repo is being shaped into a **clean starter template**. Landed so far: the
`Fse*` → unprefixed class renames, a sturdy `GameManager` restart loop (death /
fall / `restart` input), the legacy dialogue + trigger systems removed, a base
`Component` class with the components migrated onto it, the rail-shooter mecha
player replaced by a **third-person SpringArm controller**, and a **Dark
Souls-style lock-on** (`LockOnComponent` + `lockable` markers + HUD reticle).

Possible next steps (unordered): rename the lingering `fse_*` filenames + the
`CombatUI` scene; decide whether to keep the enemy/weapon/blast library or split it
into an optional module; flesh out the empty `Level` containers with example
content.
