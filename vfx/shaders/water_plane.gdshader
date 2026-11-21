// Stylised flat water: a scrolling base texture (cellular noise through a
// colour ramp) with a softer noise layer drifting over it in another
// direction, blended in the shader, a darker tint where the water is deep
// (see Bottom) and foam where it meets other geometry (see Edge).
//
// UVs are taken from world XZ, so the texture keeps its scale however the
// plane is sized or duplicated. Both textures must tile: tick `seamless` on
// any NoiseTexture2D used here, or the scroll shows a seam at each repeat.
shader_type spatial;

group_uniforms Base;
/** The main water texture (e.g. cellular noise with a colour ramp). */
uniform sampler2D base_tex : source_color, repeat_enable, filter_linear_mipmap;
/** Texture repeats per metre. 1/32 spans one repeat across a 32 m plane. */
uniform float base_scale = 0.03125;
/** Scroll direction in world XZ (normalised in the shader). */
uniform vec2 base_dir = vec2(1.0, 0.0);
/** Scroll speed in texture repeats per second. */
uniform float base_speed = 0.01;

group_uniforms Overlay;
/** Smooth greyscale noise layered over the base. */
uniform sampler2D overlay_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 overlay_color : source_color = vec4(0.85, 1.0, 0.95, 1.0);
uniform float overlay_opacity : hint_range(0.0, 1.0) = 0.35;
uniform float overlay_scale = 0.02;
uniform vec2 overlay_dir = vec2(-0.4, 1.0);
uniform float overlay_speed = 0.006;
/** Remaps the noise: values below low vanish, above high are full strength. */
uniform float overlay_low : hint_range(0.0, 1.0) = 0.3;
uniform float overlay_high : hint_range(0.0, 1.0) = 0.8;
/** 0 = smooth. Above 0, bands the overlay into that many flat steps. */
uniform int overlay_steps : hint_range(0, 16) = 0;
/** 0 = mix, 1 = add, 2 = screen. */
uniform int overlay_blend : hint_enum("Mix", "Add", "Screen") = 0;

group_uniforms Edge;
// Foam where the water touches other meshes. The shader reads the depth buffer
// (what's already drawn behind the water), rebuilds the world position of that
// pixel and measures how far below the water surface it is. Near zero means
// "something is right at the waterline here". Reading the depth buffer puts
// the water in Godot's transparent pass (drawn after opaque meshes).
uniform bool edge_enabled = true;
uniform vec4 edge_color : source_color = vec4(0.92, 1.0, 0.96, 1.0);
/** How deep (metres, measured vertically) the foam reaches below the surface. */
uniform float edge_width : hint_range(0.0, 3.0, 0.01) = 0.35;
/** 0 = hard-edged band, 1 = a soft fade out to edge_width. */
uniform float edge_softness : hint_range(0.0, 1.0) = 0.3;
/** How much noise eats into the foam band so it isn't a clean outline. */
uniform float edge_breakup : hint_range(0.0, 1.0) = 0.5;
/** Breakup noise (samples overlay_tex): repeats per metre, direction, speed. */
uniform float edge_noise_scale = 0.4;
uniform vec2 edge_noise_dir = vec2(0.0, 1.0);
uniform float edge_noise_speed = 0.05;

group_uniforms Bottom;
// Darkens the water where the floor is far below the surface, using the same
// depth-buffer reconstruction as Edge. Drawn under the overlay and the foam.
uniform bool bottom_enabled = true;
uniform vec4 bottom_color : source_color = vec4(0.0, 0.05, 0.12, 1.0);
/** How strongly the deepest water takes on bottom_color. */
uniform float bottom_strength : hint_range(0.0, 1.0) = 0.6;
/** Water depth (metres) where the darkening starts and where it is full. */
uniform float bottom_start : hint_range(0.0, 10.0, 0.05) = 0.2;
uniform float bottom_full : hint_range(0.0, 20.0, 0.05) = 2.0;
/** Static smooth noise laid on the floor, so the deep areas look uneven. */
uniform sampler2D bottom_tex : hint_default_white, repeat_enable, filter_linear_mipmap;
/** Noise repeats per metre (sampled at the floor point, so it doesn't move). */
uniform float bottom_noise_scale = 0.08;
/** 0 = depth alone, 1 = noise fully modulates the darkening. */
uniform float bottom_noise_amount : hint_range(0.0, 1.0) = 0.6;

group_uniforms;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

group_uniforms Surface;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

group_uniforms;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 scrolled_uv(float scale, vec2 dir, float speed) {
	vec2 d = length(dir) > 0.0 ? normalize(dir) : vec2(0.0);
	return world_pos.xz * scale + d * speed * TIME;
}

void fragment() {
	// Depth reconstruction, shared by Bottom and Edge.
	// 1. Depth of whatever opaque surface is behind the water at this pixel.
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	// 2. Screen position + depth -> clip space -> world space.
	//    (Godot 4.3+ uses reversed Z and keeps depth in 0..1, so only XY
	//    are remapped to -1..1.)
	vec4 clip = vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * clip;
	view /= view.w;
	vec3 scene_world = (INV_VIEW_MATRIX * view).xyz;
	// 3. How far below this bit of water surface that point lies.
	float water_depth = world_pos.y - scene_world.y;

	vec3 col = texture(base_tex, scrolled_uv(base_scale, base_dir, base_speed)).rgb;

	if (bottom_enabled) {
		// 0 at bottom_start metres deep, 1 at bottom_full and beyond.
		float deep = smoothstep(bottom_start, max(bottom_full, bottom_start + 0.001), water_depth);
		// Noise sampled at the floor point, not the surface, with no TIME:
		// it stays put on the bottom and shifts with parallax as you move.
		float bn = texture(bottom_tex, scene_world.xz * bottom_noise_scale).r;
		deep *= mix(1.0, bn, bottom_noise_amount);
		col = mix(col, bottom_color.rgb, deep * bottom_strength * bottom_color.a);
	}

	float n = texture(overlay_tex, scrolled_uv(overlay_scale, overlay_dir, overlay_speed)).r;
	n = smoothstep(overlay_low, max(overlay_high, overlay_low + 0.001), n);
	if (overlay_steps > 0) {
		float steps = float(overlay_steps);
		n = floor(n * steps + 0.5) / steps;
	}
	float a = n * overlay_opacity * overlay_color.a;
	vec3 o = overlay_color.rgb;

	if (overlay_blend == 1) {
		col = col + o * a;
	} else if (overlay_blend == 2) {
		col = 1.0 - (1.0 - col) * (1.0 - o * a);
	} else {
		col = mix(col, o, a);
	}

	if (edge_enabled) {
		// 4. 1 at the contact line, falling to 0 at edge_width deep.
		float shore = 1.0 - clamp(water_depth / max(edge_width, 0.001), 0.0, 1.0);
		// 5. Noise raises the threshold in patches, so the band breaks up.
		float en = texture(overlay_tex, scrolled_uv(edge_noise_scale, edge_noise_dir, edge_noise_speed)).r;
		float cut = en * edge_breakup;
		float foam = smoothstep(cut, cut + max(edge_softness, 0.001), shore);
		col = mix(col, edge_color.rgb, foam * edge_color.a);
	}

	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
