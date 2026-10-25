extends SceneTree
const Main=preload("res://app/main.gd")
var game
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1;print("PASS: " if ok else "FAIL: ",message)
	if not ok:failures+=1
func settle() -> void:
	game._update_actors(.016);game._update_drops();game.vision.update(game,.06);game._update_camera(.016);game._update_interaction()
	game._refresh_ui()
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	for i in range(8):
		await process_frame;settle()
	await RenderingServer.frame_post_draw
	var folder:=OS.get_environment("A1_TEST_ARTIFACTS")
	if folder.is_empty():folder="res://artifacts"
	DirAccess.make_dir_recursive_absolute(folder)
	var error: int=game.get_viewport().get_texture().get_image().save_png(folder.path_join("vision_"+name+".png"))
	if error!=OK:failures+=1;push_error("Cannot save vision evidence: "+error_string(error))
func tracer_pixels(point: Vector3) -> int:
	game.tracer_node.visible=true;game._update_tracers()
	await process_frame;await RenderingServer.frame_post_draw
	var shown: Image=game.get_viewport().get_texture().get_image()
	game.tracer_node.visible=false
	await process_frame;await RenderingServer.frame_post_draw
	var hidden: Image=game.get_viewport().get_texture().get_image()
	var at: Vector2=game.camera.unproject_position(point)
	var count:=0
	for y in range(maxi(0,int(at.y)-65),mini(shown.get_height(),int(at.y)+65)):
		for x in range(maxi(0,int(at.x)-65),mini(shown.get_width(),int(at.x)+65)):
			if shown.get_pixel(x,y).r-hidden.get_pixel(x,y).r>.08:count+=1
	game.tracer_node.visible=true
	print("VISION_TRACER_PIXELS ",count," at=",at," enabled=",game.tracer_node.material_override.get_shader_parameter("vision_enabled"))
	return count
