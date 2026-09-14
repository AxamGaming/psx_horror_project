class_name UiDrawUtil
extends RefCounted
## ============================================================================
## UI DRAW UTIL — shared rounded-rect geometry for the HUD trace widgets.
##
## R32: extracted from noise_meter_bar.gd and proximity_trace.gd, which
## carried byte-identical copies of both helpers (STATE agenda item 7).
## Static-only on purpose: callers use UiDrawUtil.rounded_points(...) and
## UiDrawUtil.closed(...) with no instance and no signal wiring, keeping the
## "UI de-hardcoded" convention intact (widgets keep their own _draw()).
## ============================================================================


## Outline points of a rounded rectangle, clockwise from the top-right corner.
## `seg` arc segments per corner; 6 is plenty at HUD scale and cheap to draw.
static func rounded_points(r: Rect2, rad: float, seg: int = 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	rad = clampf(rad, 0.0, minf(r.size.x, r.size.y) * 0.5)
	if rad <= 0.01:
		pts.push_back(r.position)
		pts.push_back(Vector2(r.end.x, r.position.y))
		pts.push_back(r.end)
		pts.push_back(Vector2(r.position.x, r.end.y))
		return pts
	var centers := [
		Vector2(r.end.x - rad, r.position.y + rad),     # top-right
		Vector2(r.end.x - rad, r.end.y - rad),          # bottom-right
		Vector2(r.position.x + rad, r.end.y - rad),     # bottom-left
		Vector2(r.position.x + rad, r.position.y + rad) # top-left
	]
	var starts := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for c in range(4):
		for i in range(seg + 1):
			var a: float = starts[c] + (PI * 0.5) * float(i) / float(seg)
			pts.push_back(centers[c] + Vector2(cos(a), sin(a)) * rad)
	return pts


## Closes a polygon outline so draw_polyline() draws the final edge too.
static func closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	if out.size() > 0:
		out.push_back(out[0])
	return out
