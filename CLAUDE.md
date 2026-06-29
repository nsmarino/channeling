# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

**time-rails** is a Godot 4.6 (Forward+) arcade rail shooter in the style of *Sin & Punishment: Star Successor*, *Kid Icarus: Uprising*, *Panzer Dragoon*, and *Space Harrier*. The player pilots a mecha along a forward-moving rail through a sci-fi anime world of twisted pines and shattered ruins. The finished prototype targets three levels with strong replay value; goals lean heavily on **visual effects (particle systems, shaders)** and **a variety of fun weapons and enemy types** to experiment with.

Main scene: `main.tscn` (project root). The project ships a Godot MCP server (`mcp__godot__*`) for AI-assisted iteration — prefer MCP tools (`run_project`, `game_eval`, `game_screenshot`) for verification over raw shell work.

## Project layout

Top-level dirs (the rearranged structure — expect things here):
- **`main.tscn`** — the playable scene, at the **project root**. `levels/` holds the rail (`rail_follower.gd`), `main.gd`, and overworld pieces.
- **`objects/`** — game objects: `objects/components/` (shared behavior components, used by enemies **and** the player), `objects/enemy/` (FseDestructible/FseEnemy bases, concrete enemies, `enemy/blast/`, movement patterns, `*Data` resources), `objects/obstacles/`, `objects/weapons/`, `objects/player/` (the player rig — `mecha_player.gd` + `MechaPlayer.tscn`), and `objects/triggers/` (the legacy dialogue/trigger system).
- **`explores/`** — standalone R&D sandboxes (`explore-animation/`, `explore-shaders/`, `explore-vfx/`); not loaded by `main.tscn`.
- **`moments/`** — new top-level dir, currently empty (reserved for upcoming work).
- **`vfx/`** — `vfx/shaders/` (e.g. `blink.gdshader`) and `vfx/particles/` (e.g. the `blast.tscn` burst).
- **`ui/`** — HUD / menus, flat (`ui/CombatUI.tscn`, `ui/combat_ui.gd`, plus the legacy `DialogueBox`/`PromptBox`).
- **`autoloads/`** — `Events`, `GameManager`, `McpInteractionServer`.
- **`resources/`** — shared `Resource` data types (weapon / dialogue / etc.).
- **`assets/`** — all imported content: `assets/models/` (incl. `assets/models/rails/mecha/mecha-frame.glb`), `assets/sounds/`, `assets/sprites/`, `assets/fonts/`, `assets/hdr/`, plus vendored `assets/brackeys-vfx/` + `assets/kenney_prototype-textures/`.
- **`addons/`** — editor plugins: `GPUTrail/`, `view_overlay_toggle/` (the multi-toggle overlay hotkey), `brackeys_particle_controls/`, `nurbs_path/` (the curved-rail authoring gizmo).

Rule of thumb: new content assets go under `assets/`; new game logic/scenes under `objects/`; shaders/particles under `vfx/`.

## Running & Tooling

- **Open in editor**: launch Godot 4.6, or `mcp__godot__launch_editor`. Run with `mcp__godot__run_project`.
- **Open Blender source**: `make blend` (or `./open-blends`) opens the Blender sources. Note: `.blend` sources are **not currently tracked in-repo** — exported `.glb` land under `assets/models/`.
- **Godot version**: 4.6.stable.official — GDScript with **typed declarations throughout**; untyped is treated as a warning.

## Architecture

### Autoloads
- **`Events`** (`autoloads/events.gd`) — central signal bus. Combat hits, enemy HP/damage, phase changes, dialogue lifecycle. Cross-system communication should go through here.
- **`GameManager`** (`autoloads/game_manager.gd`) — holds runtime references to the navigator (player `CharacterBody3D`) and overworld root.
- **`McpInteractionServer`** (`autoloads/mcp_interaction_server.gd`) — TCP server on `127.0.0.1:9090` for the Godot MCP tool. Many style warnings emanate from this file; **treat its warnings as noise** when triaging.

