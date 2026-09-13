extends Control
## ============================================================================
## NOISE METER BAR — the drawn half of the noise meter.
##
## WHY THIS IS A SEPARATE NODE (and not just _draw() on NoiseMeter):
##   The internal loudness shake and the menu hide-slide are applied to THIS
##   node via offset_transform_*. Anything drawn by the PARENT does not follow
##   that offset, so the bar art has to live here to stay glued to its own
##   transform. BleedOverlay is a child of this node for the same reason — it
##   must ride the shake to stay aligned with the pixels it re-samples.
##
## WHY `owner_meter` IS UNTYPED (no `class_name` here either):
##   NoiseMeter needs to type its `$Bar` as this script, and this script needs
##   to call back into NoiseMeter. Naming both classes creates a circular
##   class_name dependency that GDScript rejects at parse time
##   ("Could not find type X in the current scope"). Breaking the cycle here is
##   cheaper than breaking it there: the meter's API is tiny and stable, so the
##   callback is duck-typed. This matches the project's existing habit of
##   `float(_player.get("noise_level"))` in tests/fly_selftest.gd.
##
## Deliberately dumb: no state, no timers, no signal connections. It draws
## whatever the meter reports and asks for a redraw only when that value moves.
## All tunables live on NoiseMeter, so there is exactly one inspector surface.
## ============================================================================

## Set by NoiseMeter._ready(). May be null if this node is dropped into a
## mockup scene standalone — it then draws a representative empty track.
var owner_meter: Node = null


func _process(_delta: float) -> void:
	if owner_meter == null:
		return
	# Redraw only when something actually changed — a calm, fully settled meter
	# should not burn a draw call every frame.
	if bool(owner_meter.call("needs_bar_redraw")):
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return

	if owner_meter == null:
		# Standalone mockup path: no meter to read. Literals are intentional
		# here — this branch has no inspector surface to read from.
		var fb := _rounded_points(r, 4.0)
		draw_colored_polygon(fb, Color(0.09, 0.10, 0.11, 0.78))
		draw_polyline(_closed(fb), Color(0.26, 0.28, 0.30, 0.85), 1.0)
		return

	var v: float = clampf(float(owner_meter.call("displayed_noise")), 0.0, 1.0)

	# Stamp what we are about to paint BEFORE painting, so the meter's
	# needs_bar_redraw() compares against the last value actually drawn.
	owner_meter.call("mark_bar_drawn", v)

	var track: Color = owner_meter.get("track_color")
	var border: Color = owner_meter.get("border_color")
	var border_w: float = owner_meter.get("border_width")
	var pad: float = owner_meter.get("fill_padding")

	# ── Track + frame (rounded) ────────────────────────────────────────────────
	# draw_rect() cannot round corners, and the spec asks for a rounded track
	# with a faint border, so both are drawn from an explicit rounded polygon.
	var track_pts := _rounded_points(r, float(owner_meter.get("corner_radius")))
	draw_colored_polygon(track_pts, track)
	if border_w > 0.0:
		draw_polyline(_closed(track_pts), border, border_w)

	var inner := r.grow(-pad)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	# ── Tick marks (decorative scale cues) ───────────────────────────────────
	var ticks: int = owner_meter.get("tick_count")
	if ticks > 1:
		var tick_col: Color = owner_meter.get("tick_color")
		var tick_w: float = owner_meter.get("tick_width")
		for i in range(1, ticks):
			var x: float = inner.position.x + inner.size.x * float(i) / float(ticks)
			draw_line(
				Vector2(x, inner.position.y),
				Vector2(x, inner.position.y + inner.size.y),
				tick_col, tick_w)

	# ── Fill, left -> right (rounded pill) ─────────────────────────────────────
	var fill_w: float = inner.size.x * v
	if fill_w > 0.0:
		var col: Color = owner_meter.call("fill_color_for", v)
		var fr := Rect2(inner.position, Vector2(fill_w, inner.size.y))
		var frad: float = maxf(0.0, float(owner_meter.get("corner_radius")) - pad)
		# Draw-time chromatic bleed fringes (see ui_weather.gdshader header):
		# offset R/B slabs peeking out from under the core fill.
		var bleed: float = float(owner_meter.get("bleed_pixels"))
		if bleed > 0.05:
			var fr_r := Rect2(fr.position + Vector2(-bleed, 0.0), fr.size)
			var fr_b := Rect2(fr.position + Vector2(bleed, 0.0), fr.size)
			draw_colored_polygon(_rounded_points(fr_r, frad), Color(col.r, 0.0, 0.0, 0.30))
			draw_colored_polygon(_rounded_points(fr_b, frad), Color(0.0, 0.0, col.b, 0.30))
		draw_colored_polygon(_rounded_points(fr, frad), col)


# ── rounded-rect geometry ────────────────────────────────────────────────────

## Outline points of a rounded rectangle, clockwise from the top-right corner.
## `seg` arc segments per corner; 6 is plenty at HUD scale and cheap to draw.
func _rounded_points(r: Rect2, rad: float, seg: int = 6) -> PackedVector2Array:
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
func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	if out.size() > 0:
		out.push_back(out[0])
	return out
