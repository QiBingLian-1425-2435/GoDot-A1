shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform float thickness : hint_range(0.0, 0.04) = 0.014;
uniform vec4 ink : source_color = vec4(0.025, 0.040, 0.055, 1.0);
void vertex() { VERTEX += NORMAL * thickness; }
void fragment() { ALBEDO = ink.rgb; }
