extends SceneTree
## Real Main, authoritative E interaction and capsule traversal of every city entrance.
const Main=preload("res://app/main.gd")
var game
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func check(ok: bool, message: String):
	checks+=1
	print("PASS: " if ok else "FAIL: ",message)
	if not ok:failures+=1
func travel(destination: String):
	var model=game.session.model
	for route in model.stations:
		if route.get("destination","")!=destination:continue
		var p: Dictionary=model.state.players[1]
		p.pos=route.pos;p.height=route.get("height",0)
		check(model.command(1,"travel",{"route":route.uid}),"travel to "+destination)
		game._sync_world()
		while game.world_loading:await process_frame
		await physics_frame;await physics_frame
		return
	check(false,"missing route "+destination)
func run():
	game=Main.new();game.smoke=true;game.elapsed=-10000;game.capture_mode="base";root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false)
	game.sound.muted=true
	await travel("city")
	var model=game.session.model
	var p: Dictionary=model.state.players[1]
	var rooms: Array=game.world.layout.buildings
	check(rooms.size()>40,"all city buildings have entrances: "+str(rooms.size()))
	for room in rooms:
		var uid: String=room.id
		var foot:=Vector3(room.door[0],room.door[1],room.door[2])
		var normal:=Vector3(room.normal[0],0,room.normal[1])
		for side in [1,-1]:
			var start: Vector3=foot+normal*1.2*side
			var safe: Dictionary=game.player_physics.safe_standing_position(start)
			check(not safe.is_empty(),uid+" walkable approach "+str(side))
			if safe.is_empty():continue
			p.pos=Vector2(safe.position.x,safe.position.z);p.height=safe.position.y
			model.state.doors[uid]=false;game.world.update_doors(model.state.doors)
			await physics_frame
			game._update_actors(1);game._update_interaction()
			check(game.nearest.get("uid")==uid,uid+" real E candidate "+str(side))
			var blocked: Vector3=safe.position
			for i in range(50):blocked=game.player_physics.prediction_body.move_spatial(blocked,-Vector2(normal.x,normal.z)*side*.06)
			check((blocked-foot).dot(normal)*side>0,uid+" closed leaf blocks capsule")
			game._interact();game.world.update_doors(model.state.doors);await physics_frame
			check(model.state.doors[uid],uid+" E opens authority state")
			var crossed: Vector3=safe.position
			for i in range(50):crossed=game.player_physics.prediction_body.move_spatial(crossed,-Vector2(normal.x,normal.z)*side*.06)
			check((crossed-foot).dot(normal)*side<-.8,uid+" actual capsule crosses open doorway "+str(side))
		# Occupancy protection and distant rejection use the real authoritative command.
		var occupant=game.player_physics.PlayerBody.instantiate()
		game.add_child(occupant);occupant.position=foot
		await physics_frame;await physics_frame
		check(not model.command(1,"door",{"uid":uid}) and model.state.doors[uid],uid+" refuses closing on player")
		occupant.free();await physics_frame
		check(model.command(1,"door",{"uid":uid}) and not model.state.doors[uid],uid+" closes when clear")
		p.pos+=Vector2(30,30)
		check(not model.command(1,"door",{"uid":uid}),uid+" distant request rejected")
		game.world.update_doors(model.state.doors)
		var center:=Vector3(room.bounds[0]+room.bounds[2]/2,0.08,room.bounds[1]+room.bounds[3]/2)
		game.world.set_view_points(center,center+Vector3(10,20,15))
		check(game.world.has_overhead_cover(center) and game.world._material.get_shader_parameter("indoor_active"),uid+" interior roof cutaway")
	# Keep one door open across travel; exercise map cache and repeated assembly.
	var first: Dictionary=rooms[0]
	p.pos=Vector2(first.door[0],first.door[2])+Vector2(first.normal[0],first.normal[1])*1.2;p.height=.08
	var barrier:=StaticBody3D.new();barrier.collision_layer=17;barrier.collision_mask=0
	var barrier_shape:=CollisionShape3D.new();var barrier_box:=BoxShape3D.new()
	barrier_box.size=Vector3(.3,2,.3);barrier_shape.shape=barrier_box;barrier.add_child(barrier_shape)
	barrier.position=Vector3(first.door[0]+first.normal[0]*.6,.8,first.door[2]+first.normal[1]*.6)
	game.add_child(barrier);await physics_frame;await physics_frame
	check(not model.command(1,"door",{"uid":first.id}),"intervening wall rejects opening")
	barrier.free();await physics_frame
	p.height=4
	check(not model.command(1,"door",{"uid":first.id}),"wrong floor rejects opening")
	p.height=.08
	check(not model.command(1,"door",{"uid":"missing_city_door"}),"unknown door rejects opening")
	check(model.command(1,"door",{"uid":first.id}),"open door before travel")
	await capture_room(rooms)
	await travel("bunker");await travel("city")
	check(model.state.doors[first.id] and game.world._door_open[first.id],"door state survives leaving and re-entering city")
	game.queue_free();await process_frame
	print("CITY_BUILDINGS ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
func capture_room(rooms: Array):
	if DisplayServer.get_name()=="headless":return
	var p: Dictionary=game.session.model.state.players[1]
	for kind in ["home","shop","warehouse"]:
		for room in rooms:
			if room.kind!=kind:continue
			p.pos=Vector2(room.bounds[0]+room.bounds[2]/2,room.bounds[1]+room.bounds[3]/2);p.height=.08
			game._update_actors(1);game._update_camera(1);game.vision.update(game,.1);game._update_interaction();game._refresh_ui()
			game.world.set_view_points(Vector3(p.pos.x,p.height,p.pos.y),game.camera.global_position)
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/city_interior_"+kind+".png"))
			break
