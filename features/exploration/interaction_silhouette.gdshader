shader_type canvas_item;
render_mode unshaded;
uniform float width_pixels = 1.6;
void fragment() {
 vec2 step_uv = TEXTURE_PIXEL_SIZE * width_pixels;
 float center = texture(TEXTURE, UV).r;
 float edge = 0.0;
 for (int y = -1; y <= 1; y++) {
  for (int x = -1; x <= 1; x++) {
   edge = max(edge, texture(TEXTURE, UV + vec2(float(x),float(y))*step_uv).r);
  }
 }
 COLOR = vec4(vec3(1.0), max(0.0,edge-center));
}