### Player rig (`objects/player/`)

**Aim-led, Star Fox / Panzer Dragoon model** — the reticle is the only directly-driven element; the ship follows it and the camera reacts to it. (This replaced the earlier dual-cursor system where ship and reticle were steered independently.)

```
Main
└─ Level
   └─ Path3D (curve = the rail)
      └─ PathFollow3D (rail_follower.gd advances `progress` each frame; ToggleBrake stops/resumes)
         └─ PlayerRoot (Node3D)
            ├─ Navigator (MechaPlayer.tscn — the ship, group "player")
            └─ Camera3D
               └─ AimTarget (Node3D — the reticle's world position)
```

The rig is driven forward by **`levels/rail_follower.gd`** on the `PathFollow3D`: each frame it advances `progress` by `speed` (world units/sec, default ~20), with `loop` on so it wraps at the curve's end. **`ToggleBrake`** flips a `braked` flag — press to stop, press again to resume. (This replaced the old `AnimationPlayer/MoveF` track that animated `progress_ratio` 0→1; the AnimationPlayer stays in `main.tscn` but no longer autoplays.) While braked, the ship mesh plays a subtle vertical idle bob for a floating-in-midair feel — `mecha_player.gd` reads the rail's `braked` flag (via `rail_follower_path` / nearest `PathFollow3D` ancestor) and eases a sine offset on the `mecha-frame` mesh ("Brake Bob" knobs).

