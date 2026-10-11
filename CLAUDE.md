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
  - `interaction/` — `Interaction` + its step nodes (talk to NPCs; see below).
  - `level/` — `TriggerRegion`, `Portal`, level-authoring pieces.
  - `cutscene/` — `ExampleCutscene` (an Interaction; see below).
  - `pickups/`, `weapons/`.
- **`autoloads/`** — `Events`, `GameManager`, `Cinematic`.
  `mcp_interaction_server.gd` is injected per-run by the MCP tool, not a project
  autoload; **treat its warnings as noise** when triaging.
- **`ui/dialogue/`** — `DialogueUI` (DialogueBox + PromptBox), instanced in Main's HUD.
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
open editor. It also **writes the script's `.uid` file** — read the token from
there when a hand-written scene needs to reference the script. **Don't invent
UIDs by hand**: Godot only accepts ones it generated (a 64-bit id in its own
base-35 spelling), so a made-up token is silently replaced in the editor's cache
while the `.uid` file keeps the stale text, and references drift apart. The same
goes for new `.tscn` headers — omit `uid=` and let the editor assign one, or run
the rebuild and copy what it wrote.

## Architecture

### Autoloads

- **`Events`** — signal bus: `player_killed`, the cutscene bracket,
  `enemy_hp_changed` / `enemy_damaged` / `attack_hit`.
- **`GameManager`** — runtime refs + **level restart** (deferred
  `reload_current_scene()` behind a re-entrancy guard). Triggers: player death,
  falling below `fall_limit_y`, and the `restart` action. Also holds the Play
  From Here overrides (spawn point + `location_override`) for the whole session.
- **`Cinematic`** — the letterbox bars and a full-screen fade (`fade_out()` /
  `fade_in()` / `clear_fade()`, drawn over the bars). `show_bars()` / `hide_bars()` move only
  the bars (what interactions use); `begin()` / `end()` also emit the
  `cutscene_started` / `cutscene_finished` freeze, for code that wants both.

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
│   └── geometry (Enemies, Items may sit here too — see the bake note)
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

**Where things sit vs. the navmesh.** A NavigationAgent3D uses the world's shared
navigation map, which every NavigationRegion3D publishes into — an enemy does
*not* need to be under a region to path on its navmesh (IntroCutscene's
Manicoppo lives under `Cutscenes`). A region's children only matter as **bake
input**. Bake from **Static Colliders on layer 1** (`geometry_parsed_geometry_type
= 1`, `geometry_collision_mask = 1`; the template ships this way): the default,
"Mesh Instances", treats every visible mesh under the region as an obstacle, so an
enemy, prop or pickup placed there carves a permanent hole around its spawn
point. With static colliders the navmesh is exactly what the player can stand on.
The bake's `cell_size`/`cell_height` can be finer than the navigation map's
(`navigation/3d/default_cell_size`, 0.25): harmless with one region per location,
but match them if separately baked regions must connect.

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
   Every move is horizontal and enemy bodies have no collision shape, so height
   comes from the **navmesh**: after each move the body eases to the navmesh
   surface under it, keeping the offset it was placed with
   (`follow_navmesh_height`, on by default — turn off for fliers). That's what
   lets creatures walk ramps and stairs; without it they keep their spawn height
   and burrow into slopes. The offset is only measured once the nearest navmesh
   point is actually beneath the body — for the first frames after a load the map
   answers the world origin.
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

### Interactions (`objects/interaction/`)

Talking to an NPC, reading a sign. Ported from Nightbloom v1's DialogueTrigger. An
`Interaction` (Area3D; its script defaults it to layer 0 / mask 2, since
Area3D's own mask 1 never sees the player, and it warns if the mask lacks layer
2) shows a prompt while the player is inside it;
pressing `interact` emits `Events.interaction_started`, which freezes the player
exactly like a cutscene, then runs its **`InteractionStep` children top to
bottom**, awaiting each (the dialogue box closes whenever a run of SaySteps ends
and the next step isn't one — Say → Timeline → Say exits and re-enters — and
back-to-back SaySteps share one open box), closes the dialogue box, blends the
camera back and emits
`interaction_finished`. `ExampleNPC.tscn` shows a full one.

Steps (`steps/`): `SayStep` (speaker, portrait, `lines` array — the DialogueBox
types each out; press to reveal, press again to advance), `CameraStep` (blend to a
Camera3D in the level, optional `look_at_target`), `SoundStep`, `AnimationStep`,
`WaitStep`, `EventStep` (sets a GameManager flag and emits `fired` — connect it in
the editor for any state change), `TimelineStep` (plays an AnimationPlayer clip
and waits for it to end; to aim a camera at something, give the camera a
`LookAtTarget` child). New beat = extend `InteractionStep`, override
`run()`, await inside it to hold the sequence.

