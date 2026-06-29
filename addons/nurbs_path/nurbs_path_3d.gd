@tool
class_name NurbsPath3D
extends Path3D

## A control-polygon rail authored as a uniform cubic B-spline and baked EXACTLY
## into this Path3D's `Curve3D` (a cubic Bézier spline).
##
## Why this works losslessly: a uniform cubic B-spline converts segment-for-
## segment into cubic Bézier, which is precisely what Curve3D stores. So the
## curve a PathFollow3D walks is mathematically identical to the B-spline you
## drew — no sampling, no error. `levels/rail_follower.gd` consumes the baked
## `curve` unchanged.
##
## Authoring model: you place CONTROL POINTS; the curve flows smoothly near them
## (it does not pass through the interior ones — that's the B-spline trade that
## buys you tangent-free editing). The OPEN curve is clamped at the ends via
## reflected phantom points, so it interpolates the first and last control point
## with a sensible tangent. The CLOSED curve wraps into a seamless loop (pair it
## with PathFollow3D `loop = true`).
##
## Despite the "Nurbs" name (matching how rails are discussed in this project)
## this is the NON-rational case — no per-point weights. Rational NURBS (exact
## circular arcs) would add a `weights` array and bake by sampling; not needed
## for rails, so it's intentionally omitted. The name leaves room to add it.

## The control polygon. Drag these in the viewport (the gizmo), or edit them
## here. The baked rail is regenerated on every change.
@export var control_points: Array[Vector3] = []:
	set(value):
		control_points = value
		_rebuild()

## Wrap the control polygon into a seamless closed loop. Use PathFollow3D
## `loop = true` so the rig laps it forever.
@export var closed: bool = false:
	set(value):
		closed = value
		_rebuild()


func _ready() -> void:
	# Seed a visible starter rail so a freshly-added node isn't an invisible
	# nothing — gives you four handles to start dragging immediately.
	if control_points.is_empty():
		control_points = [
			Vector3(0.0, 0.0, 0.0),
			Vector3(0.0, 0.0, -6.0),
			Vector3(6.0, 0.0, -12.0),
			Vector3(6.0, 0.0, -18.0),
		]
	_rebuild()


## Regenerate `curve` from the control polygon. Cheap enough to run on every
## handle drag for the point counts a rail uses.
func _rebuild() -> void:
	var c := Curve3D.new()
	var pts := control_points
	var m := pts.size()

	if m < 2:
		if m == 1:
			c.add_point(pts[0])
		curve = c
		update_gizmos()
		return

	if closed and m >= 3:
		_assemble_closed(c, _segments_closed(pts))
	else:
		# Reflected phantom endpoints clamp the open curve so it interpolates the
		# first/last control point. With them, even m == 2 yields one valid
		# segment (a straight run), so there's no separate low-count fallback.
		_assemble_open(c, _segments_open(_phantom_extend(pts)))

	curve = c
	update_gizmos()


## One uniform-cubic-B-spline-to-Bézier segment from four consecutive control
## points. Returns [V0, V1, V2, V3]: V0/V3 are the on-curve knot endpoints,
## V1/V2 the inner Bézier handles. (Standard subdivision-matrix conversion.)
func _seg(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> Array:
	return [
		(p0 + 4.0 * p1 + p2) / 6.0,
		(4.0 * p1 + 2.0 * p2) / 6.0,
		(2.0 * p1 + 4.0 * p2) / 6.0,
		(p1 + 4.0 * p2 + p3) / 6.0,
	]


## Prepend/append reflected phantom points so the open curve is clamped to its
## endpoints: P[-1] = 2*P0 - P1 makes segment 0's V0 land exactly on P0 with a
## tangent toward P1 (and symmetrically at the tail).
func _phantom_extend(pts: Array[Vector3]) -> Array:
	var m := pts.size()
	var ext: Array = [2.0 * pts[0] - pts[1]]
	ext.append_array(pts)
	ext.append(2.0 * pts[m - 1] - pts[m - 2])
	return ext


func _segments_open(ext: Array) -> Array:
	var segs: Array = []
	for k in range(ext.size() - 3):
		segs.append(_seg(ext[k], ext[k + 1], ext[k + 2], ext[k + 3]))
	return segs


func _segments_closed(pts: Array[Vector3]) -> Array:
	var m := pts.size()
	var segs: Array = []
	for k in range(m):
		segs.append(_seg(pts[k], pts[(k + 1) % m], pts[(k + 2) % m], pts[(k + 3) % m]))
	return segs


## Knot points are shared between adjacent segments (segment k's V3 == segment
## k+1's V0), so the in/out handles read straight off the neighbouring segments.
func _assemble_open(c: Curve3D, segs: Array) -> void:
	var sc := segs.size()
	c.add_point(segs[0][0], Vector3.ZERO, segs[0][1] - segs[0][0])
	for k in range(1, sc):
		var pos: Vector3 = segs[k][0]
		c.add_point(pos, segs[k - 1][2] - pos, segs[k][1] - pos)
	var last: Array = segs[sc - 1]
	c.add_point(last[3], last[2] - last[3], Vector3.ZERO)


func _assemble_closed(c: Curve3D, segs: Array) -> void:
	var sc := segs.size()
	for k in range(sc):
		var pos: Vector3 = segs[k][0]
		c.add_point(pos, segs[(k - 1 + sc) % sc][2] - pos, segs[k][1] - pos)
	# Repeat the first knot to close the gap so PathFollow3D laps seamlessly.
	var pos0: Vector3 = segs[0][0]
	c.add_point(pos0, segs[sc - 1][2] - pos0, Vector3.ZERO)
