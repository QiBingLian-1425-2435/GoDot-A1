shader_type spatial;
render_mode cull_disabled;
#include "res://features/visibility/vision_fog.gdshaderinc"
varying vec3 world_position;
uniform sampler2D blend_map : filter_linear;
uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 terrain_size = vec2(1024.0);
uniform vec2 grass_size = vec2(4.0);
uniform vec2 mud_size = vec2(4.0);
uniform vec2 road_size = vec2(6.0);
// Low-poly diorama grading: per-layer tints, crisper path edges and soft
// large-scale colour patches so open ground does not read as one flat sheet.
uniform vec3 grass_tint : source_color = vec3(0.8,0.88,0.72);
uniform vec3 mud_tint : source_color = vec3(0.93,0.83,0.77);
uniform vec3 road_tint : source_color = vec3(0.9,0.92,0.96);
uniform float edge_sharpness : hint_range(1.0,6.0) = 2.6;
uniform float patch_strength : hint_range(0.0,0.3) = 0.12;
uniform float patch_scale = 0.045;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float value_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),u.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),u.x),u.y);
}

void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 original_uv = vec2(UV.x,1.0-UV.y);
	vec3 blend = texture(blend_map,UV).rgb;
	blend = pow(max(blend,vec3(0.0)),vec3(edge_sharpness));
	blend /= max(dot(blend,vec3(1.0)),0.001);
	vec2 tile_position = original_uv*terrain_size;
	vec3 grass_color = texture(grass,vec2(tile_position.x/grass_size.x,-tile_position.y/grass_size.y)).rgb*grass_tint;
	vec3 mud_color = texture(mud,vec2(tile_position.x/mud_size.x,-tile_position.y/mud_size.y)).rgb*mud_tint;
	vec3 road_color = texture(road,vec2(tile_position.x/road_size.x,-tile_position.y/road_size.y)).rgb*road_tint;
	vec2 p = world_position.xz*patch_scale;
	float patches = value_noise(p)*0.65+value_noise(p*2.7+17.0)*0.35;
	// Warm, sunlit tufts against cooler, deeper grass.
	vec3 grass_shift = mix(vec3(0.9,0.95,1.02),vec3(1.08,1.04,0.9),patches);
	grass_color *= mix(vec3(1.0),grass_shift,patch_strength/0.09);
	mud_color *= 1.0+(patches-0.5)*patch_strength;
	vec3 color = grass_color*blend.r+mud_color*blend.g+road_color*blend.b;
	ALBEDO = apply_vision_fog(color,world_position);
	ROUGHNESS = 0.95;
}