`mecha_player.gd` per-frame order is **aim → camera → ship → combat** (the ship reads the camera's banked transform, so the camera must rotate first):
- **Aim** (`_process_aim`): right stick (`LookLeft/Right/Up/Down`) + mouse motion (`_input`, captured on `_ready`, **Escape** toggles) drive `_aim_cursor` across the aim plane, frustum-clamped to the full view. Persistent by default; `recenter_rate` eases it back to center when idle (0 = fully persistent).
- **Camera** (`_process_camera`): eased, capped roll/pitch/yaw computed from the normalized aim (`camera_roll_max_deg` etc.). Written as **local** rotation so it composes additively on top of any rail bank the PathFollow3D/PlayerRoot applies.
- **Ship** (`_process_ship`): targets `_aim_cursor * ship_follow_fraction` (a smaller sub-box) with a snappy spring (`ship_follow_lerp`), corrected by the plane-distance ratio so it stays on-screen. Sits `ship_below_offset` (~1u) *below* the reticle so it doesn't occlude the target — the offset fades out as the reticle drops to the lower screen half. The mesh leans toward the reticle (pitch + yaw + bank roll). Frustum-clamped to its box after the spring.
- **CombatAttack** fires the equipped weapon toward the aim point.
- **Evade is a left/right pirouette dodge** (`_update_evade` + the evade block in `_process_ship`). A **left-stick flick** past `evade_trigger_deadzone` fires a one-shot evade in that direction: the ship slides laterally to a peak and springs back (`evade_lateral_distance`, `sin(p·π)` out-and-back) while spinning a full pirouette **about its up axis** (`evade_spins`, composed as `Basis(Vector3.UP, spin)` — a "screw" turn, *not* a screen-plane cartwheel). It always runs to completion (no hold/cancel); the stick must relax below `evade_rearm_threshold` to fire again. **Orientation handoff:** the lean is frozen at trigger time; the way *out* (`p≤0.5`) preserves it, the way *back* lerps to the now-current aim lean, so the ship lands correctly oriented with no snap. Throughout the evade you keep aiming and the camera keeps reacting — **only firing is gated off**; the FOV pulls back (`evade_fov_pullback`) and eases home. (The old grid/corner-anchor evade and the legacy `CombatEvade` impulse were both removed; the `CombatEvade` button-9 input mapping is now dead.)
- **Homing acquisition** (`_acquire_homing_target`) scans the **`destructible`** group, skips anything with `homing_eligible = false` or already defeated, and locks the candidate nearest the reticle **in screen space within a tight pixel radius** — so it never snaps to something far off to the side, and there's simply no lock (shots fly straight) when nothing is near the crosshair. The locked target is stored in `_homing_target` and exposed via `get_homing_target()` / `get_homing_target_screen_info()` for the HUD.
- **Hit react** is delegated to a shared **`HitReactComponent`** child (see Destructibles → Components) — the player calls `trigger()` on `take_damage` and `trigger_death()` on death, and feeds its **brake bob** in through the component's `extra_offset`. The component owns the red flash + mesh shake (+ optional particle bursts); the player keeps only the bob math. (The component is referenced **duck-typed** — `var _hit_react: Node` + `.call()/.set()` — to dodge the `class_name`-registration lag noted in Working style.)

**Input supports gamepad and keyboard/trackpad** (both bound on the same actions, so either works at any time):
- **Gamepad** — aim is the right stick; the **left stick (L/R) flicks the pirouette evade**; `CombatAttack` is button-10; `ToggleBrake` is the A button.
- **Keyboard/trackpad** (left-handed home-row layout) — aim is **mouse/trackpad motion** (captured on ready, **Escape** toggles release); **`J`/`L`** flick the evade left/right (mapped onto `MoveLeft`/`MoveRight`, which the flick-detector reads as full deflection); **`Space`** fires; **`K`** toggles the brake.

The reticle only tracks the trackpad while the mouse is captured. `CombatAttack` also keeps a legacy left-click binding, so a trackpad click fires too. (The old IJKL/keyboard movement and the legacy `CombatEvade` button-9 mapping remain dead.)

Inspector-tunable knobs are deliberately dense and live under `@export_category` blocks: Movement, Aiming, Ship Follow, Camera React, Combat, Brake Bob, Evade, References (the hit flash/shake knobs now live on the `HitReactComponent`). The user iterates heavily in the Inspector.

### HUD (`ui/CombatUI.tscn`, `ui/combat_ui.gd`)

A `CanvasLayer` reading the player each frame:
- **Health** — a `HEALTH: ###` label top-left, polled from the player's `hp` every frame (`_update_health`, same polling pattern as the crosshair — not signal-driven).
- **Crosshair** — the single `○` reticle at `get_reticle_screen_position()`; stays visible during an evade (aiming continues; `is_evading()` is only a fire-gate now).
- **Lock-on indicator** — a rotating, flashing yellow square pinned to the homing target's screen position. Built as a **zero-size `LockOn` Control** placed *on* the target with a centered `Square` child: rotating the parent spins the square in place (no pivot/size math → no orbit, the bug that bit us). The square pops in 1.6→1.0 with a **Back-ease overshoot** (child scale), and the parent scales by target distance (near = big, far = small, clamped). Vanishes instantly — no exit anim — when the lock is lost, destroyed, or switches.

### Weapons (`objects/weapons/`)

- **`FseBaseWeapon`** (`base/BaseWeapon.gd`) — data-driven via a `WeaponData` (`resources/WeaponData.gd`) resource. Exposes `try_fire(aim_direction)`, `should_fire_for_input(pressed, just_pressed)`, and an optional per-frame `homing_target` that's passed through to spawned projectiles that support it.
- **`FseBaseProjectile`** (`base/BaseProjectile.gd`) — straight-flying. Damage dispatches **both** ways so one base works for both sides:
  - `area_entered` → enemy `HitBox.receive_hit(amount)`
  - `body_entered` → bodies in `group_to_damage` exposing `take_damage` / `receive_attack` / `on_damage`
- **`HomingProjectile`** (`player/homing_projectile.gd`) — extends `FseBaseProjectile`, curves toward `homing_target` at a capped `turn_rate_deg`. The cap is the design feature: close/slow targets get caught; far/fast targets out-run the correction. That's the Space-Harrier "closer = more likely to hit" feel — emergent from the cap, not from explicit probability.
- Enemy projectile variants in `objects/weapons/enemy/` (`EnemyBoltBlue/Orange/Green.tscn`) — coloured straight projectiles with particle trails.

### Destructibles: enemies, obstacles, turret-projectiles (`objects/enemy/`, `objects/obstacles/`, `objects/weapons/enemy/`)

A **component-assembled** system. Everything the player can shoot shares one base, `FseDestructible`, and is built as an **inherited scene** so the visible body is a real editor-visible child node — no runtime `PackedScene.instantiate()` for the mesh.

**`base/fse_destructible.gd` (`class_name FseDestructible`, extends `CharacterBody3D`)** — the shared spine:
- Lifecycle states `{ INACTIVE, ACTIVE, DYING, PASSED }` (PASSED = camera flew past; components stop, body stays in scene).
- HP / `take_damage(amount, is_blast := false)` with console-logged transitions, plus a public `destroy()` that runs the full death sequence without going through HP (kamikaze-on-contact). A **`blast_only`** flag (the "green" blast category) makes it ignore all non-blast damage (still plays a hit cue).
- Emits **`hit(amount)`** when damage lands and **`died`** on death — the per-instance hooks `HitReactComponent` (flash/shake/bursts) and `BlastComponent` (explosion) connect to. The death sequence detaches SFX (and any `VfxEmitter`) into the scene root so they outlive the freed body.
- `homing_eligible` flag (default true) — the player's homing filters on it.
- Registers into the **`destructible`** group.
- **Duck-typed lifecycle broadcast**: `_dispatch_active(bool)` calls `set_active(bool)` on any component child. New drivers plug in just by implementing that method — the base needs no per-component knowledge.

Subclasses:
- **`FseEnemy`** (`objects/enemy/base/base_enemy.gd`) — adds `enemy_data`, distance activation (`activation_distance`), and `setup(player)` wiring. Group `enemy`.
- **`FseObstacle`** (`objects/obstacles/base/fse_obstacle.gd`) — adds `is_destructible` (indestructible blocks ignore damage but still play a hit cue) and optional proximity activation. Group `obstacle`.
- **`FseTurretProjectile`** (`objects/weapons/enemy/fse_turret_projectile.gd`) — a *destructible* projectile (shootable + harmful) that follows a curve from its emitter; `launch_on_curve(curve, base, speed)` stamps the path and starts a lifetime timer.

Components (`objects/components/`) — shared building blocks (top-level, **not** enemy-only: the player uses `HitReactComponent` too). Most are driven by the `set_active(bool)` lifecycle; `HitReactComponent` / `BlastComponent` are instead **event-driven** off the base's `hit` / `died` signals (no `set_active`):
- **`HitBox`** — `Area3D` on the `enemy` layer; routes `receive_hit` → parent `take_damage`.
- **`MovementComponent`** — drives the body each frame via a pluggable `MovementPattern` resource.
- **`WeaponComponent`** — fires a projectile on a cadence; aim_at_player or muzzle-forward.
- **`ContactDamage`** — `Area3D` that damages overlapping bodies on a per-body cooldown. `consume_on_hit` frees the parent; `destroy_self_on_hit` triggers the parent's explosion (e.g. Swooper dive-bomb).
- **`AnimationDriver`** — plays a keyframed `AnimationPlayer` on activate / pauses on PASSED. Alternative to MovementComponent for hand-keyframed motion. **Don't pair both on one body** — they fight over the transform.
- **`TurretEmitter`** — spawns `FseTurretProjectile`s on a cadence, handing each the emitter's `Curve2D`; cycles an `Array[PackedScene]` so one turret can alternate bolt types. Does **not** aim at the player — the curve is the behavior.
- **`HitReactComponent`** — on the parent's `hit` (or a direct `trigger()`): a red flash (the `vfx/shaders/blink.gdshader` overlay — unshaded/`cull_disabled`, `flash_modifier` pulsed 1→0 — assigned to every `MeshInstance3D` under `mesh_root`) + a decaying mesh shake, plus optional one-shot `hit_burst` / `death_burst` particle scenes. `extra_offset` lets the owner layer extra motion (the player's bob). On `BaseEnemy` and the player.
- **`BlastComponent`** — on the parent's `died`: spawns a `Blast` actor (see Blast radius below) for the explosion + chain.
- **`VfxEmitter` / `SfxEmitter`** — keyed one-shot particle/audio players (`emit("death", detach=true)` etc.). `SfxEmitter` is on every enemy; `VfxEmitter` is **no longer on `BaseEnemy`** (enemy death visuals moved to `HitReactComponent.death_burst`) but is still used by obstacles / turret-bolts.

