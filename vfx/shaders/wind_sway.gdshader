// Wind sway — a port of the WindSway geometry-nodes modifier from the Blender
// plants file (props/plants/plants.blend), done as vertex displacement.
//
// The WIND is global: Project Settings › Shader Globals (`wind_*`), shared by
// every swaying thing, and settable at runtime with
// RenderingServer.global_shader_parameter_set(). Each material keeps the
// SHAPE knobs (how this model bends) plus multipliers on the global strength
// and turbulence, so a stiff shrub and a floppy frond share one wind.
//
// Materials are normally made by vfx/wind_sway_import.gd (an import script set
// per model in the Import dock), which also fills in the surface and bounds.
//
// Blender is Z-up, Godot Y-up: height runs along object-space Y here. The wind
// direction and every distance (strength, lean, turbulence) are in WORLD space,
// so a node's scale and rotation don't change how far or which way it bends.
// The wind direction is in Godot axes. Blender's (x, y, z) arrives as (x, z, -y), so
// the modifier's default (1, 0.4, 0) is (1, 0, -0.4).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// --- the wind: Project Settings › Shader Globals ---------------------------
// How far the free end swings either way along the wind direction (m).
global uniform float wind_strength;
// Random flutter amount (m).
global uniform float wind_turbulence;
global uniform vec3 wind_direction;
// Seconds before the motion repeats seamlessly.
global uniform float wind_loop_length;
// Gust pulses per loop.
global uniform int wind_gust_waves;
global uniform float wind_flutter_speed;

group_uniforms Surface;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
// Below this alpha a pixel is cut out (keeps shadows and depth sorting sane).
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;

group_uniforms Emission;
// Glow colour; black = no emission. Multiplied by the texture and energy, like
// StandardMaterial3D's emission (Add operator).
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;
uniform sampler2D emission_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;

group_uniforms Shape;
// On: hangs from the top (scarves, banners). Off: rooted at the bottom (plants).
uniform bool anchor_at_top = false;
// Object-space Y of the mesh's lowest and highest vertex (the import script
// measures these).
uniform float bounds_bottom = 0.0;
uniform float bounds_top = 1.0;
// Higher = anchored end stiffer, free end moves more.
uniform float falloff_power : hint_range(0.2, 5.0) = 1.6;
// Size of the flutter noise on this model: higher = busier, smaller ripples.
uniform float flutter_scale : hint_range(0.0, 10.0) = 0.6;
// Constant bend downwind at the free end (m), which the sway swings around.
uniform float lean : hint_range(0.0, 2.0) = 0.1;
// Multipliers on the global wind: below 1 = stiffer, above 1 = floppier.
// strength_scale scales the sway and the lean; turbulence_scale the flutter.
uniform float strength_scale : hint_range(0.0, 4.0) = 1.0;
uniform float turbulence_scale : hint_range(0.0, 4.0) = 1.0;
// How the sway follows a copy's scale. 0 = the same distance in metres at any
// size (a 10x copy sways no further than a 1x one). 1 = in proportion to size
// (10x sways 10x as far). Between: 0.5 makes a 10x copy sway ~3x as far.
// Tune strength_scale for scale-1 copies; this sets how the others follow.
uniform float size_response : hint_range(0.0, 1.0) = 0.0;
// Add a seed derived from where the model stands, so copies placed around a
// level sway out of step with no setup.
uniform bool seed_from_position = true;

// Per node (MeshInstance3D › Instance Shader Parameters): an extra seed, for
// copies that should differ but stand in the same spot.
instance uniform int seed = 0;

// --- 3D gradient noise, standing in for Blender's 4D Noise Texture ---------

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
			dot(p, vec3(269.5, 183.3, 246.1)),
			dot(p, vec3(113.5, 271.9, 124.6)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

// Signed gradient noise, roughly -1..1.
float gradient_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(mix(dot(hash3(i + vec3(0, 0, 0)), f - vec3(0, 0, 0)),
					dot(hash3(i + vec3(1, 0, 0)), f - vec3(1, 0, 0)), u.x),
				mix(dot(hash3(i + vec3(0, 1, 0)), f - vec3(0, 1, 0)),
					dot(hash3(i + vec3(1, 1, 0)), f - vec3(1, 1, 0)), u.x), u.y),
			mix(mix(dot(hash3(i + vec3(0, 0, 1)), f - vec3(0, 0, 1)),
					dot(hash3(i + vec3(1, 0, 1)), f - vec3(1, 0, 1)), u.x),
				mix(dot(hash3(i + vec3(0, 1, 1)), f - vec3(0, 1, 1)),
					dot(hash3(i + vec3(1, 1, 1)), f - vec3(1, 1, 1)), u.x), u.y), u.z);
}

// Blender's FBM at Detail 2 / Roughness 0.5 / Lacunarity 2, normalized:
// three octaves, averaged. Returns about -0.5..0.5, i.e. Blender's
// normalized output (0..1, centred on 0.5) with the 0.5 already taken off.
float fbm(vec3 p) {
	float sum = gradient_noise(p)
			+ 0.5 * gradient_noise(p * 2.0)
			+ 0.25 * gradient_noise(p * 4.0);
	return 0.5 * sum / 1.75;
}

// Blender's Noise Texture Color: three decorrelated noise channels.
vec3 noise_color(vec3 p, float w) {
	vec3 o = vec3(w * 0.37, w * 0.61, w * 0.83);
	return vec3(fbm(p + o),
			fbm(p + o + vec3(19.19, 7.31, 3.77)),
			fbm(p + o + vec3(5.47, 23.11, 11.93)));
}

// --- vertex ----------------------------------------------------------------

void vertex() {
	float height = max(bounds_top - bounds_bottom, 0.0001);
	// 0 at the anchored end, 1 at the free end.
	float along = anchor_at_top
			? clamp((bounds_top - VERTEX.y) / height, 0.0, 1.0)
			: clamp((VERTEX.y - bounds_bottom) / height, 0.0, 1.0);
	float falloff = pow(along, falloff_power);

	float s = float(seed);
	if (seed_from_position) {
		vec3 p = NODE_POSITION_WORLD;
		s += fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453) * 100.0;
	}
	float phase = TIME / wind_loop_length * TAU;

	// Sway: a gust pulse travelling up the mesh, swinging either side of the
	// lean (-1..1), so strength_scale sets how far things actually move.
	float gust = sin(phase * float(wind_gust_waves) + s * 2.3 + along * -1.4 * height);
	vec3 steady = normalize(wind_direction) * (lean + gust * wind_strength) * strength_scale;

	// Flutter: noise sampled at a point that circles in the ground plane, so it
	// loops with the gusts.
	vec3 drift = vec3(cos(phase), 0.0, sin(phase)) * wind_flutter_speed;
	vec3 flutter = noise_color(VERTEX * flutter_scale + drift, s * 5.7) * wind_turbulence * turbulence_scale;

	// The amounts above are world-space metres along a world direction. Bring
	// them into object space, so a copy scaled 10x doesn't sway 10x as far and
	// a rotated copy still bends downwind.
	mat3 model = mat3(MODEL_MATRIX);
	float node_scale = (length(model[0]) + length(model[1]) + length(model[2])) / 3.0;
	vec3 offset_world = (steady + flutter) * falloff * pow(node_scale, size_response);
	VERTEX += inverse(model) * offset_world;
}

// --- fragment --------------------------------------------------------------

void fragment() {
	vec4 tex = texture(albedo_texture, UV) * albedo_color;
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	EMISSION = emission_color.rgb * texture(emission_texture, UV).rgb * emission_energy;
}
