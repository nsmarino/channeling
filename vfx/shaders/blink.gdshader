shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// --- Base & Texture Parameters ---
uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;

// --- Blinking Parameters ---
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_modifier : hint_range(0.0, 1.0, 0.01) = 0.0;

// --- Emissive Toggles & Controls ---
uniform bool use_emissive = false;
uniform float emissive_intensity : hint_range(0.0, 20.0, 0.1) = 1.0;

void fragment() {
    // 1. Process Albedo (Base Color) Channel
    vec4 albedo_tex = texture(texture_albedo, UV);
    vec3 mixed_base = albedo_tex.rgb * base_color.rgb;
    vec3 final_albedo = mix(mixed_base, flash_color.rgb, flash_modifier);
    
    ALBEDO = final_albedo;
    
    // 2. Process Emissive (Glow) Channel
    if (use_emissive) {
        // Feeds the flashing/base configuration directly into the neon glow buffer
        EMISSION = final_albedo * emissive_intensity;
    } else {
        EMISSION = vec3(0.0);
    }
}
