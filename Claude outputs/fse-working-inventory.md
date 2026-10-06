# fse-working — Inventory

What is in `/Users/nicholasmarino/Desktop/avern/fse-working` as of 2026-09-13, grouped so it can be found again. This folder stays as-is; the point of this doc is to know what exists so it doesn't get remade, and to know which files are the live ones.

Groupings below are inferred from filenames, sizes and dates — Nick should correct anything mislabeled. Every `.blend` has a `.blend1` autosave twin next to it (the Godot repo's `.gitignore` already ignores `*.blend1`); they are omitted here.

## Live scene files (most likely to be reopened)

| File | Size | Last saved | What it appears to be |
|---|---|---|---|
| `fse-blender-8-2.blend` | 3.8 MB | 2026-08-03 | Latest dated "whole project" Blender file. Successor to `fse-blender-7-31.blend` (3.4 MB, 08-01) and `fse-base.blend` (2.5 MB, 04-05). |
| `channel-pain-pool.blend` | 2.9 MB | 2026-07-29 | Level piece; exported to `channeling/assets/models/test/channel-pain-pool.glb`. |
| `manicoppo-for-export.blend` / `manicoppo.blend` | 19 MB each | 2026-07-15 | The Manicoppo creature. The `-for-export` copy is the one that became `assets/models/test/manicoppo-for-export.glb`. Two 19 MB near-duplicates — candidates for consolidation if ever tidying. `mannicope.blend` (1.3 MB, 04-29) is an earlier spelling/version. |
| `fse-pawn.blend` | 115 KB | 2026-08-04 | Player pawn; exported to `assets/models/character/fse-pawn.glb`. |
| `keystone.blend` | 110 KB | 2026-08-04 | Small architectural piece (keystone). |
| `yoshua-manger.blend` | 109 KB | 2026-08-25 | Most recent file in the folder. A manger prop / set piece. |
| `gogo.blend` | 2.6 MB | 2026-07-31 | Unknown subject — Nick to label. |
| `serpentine-2.blend`, `serpentine.blend` | ~120 KB | 2026-07 | Serpentine form, v1 and v2. |

## Character work (April–May 2026)

`player-character.blend` (05-17) is the latest of a chain: `player-character-before-joining-face.blend` (05-14) → `player-character-proportion-test.blend` (05-15) → `player-character.blend`. Supporting studies: `Eyes.blend`, `eye-study.blend`, `finding-scale.blend`, `new-mesh-test-1.blend`. Named characters or creatures: `darius.blend` (with `darius.jpg`, `darius-crop-2.jpg` references), `doberes.blend` (+ `doberes.jpeg`), `esthel.blend`, `spindler.blend`, `castrate.blend` (6 MB), `haunting-ground-ref.blend` (06-16, a reference-study file). The `human-base-meshes-bundle-v1.4.1/` folder is the Blender Foundation's free base-mesh asset library (49 MB `.blend` + asset catalog + thumbnails) — a library, not project work.

Rigging practice: `ik-rigging.blend`, `practice-rigging-ik.blend`, `anim-cube.blend`.

## Environment and props (April 2026 onward)

Rock walls: `RockWallSet.blend` (12 MB), `RockWalls.blend`, `RockWalls1.blend`, `practice-rock-wall.blend` (14 MB) — four files from 04-15/16 covering the same subject; `rockwall.glb` in `assets/models/test/` came from one of them. Other pieces: `practice-tomb.blend`, `fountain-practice.blend` (19 MB), `pump.blend`, `middle-path.blend`, `tree-practice.blend`, `FSE-4-16-vale.blend`.

Subfolders: `props/` exists but is **empty**; `tiles/` holds 15 small PNGs (`Face_*` colour/shape tiles, `place.png`) used with the test mesh library / gridmap explorations; `textures/` holds a single stray file literally named `.png`.

## Level exports (glTF pairs, `.gltf` + `0.bin`)

`serai.gltf` (03-31, oldest file in the folder), `channel-sorrowful-pool`, `channel-coppo-cavern`, `csg_blockout_2`, `blockout_3`, `blockout_3_mesh` (all late July / early August). These are round-trips between Godot CSG blockouts and Blender; their Godot counterparts are `placeholder/channel-*.tscn`, `explores/explore-csg/csg_blockout_2.tscn` and the two `blockout_3_*.tscn` at the repo root.

## Reference material

Tree/plant silhouettes (mid-April batch): `chamaerops-humilis`, `cornish-oak`, `lombardy-poplar`, `pinus-syl`, `scots-pine`, `silver-birch`, `staghorn-sumac`, `stone-pine`, `whitebeam`, `wild-cherry`, `windmill-palm`, `plant.png`. Useful when prop-modeling plants starts.

Other references: `islamic-arms-and-armor.pdf` (20 MB, 08-06 — weapons reference), `three-judges.jpg`, `palette.png` (08-02, colour palette), `anime_face_side_view_step_by_step_drawing.png`, `hq720.jpg`, `RLA3033-SILVER-1T.webp`, `ava-for-texture.webp`, `claw.jpeg`, `springfield.jpg`, `stando.png`, `ren.png`, `can-can-bunny.png`, `exp.png`, `test-photobash-1.jpg`, `IMG_9441.jpeg`, `677119076_5Tusken.png...png`, `male_skeleton_first_anatomy_study.OBJ` (2016 anatomy model).

Baked textures: `BodyPass1 Color.png`, `Cube.004 Color.png`, `Cube.005 Color.png`.

## Recordings and screenshots

Renders/recordings: `0001-0054.mp4`, `0001-0200.mp4`, `0001-0250.mkv` (Blender frame-range renders), `cool.mov` (74 MB), `Screen Recording 2026-04-27...mov`. Eight `Screenshot 2026-*.png` files from April, May and August.

Not project-related: `Tickets - Coach USA.pdf`.

## Observations for the pipeline doc

- Files are named by subject with no category prefix, and versions are expressed three different ways: a date in the name (`fse-blender-7-31`), a suffix number (`RockWalls1`, `serpentine-2`), or a phrase (`-before-joining-face`, `-for-export`). The pipeline doc proposes one convention for new files only.
- The Godot repo's `open-blends` script expects `blender/level/level.blend` and `blender/models/props.blend` inside the repo — an earlier intention to keep source `.blend`s in the repo. It never happened; `via-cowork` effectively replaces that idea, outside the repo.
- Export targets in Godot already have a light taxonomy (`buildings`, `character`, `decor`, `ground`, `rails`, `test`). Most exports so far went to `test/`.
