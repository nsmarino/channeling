# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

**time-rails** is a Godot 4.6 (Forward+) arcade rail shooter in the style of *Sin & Punishment: Star Successor*, *Kid Icarus: Uprising*, *Panzer Dragoon*, and *Space Harrier*. The player pilots a mecha along a forward-moving rail through a sci-fi anime world of twisted pines and shattered ruins. The finished prototype targets three levels with strong replay value; goals lean heavily on **visual effects (particle systems, shaders)** and **a variety of fun weapons and enemy types** to experiment with.

Main scene: `levels/main.tscn`. The project ships a Godot MCP server (`mcp__godot__*`) for AI-assisted iteration — prefer MCP tools (`run_project`, `game_eval`, `game_screenshot`) for verification over raw shell work.

## Running & Tooling

- **Open in editor**: launch Godot 4.6, or `mcp__godot__launch_editor`. Run with `mcp__godot__run_project`.
- **Open Blender source**: `make blend` (or `./open-blends`) — opens `blender/level/level.blend` and `blender/models/props.blend` once those files exist. Blender sources live under `blender/` (currently `blockout.blend`).
- **Godot version**: 4.6.stable.official — GDScript with **typed declarations throughout**; untyped is treated as a warning.

## Architecture

### Autoloads
- **`Events`** (`autoloads/events.gd`) — central signal bus. Combat hits, enemy HP/damage, phase changes, dialogue lifecycle. Cross-system communication should go through here.
- **`GameManager`** (`autoloads/game_manager.gd`) — holds runtime references to the navigator (player `CharacterBody3D`) and overworld root.
- **`McpInteractionServer`** (`autoloads/mcp_interaction_server.gd`) — TCP server on `127.0.0.1:9090` for the Godot MCP tool. Many style warnings emanate from this file; **treat its warnings as noise** when triaging.

### Player rig (`objects/overworld/player/mecha/`)

**Aim-led, Star Fox / Panzer Dragoon model** — the reticle is the only directly-driven element; the ship follows it and the camera reacts to it. (This replaced the earlier dual-cursor system where ship and reticle were steered independently.)

```
Main
└─ Level
   └─ Path3D (curve = the rail)
      └─ PathFollow3D (progress_ratio animated 0→1 by Main/AnimationPlayer/MoveF)
         └─ PlayerRoot (Node3D)
            ├─ Navigator (MechaPlayer.tscn — the ship, group "player")
            └─ Camera3D
               └─ AimTarget (Node3D — the reticle's world position)
```

