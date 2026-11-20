@tool
extends RefCounted
class_name VSPro

## Edition gate for the free vs pro versions. Single source of truth for the PRO feature list.
##

const IS_PRO := false
const ALERT := "This feature is available in VERTEX STUDIO PRO. Upgrade to unlock."
const STORE_URL := "https://splitpainter.itch.io/vertex-studio"

enum Feature {
	SPLIT_VERTS,
	SELECT_LASSO,
	SELECT_RECTANGLE,
	SELECT_ELLIPSE,
	SELECT_POINT_DRAG,
	SELECT_LINKED,
	INVERT_SELECTION,
	PAINT_PRECISION,
	PAINT_NORMALS,
	VERTEX_GROUPS,
	SNAPSHOTS,
	REPLACE_COLORS,
	SINGLE_CHANNEL,
	FALLOFF,
	RESYNC_UVS,
	EXPORT_OBJ,
	EXPORT_GLTF,
}

const FEATURE_NAMES := {
	Feature.SPLIT_VERTS: "SHARED VERTS: SPLIT",
	Feature.SELECT_LASSO: "SELECTION: LASSO",
	Feature.SELECT_RECTANGLE: "SELECTION: RECTANGLE",
	Feature.SELECT_ELLIPSE: "SELECTION: ELLIPSE",
	Feature.SELECT_POINT_DRAG: "SELECTION: SINGLE, DRAG TO ADD",
	Feature.SELECT_LINKED: "SELECTION: LINKED",
	Feature.INVERT_SELECTION: "SELECTION: INVERT",
	Feature.PAINT_PRECISION: "PAINT: PRECISION",
	Feature.PAINT_NORMALS: "PAINT: NORMALS",
	Feature.VERTEX_GROUPS: "VERTEX GROUPS",
	Feature.SNAPSHOTS: "VARIATIONS",
	Feature.REPLACE_COLORS: "REPLACE COLORS",
	Feature.SINGLE_CHANNEL: "PAINT: SINGLE CHANNEL",
	Feature.FALLOFF: "BRUSH: FALLOFF CURVE",
	Feature.RESYNC_UVS: "MESH TOOLS: RE-SYNC UVS",
	Feature.EXPORT_OBJ: "MESH TOOLS: EXPORT AS OBJ",
	Feature.EXPORT_GLTF: "MESH TOOLS: EXPORT AS GLTF",
}


static func locked(_feature: int) -> bool:
	return not IS_PRO


static func alert_text(feature := -1) -> String:
	var label: String = FEATURE_NAMES.get(feature, "")
	return ALERT if label.is_empty() else "%s: %s" % [label, ALERT]
