shader_type spatial;

// Hit-flash OVERLAY. Meant to be assigned as MeshInstance3D.material_overlay so
// it renders on top of the model's real materials without replacing them. At
// flash_modifier = 0 it is fully transparent (invisible); ramping toward 1 washes
// the mesh in flash_color. Drive flash_modifier from code (mecha_player.gd pulses
// it 1 -> 0 on hit). unshaded + emission so the flash reads at any light angle and
// blooms with the scene glow.
// cull_disabled so thin / single-sided surfaces (e.g. the wings) flash too.
render_mode blend_mix, unshaded, cull_disabled, shadows_disabled;

// --- Flash Parameters ---
uniform vec4 flash_color : source_color = vec4(1.0, 0.05, 0.1, 1.0);
uniform float flash_modifier : hint_range(0.0, 1.0, 0.01) = 0.0;
// Extra emission multiplier so the flash pops against the scene glow.
uniform float emissive_intensity : hint_range(0.0, 20.0, 0.1) = 3.0;

void fragment() {
    ALBEDO = flash_color.rgb;
    EMISSION = flash_color.rgb * emissive_intensity * flash_modifier;
    // Fade the whole overlay in/out by alpha, so at rest it shows nothing.
    ALPHA = flash_modifier * flash_color.a;
}
