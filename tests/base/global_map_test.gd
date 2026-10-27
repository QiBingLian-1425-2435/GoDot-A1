extends SceneTree

const GlobalMap = preload("res://ui/map/global_map.gd")

func _init() -> void:
	var map=GlobalMap.new()
	root.add_child(map)
	await process_frame
	assert(map._map_rect.texture!=null and map._map_tiles.is_empty())
	var rect:=Rect2(30,68,1220,686.25)
	var center:=map.world_to_map(Vector2(390,-250),rect)
	assert(center.distance_to(rect.get_center())<0.01)
	map.set_state({1:{"name":"房主","pos":Vector2(390,-250)},2:{"name":"队友","pos":Vector2(420,-180)}},1,"surface")
	map.set_open(true)
	assert(map.is_open())
	assert(map._players.size()==2)
	assert(is_equal_approx(map._zoom,1.0))
	map.set_zoom(9.0)
	assert(is_equal_approx(map._zoom,3.0))
	assert(map._map_tiles.size()==4)
	var map_point:=map.world_to_map(Vector2(390,-250),Rect2(Vector2.ZERO,map._map_content.size))
	assert(map.map_to_view(map_point).distance_to(map._map_view.size*.5)<.01)
	map.set_zoom(0.1)
	assert(is_equal_approx(map._zoom,1.0))
	map.center_on_local()
	assert(is_equal_approx(map._zoom,2.0))
	assert(map._pan.length()<0.01)
	map._pan=Vector2(99999,-99999);map._apply_view()
	var limit:Vector2=map._map_content.size*(map._zoom-1.0)*.5
	assert(map._pan.x<=limit.x and map._pan.y>=-limit.y)
	map.reset_view()
	assert(is_equal_approx(map._zoom,1.0) and map._pan==Vector2.ZERO)
	var capture_path:=""
	var capture_zoomed:=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture_path=arg.trim_prefix("--capture=")
		if arg=="--capture-zoomed":capture_zoomed=true
	if not capture_path.is_empty():
		if capture_zoomed:map.set_zoom(3.0,map._map_view.size*.5)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(capture_path)==OK)
	map.set_open(false)
	assert(not map.is_open())
	print("GLOBAL_MAP_TEST PASS")
	quit()
