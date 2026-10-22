extends SceneTree
const Main=preload("res://app/main.gd")
var game
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func settle():game._update_actors(1);game._update_camera(1);game._update_drops();game.vision.update(game,.06);game.field_item_view.update(game);game._update_interaction();game._refresh_ui()
func capture(name:String):
	if DisplayServer.get_name()=="headless":return
	for i in range(4):await process_frame;settle()
	await RenderingServer.frame_post_draw
	var folder:=OS.get_environment("A1_TEST_ARTIFACTS")
	if folder.is_empty():folder=ProjectSettings.globalize_path("res://artifacts")
	DirAccess.make_dir_recursive_absolute(folder)
	check(game.get_viewport().get_texture().get_image().save_png(folder+"/items_"+name+".png")==OK,"capture "+name)
func run():
	game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game.sound.muted=true
	game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game._start_solo()
	var model=game.session.model;var p:Dictionary=model.state.players[1]
	p.pos=Vector2(0,-8.2);game.session.send("travel",{"route":"bunker_to_surface"})
	while game.world_loading:await process_frame
	await physics_frame;await physics_frame
	var containers:=0;var chosen:Dictionary={}
	for station in model.stations:
		if station.get("kind")!="loot":continue
		containers+=1
		if not chosen.is_empty():continue
		for direction in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
			var foot:=Vector3(station.pos.x,float(station.height),station.pos.y)+Vector3(direction.x,0,direction.y)*1.6
			var safe:Dictionary=game.player_physics.safe_standing_position(foot)
			if safe.is_empty():continue
			foot=safe.position
			if absf(foot.y-float(station.height))>2 or not game.world.can_reach_loot(station.uid,foot):continue
			p.pos=Vector2(foot.x,foot.z);p.height=foot.y;p.aim=-direction;settle()
			if game.nearest.get("kind")=="loot":chosen=game.nearest.duplicate();break
	check(containers>100 and not chosen.is_empty(),"real source containers expose reachable E-search interaction")
	if chosen.is_empty():game.queue_free();await process_frame;quit(1);return
	model._insert(p.bag,model._item("lockpick",2));settle()
	game._interact();settle()
	check(model.state.containers.has(chosen.uid) and model.state.drops.is_empty() and game.ui._loot_uid==chosen.uid,"actual E opens container panel without spawning floor loot")
	var box:Dictionary=model.state.containers[chosen.uid]
	var original:Array=box.items.duplicate(true)
	check(model.command(1,"search",{"uid":chosen.uid}) and box.items==original,"reopening original source container never rerolls contents")
	for i in range(150):model.tick(.01)
	settle()
	await capture("container_search")
	check(box.revealed==1 and game.ui._loot_status.text.contains("1 /"),"real map search reveals sequentially and updates panel")
	var before_weight:float=model.Items.weight(p.bag)
	game.ui._loot_selected=0;game.ui.ContainerPanel.take(game.ui,false);settle()
	check(box.items[0].is_empty() and model.Items.weight(p.bag)>before_weight,"panel takes revealed real item directly into bag")
	game.ui._close_dialog();settle()
	check(p.loot_uid.is_empty(),"closing real container stops active search")
	model.add_player(2,"烟雾后的队友")
	var origin:=Vector3(p.pos.x,float(p.height),p.pos.y);var direction:=Vector2.ZERO
	for angle in range(16):
		var candidate:=Vector2.from_angle(TAU*angle/16.0)
		p.aim=candidate;settle()
		var target:=origin+Vector3(candidate.x,0,candidate.y)*.9
		if not model.field_placement.call(origin,target).is_empty() and game.vision.can_see(target+Vector3.UP):direction=candidate;break
	check(not direction.is_zero_approx(),"actual collision query finds valid tool placement")
	if direction.is_zero_approx():game.queue_free();await process_frame;quit(1);return
	p.aim=direction
	var target:=origin+Vector3(direction.x,0,direction.y)*1.2
	model.state.players[2].pos=Vector2(target.x,target.z);model.state.players[2].height=origin.y
	settle();check(game.actors[2].visible,"teammate initially visible")
	p.bag[20]=model._item("smoke_grenade",1);game.session.send("use",{"index":20});settle()
	check(model.state.field_effects.size()==1 and not game.actors[2].visible,"confirmed smoke hides actual teammate in local vision")
	check(game.world._terrain_material.get_shader_parameter("vision_smoke_count")==1,"actual terrain shader receives smoke volume")
	check(game.field_item_view.nodes.size()==1,"actual smoke cloud node renders")
	# Smoke contributes no physical collider and cannot stop a projectile.
	var excluded:Array[RID]=[]
	var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin+Vector3.UP,target+Vector3.UP,8,excluded))
	check(hit.is_empty(),"smoke does not introduce a projectile collider")
	await capture("smoke")
	for effect in model.state.field_effects:effect.ttl=.001
	model.tick(.01);settle()
	check(model.state.field_effects.is_empty() and game.actors[2].visible,"expiry restores real teammate visibility")
	p.bag[20]=model._item("glowstick",1);p.bag[21]=model._item("beacon",1)
	game.session.send("use",{"index":20});game.session.send("use",{"index":21});settle()
	var lights:=0;var labels:=0
	for part in game.field_item_view.nodes.values():
		for node in part.root.get_children():
			if node is OmniLight3D:lights+=1
			if node is Label3D and node.no_depth_test:labels+=1
	check(lights==1 and labels==1,"lightstick illuminates and beacon has a shared-visible marker")
	await capture("field_tools")
	var cached_world:String=game.world_id
	# Use existing authoritative route handling to check round-trip container state.
	var route:Dictionary={"kind":"travel","uid":"test_return","world":"surface","pos":p.pos,"height":p.height,"destination":"bunker","spawn":Vector3(-1,0,4)}
	model.stations.append(route);game.session.send("travel",{"route":"test_return"});settle()
	check(model.state.field_effects.is_empty() and game.field_item_view.nodes.is_empty(),"travel removes temporary field effects and nodes")
	check(model.world_cache[cached_world].containers.has(chosen.uid),"searched container state survives leaving that map")
	p=model.state.players[1];p.pos=Vector2(0,-8.2);game.session.send("travel",{"route":"bunker_to_surface"})
	while game.world_loading:await process_frame
	settle();check(model.state.containers.has(chosen.uid),"returning to same room/map cannot reroll the opened container")
	game.queue_free();await process_frame;await process_frame
	print("ITEM_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
