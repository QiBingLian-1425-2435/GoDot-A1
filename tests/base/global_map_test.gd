extends SceneTree

const GlobalMap = preload("res://ui/map/global_map.gd")

func _init() -> void:
	var map=GlobalMap.new()
	root.add_child(map)
	await process_frame
	assert(map._map_rect.texture!=null)
	var rect:=Rect2(30,68,1220,686.25)
	var center:=map.world_to_map(Vector2(390,-205),rect)
	assert(center.distance_to(rect.get_center())<0.01)
	map.set_state({1:{"name":"房主","pos":Vector2(390,-205)},2:{"name":"队友","pos":Vector2(420,-180)}},1,"surface")
	map.set_open(true)
	assert(map.is_open())
	assert(map._players.size()==2)
	var capture_path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture_path=arg.trim_prefix("--capture=")
	if not capture_path.is_empty():
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(capture_path)==OK)
	map.set_open(false)
	assert(not map.is_open())
	print("GLOBAL_MAP_TEST PASS")
	quit()
