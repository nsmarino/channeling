# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

**time-rails** is a Godot 4.6 (Forward+) arcade rail shooter in the style of *Sin & Punishment: Star Successor*, *Kid Icarus: Uprising*, *Panzer Dragoon*, and *Space Harrier*. The player pilots a mecha along a forward-moving rail through a sci-fi anime world of twisted pines and shattered ruins. The finished prototype targets three levels with strong replay value; goals lean heavily on **visual effects (particle systems, shaders)** and **a variety of fun weapons and enemy types** to experiment with.

Main scene: `levels/main.tscn`. The project ships a Godot MCP server (`mcp__godot__*`) for AI-assisted iteration — prefer MCP tools (`run_project`, `game_eval`, `game_screenshot`) for verification over raw shell work.

## Running & Tooling

- **Open in editor**: launch Godot 4.6, or `mcp__godot__launch_editor`. Run with `mcp__godot__run_project`.
- **Open Blender source**: `make blend` (or `./open-blends`) — opens `blender/level/level.blend` and `blender/models/props.blend` once those files exist. Phase 3 will populate `blender/` with the mecha source.
- **Godot version**: 4.6.stable.official — GDScript with **typed declarations throughout**; untyped is treated as a warning.

## Architecture

### Autoloads
- **`Events`** (`autoloads/events.gd`) — central signal bus. Combat hits, enemy HP/damage, phase changes, dialogue lifecycle. Cross-system communication should go through here.
- **`GameManager`** (`autoloads/game_manager.gd`) — holds runtime references to the navigator (player `CharacterBody3D`) and overworld root.
- **`McpInteractionServer`** (`autoloads/mcp_interaction_server.gd`) — TCP server on `127.0.0.1:9090` for the Godot MCP tool. Many style warnings emanate from this file; **treat its warnings as noise** when triaging.

### Player rig (`objects/overworld/player/mecha/`)

The signature interaction is a **dual screen-space cursor system**:

```
Main
└─ PlayerRoot (Node3D, animated forward by AnimationPlayer/MoveF)
   ├─ Navigator (MechaPlayer.tscn — the ship, group "player")
   └─ Camera3D
      └─ AimTarget (Node3D — the reticle's world position)
```

`mecha_player.gd` script highlights:
- The **ship** and the **reticle** are both points on planes a fixed distance in front of the camera (`player_plane_distance`, `aim_plane_distance`), steered in camera-local X/Y and clamped to the camera frustum at that depth (`_move_cursor` / `_frustum_extents`). Because the camera rides `PlayerRoot`, banking/translation on a curved rail will be inherited automatically (Phase 3 work).
- Ship cursor → `MoveLeft/Right/Up/Down` (left stick + IJKL).
- Aim cursor → `LookLeft/Right/Up/Down` (right stick) **plus** mouse motion via `_input`; mouse is captured on `_ready`, **Escape** toggles release.
- **CombatAttack** fires the equipped weapon toward the aim point.
- **CombatEvade** seeds a decaying linear impulse on the ship cursor in the current direction of travel (fallback: straight up). The standard frustum clamp re-applies after integration, so an evade cannot cross the play box.
- **Homing acquisition** (`_acquire_homing_target`) finds the enemy nearest the reticle in screen space within an aim cone, and sets it on the equipped weapon each frame — so non-locked shots fly straight.

Inspector-tunable knobs are deliberately dense and live under `@export_category` blocks: Movement, Aiming, Combat, Evade, References. The user iterates heavily in the Inspector.

### Weapons (`objects/weapons/`)

- **`FseBaseWeapon`** (`base/BaseWeapon.gd`) — data-driven via a `WeaponData` (`resources/WeaponData.gd`) resource. Exposes `try_fire(aim_direction)`, `should_fire_for_input(pressed, just_pressed)`, and an optional per-frame `homing_target` that's passed through to spawned projectiles that support it.
- **`FseBaseProjectile`** (`base/BaseProjectile.gd`) — straight-flying. Damage dispatches **both** ways so one base works for both sides:
  - `area_entered` → enemy `HitBox.receive_hit(amount)`
  - `body_entered` → bodies in `group_to_damage` exposing `take_damage` / `receive_attack` / `on_damage`
- **`HomingProjectile`** (`player/homing_projectile.gd`) — extends `FseBaseProjectile`, curves toward `homing_target` at a capped `turn_rate_deg`. The cap is the design feature: close/slow targets get caught; far/fast targets out-run the correction. That's the Space-Harrier "closer = more likely to hit" feel — emergent from the cap, not from explicit probability.
- Enemy projectile variants in `objects/weapons/enemy/` (`EnemyBoltBlue/Orange/Green.tscn`) — coloured straight projectiles with particle trails.

### Enemies (`objects/enemy/`)

Rebuilt for the rails shooter as a **component-assembled** system; the old navmesh/melee `fse_enemy.gd` stack was archived. Each enemy is an **inherited scene** of `base/BaseEnemy.tscn`, so the visible body is a real editor-visible child node — no runtime `PackedScene.instantiate()` for the mesh.