Movement patterns (`objects/enemy/movement/`) — `MovementPattern` Resource base + `WeaveMovement`, `SwoopMovement`, `StrafeMovement`, `BobMovement` (player-independent sine oscillation, for obstacles), `CurveFollowMovement` (samples a `Curve2D` by arc length, for turret bolts). Swap one on a `MovementComponent` in the Inspector.

Concrete enemies (`objects/enemy/enemies/`): **Weaver** (weave, single shot), **Swooper** (dive + `ContactDamage` with `destroy_self_on_hit`), **Turret** (strafe, volley). Each has an `*.tres` `FseEnemyData` (`objects/enemy/EnemyData.gd`) for `max_hp`, `move_speed`, `contact_damage`, `score`.

Obstacles (`objects/obstacles/`): **BobBlock** (MovementComponent + BobMovement), **AnimObstacle** (AnimationDriver + keyframed clip), **StationaryTurret** (a stationary `FseObstacle` with a `TurretEmitter` firing curve-following `TurretBolt`s). `TurretBolt` (`objects/weapons/enemy/TurretBolt.tscn`) is destructible but sets `homing_eligible = false` so the player can't lock onto incoming fire.

### Blast radius & chain reactions (`objects/enemy/blast/`, `objects/components/blast_component.gd`)

