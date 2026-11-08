shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;
uniform float mask_value = 1.0;
// R identifies the target; G identifies depth-tested occluders. Background
// stays black, so an occlusion cut cannot masquerade as the outer silhouette.
void fragment() { ALBEDO = vec3(mask_value, 1.0 - mask_value, 0.0); }
