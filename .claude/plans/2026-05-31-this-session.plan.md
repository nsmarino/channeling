# Phase 2 — Component-Based Enemies, VFX, Homing Projectiles

## Goal
Three unique enemies (distinct body, movement, attack, projectile+particle, death+particle) encountered as the player advances, plus Space-Harrier-style homing player projectiles. No resource UI — console logging only.

## Decisions locked (from AskUserQuestion)
- **Rebuild the BaseEnemy stack** for rails (drop navmesh/pursue/wander/leash/melee). Keep HP / `take_damage` / death-signal / `Events` / SFX ideas.
- **Pluggable resource patterns** for movement (and simple cadence config for weapons).
- **Homing**: reticle cone + nearest enemy, capped turn rate (close = caught, far = escapes — emergent feel).
- **Encounters**: hand-placed enemies, self-activating by distance (editor-visible, per-enemy trigger).

---

## Architecture

### Collision layers (define names in `project.godot`)
1 `environment` · 2 `player` · 3 `enemy` · 4 `player_projectile` · 5 `enemy_projectile`
- Enemy `HitBox` Area3D: layer **enemy**, scans nothing.
- Player projectile Area3D: layer **player_projectile**, mask **enemy**.
- Enemy projectile Area3D: layer **enemy_projectile**, mask **player**.

### New lean base: `BaseEnemy.tscn` + `base_enemy.gd`
`CharacterBody3D` (group `enemy`), **no mesh** (added by inherited scenes → editor-visible). State enum `INACTIVE → ACTIVE → DYING` (no state-machine node). Children = component nodes the root coordinates:
- **HitBox** (`Area3D`+`CollisionShape3D`, `hit_box.gd`) — `area_entered` from player projectiles → `owner.take_damage(dmg)`.
- **MovementComponent** (`Node`, `movement_component.gd`) — holds a `MovementPattern` resource; each physics frame computes velocity from the pattern and drives the body. Only runs while `ACTIVE`.
- **WeaponComponent** (`Node`, `weapon_component.gd`) — fires an enemy projectile scene on a cadence (interval, burst, aimed-at-player or forward). Only while `ACTIVE`.
- **VfxEmitter** (`Node3D`, `vfx_emitter.gd`) — registry of `GPUParticles3D` one-shots played by key (`"attack"`, `"death"`).
- **SfxEmitter** (`Node3D`, `sfx_emitter.gd`) — plays `AudioStreamPlayer3D` children by key.

`base_enemy.gd` responsibilities: HP + `take_damage(amount)` (console log HP transitions, reused from old logic), `die()` → VfxEmitter `"death"` + SfxEmitter + disable components + reparent particle/free after delay, distance-based self-activation (`activation_distance`, checks player each frame while INACTIVE), `contact_damage` to player on body touch.

### Movement patterns (`Resource` subclasses, `@export` params)
- `movement_pattern.gd` (base): `func compute_velocity(enemy, player, time_active, delta) -> Vector3`
- `weave_movement.gd` — sine side-to-side + slow drift toward player.
- `swoop_movement.gd` — arc in from an offset toward the player, then hold.
- `strafe_movement.gd` — hold standoff distance, strafe laterally.

### EnemyData (`EnemyData.gd`, trimmed)
Remove `character_scene`, `anim_*`, `pursue_range`, `leash_radius` (navmesh-era). Keep/define: `display_name`, `max_hp`, `move_speed`, `contact_damage`, `score`. (Weapon cadence lives on WeaponComponent; movement params on the pattern resource.)