A chain-reaction explosion mechanic. Enemies fall into three blast categories:
- **Yellow** — destructible, no blast (a `HitReactComponent`, no `BlastComponent`).
- **Red** — destructible *and* spawns a blast on death (`BlastComponent`).
- **Green** — `blast_only = true`: immune to normal fire, dies *only* to a blast.

`BlastComponent` connects to the parent's `died` signal and spawns a transient **`Blast`** (`objects/enemy/blast/Blast.tscn` + `blast.gd`, `class_name FseBlast`) at the corpse, detached into the scene root so it outlives the body. After a small `detonation_delay` (gives chains a visible ripple) the Blast damages every `destructible` whose center is within `radius` via `take_damage(dmg, is_blast = true)` — which reaches greens and re-detonates other reds, cascading. Already-`DYING`/defeated targets are skipped, so chains terminate. The Blast parents a `BurstVfx` (`vfx/particles/blast.tscn`) it fires one-shot. Sizes scale together (small Ø3 / 10 dmg / 10 hp … large Ø12 / 90 dmg / 90 hp). Prototype `SmallYellow/Red/Green` enemies live in `objects/enemy/enemies/explore-blast-radius/`.

### Combat collision layers (defined in `project.godot`)

| # | Name | Used by |
|---|---|---|
| 1 | `environment` | static world (currently unused) |
| 2 | `player` | `MechaPlayer` body |
| 3 | `enemy` | enemy `HitBox` areas |
| 4 | `player_projectile` | player projectile areas (mask scans `enemy`) |
| 5 | `enemy_projectile` | enemy projectile areas (mask scans `player`) |

### Exploration prototypes (`explores/`)