func run() -> void:
	game=Main.new();game.smoke=true;game.elapsed=-10000;game.capture_mode="base";root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false)
	var model=game.session.model;var p: Dictionary=model.state.players[1]
	model.add_player(2,"前方队友");model.add_player(3,"背后队友")
	model.state.players[2].pos=p.pos+Vector2(0,4);p.aim=Vector2.UP
	settle()
	check(not game.vision.enabled and game.actors[2].visible,"base characters remain visible behind the local duck")
	p.pos=Vector2(0,-8.2);game._update_interaction();game._interact()
	while game.world_loading:await process_frame
	await physics_frame;await physics_frame
	settle()
	check(game.world_id=="surface" and game.vision.enabled,"the real base exit activates local vision")
	check(game.world._vision_groups.size()>100,"original loot container meshes are registered as visibility targets")
	var spawn: Vector2=p.pos
	var forward:=Vector2.UP
	for i in range(24):
		var direction:=Vector2.from_angle(TAU*float(i)/24)
		game.vision.aim=direction
		if game.vision.can_see(Vector3(spawn.x+direction.x*6,float(p.height)+1,spawn.y+direction.y*6)):
			forward=direction;break
	p.aim=forward
	model.state.players[2].pos=spawn+forward*6;model.state.players[2].height=p.height
	model.state.players[3].pos=spawn-forward*6;model.state.players[3].height=p.height
	for spec in [["front",forward,4.0],["rear",-forward,4.0],["near",-forward,1.2]]:
		var item: Dictionary=model._item("scrap",1)
		item.pos=spawn+Vector2(spec[1])*float(spec[2]);item.height=p.height
		if spec[0]!="rear":
			for distance in ([2.2,3.0,4.0,5.0,6.0] if spec[0]=="front" else [.5,.8,1.0,1.2]):
				var at: Vector2=spawn+Vector2(spec[1])*distance
				var floor_hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x,float(p.height)+.3,at.y),Vector3(at.x,float(p.height)-2,at.y),1))
				if floor_hit.is_empty():continue
				var height: float=floor_hit.position.y+.02
				if game.vision.can_see(Vector3(at.x,height+.2,at.y)):
					item.pos=at;item.height=height;break
		model.state.drops[spec[0]]=item
	settle()
	print("VISION_DROP_STATE ",game.drops.front.visible," ",game.drops.rear.visible," ",game.drops.near.visible)
	check(game.actors[1].visible and game.actors[2].visible and not game.actors[3].visible,"only the local duck and forward character render outside the near circle")
	check(game.drops.front.visible and not game.drops.rear.visible and game.drops.near.visible,"forward and nearby drops render while rear drops and labels disappear")
	var before: Dictionary=model.state.duplicate(true)
	settle()
	check(model.state==before,"view evaluation does not change shared actors, inventory or world state")
	p.hp=0;model.tick(.01);model.command(1,"possess",{"target":2});settle()
	check(game.vision.observer.distance_to(game.actors[2].position)<.01,"possessed soul uses teammate observer in real exploration vision")
	model.Souls.revive(model,p);p.pos=spawn;p.aim=forward;settle()
	check(game.world._terrain_material.get_shader_parameter("vision_enabled"),"the real terrain receives the local fog parameters")
	await capture("forward")
	if DisplayServer.get_name()!="headless":
		model.state.shots=[{"from":spawn+forward*2,"to":spawn+forward*6,"height":float(p.height)+1.8,"ttl":.14,"weapon":"rifle","player_id":2,"sequence":777,"impact":"none"}]
		var point:=Vector3(spawn.x+forward.x*4,float(p.height)+1.8,spawn.y+forward.y*4)
		var pixels: int=await tracer_pixels(point)
		check(pixels>5,"a tracer inside the view cone actually renders bright pixels")
		p.aim=-forward;settle()
		pixels=await tracer_pixels(point)
		check(pixels==0,"a tracer outside sight contributes no pixels that reveal its hidden shooter")
		model.state.shots.clear();game._update_tracers();p.aim=forward;settle()
	p.aim=-forward;settle()
	check(not game.actors[2].visible and game.actors[3].visible and not game.drops.front.visible and game.drops.rear.visible,"turning swaps front and rear visibility without remembering targets")
	await capture("turned")
	# A hidden pickup within E range must not leak a label or interaction prompt.
	model.state.drops.clear()
	var hidden: Dictionary=model._item("scrap",1);hidden.pos=spawn+forward*1.7;hidden.height=p.height
	model.state.drops.hidden=hidden;settle()
	check(not game.drops.hidden.visible and game.nearest.get("uid","")!="hidden","an unseen nearby item has no pickup prompt")
	var hidden_containers:=0
	for target in game.world.vision_targets():
		if target.nodes.is_empty():continue # Semantic search targets can have bounds without a render node.
		if not target.nodes[0].visible:hidden_containers+=1
	check(hidden_containers>50,"real static containers outside sight are hidden with their full mesh groups")
	# Find one original container with an exposed sample and verify turn-away hiding.
	var exercised:=false
	for target in game.world.vision_targets():
		if target.nodes.is_empty():continue
		var point: Vector3=target.points[0]
		for direction in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
			p.pos=Vector2(point.x,point.z)-direction*5;p.height=point.y-.6;p.aim=direction
			settle()
			if not target.nodes[0].visible:continue
			p.aim=-direction;settle()
			if not target.nodes[0].visible:exercised=true;break
		if exercised:break
	check(exercised,"a real original container appears in front and disappears when turning away")
	var portal: Dictionary={}
	for station in model.stations:
		if station.get("destination")=="cave":portal=station
	p.pos=portal.pos;p.height=portal.height;game.session.send("travel",{"route":portal.uid})
	while game.world_loading:await process_frame
	settle()
	check(game.world_id=="cave" and game.vision.enabled and game.world._terrain_material.get_shader_parameter("vision_enabled"),"the cave also enables vision with a fresh observer and ray mask")
	await capture("cave")
	var back: Dictionary={}
	for station in model.stations:
		if station.get("destination")=="surface":back=station
	p.pos=back.pos;p.height=back.height;game.session.send("travel",{"route":back.uid})
	while game.world_loading:await process_frame
	settle()
	check(game.world_id=="surface" and game.vision.enabled,"cave exit rebuilds source container visibility on the surface")
	p.pos=spawn;p.height=-1.13
	game.session.send("travel",{"route":"surface_to_bunker"});await process_frame;settle()
	check(game.world_id=="bunker" and not game.vision.enabled and game.actors[2].visible and game.actors[3].visible,"returning to base restores every party character")
	game._return_menu();check(not game.in_game,"leaving the session still cleans up normally")
	game.queue_free();await process_frame
	print("VISION_INTEGRATION ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
