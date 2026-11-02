extends "res://tests/base/city_buildings_test.gd"
## Walk every flight with the actual capsule, including the full nine-storey tower.
func walk_to(at: Vector3, target: Vector3) -> Vector3:
	var limit:=ceili(Vector2(target.x-at.x,target.z-at.z).length()/.04)+40
	for i in range(limit):
		var offset:=Vector2(target.x-at.x,target.z-at.z)
		if offset.length()<.025:break
		at=game.player_physics.prediction_body.move_spatial(at,offset.limit_length(.04))
	return at
func run():
	game=Main.new();game.smoke=true;game.elapsed=-10000;game.capture_mode="base";root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game.sound.muted=true
	await travel("city")
	var towers:=0
	var flights:=0
	var highest:=0.0
	var rooms: Array=game.world.layout.buildings+game.world.layout.open_buildings
	for room in rooms:
		if room.stairs.is_empty():continue
		towers+=1
		var path: Array[Vector3]=[]
		for route in room.stairs:
			for point in route:path.append(Vector3(point[0],point[1],point[2]))
		var safe: Dictionary=game.player_physics.safe_standing_position(path[0])
		check(not safe.is_empty(),room.id+" stair approach clear")
		if safe.is_empty():continue
		var at: Vector3=safe.position
		for target in path:
			at=walk_to(at,target)
			check(at.distance_to(target)<.15,room.id+" climb waypoint "+str(target)+" actual "+str(at))
			flights+=1
			highest=maxf(highest,at.y)
		# Walking out of the stairwell onto the room floor must be supported.
		var into_room:=at+Vector3(2.0,0,0)
		var landed:=walk_to(at,into_room)
		check(landed.distance_to(into_room)<.15,room.id+" upper floor accessible")
		at=walk_to(landed,at)
		game.world.set_view_points(at,at+Vector3(10,20,15))
		check(game.world.has_overhead_cover(at),room.id+" upper storey cutaway active")
		if int(room.floors)==9:await capture_upper(at)
		path.reverse()
		for target in path:
			at=walk_to(at,target)
			check(at.distance_to(target)<.15,room.id+" descend waypoint "+str(target)+" actual "+str(at))
	check(towers>25 and highest>26,"all multi-storey buildings and ninth floor reached: "+str(towers)+" / "+str(highest))
	game.queue_free();await process_frame
	print("CITY_STAIRS ",checks," checks; ",failures," failures; buildings=",towers," waypoints=",flights)
	quit(1 if failures else 0)
func capture_upper(at: Vector3):
	if DisplayServer.get_name()=="headless":return
	var p: Dictionary=game.session.model.state.players[1]
	p.pos=Vector2(at.x,at.z);p.height=at.y
	game._update_actors(1);game._update_camera(1);game.vision.update(game,.1);game._update_interaction();game._refresh_ui()
	game.world.set_view_points(at,game.camera.global_position)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/city_ninth_floor.png"))
