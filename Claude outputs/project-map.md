# Fortress Shepherd Eunuch — Project Map

Where everything lives, what tooling is connected, and how to work on this project from Cowork. Read this first in any new session.

*Last surveyed: 2026-09-13.*

## The two folders

**Godot project (the game itself)**
`/Users/nicholasmarino/Desktop/godot/channeling`
The Godot project is named `channeling` — that is the codename in `project.godot` and the git remote (`https://github.com/nsmarino/channeling.git`, `main` tracks `origin/main`). "Fortress Shepherd Eunuch" / "FSE" is the game; `channeling` is the repo. Connect this folder to a Cowork session to read or edit scenes, scripts and assets.

**Working files (Blender, references, exports)**
`/Users/nicholasmarino/Desktop/avern/fse-working`
Disorganized by Nick's own description, and we are not reorganizing it. It holds every `.blend` file made so far, glTF exports, reference images, screenshots and screen recordings. See `fse-working-inventory.md` for what is in there.

**New work from Cowork goes in**
`/Users/nicholasmarino/Desktop/avern/fse-working/via-cowork`
Empty as of this survey. Conventions for what goes where inside it are in `blender-asset-pipeline.md`.

## Tooling that is connected

| Tool | State on 2026-09-13 | Notes |
|---|---|---|
| Godot MCP (`mcp__remote-devices__godot__*`) | Working | Reads project info and file lists, can run the project, eval GDScript in the running game, screenshot, launch the editor. Installed Godot reports `4.6.stable`; `project.godot` lists features `4.7` + `Forward Plus`. The repo's `CLAUDE.md` mentions a `/Applications/Godot_4.7.app` for the class-cache rebuild trick. |
| Blender MCP (`mcp__remote-devices__Blender__*`) | Server announced, Blender not running | The live tools (`get_objects_summary`, `execute_blender_code`, screenshots) need Blender open with the MCP addon's server started on `localhost:9876`. The `*_for_cli` tools open a `.blend` in background Blender but currently fail with "Blender executable not found at 'blender'" — the `BLENDER_PATH` environment variable needs to be set to the Blender binary (typically `/Applications/Blender.app/Contents/MacOS/Blender`) in the MCP server config for those to work. |
| Folder access | Both folders granted | Re-grant per session if needed: the Godot folder via "Add folder", `fse-working` on request. |
| `device_bash` | Unavailable this session | The local Linux workspace failed to start, so surveys used folder listings and file staging instead. Worth retrying in a future session — it makes bulk inspection much cheaper. |

## Authoritative docs already in the repo

The Godot repo carries its own documentation, and it is the source of truth for code-level questions. Don't duplicate it in this Project; read it when working on gameplay:

- `channeling/CLAUDE.md` — architecture, conventions, autoloads, player movement API, the Destructible/Enemy/Breakable family, enemy AI stack, collision layers, input map, working-style rules (tune in the Inspector; small reviewable changes; **never commit without explicit permission**).
- `channeling/docs/enemy-prototyping.md` — how to brief a new creature (encounter descriptions over spec sheets), the action system, component map, in-game testing practice, traps, and a "things not yet built" list.

## The game in one paragraph

A 3D action game in Godot 4 (Forward+) with a third-person `CharacterBody3D` player. Combat is bump-based: you damage things by running into them. There is an energy resource that regenerates and is spent all-or-nothing on moves like Power Slam / Power Dive; lock-on exists. Enemies inherit a full AI stack from `BaseEnemy.tscn` (perception cone, FSM brain as a scheduler, weighted `EnemyAction` nodes). Four prototype creatures exist: **Manicoppo, Gevi-Dava, Ugrehk, Essurou**. Interactables (bounce mushrooms) and breakables (Mushroom 1) are separate families. Levels are CSG blockouts plus placeholder "channel" scenes (`channel-coppo-cavern`, `channel-sorrowful-pool`, `channel-thorn-thicket`, `bridge-station`). A legacy rifle/projectile weapon system is still in the tree but is not the direction.

Current phase per the repo: **encounter prototyping** — tune the creatures by playing, wire `TriggerRegion`s into real encounters, fill the CSG blockout, and only then mise-en-scène (textures, lighting, Blender models). The Project's stated goal is a prototype level showcasing combat and exploration.

## Godot project layout (top level)

```
channeling/
  main.tscn                 playable scene (player, HUD, blockout, NavigationRegion3D, EnemyCoordinator, 3 Manicoppos)
  blockout_3_mesh.tscn      recent blockout iterations at the root
  blockout_3_use_smaller_chunks.tscn
  project.godot             autoloads Events / GameManager / Cinematic; 6 physics layers; input map
  CLAUDE.md, docs/          repo documentation (see above)
  Makefile, open-blends     script that opens blender/level/level.blend and blender/models/props.blend —
                            neither path exists yet; this is the intended in-repo Blender layout that never materialized
  addons/                   GPUTrail, nurbs_path (NurbsPath3D), play_from_here, view_overlay_toggle, brackeys_particle_controls
  assets/                   models/, sounds/, fonts/, hdr/, sprites/, brackeys-vfx/, kenney_prototype-textures/
  autoloads/                events.gd, game_manager.gd, cinematic.gd
  encounters/               exercise-1.tscn
  explores/                 throwaway experiments: animation, csg, gridmap, shaders, vfx
  levels/                   main.gd, overworld/ (base_overworld, proto-overworld), dungeon/ (lance-blockout)
  objects/                  player/, components/, enemy/, breakables/, interactables/, level/, pickups/, weapons/, cutscene/
  placeholder/              untextured channel scenes + placeholder creature models
  resources/, ui/, vfx/     CombatUI.tscn; particle scenes
  *.tres at root            environs-material, floor-material, terrain-material
  main.exr / main.lmbake    baked lightmap for main.tscn
```

Godot MCP counts: 65 scenes, 81 scripts, 326 assets.

### `assets/models/` — where Blender exports land

```
assets/models/
  buildings/   support-with-arches.glb
  character/   fse-pawn.glb, npc/guy-to-test-root-motion.glb
  decor/       debris.glb
  ground/      ground-large-1.glb
  rails/       blast-fish.glb, kelp-walls.glb, mecha/mecha-frame.glb
  test/        Y Bot.fbx, channel-pain-pool.glb, ground.glb, halberd.gltf,
               manicoppo-for-export.glb, rockwall.glb, test-mesh-library.glb (+ ml.tres, test-mesh-tiles/)
  channeling1.glb, csg-hill.glb, stem-mesh.bin   (loose at the top)
```

The `buildings / character / decor / ground` split is the seed of a prop taxonomy; `blender-asset-pipeline.md` proposes extending it rather than inventing a new one. Everything is `.glb` (one `.gltf` + one `.fbx`); the game does not import `.blend` files directly.

## Working from Cowork — quick rules

Carry over from the repo's `CLAUDE.md`: run the project with the Godot MCP (`run_project`, then `game_eval` in a *separate* turn), keep GDScript statically typed, tune numbers in the Inspector via `@export` rather than hardcoding, prefer small diffs, and never commit without being told to. New `class_name` scripts need the headless class-cache rebuild described there.

For Blender work: put new `.blend` files under `fse-working/via-cowork/` following `blender-asset-pipeline.md`, export `.glb` into the matching `channeling/assets/models/<category>/` folder, and record anything durable (a new prop family, a naming decision) back in this Project.
