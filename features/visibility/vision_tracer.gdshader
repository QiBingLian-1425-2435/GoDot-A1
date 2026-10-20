shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://features/visibility/vision_fog.gdshaderinc"
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	ALBEDO=COLOR.rgb;
	EMISSION=COLOR.rgb*1.2;
	ALPHA=COLOR.a*vision_visibility(world_position);
}
