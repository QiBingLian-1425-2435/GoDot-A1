extends Node3D
const Map = preload("res://worlds/ground_zero/ground_zero.gd")
var map
var camera: Camera3D
var capture_path := ""
var elapsed := 0.0
var target := Vector3(455.72,0,-103.62)
var overview := false

func _ready() -> void:
	set_process(false)
	var zone := "surface"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zone="):zone=arg.trim_prefix("--zone=")
		if arg.begins_with("--capture="):capture_path=arg.trim_prefix("--capture=")
		if arg=="--overview":overview=true
		if arg.begins_with("--point="):
			var parts := arg.trim_prefix("--point=").split(",")
			target=Vector3(float(parts[0]),float(parts[1]),float(parts[2]))
	map=Map.new(); map.zone=zone; map.build_collisions=false; map.overview_mode=overview
	add_child(map)
	if not map.loaded: await map.map_loaded
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("a3b1b1")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("d6d9ce")
	env.ambient_light_energy=.3
	env.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	world_env.environment=env; add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-55,-30,0); sun.light_energy=.42
	sun.shadow_enabled=true; sun.directional_shadow_max_distance=100
	add_child(sun)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=34 if not overview else 520
	camera.far=1800
	add_child(camera)
	if zone=="cave" and target.x==455.72:target=Vector3(582,0,-550)
	if overview: target=Vector3(390,0,-205)
	target.y=map.terrain_height(Vector2(target.x,target.z))
	camera.position=target+Vector3(30,46,42)*(12 if overview else 1)
	camera.look_at(target)
	map.set_view_points(target,camera.position)
	print("GROUND_ZERO_PREVIEW ready target=",target)
	elapsed=0
	set_process(true)

func _process(delta: float) -> void:
	elapsed+=delta
	if not capture_path.is_empty() and elapsed>3:
		set_process(false)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_path)
		print("GROUND_ZERO_PREVIEW captured ",capture_path)
		get_tree().quit()
	elif DisplayServer.get_name()=="headless" and elapsed>2:get_tree().quit()
