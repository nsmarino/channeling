@tool
extends RefCounted
class_name VSObjExport

## Wavefront OBJ writer that keeps the painted colors.

## Position line
const V_FMT := "v %.6f %.6f %.6f"
## Position + color line (`v x y z r g b` extension)
const VC_FMT := "v %.6f %.6f %.6f %.4f %.4f %.4f"
## Same with the painted alpha on the end
const VCA_FMT := "v %.6f %.6f %.6f %.4f %.4f %.4f %.4f"
const VT_FMT := "vt %.4f %.4f"
const VN_FMT := "vn %.4f %.4f %.4f"
## Lines buffered before saved into disk
const FLUSH_LINES := 8192


static func write(_targets: Array, _path: String, _include_alpha := false) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


static func _write_mesh(f: FileAccess, md: VSMeshData, xform: Transform3D, used: Dictionary,
		include_alpha: bool) -> Dictionary:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return {}


static func _corner(_i: int, _vbase: int, _tbase: int, _nbase: int, _have_uv: bool, _have_n: bool) -> String:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	return ""


static func _node_xform(mi: MeshInstance3D) -> Transform3D:
	if mi == null:
		return Transform3D.IDENTITY
	return mi.global_transform if mi.is_inside_tree() else mi.transform


static func _safe_name(n: String) -> String:
	var out := n.strip_edges().replace(" ", "_")
	return out if not out.is_empty() else "mesh"
