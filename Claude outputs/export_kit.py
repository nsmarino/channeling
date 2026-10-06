"""
export_kit.py — export every prop collection in the open kit .blend to Godot as .glb.

Convention (see via-cowork/README.md):
  * one .blend per kit, one top-level collection per exportable prop
  * collection name == output filename (kebab-case)
  * collections starting with "_" (_ref, _wip, _scratch) are skipped
  * the target folder in Godot is derived from where the .blend lives:
        via-cowork/props/<category>/x.blend  ->  channeling/assets/models/<category>/
        via-cowork/characters/...            ->  channeling/assets/models/character/
        via-cowork/levels/...                ->  channeling/assets/models/levels/

Run it three ways:
  1. Inside Blender's Text Editor / Python console:   exec(open("/path/to/export_kit.py").read())
  2. Through the Blender MCP (execute_blender_code):   same exec(...) line
  3. Headless from a shell:
       /Applications/Blender.app/Contents/MacOS/Blender -b kit.blend --python export_kit.py -- [--dry-run] [--only name] [--out DIR]

Nothing is written unless the export succeeds; a dry run just prints the plan.
"""

import os
import re
import sys

import bpy

# ---------------------------------------------------------------- settings

GODOT_MODELS = os.path.expanduser("~/Desktop/godot/channeling/assets/models")

# via-cowork folder name  ->  assets/models subfolder
FOLDER_MAP = {
    "characters": "character",
    "levels": "levels",
}

SKIP_PREFIX = "_"


# ---------------------------------------------------------------- helpers

def _argv_after_dashes():
    if "--" in sys.argv:
        return sys.argv[sys.argv.index("--") + 1:]
    return []


def _flag(args, name, default=None, takes_value=False):
    if name not in args:
        return default
    i = args.index(name)
    if takes_value:
        return args[i + 1] if i + 1 < len(args) else default
    return True


def _category_from_blend_path(blend_path):
    """props/rocks/x.blend -> rocks ; characters/x.blend -> character ; else None."""
    parts = os.path.normpath(blend_path).split(os.sep)
    if "via-cowork" not in parts:
        return None
    rel = parts[parts.index("via-cowork") + 1:-1]  # folders between via-cowork and the file
    if not rel:
        return None
    if rel[0] == "props" and len(rel) >= 2:
        return rel[1]
    return FOLDER_MAP.get(rel[0], rel[0])


def _is_kebab(name):
    return re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name) is not None


def _all_objects(collection):
    return list(collection.all_objects)


def _exportable_collections():
    scene_root = bpy.context.scene.collection
    return [c for c in scene_root.children if not c.name.startswith(SKIP_PREFIX)]


def _select_only(objects):
    bpy.ops.object.select_all(action="DESELECT")
    skipped = []
    for ob in objects:
        if ob.hide_viewport or ob.hide_get():
            skipped.append(ob.name)
            continue
        ob.select_set(True)
    if objects:
        first_visible = next((o for o in objects if o.name not in skipped), None)
        bpy.context.view_layer.objects.active = first_visible
    return skipped


def _has_armature(objects):
    return any(o.type == "ARMATURE" for o in objects)


# ---------------------------------------------------------------- main

def export_kit(out_dir=None, only=None, dry_run=False):
    blend_path = bpy.data.filepath
    if not blend_path:
        print("export_kit: save the .blend first — the target folder is derived from its location.")
        return []

    category = _category_from_blend_path(blend_path)
    if out_dir is None:
        if category is None:
            print("export_kit: this .blend is not under via-cowork/; pass --out DIR explicitly.")
            return []
        out_dir = os.path.join(GODOT_MODELS, category)

    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    plan = []
    for coll in _exportable_collections():
        if only and coll.name != only:
            continue
        objs = _all_objects(coll)
        if not objs:
            print(f"  skip  {coll.name}: empty collection")
            continue
        if not _is_kebab(coll.name):
            print(f"  warn  {coll.name}: not kebab-case — the .glb will be named exactly this")
        plan.append((coll, objs, os.path.join(out_dir, coll.name + ".glb")))

    print(f"export_kit: {os.path.basename(blend_path)} -> {out_dir}")
    for coll, objs, path in plan:
        print(f"  {'plan' if dry_run else 'export'}  {coll.name:32s} {len(objs):3d} objects  -> {path}")

    if dry_run:
        return [p for _, _, p in plan]

    os.makedirs(out_dir, exist_ok=True)
    written = []
    for coll, objs, path in plan:
        skipped = _select_only(objs)
        if skipped:
            print(f"  warn  {coll.name}: hidden objects not exported: {', '.join(skipped)}")
        bpy.ops.export_scene.gltf(
            filepath=path,
            export_format="GLB",
            use_selection=True,
            export_apply=True,          # apply modifiers
            export_yup=True,            # Blender +Y -> glTF/Godot -Z forward
            export_materials="EXPORT",
            export_texcoords=True,
            export_normals=True,
            export_cameras=False,
            export_lights=False,
            export_animations=_has_armature(objs),
            export_skins=_has_armature(objs),
            export_image_format="AUTO",
        )
        written.append(path)
    bpy.ops.object.select_all(action="DESELECT")
    print(f"export_kit: wrote {len(written)} file(s)")
    return written


# Runs on import/exec. Headless invocations pass flags after "--"; interactive
# ones (Text Editor, console, MCP) have no flags and get the defaults.
_a = _argv_after_dashes()
export_kit(
    out_dir=_flag(_a, "--out", None, takes_value=True),
    only=_flag(_a, "--only", None, takes_value=True),
    dry_run=bool(_flag(_a, "--dry-run", False)),
)
