extends Control
## ============================================================================
## PROXIMITY TRACE — the drawn half of ProximityMonitor.
##
## Separate node for the same reason as NoiseMeterBar: the CONTACT jitter and
## the hide-slide live on THIS node's offset_transform, so the art has to be
## drawn here to stay glued to it. Reads everything from `owner` duck-typed
## (no class_name both ways — circular class_name deps do not parse).
##
## Drawn, not textured: bezel, inner screen, centre phosphor glow (runtime
## radial gradient), the heartbeat polyline (wide glow pass + bright core),
## contact clip/glitch, segment LEDs and the optional label.
## ============================================================================

## Set by ProximityMonitor._ready(). (Named `monitor`, not `owner`: `owner` is
## a built-in Node property and cannot be shadowed.) Standalone (mockup) use:
## draws a calm flatline instead of crashing.
var monitor: Node = null

var _glow_tex: Texture2D = null
var _t: float = 0.0
## Telemetry: how many times _draw() actually painted (selftest/repro).
var debug_draw_calls: int = 0


func _ready() -> void:
	_glow_tex = _make_radial_glow(96)


func _process(delta: float) -> void:
	_t += delta
	if not visible:
		return
	queue_redraw()


## Soft radial blob, generated once: the mockup's hot phosphor middle.
func _make_radial_glow(dim: int) -> Texture2D:
	var img := Image.create(dim, dim, false, Image.FORMAT_RGBA8)
	var c: float = (dim - 1) * 0.5
	for y in range(dim):
		for x in range(dim):
			var d: float = Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)   # smoothstep falloff
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Lub-dub: sharp lub, small negative rebound, softer dub. Period = 1.0.
func _heartbeat(u: float) -> float:
	u = u - floor(u)
	# Sigmas are tuned against the 1 px draw step: narrower gaussians get
	# undersampled and the lub-dub collapses into a ripple (R25 capture bug).
	return 1.00 * exp(-pow((u - 0.10) / 0.038, 2.0)) \
		- 0.30 * exp(-pow((u - 0.190) / 0.055, 2.0)) \
		+ 0.55 * exp(-pow((u - 0.310) / 0.048, 2.0))