Standalone sandboxes for in-progress R&D — not loaded by `main.tscn`:
- `explore-animation/` — IK / procedural animation tests (mecha-rigging reference).
- `explore-vfx/` — particle/effect studies.
- `explore-shaders/` — `outline-posterize-color-dither.gdshader` (Sobel + posterize + Bayer dither — fullscreen quad in front of the camera; **conflicts with Volumetric Fog** unless `fog_disabled` is added to `render_mode`; long-term move to a `CompositorEffect`), plus `simple-water.gdshader` and `grass.gdshader`.

### Third-party / in-progress

- **`addons/GPUTrail/`** — vendored [GPUTrail3D](https://github.com/) addon for GPU-driven ribbon trails (projectiles, evade streaks); not wired into `main.tscn` yet.
- **`assets/models/rails/mecha/mecha-frame.glb`** — the imported mecha frame. Rail level geometry also lives under `assets/models/rails/`.

### Curved-rail authoring (`addons/nurbs_path/`)

An in-editor `@tool` plugin for composing the curved rails the player follows.
Add a **`NurbsPath3D`** node (a `Path3D` subclass) and author its rail as a
**control polygon** instead of hand-tuning Bézier tangents:
- The node holds an `Array[Vector3] control_points` + a `closed` flag and, on any
  change, rebuilds its own `Curve3D` (`nurbs_path_3d.gd`). It's a **uniform cubic
  B-spline**, which converts *exactly* — segment-for-segment — into the cubic
  Bézier that `Curve3D` stores, so there's **no sampling error**. `PathFollow3D`
  + `levels/rail_follower.gd` consume the baked `curve` with zero changes.
- Open curves are **clamped** (reflected phantom endpoints) so the rail starts/ends
  on the first/last control point; `closed` wraps into a seamless loop (pair with
  PathFollow3D `loop = true`). Interior control points are *approximated*, not
  interpolated — that's the B-spline trade that removes per-point tangent fiddling.
- **Editing** is a viewport gizmo (`nurbs_path_gizmo.gd`): drag a handle per control
  point (free move on a camera-facing plane, with undo/redo); **Shift+Left-click**
  in the viewport appends a point (`nurbs_path_plugin.gd`, `_forward_3d_gui_input`,
  raycast onto a horizontal plane at the last point's height). Removing points is
  via the Inspector `control_points` array for now.
- Despite the name it's the **non-rational** case (no weights) — rational NURBS
  (exact circular arcs) would add a `weights` array baked by sampling; omitted
  because rails don't need it. The plugin/gizmo reference the node **duck-typed**
  (matched by script resource, not `class_name`) to dodge the class-cache lag.
- This is the in-editor counterpart to the longer-horizon "Blender→JSON→`Curve3D`"
  idea below — same `Curve3D` target, no round-trip.

### Legacy code still present (not active in `main.tscn`)

- **Dialogue system** (`objects/triggers/dialogue/`, `ui/DialogueBox.tscn`, `resources/dialogue/`) — `DialogueTrigger` + `Events` lifecycle exists from the source project; not used by the current scene. Keep around in case dialogue between rail segments becomes a feature.

## Global groups

`"player"`, `"enemy"`, `"obstacle"`, `"destructible"`, `"level"` — registered automatically (player in scene definition; `destructible` in `FseDestructible._ready`; `enemy`/`obstacle` in the respective subclass). The player's homing scans `destructible`; lookups use `get_tree().get_first_node_in_group(...)` / `get_nodes_in_group(...)`.

## Conventions

- GDScript with **static typing** throughout. Untyped declarations warn.
- `class_name` prefixes use `Fse*` (legacy from the source project) — keep the convention for consistency.
- Cross-system signals go through `Events` rather than direct node-to-node connections.
- Scene files for exploration live under `explores/`; production game objects under `objects/{player,enemy,obstacles,weapons,triggers,components}/`.
- Component scripts attach by `script` on a child node and resolve siblings/parents in `_ready`; the `FseDestructible` parent coordinates them via the duck-typed `set_active(bool)` broadcast — a new driver only needs that one method.
- Imported content lives under `assets/` (`assets/models/`, `assets/sounds/`, …); editor plugins under `addons/`. Exported `.glb`/`.obj` land under `assets/models/` (`assets/models/rails/` holds level geometry).

## Working style notes

- Tuning happens in the **Inspector**, not in code — keep `@export` knobs front-and-center for new behavior. The user iterates by playing, tweaking, re-playing.
- The user prefers **small, reviewable changes** over big batches. Show a diff before committing when in doubt.
- **Never commit without explicit permission.** The user reviews changes manually.
- Verify with MCP: `run_project` then `game_eval` in **separate turns** (the MCP server takes a moment to connect after launch — eval calls in the same batch as `run_project` will fail with "Not connected").
- Avoid concurrent edits to the same file in one batch — they race and the second one's "file has been modified since read" error can leave half-applied changes.
- The Godot debugger break-on-error is enabled; a single parse error in eval-injected GDScript can pause the running game. Keep eval snippets short and avoid mixing tabs/spaces.
- **New-script `.uid` gotcha**: a freshly-written `.gd` with a `class_name` won't register until Godot generates its `.uid` — until then, scenes that subclass it fail with "Could not find base class". The MCP `get_uid` / `update_project_uids` tools sometimes generate it and sometimes report "Found 0 scripts". When they fail, write the `.uid` file directly (`uid://<unique-token>`, check for collisions). Scenes referencing scripts by **path** still load (only cosmetic "invalid UID" warnings), so the `.uid` mainly matters for `class_name` resolution. The same lag bites a **`class_name` used as a *type* in another script** (`var x: HitReactComponent`) — it errors "Could not find type …" until the global class cache catches up (a bare `run_project` doesn't refresh it). **Duck-typing the reference** (`var x: Node` + `.call()/.set()`) sidesteps it.
- During verification, enemies kill the player fast, which fires `Events.player_killed` → `get_tree().quit()` and ends the run mid-eval. For sustained inspection, set the player's `hp`/`max_hp` huge and halt the rail in a `game_eval` first (set the `PathFollow3D`'s `braked = true`, or `speed = 0`).

