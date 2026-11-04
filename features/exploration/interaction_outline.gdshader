shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform float width = 0.025;
void vertex() { VERTEX += NORMAL * width; }
void fragment() { ALBEDO = vec3(1.0); }
