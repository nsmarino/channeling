# Vertex Studio Free

This is the FREE version of Vertex Studio (GDExtension/C++ Edition).

## Free versus Pro ⭐

- **Free** includes the core, essential features for vertex painting: brush, eraser, bucket fill, opacity, point selection, select all / deselect, swatches & palettes (including PNG import), blur, debug views, view modes and the non-destructive material setup.
- **Pro ⭐**: everything from Free plus lasso / rectangle / ellipse & linked selection tools, invert selection, split-vertex painting, paint precision, paint normals, vertex groups, replace colors, single-channel R/G/B/A painting, falloff curve editing, and Variations + the VSRuntime node (Inspector/runtime switching and snapshot blending).

Get the **Pro ⭐** version: https://splitpainter.itch.io/vertex-studio/

## Features
Vertex Studio is a Godot plugin for **editing, managing and painting vertex colors and vertex normals** of 3D meshes. A complete solution for vertex painting inside the Godot editor. Vertex Studio is a must-have tool for making games inspired by PS1, N64 or early PC games aesthetics, but it's useful even in modern workflows, since vertex coloring can also be used for texture blending and masking.

It has tools for:

- Painting and filling vertices (brush, eraser, opacity adjustment, brush falloff, color palettes, bucket fill, blur, color replacement by threshold, individual RGBA channel selection).

   - Supports both static and skeletal/skinned animated meshes.

- Selecting vertices (lasso, rectangle and ellipse selection); linked by material selection (like Blender).
- Changing vertex and face normals between hard and smooth.
- Painting individual vertices or split vertices (shared vertices of hard edges, allowing for multipler colors in a single "physical vertex").
- Grouping vertices into vertex groups like Blender.
- Creating and managing variations/snapshots of vertex colors, selections and vertex smoothness topology, creating non-destructive variations of a single mesh.
- Switching between mesh variations at runtime and blending between variations.

## Godot version required?
4.3+

## Documentation and tutorials
https://alfredbaudisch.github.io/godot-vertex-studio-docs/index.html

## Forums
https://splitpainter.itch.io/vertex-studio/community

## Bug reports
https://github.com/alfredbaudisch/godot-vertex-studio-docs/issues

## High-performance GDExtension edition

This is the **GDExtension edition** of Vertex Studio, which bundles a compiled native core (`bin/libvsnative.*` + `bin/vertex_studio.gdextension`), developed with C++.

### GDScript vs GDExtension differences

- Support to painting meshes with hundreds of thousands to millions of vertices, where as in the GDScript version, the interface starts stuttering at around 50k vertices.
  - Painting up to about 1M triangles is smooth. From 2M to 4M it is still usable in real-time, but expect the occasional stutter.
- `Show Vertices` becomes usable on dense meshes, and the vertex cloud is hidden while you navigate so orbiting stays responsive. BEWARE: depending on the machine configure, `Show Vertices` can also cause performance issues even with the GDExtension version.
  - In the settings, you can configure the `Very Dense Mesh Vertex Count` in order to make `Show Vertices` disable automatically in case it causes performance issues.
  - `Always Show Vertices` is a different matter: past a few tens of thousands of vertices it draws an unreadable clump of squares, so it is not really usable at high density no matter how fast it is. Above the `Dense Mesh Vertex Count` setting it is switched off automatically. On dense meshes the cloud is also subsampled, so you see a uniform sample of the mesh instead of every single vertex.
- Better backface/occluding vertices performance. It's also possible to use x-ray to paint backface vertices without performance impact (disable `Show Front Verts Only`).
  - How smooth this feels still depends on the mesh: a flat plane is the easy case, while a dense self-occluding shape (a torus, a character) makes every visibility test do real work.
- Painting is always live with the GDExtension version (the GDScript version is not very usable on high poly meshes).
- Painting normals is the heaviest tool: smoothing is instant, but a hard edit has to split vertices and rebuild the surface, so it can stutter on dense meshes. `Fill All Hard` / `Fill All Smooth` past the `Async Fill Normals Vertex Count` setting (100k by default) run on a worker thread to avoid freezing the editor.
- Saving and applying variations of dense meshes also runs in the background.
- For meshes above ~50k vertices, save the scene as **`.scn`** (binary) rather than `.tscn` (text), because text scenes of dense meshes are slow to write and read and take much more disk space.

### GDExtension troubleshooting

- If the native library cannot be loaded (unsupported platform), Vertex Studio  automatically falls back to the GDScript implementation (it has all the same features, but with a vertex/triangle upper limit, see above in the differences section).

## Building the native core yourself

Vertex Studio Pro includes the C++ source of the native core (shipped in a separate download `gdextension-source`). To rebuild it:

1. Get godot-cpp and an `extension_api.json` dumped from the Godot build you target:
   ```
   git clone --depth 1 https://github.com/godotengine/godot-cpp.git
   godot --headless --dump-extension-api --dump-gdextension-interface
   ```
2. `pip install scons`
3. From `gdextension/`, run `scons -j8` (`target=template_debug` for a debug build). Point `GODOT_CPP_PATH` and `GODOT_API_JSON` at the two paths  above if they are not where the SConstruct expects them.

The library is written to `addons/vertex_studio/bin/`, next to the `gdextension/` folder. Godot must be restarted to pick up a new build.

The shipped binaries are built against the **4.3** API on purpose (cover Godot 4.3 through 4.7). Building against a newer dump raises the minimum version accordingly, keep`compatibility_minimum` in `vertex_studio.gdextension` in sync with whatever API you build against.

## License
See the [LICENSE](LICENSE) file.
