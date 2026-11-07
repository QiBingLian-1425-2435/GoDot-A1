extends Node3D
var camera:Camera3D
var capture:=""
var target:=Vector3(0,0,0)
var yaw:=18.0
var elevation:=48.0
var span:=34.0
func _ready():
 var env:=WorldEnvironment.new();env.environment=Environment.new();add_child(env)
 env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("9c9482")
 env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("d7d1bc");env.environment.ambient_light_energy=.45
 env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-30,0);sun.light_color=Color("fff1da");sun.light_energy=.75;sun.shadow_enabled=true;sun.directional_shadow_max_distance=100;add_child(sun)
 add_child(preload("res://worlds/survivor_base/survivor_base.gd").new())
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.far=250;add_child(camera);camera.current=true
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--capture="):capture=arg.trim_prefix("--capture=")
  if arg.begins_with("--size="):span=float(arg.trim_prefix("--size="))
  if arg.begins_with("--point="):
   var a=arg.trim_prefix("--point=").split(",");target=Vector3(float(a[0]),float(a[1]),float(a[2]))
 _camera()
 if not capture.is_empty():
  for i in range(12):await get_tree().process_frame
  await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png(capture)
  get_tree().quit()
func _camera():
 camera.size=span
 camera.position=target+Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))*70
 camera.look_at(target)
func _unhandled_input(event):
 if event is InputEventMouseButton and event.pressed:
  if event.button_index==MOUSE_BUTTON_WHEEL_UP:span=maxf(8,span-2)
  if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:span=minf(65,span+2)
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
  yaw-=event.relative.x*.3;elevation=clampf(elevation+event.relative.y*.2,20,80)
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
  target+=camera.global_basis.x*(-event.relative.x*.025)+camera.global_basis.y*(event.relative.y*.025)
 _camera()
