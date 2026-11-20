shader_type canvas_item;

// Darkens the edges of the screen. Tween `amount` 0 → 1 to bring it in.

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Distance from the centre (0 = centre, 1 = corners) where darkening begins…
uniform float inner : hint_range(0.0, 1.0) = 0.3;
// …and where it reaches full `opacity`.
uniform float outer : hint_range(0.0, 1.5) = 0.85;
uniform float opacity : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	// 0 at the centre, ~0.71 mid-edge, 1 in the corners; follows the screen's shape.
	float d = length((SCREEN_UV - 0.5) * 2.0) * 0.7071;
	float dark = smoothstep(inner, outer, d) * opacity * amount;
	COLOR = vec4(color.rgb, color.a * dark);
}
