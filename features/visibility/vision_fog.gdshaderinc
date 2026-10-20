uniform bool vision_enabled = false;
uniform vec3 vision_origin;
uniform vec2 vision_aim = vec2(0.0,-1.0);
uniform sampler2D vision_rays : filter_linear, repeat_enable;
uniform float vision_range=37.0;
uniform float vision_sense=1.5;
uniform float vision_cos_inner=0.64279;
uniform float vision_cos_outer=0.61566;

float vision_visibility(vec3 world) {
	if (!vision_enabled) { return 1.0; }
	vec2 offset = world.xz-vision_origin.xz;
	float distance = length(offset);
	vec2 direction = offset/max(distance,0.0001);
	float cone = smoothstep(vision_cos_outer,vision_cos_inner,dot(direction,vision_aim));
	float near = 1.0-smoothstep(vision_sense,vision_sense+0.3,distance);
	float radius = 1.0-smoothstep(vision_range-0.5,vision_range,distance);
	float angle = atan(offset.y,offset.x)/6.28318530718;
	float wall = texture(vision_rays,vec2(angle+0.5/float(textureSize(vision_rays,0).x),0.5)).r*vision_range;
	float sight = 1.0-smoothstep(wall+0.08,wall+0.65,distance);
	return max(near,cone*radius)*sight;
}
vec3 apply_vision_fog(vec3 color, vec3 world) {
	float amount=vision_visibility(world);
	float gray = dot(color,vec3(0.2126,0.7152,0.0722));
	return mix(vec3(gray)*0.32,color,amount);
}
