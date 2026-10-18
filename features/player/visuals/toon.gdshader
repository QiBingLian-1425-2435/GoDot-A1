shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 accent : source_color = vec4(1.0);
void fragment() {
    vec3 base = texture(albedo_texture, UV).rgb;
    ALBEDO = base * mix(vec3(1.0), accent.rgb, 0.10);
    ROUGHNESS = 1.0;
    EMISSION = ALBEDO * vec3(0.16, 0.18, 0.23);
}
void light() {
    float facing = dot(NORMAL, LIGHT);
    float band = facing > 0.48 ? 1.0 : (facing > -0.12 ? 0.60 : 0.23);
    DIFFUSE_LIGHT += band * LIGHT_COLOR * ATTENUATION / PI;
}
