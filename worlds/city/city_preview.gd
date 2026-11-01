extends Node3D
## Developer preview: res://worlds/city/city_preview.tscn -- --capture=out.png [--point=x,y,z] [--size=40] [--overview]
const City = preload("res://worlds/city/city.gd")
const SurfaceLook = preload("res://worlds/ground_zero/surface_look.gd")
var capture_path := ""
var elapsed := 0.0

func _ready() -> void:
	set_process(false)
	var target := Vector3(140,0,-140)
	var size := 40.0
	var overview := false
	var offset := Vector3(15,23,21)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture_path=arg.trim_prefix("--capture=")
		if arg.begins_with("--size="):size=float(arg.trim_prefix("--size="))
		if arg=="--overview":overview=true
		if arg.begins_with("--offset="):
			var o := arg.trim_prefix("--offset=").split(",");offset=Vector3(float(o[0]),float(o[1]),float(o[2]))
		if arg.begins_with("--point="):
			var parts := arg.trim_prefix("--point=").split(",")
			target=Vector3(float(parts[0]),float(parts[1]),float(parts[2]))
	var map = City.new();map.build_collisions=false;add_child(map)
	if not map.loaded: await map.map_loaded
	var world_env := WorldEnvironment.new();var env := Environment.new();world_env.environment=env;add_child(world_env)
	var sun := DirectionalLight3D.new();sun.directional_shadow_max_distance=120 if not overview else 600;add_child(sun)
	SurfaceLook.apply_surface(env,sun)
	var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=size;camera.far=3000;add_child(camera)
	camera.position=target+offset*(10.0 if overview else maxf(1.0,size/30.0))
	camera.look_at(target)
	elapsed=0;set_process(true)

func _process(delta: float) -> void:
	elapsed+=delta
	if not capture_path.is_empty() and elapsed>2:
		set_process(false)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_path)
		get_tree().quit()
