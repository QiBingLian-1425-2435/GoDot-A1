shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform sampler2D mask_map : filter_linear, repeat_enable;
uniform vec4 water_tint : source_color = vec4(0.11,0.14,0.17,0.17);
void fragment() {
	vec2 edge = min(UV2,vec2(1.0)-UV2);
	float border = smoothstep(0.0,0.12,min(edge.x,edge.y));
	float noise = texture(mask_map,UV).r;
	ALBEDO = water_tint.rgb;
	ALPHA = water_tint.a*border*smoothstep(0.2,0.7,noise);
	ROUGHNESS = 0.18;
}