`base/base_enemy.gd` (`class_name FseEnemy`):
- Lifecycle: `INACTIVE → ACTIVE → DYING` plus `PASSED` (when the camera flies past — components stop, body stays in scene).
- Distance-based self-activation via `activation_distance`.
- HP / `take_damage` with console-logged transitions; death detaches VFX/SFX into the scene root so they survive the freed enemy.
- Components are optional children resolved by name (HitBox, MovementComponent, WeaponComponent, VfxEmitter, SfxEmitter).

Components (`objects/enemy/components/`):
- **`HitBox`** — `Area3D` on the `enemy` collision layer; calls `take_damage` on the parent on `receive_hit`.
- **`MovementComponent`** — drives the body each frame using a pluggable `MovementPattern` resource.
- **`WeaponComponent`** — fires a projectile scene on a cadence; aim_at_player or muzzle-forward.
- **`VfxEmitter` / `SfxEmitter`** — keyed one-shot players (`emit("death", detach=true)` etc.).

Movement patterns (`objects/enemy/movement/`) — `MovementPattern` Resource base + subclasses `WeaveMovement`, `SwoopMovement`, `StrafeMovement`. Swap one on a `MovementComponent` in the Inspector to change behavior without touching code.

Concrete enemies (`objects/enemy/enemies/`): **Weaver** (blue sphere, weave, single shot), **Swooper** (orange cone, dive, burst), **Turret** (green box, strafe, volley). Each has an `*.tres` `FseEnemyData` (`objects/enemy/EnemyData.gd`) for `max_hp`, `move_speed`, `contact_damage`, `score`.

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
- `explore-animation/` — IK / procedural animation tests (Phase 3 reference).
- `explore-vfx/` — particle/effect studies.
- `explore-shaders/` — `outline-posterize-color-dither.gdshader` (Sobel + posterize + Bayer dither — fullscreen quad in front of the camera; **conflicts with Volumetric Fog** unless `fog_disabled` is added to `render_mode`; long-term move to a `CompositorEffect`), plus `simple-water.gdshader` and `grass.gdshader`.

### Legacy code still present (not active in `main.tscn`)

- **Dialogue system** (`objects/overworld/triggers/dialogue/`, `ui/overworld/DialogueBox.tscn`, `resources/dialogue/`) — `DialogueTrigger` + `Events` lifecycle exists from the source project; not used by the current scene. Keep around in case dialogue between rail segments becomes a feature.

## Global groups

`"player"`, `"enemy"`, `"level"` — registered automatically (player in scene definition, enemy in `FseEnemy._ready`). Lookups use `get_tree().get_first_node_in_group(...)` / `get_nodes_in_group(...)`.

## Conventions

- GDScript with **static typing** throughout. Untyped declarations warn.
- `class_name` prefixes use `Fse*` (legacy from the source project) — keep the convention for consistency.
- Cross-system signals go through `Events` rather than direct node-to-node connections.
- Scene files for exploration live under `objects/explore-*/`; production game objects under `objects/{overworld,enemy,weapons,base,components}/`.
- Component scripts attach by `script` on a child node and resolve siblings/parents in `_ready`; the parent (`FseEnemy`) coordinates them.
- Blender source under `blender/`; exported `.glb`/`.obj` land in the project root or `models/`.

## Working style notes

- Tuning happens in the **Inspector**, not in code — keep `@export` knobs front-and-center for new behavior. The user iterates by playing, tweaking, re-playing.
- The user prefers **small, reviewable changes** over big batches. Show a diff before committing when in doubt.
- **Never commit without explicit permission.** The user reviews changes manually.
- Verify with MCP: `run_project` then `game_eval` in **separate turns** (the MCP server takes a moment to connect after launch — eval calls in the same batch as `run_project` will fail with "Not connected").
- Avoid concurrent edits to the same file in one batch — they race and the second one's "file has been modified since read" error can leave half-applied changes.
- The Godot debugger break-on-error is enabled; a single parse error in eval-injected GDScript can pause the running game. Keep eval snippets short and avoid mixing tabs/spaces.

## Phase roadmap (where we are)

1. ✅ **Rail player** — bounded ship cursor, frustum-clamped aim reticle, projectile fire (commit `68a70b3`).
2. ✅ **Rigged camera + unified clamp** — camera rides `PlayerRoot`; ship & reticle share one clamp helper (`3ff5f3f`).
3. ✅ **Component enemies** — 3 enemies, homing projectiles, VFX/SFX on death (`617e8b6`, `bfa29b9`).
4. ✅ **Evade + mouse aim + tuning** — `CombatEvade` impulse, mouse-driven reticle, widened homing cone, slower rail (`f58e4c5`).
5. ⏳ **Mecha in Blender + procedural animation** — rig in Blender, import to Godot, drive with `TwoBoneIK3D` / `LookAtModifier3D` / `BoneAttachment3D` instead of canned clips. Companion VFX for the evade.
6. Future: more weapons, object-grabbing, time-manipulation tools, two more levels.
