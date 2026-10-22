uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
#include "res://features/visibility/vision_fog.gdshaderinc"
uniform bool has_albedo = false;
uniform bool roof_surface = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool alpha_clip = false;
uniform float cutoff = 0.5;
uniform float surface_roughness = 0.9;
uniform vec3 emission_color = vec3(0.0);
uniform bool view_enabled = false;
uniform vec3 view_player;
uniform vec3 view_camera;
varying vec3 world_position;
varying vec3 world_normal;
varying vec4 instance_tint;
void vertex() {
	world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX*NORMAL);
	instance_tint = INSTANCE_CUSTOM.a>0.5 ? INSTANCE_CUSTOM : vec4(1.0);
}
void fragment() {
	vec4 texel = has_albedo ? texture(albedo_map,UV*uv_scale+uv_offset) : vec4(1.0);
	if (alpha_clip && texel.a*tint.a<cutoff) { discard; }
	// Local view cutaway leaves world physics and other players' cameras intact.
	// Floors below the duck remain opaque; overhead rocks/roofs reveal the room.
	if (view_enabled && world_position.y>view_player.y+0.65) {
		vec3 ray = view_camera-view_player;
		float distance = length(ray);
		vec3 axis = ray/max(distance,0.001);
		vec3 offset = world_position-view_player;
		float along = dot(offset,axis);
		float radius = length(offset-axis*along);
		float coverage = smoothstep(1.8,2.6,radius);
		float noise = fract(sin(dot(floor(world_position*24.0),vec3(12.9898,78.233,37.719)))*43758.5453);
		if (along>0.0 && along<distance-0.3 && noise>coverage) { discard; }
	}
	// Reveal the roof above the visible floor, projected along this client's camera.
	// Include gables belonging to roof meshes; ordinary walls and lower floors stay intact.
	if (view_enabled && vision_enabled && vision_roof_cutaway && world_position.y>vision_origin.y+1.35 && (roof_surface || abs(world_normal.y)>0.4)) {
		vec3 axis = normalize(view_camera-vision_origin);
		vec3 floor_point = world_position-axis*((world_position.y-vision_origin.y)/max(axis.y,0.1));
		float reveal = vision_visibility(floor_point);
		float noise = fract(sin(dot(floor(world_position*32.0),vec3(12.9898,78.233,37.719)))*43758.5453);
		if (reveal>0.02 && noise<reveal) { discard; }
	}
	ALBEDO = apply_vision_fog(texel.rgb*tint.rgb*instance_tint.rgb,world_position);
	ROUGHNESS = surface_roughness;
	EMISSION = apply_vision_fog(emission_color,world_position);
#ifdef SOURCE_TRANSPARENT
	ALPHA=texel.a*tint.a*instance_tint.a;
#endif
}
