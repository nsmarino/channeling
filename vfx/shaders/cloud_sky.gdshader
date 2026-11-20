// Stylized sky with drifting clouds.
//
// The gradient and sun reproduce ProceduralSkyMaterial (same knobs, same math), so
// swapping this in keeps the look you had; the clouds are two layers of scrolling
// noise projected onto a flat ceiling, so they shrink with distance toward the horizon.
//
// Uses TIME, so Godot renders the sky in real-time mode (radiance updated every frame).
// If that ever shows up in a profile, set wind_speed to 0 and remove TIME below.
shader_type sky;
render_mode use_debanding;

group_uniforms Sky;
uniform vec3 sky_top_color : source_color = vec3(0.385, 0.454, 0.55);
uniform vec3 sky_horizon_color : source_color = vec3(0.646, 0.656, 0.67);
uniform float sky_curve : hint_range(0.001, 1.0) = 0.15;
uniform vec3 ground_bottom_color : source_color = vec3(0.2, 0.169, 0.133);
uniform vec3 ground_horizon_color : source_color = vec3(0.646, 0.656, 0.67);
uniform float ground_curve : hint_range(0.001, 1.0) = 0.02;
uniform float sky_energy : hint_range(0.0, 16.0) = 1.0;

group_uniforms Sun;
// Halo around the disc, in degrees. The disc itself is the light's angular size.
uniform float sun_angle_max : hint_range(0.0, 360.0) = 30.0;
uniform float sun_curve : hint_range(0.001, 1.0) = 0.15;

group_uniforms Clouds;
uniform vec3 cloud_color : source_color = vec3(0.96, 0.93, 1.0);
// Colour of the thick, sun-facing-away parts.
uniform vec3 cloud_shadow_color : source_color = vec3(0.56, 0.47, 0.72);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
// Edge width: low = hard cartoon edges, high = wispy.
uniform float cloud_softness : hint_range(0.005, 0.5) = 0.12;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.9;
// Bigger = bigger clouds.
uniform float cloud_size : hint_range(0.05, 4.0) = 0.6;
// Small breakup noise eaten out of the big shapes.
uniform float detail_strength : hint_range(0.0, 1.0) = 0.35;
uniform float detail_size : hint_range(0.05, 1.0) = 0.3;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_speed : hint_range(0.0, 0.5) = 0.015;
// How far above the horizon the clouds fade in (EYEDIR.y units).
uniform float horizon_fade : hint_range(0.001, 0.5) = 0.12;
// 0 = smooth shading; 2-4 = banded, cel-shaded clouds.
uniform int shade_steps : hint_range(0, 6) = 0;
// Bright rim on clouds near the sun.
uniform float silver_lining : hint_range(0.0, 4.0) = 0.8;
// How much the sun's colour tints the clouds.
uniform float sun_tint : hint_range(0.0, 1.0) = 0.25;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

// Normalized to roughly 0..1.
float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	float total = 0.0;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < octaves; i++) {
		v += a * value_noise(p);
		total += a;
		p = rot * p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v / total;
}

float cloud_density(vec2 uv, vec2 drift) {
	float base = fbm(uv / cloud_size + drift, 5);
	float detail = fbm(uv / (cloud_size * detail_size) + drift * 1.7, 3);
	float n = base - (detail - 0.5) * detail_strength * 0.5;
	// Coverage 0 -> threshold above anything fbm reaches; 1 -> below everything.
	float threshold = mix(0.78, 0.22, cloud_coverage);
	return smoothstep(threshold - cloud_softness, threshold + cloud_softness, n);
}

void sky() {
	float v_angle = acos(clamp(EYEDIR.y, -1.0, 1.0));
	vec3 col;

	if (EYEDIR.y >= 0.0) {
		float c = 1.0 - v_angle / (PI * 0.5);
		col = mix(sky_horizon_color, sky_top_color, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	} else {
		float c = (v_angle - PI * 0.5) / (PI * 0.5);
		col = mix(ground_horizon_color, ground_bottom_color, clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
	}
	col *= sky_energy;

	float sun_angle = PI;
	if (LIGHT0_ENABLED) {
		sun_angle = acos(clamp(dot(LIGHT0_DIRECTION, EYEDIR), -1.0, 1.0));
		vec3 sun = LIGHT0_COLOR * LIGHT0_ENERGY;
		float halo_max = radians(sun_angle_max);
		if (sun_angle < LIGHT0_SIZE) {
			col = sun;
		} else if (sun_angle < halo_max) {
			float c2 = (sun_angle - LIGHT0_SIZE) / (halo_max - LIGHT0_SIZE);
			col = mix(sun, col, clamp(1.0 - pow(1.0 - c2, 1.0 / sun_curve), 0.0, 1.0));
		}
	}

	if (EYEDIR.y > 0.0 && cloud_opacity > 0.0) {
		// Flat ceiling projection; the +0.1 keeps the horizon from going to infinity.
		vec2 uv = EYEDIR.xz / (EYEDIR.y + 0.1);
		vec2 drift = normalize(wind_direction + vec2(1e-5)) * TIME * wind_speed;

		float d = cloud_density(uv, drift);
		d *= smoothstep(0.0, horizon_fade, EYEDIR.y);

		if (d > 0.001) {
			// Cheap self-shadowing: compare density a step toward the sun.
			vec2 sun_step = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION.xz + vec2(1e-5)) * 0.08 * cloud_size : vec2(0.0);
			float d_sun = cloud_density(uv + sun_step, drift);
			float light = clamp(0.65 - (d_sun - d) * 1.5 - d * 0.25, 0.0, 1.0);
			if (shade_steps > 0) {
				float s = float(shade_steps);
				light = floor(light * s + 0.5) / s;
			}
			vec3 cloud = mix(cloud_shadow_color, cloud_color, light);

			if (LIGHT0_ENABLED) {
				cloud = mix(cloud, cloud * LIGHT0_COLOR, sun_tint);
				// Thin edges near the sun glow.
				float near_sun = pow(clamp(1.0 - sun_angle / radians(40.0), 0.0, 1.0), 2.0);
				cloud += LIGHT0_COLOR * silver_lining * near_sun * (1.0 - d);
			}
			col = mix(col, cloud * sky_energy, d * cloud_opacity);
		}
	}

	COLOR = col;
}
