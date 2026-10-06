"""
audit_kit.py — pre-export checks for a prop kit .blend. Read-only; changes nothing.

Run inside Blender (Text Editor, Python console, or the Blender MCP):
    exec(open("/path/to/audit_kit.py").read())
or headless:
    /Applications/Blender.app/Contents/MacOS/Blender -b kit.blend --python audit_kit.py

Checks, per exportable collection (top-level, not starting with "_"):
  * collection name is kebab-case (it becomes the .glb filename)
  * objects have applied rotation and scale (rotation 0, scale 1)
  * the prop's lowest point sits on z = 0 (origin at the base) — warn if not
  * every mesh has a material and a UV map
  * n-gons (faces with more than 4 verts) — informational
  * object names carrying ".001"-style duplicate suffixes (they leak into Godot node names)
  * collision hints present (-col / -convcol / -colonly / -convcolonly) — informational
  * objects sitting loose in the Scene Collection root (won't be exported)
"""

import re

import bpy
from mathutils import Vector

SKIP_PREFIX = "_"
COLLISION_SUFFIXES = ("-col", "-convcol", "-colonly", "-convcolonly", "-rigid", "-noimp")


def _is_kebab(name):
    return re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name) is not None


def _lowest_z(objects):
    zs = []
    for ob in objects:
        if ob.type != "MESH":
            continue
        for corner in ob.bound_box:
            zs.append((ob.matrix_world @ Vector(corner)).z)
    return min(zs) if zs else None


def audit_kit():
    scene_root = bpy.context.scene.collection
    problems = 0

    loose = [o.name for o in scene_root.objects]
    if loose:
        print(f"WARN  objects loose in Scene Collection (not exported): {', '.join(loose)}")
        problems += 1

    for coll in scene_root.children:
        if coll.name.startswith(SKIP_PREFIX):
            continue
        objs = list(coll.all_objects)
        print(f"\n== {coll.name}  ({len(objs)} objects)")
        if not objs:
            print("  WARN  empty collection")
            problems += 1
            continue
        if not _is_kebab(coll.name):
            print("  WARN  name is not kebab-case; it becomes the .glb filename")
            problems += 1

        has_collision = False
        for ob in objs:
            tag = f"  [{ob.name}]"
            if any(ob.name.endswith(s) for s in COLLISION_SUFFIXES):
                has_collision = True
            if re.search(r"\.\d{3}$", ob.name):
                print(f"{tag} WARN  duplicate-style suffix in name (rename before export)")
                problems += 1
            if any(abs(r) > 1e-6 for r in ob.rotation_euler):
                print(f"{tag} WARN  rotation not applied {tuple(round(r, 3) for r in ob.rotation_euler)}")
                problems += 1
            if any(abs(s - 1.0) > 1e-6 for s in ob.scale):
                print(f"{tag} WARN  scale not applied {tuple(round(s, 3) for s in ob.scale)}")
                problems += 1
            if ob.type == "MESH":
                me = ob.data
                if not me.materials or all(m is None for m in me.materials):
                    print(f"{tag} WARN  no material")
                    problems += 1
                if not me.uv_layers:
                    print(f"{tag} WARN  no UV map")
                    problems += 1
                ngons = sum(1 for p in me.polygons if len(p.vertices) > 4)
                if ngons:
                    print(f"{tag} info  {ngons} n-gon(s)")
            if ob.hide_viewport or ob.hide_get():
                print(f"{tag} WARN  hidden — export_kit will skip it")
                problems += 1

        low = _lowest_z(objs)
        if low is not None and abs(low) > 0.01:
            print(f"  WARN  lowest point at z={low:.3f}; placeable props should sit on z=0")
            problems += 1
        print(f"  info  collision hints: {'yes' if has_collision else 'none (Godot will import without collision)'}")

    print(f"\naudit_kit: {problems} warning(s)")
    return problems


audit_kit()
