shader_type canvas_item;

// Soft glow that follows a cut-out icon's alpha (a drop shadow with no offset).
//
// The icon is drawn inset by `padding` on each side, so the glow has room inside
// the rect — a TextureRect only draws within its own bounds. Tween `glow_amount`
// 0 → 1 to fade the glow in.

uniform vec4 glow_color : source_color = vec4(1.0);
uniform float glow_amount : hint_range(0.0, 1.0) = 0.0;
// Spread, as a fraction of the icon's size.
uniform float glow_radius : hint_range(0.0, 0.3) = 0.08;
// Glow opacity at full amount (the halo is summed from many taps, so keep < 1).
uniform float glow_strength : hint_range(0.0, 4.0) = 1.6;
// Inset on each side, as a fraction of the rect.
uniform float padding : hint_range(0.0, 0.4) = 0.15;

// 1 inside the 0–1 UV square, 0 outside (the inset padding).
float inside(vec2 uv) {
	vec2 s = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return s.x * s.y;
}

void fragment() {
	vec2 uv = (UV - 0.5) * (1.0 + 2.0 * padding) + 0.5;
	vec4 icon = vec4(0.0);
	if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
		icon = texture(TEXTURE, uv) * COLOR;
	}

	float halo = 0.0;
	if (glow_amount > 0.0) {
		// Two rings of 12 taps: a cheap blur of the alpha.
		const int TAPS = 12;
		for (int ring = 1; ring <= 2; ring++) {
			float r = glow_radius * float(ring) * 0.5;
			for (int i = 0; i < TAPS; i++) {
				float a = TAU * (float(i) + 0.5 * float(ring)) / float(TAPS);
				vec2 tap = uv + vec2(cos(a), sin(a)) * r;
				halo += texture(TEXTURE, tap).a * inside(tap);
			}
		}
		halo = clamp(halo / float(TAPS * 2) * glow_strength, 0.0, 1.0) * glow_amount;
	}

	// Icon over glow.
	vec4 glow = vec4(glow_color.rgb, glow_color.a * halo * COLOR.a);
	COLOR = vec4(mix(glow.rgb, icon.rgb, icon.a), icon.a + glow.a * (1.0 - icon.a));
}
