shader_type spatial;
render_mode cull_disabled;
uniform sampler2D blend_map : filter_linear;
uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 terrain_size = vec2(1024.0);
uniform vec2 grass_size = vec2(4.0);
uniform vec2 mud_size = vec2(4.0);
uniform vec2 road_size = vec2(6.0);

void fragment() {
	vec2 original_uv = vec2(UV.x,1.0-UV.y);
	vec3 blend = texture(blend_map,UV).rgb;
	blend /= max(dot(blend,vec3(1.0)),0.001);
	vec2 tile_position = original_uv*terrain_size;
	vec3 grass_color = texture(grass,vec2(tile_position.x/grass_size.x,-tile_position.y/grass_size.y)).rgb;
	vec3 mud_color = texture(mud,vec2(tile_position.x/mud_size.x,-tile_position.y/mud_size.y)).rgb;
	vec3 road_color = texture(road,vec2(tile_position.x/road_size.x,-tile_position.y/road_size.y)).rgb;
	ALBEDO = grass_color*blend.r+mud_color*blend.g+road_color*blend.b;
	ROUGHNESS = 0.95;
}