`mecha_player.gd` per-frame order is **aim → camera → ship → combat** (the ship reads the camera's banked transform, so the camera must rotate first):
- **Aim** (`_process_aim`): right stick (`LookLeft/Right/Up/Down`) + mouse motion (`_input`, captured on `_ready`, **Escape** toggles) drive `_aim_cursor` across the aim plane, frustum-clamped to the full view. Persistent by default; `recenter_rate` eases it back to center when idle (0 = fully persistent).
- **Camera** (`_process_camera`): eased, capped roll/pitch/yaw computed from the normalized aim (`camera_roll_max_deg` etc.). Written as **local** rotation so it composes additively on top of any rail bank the PathFollow3D/PlayerRoot applies.
- **Ship** (`_process_ship`): targets `_aim_cursor * ship_follow_fraction` (a smaller sub-box) with a snappy spring (`ship_follow_lerp`), corrected by the plane-distance ratio so it stays on-screen. Sits `ship_below_offset` (~1u) *below* the reticle so it doesn't occlude the target — the offset fades out as the reticle drops to the lower screen half. The mesh leans toward the reticle (pitch + yaw + bank roll). Frustum-clamped to its box after the spring.
- **CombatAttack** fires the equipped weapon toward the aim point.
- **Evade is a left/right pirouette dodge** (`_update_evade` + the evade block in `_process_ship`). A **left-stick flick** past `evade_trigger_deadzone` fires a one-shot evade in that direction: the ship slides laterally to a peak and springs back (`evade_lateral_distance`, `sin(p·π)` out-and-back) while spinning a full pirouette **about its up axis** (`evade_spins`, composed as `Basis(Vector3.UP, spin)` — a "screw" turn, *not* a screen-plane cartwheel). It always runs to completion (no hold/cancel); the stick must relax below `evade_rearm_threshold` to fire again. **Orientation handoff:** the lean is frozen at trigger time; the way *out* (`p≤0.5`) preserves it, the way *back* lerps to the now-current aim lean, so the ship lands correctly oriented with no snap. Throughout the evade you keep aiming and the camera keeps reacting — **only firing is gated off**; the FOV pulls back (`evade_fov_pullback`) and eases home. (The old grid/corner-anchor evade and the legacy `CombatEvade` impulse were both removed; the `CombatEvade` button-9 input mapping is now dead.)
- **Homing acquisition** (`_acquire_homing_target`) scans the **`destructible`** group, skips anything with `homing_eligible = false` or already defeated, and locks the candidate nearest the reticle **in screen space within a tight pixel radius** — so it never snaps to something far off to the side, and there's simply no lock (shots fly straight) when nothing is near the crosshair. The locked target is stored in `_homing_target` and exposed via `get_homing_target()` / `get_homing_target_screen_info()` for the HUD.

**Input is gamepad-only.** IJKL / keyboard movement and the spacebar evade were removed. The **left stick (L/R) drives the pirouette evade**; aim is the right stick + mouse.

Inspector-tunable knobs are deliberately dense and live under `@export_category` blocks: Movement, Aiming, Ship Follow, Camera React, Combat, Evade, References. The user iterates heavily in the Inspector.

### HUD (`ui/overworld/CombatUI.tscn`, `combat_ui.gd`)

A `CanvasLayer` reading the player each frame:
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
- HP / `take_damage` with console-logged transitions, and a public `destroy()` that runs the full death sequence without going through HP (for kamikaze-on-contact).
- Death detaches VFX/SFX into the scene root so they survive the freed body.
- `homing_eligible` flag (default true) — the player's homing filters on it.
- Registers into the **`destructible`** group.
- **Duck-typed lifecycle broadcast**: `_dispatch_active(bool)` calls `set_active(bool)` on any component child. New drivers plug in just by implementing that method — the base needs no per-component knowledge.

Subclasses:
- **`FseEnemy`** (`objects/enemy/base/base_enemy.gd`) — adds `enemy_data`, distance activation (`activation_distance`), and `setup(player)` wiring. Group `enemy`.
- **`FseObstacle`** (`objects/obstacles/base/fse_obstacle.gd`) — adds `is_destructible` (indestructible blocks ignore damage but still play a hit cue) and optional proximity activation. Group `obstacle`.
- **`FseTurretProjectile`** (`objects/weapons/enemy/fse_turret_projectile.gd`) — a *destructible* projectile (shootable + harmful) that follows a curve from its emitter; `launch_on_curve(curve, base, speed)` stamps the path and starts a lifetime timer.

Components (`objects/enemy/components/`) — all driven by the same `set_active(bool)` lifecycle:
- **`HitBox`** — `Area3D` on the `enemy` layer; routes `receive_hit` → parent `take_damage`.
- **`MovementComponent`** — drives the body each frame via a pluggable `MovementPattern` resource.
- **`WeaponComponent`** — fires a projectile on a cadence; aim_at_player or muzzle-forward.
- **`ContactDamage`** — `Area3D` that damages overlapping bodies on a per-body cooldown. `consume_on_hit` frees the parent; `destroy_self_on_hit` triggers the parent's explosion (e.g. Swooper dive-bomb).
- **`AnimationDriver`** — plays a keyframed `AnimationPlayer` on activate / pauses on PASSED. Alternative to MovementComponent for hand-keyframed motion. **Don't pair both on one body** — they fight over the transform.
- **`TurretEmitter`** — spawns `FseTurretProjectile`s on a cadence, handing each the emitter's `Curve2D`; cycles an `Array[PackedScene]` so one turret can alternate bolt types. Does **not** aim at the player — the curve is the behavior.
- **`VfxEmitter` / `SfxEmitter`** — keyed one-shot players (`emit("death", detach=true)` etc.).

Movement patterns (`objects/enemy/movement/`) — `MovementPattern` Resource base + `WeaveMovement`, `SwoopMovement`, `StrafeMovement`, `BobMovement` (player-independent sine oscillation, for obstacles), `CurveFollowMovement` (samples a `Curve2D` by arc length, for turret bolts). Swap one on a `MovementComponent` in the Inspector.

Concrete enemies (`objects/enemy/enemies/`): **Weaver** (weave, single shot), **Swooper** (dive + `ContactDamage` with `destroy_self_on_hit`), **Turret** (strafe, volley). Each has an `*.tres` `FseEnemyData` (`objects/enemy/EnemyData.gd`) for `max_hp`, `move_speed`, `contact_damage`, `score`.

Obstacles (`objects/obstacles/`): **BobBlock** (MovementComponent + BobMovement), **AnimObstacle** (AnimationDriver + keyframed clip), **StationaryTurret** (a stationary `FseObstacle` with a `TurretEmitter` firing curve-following `TurretBolt`s). `TurretBolt` (`objects/weapons/enemy/TurretBolt.tscn`) is destructible but sets `homing_eligible = false` so the player can't lock onto incoming fire.

### Combat collision layers (defined in `project.godot`)

| # | Name | Used by |
|---|---|---|
| 1 | `environment` | static world (currently unused) |
| 2 | `player` | `MechaPlayer` body |
| 3 | `enemy` | enemy `HitBox` areas |
| 4 | `player_projectile` | player projectile areas (mask scans `enemy`) |
| 5 | `enemy_projectile` | enemy projectile areas (mask scans `player`) |

### Exploration prototypes (`objects/explore-*/`)

Standalone sandboxes for in-progress R&D — not loaded by `main.tscn`:
- `explore-animation/` — IK / procedural animation tests (mecha-rigging reference).
- `explore-vfx/` — particle/effect studies.
- `explore-shaders/` — `outline-posterize-color-dither.gdshader` (Sobel + posterize + Bayer dither — fullscreen quad in front of the camera; **conflicts with Volumetric Fog** unless `fog_disabled` is added to `render_mode`; long-term move to a `CompositorEffect`), plus `simple-water.gdshader` and `grass.gdshader`.

### Third-party / in-progress

- **`GPUTrail-main/`** — vendored [GPUTrail3D](https://github.com/) addon for GPU-driven ribbon trails (projectiles, evade streaks). `test-ribbons.tscn` (project root) is the scratch sandbox for it; not wired into `main.tscn` yet.
- **`models/rails/mecha/mecha-frame.glb`** — the imported mecha frame. Rail level geometry also lives under `models/rails/` (e.g. `kelp-walls.glb`).

### Legacy code still present (not active in `main.tscn`)

- **Dialogue system** (`objects/overworld/triggers/dialogue/`, `ui/overworld/DialogueBox.tscn`, `resources/dialogue/`) — `DialogueTrigger` + `Events` lifecycle exists from the source project; not used by the current scene. Keep around in case dialogue between rail segments becomes a feature.

## Global groups

`"player"`, `"enemy"`, `"obstacle"`, `"destructible"`, `"level"` — registered automatically (player in scene definition; `destructible` in `FseDestructible._ready`; `enemy`/`obstacle` in the respective subclass). The player's homing scans `destructible`; lookups use `get_tree().get_first_node_in_group(...)` / `get_nodes_in_group(...)`.

## Conventions

- GDScript with **static typing** throughout. Untyped declarations warn.
- `class_name` prefixes use `Fse*` (legacy from the source project) — keep the convention for consistency.
- Cross-system signals go through `Events` rather than direct node-to-node connections.
- Scene files for exploration live under `objects/explore-*/`; production game objects under `objects/{overworld,enemy,weapons,base,components}/`.
- Component scripts attach by `script` on a child node and resolve siblings/parents in `_ready`; the `FseDestructible` parent coordinates them via the duck-typed `set_active(bool)` broadcast — a new driver only needs that one method.
- Blender source under `blender/`; exported `.glb`/`.obj` land in the project root or `models/` (`models/rails/` holds level geometry).

## Working style notes

- Tuning happens in the **Inspector**, not in code — keep `@export` knobs front-and-center for new behavior. The user iterates by playing, tweaking, re-playing.
- The user prefers **small, reviewable changes** over big batches. Show a diff before committing when in doubt.
- **Never commit without explicit permission.** The user reviews changes manually.
- Verify with MCP: `run_project` then `game_eval` in **separate turns** (the MCP server takes a moment to connect after launch — eval calls in the same batch as `run_project` will fail with "Not connected").
- Avoid concurrent edits to the same file in one batch — they race and the second one's "file has been modified since read" error can leave half-applied changes.
- The Godot debugger break-on-error is enabled; a single parse error in eval-injected GDScript can pause the running game. Keep eval snippets short and avoid mixing tabs/spaces.
- **New-script `.uid` gotcha**: a freshly-written `.gd` with a `class_name` won't register until Godot generates its `.uid` — until then, scenes that subclass it fail with "Could not find base class". The MCP `get_uid` / `update_project_uids` tools sometimes generate it and sometimes report "Found 0 scripts". When they fail, write the `.uid` file directly (`uid://<unique-token>`, check for collisions). Scenes referencing scripts by **path** still load (only cosmetic "invalid UID" warnings), so the `.uid` mainly matters for `class_name` resolution.
- During verification, enemies kill the player fast, which fires `Events.player_killed` → `get_tree().quit()` and ends the run mid-eval. For sustained inspection, set the player's `hp`/`max_hp` huge and `pause()` the rail AnimationPlayer in a `game_eval` first.

## Current direction

The earlier numbered "phase roadmap" is retired — the core systems it tracked (rail player, rigged camera, component enemies/destructibles, aim-led control, lock-on HUD) are all in and stable; see git history for how they landed.

Active work:
- **Encounter choreography** — hand-built graybox enemy-wave scenes under `objects/enemy/prototyping/` (`example-enemy-group*`, `scene-4`) instanced into `main.tscn`. These are rough primitive/`AnimationPlayer` blockouts for sketching wave timing and layout, *not* yet wired into the `FseEnemy`/`FseDestructible` component system.
- **Level blockout** — `blender/blockout.blend` (in progress).
- **Player feel** — evade is now a combat-only left/right pirouette dodge (see Player rig above); puzzle gameplay is no longer tied to evade. Future evade work: VFX, possible i-frames, and tuning enemies like the Swooper so its dive-bombs can be cleanly dodged.

Longer-horizon ideas (unordered): curved Bézier rails (Blender→JSON→`Curve3D`), independent `Progress Speed`, a PursuitEnemy miniboss, more weapons, object-grabbing, time-manipulation tools, powerups, mecha rigging/procedural animation (`mecha-frame.glb` imported; `TwoBoneIK3D` / `LookAtModifier3D` / `BoneAttachment3D`), and two more levels.