func _draw() -> void:
	debug_draw_calls += 1
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 4.0 or r.size.y <= 4.0:
		return

	var prox: float = 0.0
	var phase: float = 0.0
	var col: Color = Color(0.62, 0.78, 0.60)
	var alpha: float = 0.35
	var amp: float = 0.06
	var band: int = 0
	var glow: float = 0.55
	var leds: int = 4
	var led_col: Color = Color(0.95, 0.2, 0.16)
	var label: bool = false
	var label_col: Color = Color(0.85, 0.9, 0.82, 0.9)
	var width: float = 2.0
	var clip: float = 0.8
	var jitter: float = 0.1
	var noise: FastNoiseLite = null
	if monitor != null:
		prox = float(monitor.call("current_prox"))
		phase = float(monitor.call("beat_phase"))
		col = monitor.call("trace_color")
		alpha = float(monitor.call("trace_alpha"))
		amp = float(monitor.call("trace_amp"))
		band = int(monitor.call("band_index"))
		glow = float(monitor.get("glow_strength"))
		leds = int(monitor.get("led_count"))
		led_col = monitor.get("led_color")
		label = bool(monitor.get("show_label"))
		label_col = monitor.get("label_color")
		width = float(monitor.get("trace_width"))
		clip = float(monitor.get("clip_top"))
		jitter = float(monitor.get("jitter_amount"))
		noise = monitor.call("jitter_seed_noise")

	# ── Bezel + screen ───────────────────────────────────────────────────────
	draw_colored_polygon(UiDrawUtil.rounded_points(r, 6.0), Color(0.055, 0.058, 0.062, 0.88))
	draw_polyline(UiDrawUtil.closed(UiDrawUtil.rounded_points(r, 6.0)), Color(0.24, 0.26, 0.28, 0.8), 1.0)
	var screen := r.grow(-3.0)
	draw_colored_polygon(UiDrawUtil.rounded_points(screen, 4.0), Color(0.045, 0.065, 0.055, 0.92))

	# ── Centre phosphor glow ─────────────────────────────────────────────────
	if _glow_tex != null and glow > 0.001:
		var g_strength: float = glow * (0.35 + 0.65 * prox) * alpha
		var gr: Rect2 = Rect2(screen.position + screen.size * 0.5 - screen.size * 0.55,
			screen.size * 1.1)
		draw_texture_rect(_glow_tex, gr, false, Color(col.r, col.g, col.b, g_strength * 0.5))

	# ── Heartbeat trace: glow pass then core pass ────────────────────────────
	var inner := screen.grow(-2.0)
	var mid_y: float = inner.position.y + inner.size.y * 0.5
	var half_h: float = inner.size.y * 0.5
	var cycles: float = 2.0
	var pts := PackedVector2Array()
	var x: float = 0.0
	var step: float = 1.0
	while x <= inner.size.x:
		var u: float = x / maxf(inner.size.x, 1.0) * cycles + phase
		var h: float = _heartbeat(u)
		var jy: float = 0.0
		var jx: float = 0.0
		if noise != null:
			jy = noise.get_noise_1d(x * 0.35 + phase * 3.1) * jitter * prox * half_h * 0.35
		# CONTACT tears: occasional 1-2 px horizontal rips in the sample.
		if band == 3 and noise != null:
			var g: float = noise.get_noise_1d(x * 1.7 + floor(_t * 18.0) * 13.7)
			if g > 0.82:
				jx = 2.0
		var y: float = mid_y - amp * half_h * h - jy
		# Flat-top clipping once the amplitude exceeds the clip fraction.
		var lim: float = clip * half_h
		y = clampf(y, mid_y - lim, mid_y + lim)
		pts.push_back(Vector2(inner.position.x + x + jx, y))
		x += step
	if pts.size() >= 2:
		# Chromatic bleed at DRAW time: offset R/B fringe passes peeking
		# out from under the core line. No screen-texture sampling, so it
		# works identically in-game and in captures (see ui_weather.gdshader).
		var bleed: float = 1.5
		if monitor != null:
			bleed = float(monitor.get("bleed_pixels"))
		if bleed > 0.05:
			var pr := PackedVector2Array(pts)
			var pb := PackedVector2Array(pts)
			for k in range(pr.size()):
				pr[k] = pr[k] + Vector2(-bleed, 0.0)
				pb[k] = pb[k] + Vector2(bleed, 0.0)
			draw_polyline(pr, Color(col.r, 0.0, 0.0, alpha * 0.30), width, true)
			draw_polyline(pb, Color(0.0, 0.0, col.b, alpha * 0.30), width, true)
		draw_polyline(pts, Color(col.r, col.g, col.b, alpha * 0.28), width * 3.0, true)
		draw_polyline(pts, Color(col.r, col.g, col.b, alpha), width, true)

	# ── Segment LEDs ─────────────────────────────────────────────────────────
	if leds > 0:
		var lit: int = int(roundf(clampf(prox, 0.0, 1.0) * float(leds)))
		var blink: float = 1.0
		if band == 3:
			blink = 0.45 + 0.55 * (1.0 if sin(_t * 14.0) > 0.0 else 0.0)
			lit = leds
		var lw: float = 5.0
		var gap: float = 3.0
		var x0: float = r.end.x - 4.0 - float(leds) * (lw + gap) + gap
		for k in range(leds):
			var lr := Rect2(x0 + float(k) * (lw + gap), r.end.y - 7.0, lw, 3.0)
			if k < lit:
				draw_rect(lr, Color(led_col.r, led_col.g, led_col.b, blink), true)
			else:
				draw_rect(lr, Color(0.16, 0.17, 0.18, 0.9), true)

	# ── Optional label (art direction: off by default) ───────────────────────
	if label:
		var names: Array[String] = ["TRK FAR", "TRK NEAR", "TRK CLOSE", "TRK CONTACT"]
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(r.position.x + 2.0, r.position.y - 4.0),
			names[band], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, label_col)
