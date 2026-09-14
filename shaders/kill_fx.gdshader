shader_type canvas_item;
// ============================================================================
// KILL FX (R30) — full-screen post pass for the creature-kill cutscene.
//
// One ColorRect on CanvasLayer 4 (above the VHS layer 2 and the HUD layer 1,
// below the crisp UI layer 10), sampling the screen AFTER the VHS pass so the
// scare effects sit on top of the tape grain, not under it.
//
// Everything is driven by uniforms the KillDirector pushes per frame; at rest
// (all uniforms 0) the pass is a straight screen copy, so leaving the node
// visible between kills costs one fullscreen sample and nothing else.
//
// Looks implemented (design R30):
//   flash    red impact bloom (additive, capped by Settings.reduce_flashes)
//   chroma   radial chromatic aberration — the lens "punch-through"
//   tear     horizontal scanline bands torn sideways (tape damage read)
//   vignette pulsing dark iris closing on the edges
//   smear    blood/dust on the lens after the crash (real texture, not noise)
//   desat    slow colour drain into the death fade
//   grain    coarse PSX dither over the top
// ============================================================================

group_uniforms KillFX;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(0.62, 0.02, 0.01, 1.0);
uniform float chroma : hint_range(0.0, 1.0) = 0.0;
uniform float tear : hint_range(0.0, 1.0) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform float smear : hint_range(0.0, 1.0) = 0.0;
uniform float desat : hint_range(0.0, 1.0) = 0.0;
uniform float grain : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 0.0;   // narrative black-out (unscaled by settings)
uniform float jolt_px : hint_range(0.0, 24.0) = 0.0;
uniform float clock : hint_range(0.0, 10000.0) = 0.0;

uniform sampler2D Source : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D Lens : repeat_disable;   // lens_blood.png

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Tape tear: a few horizontal bands slide sideways.
	if (tear > 0.001) {
		float band = floor(uv.y * 22.0 + clock * 3.0);
		float r = hash12(vec2(band, floor(clock * 11.0)));
		float amt = step(0.70, r) * (r - 0.70) / 0.30;
		uv.x += (amt - 0.5) * 0.11 * tear;
	}
	// Whole-frame sub-pixel jolt (the camera-being-hit read).
	if (jolt_px > 0.001) {
		uv += vec2(hash12(vec2(clock, 1.7)) - 0.5, hash12(vec2(clock, 8.3)) - 0.5)
				* jolt_px * vec2(1.0 / 640.0, 1.0 / 360.0);
	}
	uv = clamp(uv, vec2(0.001), vec2(0.999));

	vec2 c = uv - 0.5;
	float r2 = dot(c, c);

	// Radial chromatic aberration: worst at the corners, like real glass.
	float ca = chroma * (0.0018 + 0.014 * r2);
	vec3 col;
	col.r = texture(Source, uv + c * ca).r;
	col.g = texture(Source, uv).g;
	col.b = texture(Source, uv - c * ca).b;

	// Blood/dust smeared on the lens after the crash.
	if (smear > 0.001) {
		vec4 lens = texture(Lens, uv * vec2(1.0, 0.8) + vec2(0.0, 0.1));
		col = mix(col, lens.rgb * 1.5, clamp(lens.a * smear, 0.0, 0.88));
	}

	// Colour drain into the death fade.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum) * vec3(0.92, 0.95, 1.0), desat);

	// Pulsing iris.
	float vig = smoothstep(0.80, 0.12, r2 * (1.0 + 1.8 * vignette));
	col *= mix(1.0, vig, clamp(vignette, 0.0, 1.0) * 0.9);

	// Red impact bloom.
	col = mix(col, flash_color.rgb * 1.45, clamp(flash, 0.0, 1.0) * 0.88);

	// Coarse dither.
	if (grain > 0.001) {
		col += (hash12(uv * vec2(640.0, 360.0) + clock) - 0.5) * grain * 0.14;
	}

	// Narrative fade to black (death hand-off); never gated by settings.
	col = mix(col, vec3(0.0), clamp(fade, 0.0, 1.0));

	COLOR = vec4(col, 1.0);
}
