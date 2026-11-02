shader_type spatial;
render_mode cull_back;
// Flat-shaded, vertex-coloured low-poly city with the shared vision shadow and the
// local camera cutaway (tall buildings between camera and player dissolve).
#include "res://features/visibility/vision_fog.gdshaderinc"
uniform bool view_enabled = false;
uniform vec3 view_player;
uniform vec3 view_camera;
uniform float cutaway_radius = 3.2;
uniform bool indoor_active = false;
uniform vec4 indoor_bounds;
uniform float indoor_cut_height = 1.8;
varying vec3 world_position;
varying vec4 vertex_tint;
void vertex() {
	world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	vertex_tint = COLOR;
}
void fragment() {
	// Reveal the occupied storey; the cut height follows the observer on the stairs.
	// Only visuals change; physical walls, ceiling and line-of-sight remain intact.
	if (indoor_active && world_position.y > indoor_cut_height &&
		world_position.x > indoor_bounds.x && world_position.x < indoor_bounds.z &&
		world_position.z > indoor_bounds.y && world_position.z < indoor_bounds.w) { discard; }
	if (view_enabled && world_position.y>view_player.y+3.4) {
		vec3 ray = view_camera-view_player;
		float distance = length(ray);
		vec3 axis = ray/max(distance,0.001);
		vec3 offset = world_position-view_player;
		float along = dot(offset,axis);
		float radius = length(offset-axis*along);
		float coverage = smoothstep(cutaway_radius,cutaway_radius+1.4,radius);
		float noise = fract(sin(dot(floor(world_position*24.0),vec3(12.9898,78.233,37.719)))*43758.5453);
		if (along>0.0 && along<distance-0.3 && noise>coverage) { discard; }
	}
	ALBEDO = apply_vision_fog(vertex_tint.rgb,world_position);
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
