shader_type canvas_item;
// ============================================================================
// UI WEATHER — procedural VHS-atmosphere layer for HUD widgets (noise meter,
// proximity monitor). Replaces the old screen-sampling bleed shader (R25 fix).
//
// WHY NOT hint_screen_texture: the screen texture is copied ONCE per frame at
// the FIRST sampling point in the render list — in this project that is the
// VHS pass on CanvasLayer 2, i.e. BEFORE any UI is drawn. A widget overlay
// that samples it therefore gets a stale copy (world only) and, being an
// opaque mix, PAINTS OVER the widget's own bezel/trace/fill with blurred world
// + grain. In-game that hid both widgets' content; captures without the VHS
// pass looked fine, which is why it slipped through.
//
// This shader samples NOTHING. It outputs only the atmosphere as a blended
// pattern layer over whatever the widget drew:
//   - animated film grain (white speckle)
//   - CRT scanline banding + edge vignette (black alpha)
//   - a cold grade tint wash
// all multiplied by `influence` and by a rounded-rect feather mask so the
// treatment melts into the screen at the corners instead of ending in a crisp
// rectangle (art direction R25: "blend it, round it").
// Chromatic bleed is done at DRAW time by the widgets (offset R/B fringe
// passes), which needs no sampling either.
// ============================================================================

group_uniforms Blend;
uniform float influence : hint_range(0.0, 1.0) = 1.0;

group_uniforms Grain;
uniform float grain_amount : hint_range(0.0, 0.4, 0.005) = 0.10;
uniform float grain_speed : hint_range(0.0, 60.0, 0.5) = 17.0;
// Grain cell size in PIXELS. Sub-pixel pattern periods alias into moire bands
// (the "shader only in the middle" artifact): keep >= 2.
uniform float grain_block_px : hint_range(1.0, 8.0, 0.5) = 2.0;

group_uniforms Scanline;
uniform float scanline_amount : hint_range(0.0, 0.5, 0.005) = 0.10;
// Scanline period in PIXELS. The old UV-space density (140 lines over a 44 px
// widget = 0.31 px period) was unresolvable and aliased into a smear band.
// Keep >= 2.0; 3.0 reads as fine CRT lines without moire.
uniform float scanline_period_px : hint_range(2.0, 12.0, 0.5) = 3.0;

group_uniforms Vignette;
uniform float vignette_amount : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float vignette_softness : hint_range(0.05, 4.0, 0.01) = 1.6;

group_uniforms Grade;
uniform vec3 grade_tint = vec3(0.86, 0.93, 0.90);
uniform float grade_amount : hint_range(0.0, 1.0, 0.01) = 0.10;

group_uniforms Mask;
// Widget rect in pixels, set from code each resize; used for a pixel-accurate
// rounded-corner feather so the effect has no crisp rectangle edges.
uniform vec2 rect_size = vec2(220.0, 44.0);
uniform float corner_radius : hint_range(0.0, 40.0, 0.5) = 8.0;
uniform float edge_feather : hint_range(0.0, 24.0, 0.5) = 4.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Rounded-rect SDF in pixel space (0 inside, positive outside).
float rounded_sdf(vec2 px, vec2 size, float rad) {
	vec2 q = abs(px - size * 0.5) - (size * 0.5 - vec2(rad));
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - rad;
}

void fragment() {
	float inf = clamp(influence, 0.0, 1.0);

	// Feathered rounded mask: 1 well inside, fading to 0 across the corner
	// ring and the outer feather.
	float d = rounded_sdf(UV * rect_size, rect_size, corner_radius);
	float mask = 1.0 - smoothstep(-edge_feather, 0.0, d);
	// Extra soft inner falloff so the treatment never reads as a sticker.
	mask *= 1.0 - 0.35 * smoothstep(-edge_feather * 3.0, -edge_feather, d);

	// Pixel-space coordinates: patterns must have resolvable periods or they
	// alias into moire bands on real hardware (R25c fix).
	vec2 px = UV * rect_size;

	// Film grain (bright speckle), quantised to grain_block_px cells.
	float g = hash21(floor(px / grain_block_px) + vec2(floor(TIME * grain_speed)));
	float light = max(0.0, g - 0.5) * 2.0 * grain_amount;

	// Scanline banding + edge vignette (dark).
	float sl = 0.5 + 0.5 * sin(px.y * (6.2831853 / scanline_period_px));
	vec2 dv = abs(UV - 0.5) * 2.0;
	float vig = vignette_amount * pow(max(dv.x, dv.y), vignette_softness);
	float dark = clamp(sl * scanline_amount + vig, 0.0, 1.0);

	// Grade tint wash (very light coloured veil).
	float tint_a = grade_amount * 0.5;

	// Single-layer approximation: strongest cue wins (dark veil, grain
	// speckle, or tint veil); the other two are subtle enough to drop.
	vec3 col = vec3(0.0);
	float a = dark;
	if (light > a && light > tint_a) {
		col = vec3(1.0);
		a = light;
	} else if (tint_a > a) {
		col = grade_tint;
		a = tint_a;
	}
	COLOR = vec4(col, a * inf * mask);
}