**Cutscenes are Interactions.** `start_on_enter` starts on walking in (no prompt;
re-arms only after the player leaves), `letterbox` slides the Cinematic bars in
for the duration, and a `TimelineStep` carries anything that needs exact timing —
camera cuts keyed on `current`, FOV pulls, audio tracks. The clip needs no
"finish" key: the sequence moves on when it ends, then blends back to the player
(any camera the timeline cut to is put back afterwards). Timed choreography goes
in the timeline; anything that waits on the player (dialogue) goes in steps
around it. See `objects/cutscene/ExampleCutscene.tscn`.

Camera transitions (Interaction › Camera) come in both directions, each `BLEND`
(sweep around the player), `FADE` (to black, switch while dark, fade back in) or
`CUT`, with their own blend / fade / hold times:
- **`camera_enter`** shapes the *first* switch away from the player's camera,
  whichever step makes it — a `CameraStep`, or a `TimelineStep` whose clip keys
  a camera `current`. Later switches between level cameras use the CameraStep's
  own `blend_time`. Steps make that first switch through
  `begin_camera_switch()` (await; fades out) → switch → `end_camera_switch()`
  (blends in / fades back in); a TimelineStep doesn't await the end, so the clip
  plays on underneath, and leaves FOV to the clip.
- **`camera_return`** takes the view back to the player at the end. FADE also
  drops the letterbox while dark, and is skipped when no step moved the camera,
  so a plain conversation never flashes to black.

**Cutscenes with actors** — `objects/cutscene/IntroCutscene.tscn` is the worked
example. Any actor — enemy, NPC, **the player** — is puppeted the same way: a
`PathFollow3D` (`rotation_mode` Y; -Z faces along the path) carries an
**`ActorDriver`**, the timeline keys the follower's `progress_ratio`, and keys the
driver's `driving` **on at the start and off at the end**. The driver copies its
position and facing onto the actor (`actor` path, or `actor_group` such as
`player` when a cutscene file can't reach it by path); facing goes to the actor's
`get_facing_node()` if it has one (the player's `Model` — the body never rotates),
else the actor itself. It's off by default on purpose: a RemoteTransform3D pushes
for as long as it exists and pins its target forever.

The actor must not be moving itself: an enemy asleep in `MANUAL` activation (an
`EventStep` connected to its `activate()` wakes it afterwards), or the player held
by the Interaction's **`puppet_player`**, which claims `begin_scripted_move` for
the run and releases it on finish and when freed mid-run. Clips play on an
**animation playback track** aimed at the actor's AnimationPlayer (plus a method
key setting `playback_default_blend_time` so switches crossfade). Pace walks at
the actor's in-game speed (3 m/s for the Manicoppo) or feet slide, and end paths
on the navmesh. Note the player snaps to its path start at the clip's first frame
— put an enter FADE over that.

**`LookAtTarget`** (child of a Camera3D) keeps the camera aimed at a node (or a
group) every frame while it's active, optional `smoothing`; it stands aside while
an Interaction blend owns the camera, and a blend *into* a tracking camera lands on
the LookAtTarget's aim (read every step) rather than the camera's placed rotation,
so there's no snap when it takes over. Parent the camera to a PathFollow3D for a
tracking shot — IntroCutscene's CamB rides the player's follower behind the
shoulder and looks at the approaching Manicoppo.

**Hand-writing transforms in `.tscn`:** Godot writes a `Transform3D` basis **row
by row** (`x.x, y.x, z.x, x.y, …`), not axis by axis. Getting it backwards
inverts the rotation — a camera aims mirrored — and a 180° yaw test can't catch
it, because that rotation is its own inverse.

**Give every timeline a `RESET` animation** keying its cameras' `current` to
false — check this: Godot fills a new RESET key with the value at the moment you
key the track, so a camera that was current then gets RESET to *true* (and FOVs to their authored values). Previewing a clip in the editor really
sets the animated properties, and saving mid-preview stores them — a camera saved
`current = true` steals the view the moment the location loads. The editor
restores RESET values before saving; `TimelineStep` also checks on load, warns,
and hands the view back to the player.

State: `GameManager.flags` (`set_flag` / `has_flag`) live for the session and
survive restarts. `once_flag` makes an interaction happen once and sets the flag;
`required_flag` gates one on it — pair two Interactions on one NPC for "first
meeting" then "follow-up". `one_shot` only lasts until the location reloads.

Details that matter: only one interaction holds the prompt at a time (static
arbitration, first in range wins); the press that ends a conversation must be
released before it can restart; an Interaction freed mid-run (restart, travel)
still hands control back in `_exit_tree`. Player control is a **lock count**
(`_lock_control` / `_unlock_control`), so a cutscene and an interaction can't
release each other; `Player.is_control_enabled()` gates `PlayerAbility` and
`LockOnComponent`, which read input themselves. Enemies are NOT paused during a
conversation — place NPCs where nothing will attack.

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
`lock_on` (O / R3), `attack` (LMB / R2), `power_slam` (`;` / X), `interact`
(E / Y), `restart` (R / Back).

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
