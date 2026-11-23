shader_type canvas_item;

// Full-screen look: posterize, optional palette snap, ordered dither.
// Runs on a ColorRect in Main's ScreenEffect CanvasLayer, so it reads the
// finished frame (every camera, transparents, glow and tonemapping included)
// and sits under the HUD layers. Ported from
// explores/explore-shaders/outline-posterize-color-dither.gdshader, minus the
// outline, which needs the 3D depth/normal buffers a 2D shader can't read.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform bool enable_color_limit = true;
uniform int color_levels : hint_range(2, 48) = 32;

uniform bool enable_color_palette = false;
uniform vec4 color1 : source_color = vec4(1.0, 0.925, 0.839, 1.0);
uniform vec4 color2 : source_color = vec4(1.0, 0.831, 0.639, 1.0);
uniform vec4 color3 : source_color = vec4(1.0, 0.667, 0.369, 1.0);
uniform vec4 color4 : source_color = vec4(0.816, 0.506, 0.349, 1.0);
uniform vec4 color5 : source_color = vec4(0.553, 0.412, 0.478, 1.0);
uniform vec4 color6 : source_color = vec4(0.329, 0.306, 0.408, 1.0);
uniform vec4 color7 : source_color = vec4(0.125, 0.236, 0.337, 1.0);
uniform vec4 color8 : source_color = vec4(0.05, 0.169, 0.271, 1.0);

uniform bool enable_dithering = true;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;
// Screen pixels per dither cell; raise it for a chunkier pattern on big screens.
uniform float dither_pixel_size : hint_range(1.0, 8.0, 1.0) = 1.0;

float posterize(float val, int levels) {
	return round(val * float(levels)) / float(levels);
}

// 4x4 Bayer threshold: 1.0 if brightness clears this pixel's threshold.
float dither(vec2 position, float brightness) {
	int x = int(mod(position.x, 4.0));
	int y = int(mod(position.y, 4.0));
	const float bayer[16] = float[](
		0.0, 0.5, 0.125, 0.625,
		0.75, 0.25, 0.875, 0.375,
		0.1875, 0.6875, 0.0625, 0.5625,
		0.9375, 0.4375, 1.0, 0.8125
	);
	return brightness < bayer[x + y * 4] ? 0.0 : 1.0;
}

void fragment() {
	vec3 final_color = texture(screen_texture, SCREEN_UV).rgb;

	if (enable_color_limit) {
		final_color = vec3(
			posterize(final_color.r, color_levels),
			posterize(final_color.g, color_levels),
			posterize(final_color.b, color_levels));
	}

	if (enable_color_palette) {
		vec3 palette[8] = vec3[](
			color1.rgb, color2.rgb, color3.rgb, color4.rgb,
			color5.rgb, color6.rgb, color7.rgb, color8.rgb);
		vec3 closest_color = palette[0];
		vec3 d = final_color - palette[0];
		float closest_distance = dot(d, d);
		for (int i = 1; i < 8; i++) {
			d = final_color - palette[i];
			float dist = dot(d, d);
			if (dist < closest_distance) {
				closest_distance = dist;
				closest_color = palette[i];
			}
		}
		final_color = closest_color;
	}

	if (enable_dithering) {
		vec2 cell = floor(FRAGCOORD.xy / dither_pixel_size);
		float brightness = dot(final_color, vec3(0.3, 0.59, 0.11));
		brightness += dither_strength * (dither(cell, brightness) - 0.5);
		final_color *= 1.0 + dither_strength * (dither(cell, brightness) - 0.5);
	}

	COLOR = vec4(final_color, 1.0);
}
