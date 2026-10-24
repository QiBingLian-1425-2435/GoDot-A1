extends SceneTree
const Main=preload("res://app/main.gd")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func run():
	var game=Main.new();game.smoke=true;game.elapsed=-10000;game.capture_mode="base"
	root.add_child(game);game.set_physics_process(false);game.sound.muted=true
	var m=game.session.model;var p:Dictionary=m.state.players[1]
	p.pos=Vector2(0,-8.2)
	m.command(1,"travel",{"route":"bunker_to_surface"});game._sync_world();game.session.set_physics_process(false)
	while game.world_loading:await process_frame
	for i in range(3):await physics_frame
	game.enemy_director.update(game,.016)
	check(m.state.enemies.size()==4,"real Ground Zero seeds four hostiles on safe ground")
	if m.state.enemies.is_empty():game.queue_free();quit(1);return
	var probe=game.enemy_director.body_for(-1)
	var all_clear:=true
	for e in m.state.enemies.values():all_clear=all_clear and probe.is_clear(m.Enemies.at(e))
	check(all_clear,"all spawn capsules are clear of source map geometry")
	var chosen:Dictionary={};var player_at:=Vector3.ZERO
	for e in m.state.enemies.values():
		var origin:Vector3=m.Enemies.at(e)
		for i in range(12):
			var dir:=Vector2.from_angle(TAU*i/12);var at:=origin
			for j in range(12):at=probe.move_spatial(at,dir*.3)
			if at.distance_to(origin)>3 and game.enemy_director.clear_sight(origin+Vector3.UP,at+Vector3.UP):
				chosen=e;player_at=at;break
		if not chosen.is_empty():break
	check(not chosen.is_empty(),"a real spawn has an open pursuit and attack route")
	if not chosen.is_empty():
		for e in m.state.enemies.values():
			if e.id!=chosen.id:e.hp=0
		p.pos=Vector2(player_at.x,player_at.z);p.height=player_at.y;p.hp=100;p.aim=(chosen.pos-p.pos).normalized()
		chosen.aim=(p.pos-chosen.pos).normalized();var start:Vector2=chosen.pos
		var clear:=true
		for i in range(45):
			m.tick(.1);clear=clear and probe.is_clear(m.Enemies.at(chosen))
			game.enemy_director.update(game,.1)
			if chosen.mode=="windup":break
		check(chosen.pos.distance_to(start)>1 and chosen.mode=="windup","source-map hostile physically pursues and winds up")
		check(clear,"chase never overlaps map collision")
		var wall:=StaticBody3D.new();wall.collision_layer=1|8|16;wall.collision_mask=0
		var collider:=CollisionShape3D.new();var barrier:=BoxShape3D.new();barrier.size=Vector3(.3,2,.3);collider.shape=barrier;wall.add_child(collider)
		wall.position=(m.Enemies.at(chosen)+m.Enemies.at(p))*.5+Vector3(0,.85,0);game.add_child(wall)
		await physics_frame;await physics_frame
		for i in range(7):m.tick(.1)
		check(p.hp==100,"real physics blocker prevents a wound through cover")
		p.aim=(chosen.pos-p.pos).normalized();p.fire_timer=0;m.command(1,"fire")
		check(chosen.hp==100,"real physics blocker prevents shooting through cover")
		wall.free();await physics_frame
		chosen.mode="idle";chosen.timer=0;m.tick(.1)
		game._update_actors(.1);game._update_camera(1);game.vision.update(game,.1);game.enemy_director.update(game,.1);game._refresh_ui();game.ui._toast_label.visible=false
		for i in range(4):await process_frame
		check(game.enemy_director.views[chosen.id].visible,"enemy is visible inside player line of sight")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var folder:=OS.get_environment("A1_TEST_ARTIFACTS")
			if folder.is_empty():folder=ProjectSettings.globalize_path("res://artifacts")
			DirAccess.make_dir_recursive_absolute(folder)
			check(game.get_viewport().get_texture().get_image().save_png(folder+"/enemy_encounter.png")==OK,"capture real encounter")
		for i in range(7):m.tick(.1)
		check(p.hp<100,"real map melee damages player after windup")
		p.aim=(chosen.pos-p.pos).normalized()
		for i in range(3):p.fire_timer=0;m.command(1,"fire")
		m.tick(.1);game.enemy_director.update(game,.1)
		check(chosen.hp==0 and chosen.mode=="dead","real world gun ray kills the attacking monster")
		# World transition keeps defeated enemies in this room's map cache.
		m.stations=[{"kind":"travel","uid":"qa_back","world":"surface","destination":"bunker","pos":p.pos,"spawn":Vector3.ZERO}]
		check(m.command(1,"travel",{"route":"qa_back"}),"return travel accepted")
		game._sync_world();await process_frame
		check(m.state.enemies.is_empty() and game.enemy_director.views.is_empty(),"base has no enemies or stale visuals")
		m.stations=[{"kind":"travel","uid":"qa_forward","world":"bunker","destination":"surface","pos":p.pos,"spawn":player_at}]
		m.command(1,"travel",{"route":"qa_forward"})
		check(m.state.enemies[chosen.id].hp==0 and m.state.enemies_seeded,"returning to map does not respawn defeated enemies")
	game._return_menu();game.queue_free();await process_frame;await process_frame
	print("ENEMY_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