### Player homing
- `homing_projectile.gd` extends `FseBaseProjectile`; override `_physics_process` to steer `_direction` toward `homing_target` at capped `turn_rate_deg`. Null target → straight (inherited).
- `HomingProjectile.tscn` (player) with a `GPUParticles3D` trail; `PlayerProjectile.tscn`/blaster point to it.
- `BaseWeapon.gd`: in `_spawn_projectiles`, if `homing_target` set on the weapon, assign it to each projectile (`projectile.set("homing_target", …)`). Backward-compatible.
- `mecha_player.gd`: `_acquire_homing_target()` — among `enemy` group, project each to screen, keep those within an aim cone of the reticle, pick nearest to reticle (tie-break nearest to player). Set `_equipped_weapon.homing_target` before `try_fire`.
- Minimal player HP: add `hp`, `receive_attack(dmg)` (console log) so enemy projectiles/contact have an effect to report.

### The three enemies (inherited scenes + `.tres` data + particle sub-resources)
1. **Weaver** — diamond/sphere body; `weave_movement`; slow single aimed shots; blue spark death burst.
2. **Swooper** — cone body; `swoop_movement`; fast burst when close; fiery death explosion.
3. **Turret** — box/pyramid body; `strafe_movement`; rapid volley; green plume death.
Each: distinct primitive mesh+material, its MovementPattern resource, WeaponComponent cadence, enemy projectile with particle trail, death `GPUParticles3D`.

### Enemy projectiles
`EnemyProjectile.tscn` (straight, `FseBaseProjectile`, `group_to_damage = &"player"`) with a particle trail; per-enemy color variants via material override or small scene variants.

### Encounters / level
- Place the 3 enemies under `Level` in `main.tscn` at increasing −Z, each with `activation_distance`; self-activate when the advancing player gets near.
- **Rail reach**: `MoveF` currently loops 0→−40 over 10s. Extend travel (~−90 over ~18s, keep loop) so all three are flown past. Place enemies ≈ −15, −40, −70.

---

## File plan
**New**
- `objects/enemy/base/base_enemy.gd`, rebuilt `objects/enemy/base/BaseEnemy.tscn`
- `objects/enemy/components/{hit_box,movement_component,weapon_component,vfx_emitter,sfx_emitter}.gd`
- `objects/enemy/movement/{movement_pattern,weave_movement,swoop_movement,strafe_movement}.gd`
- `objects/enemy/enemies/{Weaver,Swooper,Turret}.tscn` + `{weaver,swooper,turret}.tres` + movement `.tres`
- `objects/weapons/enemy/EnemyProjectile.tscn`
- `objects/weapons/player/HomingProjectile.tscn` + `objects/weapons/player/homing_projectile.gd`

**Modified**
- `objects/enemy/EnemyData.gd` (trim), `objects/weapons/base/BaseWeapon.gd` (pass homing target), `objects/weapons/player/PlayerProjectile.tscn`/`PlayerBlaster.tscn` (use homing), `objects/overworld/player/mecha/mecha_player.gd` (target acquisition + player HP), `levels/main.tscn` (place enemies, extend rail), `project.godot` (layer names)

**Removed (navmesh-era, superseded)**
- `objects/enemy/base/{fse_enemy,AIState,state_machine}.gd`, `objects/enemy/base/states/*`, `objects/enemy/enemies/TestEnemy.tscn`, `objects/enemy/enemies/goblin.tres`
- (Keep generic `objects/base/state/*` — still used by MechaPlayer; keep `EnemyData.gd`.)

---

## Verification (MCP, headless)
Run project; via `game_eval`: confirm 3 enemies exist, each activates by distance, takes damage from player projectiles (HP logs), fires its projectile type, and dies with a death particle one-shot. Confirm homing: spawn a projectile with a target and check `_direction` curves toward it; confirm a far target out-runs the turn cap while a near one converges. Screenshot for visual sanity.

## Notes / risks
- Rail loop reset means enemies that died won't respawn on loop — fine for prototype.
- Keeping particles parented to a dying enemy: reparent the death one-shot to the level (or use a short-lived standalone) so it isn't freed mid-emit.
- Homing target set on the weapon is per-shot; cleared each frame when no valid target so non-locked shots fly straight.