## Current direction

The earlier numbered "phase roadmap" is retired — the core systems it tracked (rail player, rigged camera, component enemies/destructibles, aim-led control, lock-on HUD) are all in and stable; see git history for how they landed.

Active work:
- **Blast radius / chain reactions** — the yellow/red/green blast-category enemies + `BlastComponent` / `Blast` are in; prototyped in `objects/enemy/enemies/explore-blast-radius/` with a test cluster in `main.tscn`. Building out the `blast.tscn` burst VFX, and (next) the Medium/Large size variants.
- **Shared component layer** — the behavior components moved to `objects/components/` so the player can share them (`HitReactComponent`). Enemy death VFX consolidated onto `HitReactComponent.death_burst` (the old per-enemy `VfxEmitter` death particles were removed).
- **Level blockout** — in progress in Blender (sources not tracked in-repo; exports land under `assets/models/`).
- **Player feel** — health readout, hit-react (now the shared `HitReactComponent`: flash + shake + hit/death particle bursts), a velocity-driven rail with a `ToggleBrake` brake, and the combat-only left/right pirouette evade (all in the Player rig section above). Puzzle gameplay is no longer tied to evade. Future evade work: VFX, possible i-frames, and tuning enemies like the Swooper so its dive-bombs can be cleanly dodged.

Longer-horizon ideas (unordered): curved Bézier rails (Blender→JSON→`Curve3D`), independent `Progress Speed`, a PursuitEnemy miniboss, more weapons, object-grabbing, time-manipulation tools, powerups, mecha rigging/procedural animation (`mecha-frame.glb` imported; `TwoBoneIK3D` / `LookAtModifier3D` / `BoneAttachment3D`), and two more levels.
