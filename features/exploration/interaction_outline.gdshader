shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;
uniform float mask_value = 1.0;
void fragment() { ALBEDO = vec3(mask_value); }
