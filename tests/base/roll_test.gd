extends SceneTree
const Model = preload("res://features/base/base_model.gd")
const Local = preload("res://features/player/local_movement.gd")
const Main = preload("res://app/main.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1; print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures += 1
func move(m, seq: int, direction: Vector2):
	m.command(1,"move",{"direction":direction,"aim":Vector2.UP,"roll_seq":seq})
func run():
	test_latency(6)
	test_latency(12)
	var m = Model.new(); m.add_player(1,"roll")
	var p: Dictionary = m.state.players[1]
	p.pos=Vector2.ZERO
	move(m,1,Vector2.RIGHT);m.tick(.01)
	check(p.roll.active and p.roll.direction==Vector2.RIGHT and p.stamina==80,"roll uses movement instead of mouse aim and costs stamina once")
	check(not m.command(1,"fire") and not m.command(1,"reload"),"roll cannot shoot or reload")
	for i in range(64): move(m,1,Vector2.LEFT);m.tick(.01)
	check(not p.roll.active and absf(p.pos.x-3)<.001 and absf(p.pos.y)<.001,"roll direction locks and finishes at three metres")
	move(m,2,Vector2.RIGHT);m.tick(.01)
	check(not p.roll.active,"cooldown rejects another roll without queuing it")
	for i in range(110):move(m,2,Vector2.ZERO);m.tick(.01)
	check(not p.roll.active,"holding same request never repeats roll")
	move(m,3,Vector2.ZERO);m.tick(.01)
	check(p.roll.active and p.roll.direction==Vector2.UP,"standing roll falls back to facing")
	m.reset_transients(1);move(m,3,Vector2.ZERO);m.tick(.01)
	check(not p.roll.active,"reset cancels roll and does not replay previous request")
	p.stamina=19;move(m,4,Vector2.RIGHT);m.tick(.01)
	check(not p.roll.active,"low stamina rejects roll")
	p.stamina=100;p.reloading=true;move(m,5,Vector2.RIGHT);m.tick(.01)
	check(not p.roll.active,"reload cannot be bypassed by rolling")
	p.reloading=false;p.pos=Vector2.ZERO
	m.obstacles.assign([Rect2(1,-10,1,20)])
	move(m,6,Vector2.RIGHT)
	for i in range(65):m.tick(.01)
	check(p.pos.x<=.681,"roll uses collision solver and cannot pass through wall")
	# The client predicts the same action without writing the authoritative player.
	m.obstacles.clear();m.reset_transients(1);p.pos=Vector2.ZERO;p.stamina=100
	var predictor=Local.new();predictor.solver=m.solve_motion.bind(0);predictor.confirm(p)
	predictor.set_input({"direction":Vector2.DOWN,"aim":Vector2.UP,"roll_seq":7})
	predictor.advance(.05,p)
	var display:Dictionary=predictor.sample_player(p)
	check(display.roll.active and display.pos.y>0 and not p.roll.active and p.pos==Vector2.ZERO,"client roll starts immediately without mutating shared authority")
	# Real Main, Space intent, collision and procedural skeleton poses.
	var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game.sound.muted=true
	game.set_process(false);game.set_physics_process(false);game._start_solo();game.session.set_physics_process(false)
	p=game.session.model.state.players[1];p.pos=Vector2(-1,4);p.aim=Vector2.RIGHT
	var key:=InputEventKey.new();key.physical_keycode=KEY_SPACE;key.pressed=true
	game._unhandled_input(key);game.session.send("move",{"direction":Vector2.RIGHT,"aim":Vector2.UP})
	game.session.model.tick(.01)
	check(p.roll.active and p.roll.direction==Vector2.RIGHT,"Space routes into authoritative movement roll")
	var actor=game.actors[1]
	game.camera_zoom=6
	var max_angle_step:=0.0;var prior:=Quaternion.IDENTITY
	for i in range(64):
		game.session.model.tick(.01);game._update_actors(.01);game._update_camera(1);game._refresh_ui()
		var q:Quaternion=actor.pivot.basis.get_rotation_quaternion()
		max_angle_step=maxf(max_angle_step,prior.angle_to(q));prior=q
		if i in [10,30,52] and DisplayServer.get_name()!="headless":
			await process_frame;await RenderingServer.frame_post_draw
			var folder:=OS.get_environment("A1_TEST_ARTIFACTS")
			if folder.is_empty():folder=ProjectSettings.globalize_path("res://artifacts")
			DirAccess.make_dir_recursive_absolute(folder)
			check(game.get_viewport().get_texture().get_image().save_png(folder+"/roll_%d.png"%i)==OK,"capture roll phase %d"%i)
	check(max_angle_step<.3,"full-body rotation progresses smoothly without orientation jumps")
	check(actor.pivot.transform.is_equal_approx(Transform3D.IDENTITY),"roll finishes upright without residual rig transform")
	game.ui.toggle_inventory(true);var seq:int=game.session._roll_seq;game._unhandled_input(key)
	check(game.session._roll_seq==seq,"Space does not roll while inventory is open")
	game.ui.close_inventory()
	var wall:=StaticBody3D.new();wall.collision_layer=1;wall.position=Vector3(0,1,4)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.2,2,3);shape.shape=box;wall.add_child(shape);game.add_child(wall)
	await physics_frame;await physics_frame
	game.session.model.reset_transients(1);p.pos=Vector2(-1,4);p.stamina=100
	game.session.request_roll();game.session.send("move",{"direction":Vector2.RIGHT,"aim":Vector2.RIGHT})
	for i in range(65):game.session.model.tick(.01)
	check(p.pos.x<=-.40,"real CharacterBody3D roll stops at solid wall")
	game.queue_free();await process_frame;await process_frame
	print("ROLL checks=",checks," failures=",failures);quit(1 if failures else 0)

func test_latency(delay: int):
	var m=Model.new();m.add_player(1,"latency");var p:Dictionary=m.state.players[1];p.pos=Vector2.ZERO
	var predictor=Local.new();predictor.solver=m.solve_motion.bind(0);predictor.confirm(p)
	var outbound:Array=[];var inbound:Array=[];var serial:=0;var requested:=0
	for frame in range(360):
		var edge:bool=frame in [30,150]
		if edge:requested+=1
		var input:Dictionary={"direction":Vector2.RIGHT if edge else Vector2.ZERO,"aim":Vector2.UP,"roll_seq":requested,"roll_direction":Vector2.RIGHT}
		predictor.set_input(input)
		if frame%3==0 or edge:
			serial+=1;predictor.note_sent(serial,edge)
			outbound.append({"due":frame+delay,"seq":serial,"input":input.duplicate()})
		while not outbound.is_empty() and outbound[0].due<=frame:
			var packet:Dictionary=outbound.pop_front()
			p.input_seq=packet.seq;p.input_origin=p.pos;p.input_stamina=p.stamina;p.input_weight=p.weight;p.input_max_weight=p.max_weight;p.input_roll=p.roll.duplicate(true)
			m.command(1,"move",packet.input)
		m.tick(1.0/60.0)
		if frame%3==0:inbound.append({"due":frame+delay,"state":p.duplicate(true)})
		while not inbound.is_empty() and inbound[0].due<=frame:predictor.confirm(inbound.pop_front().state)
		predictor.advance(1.0/60.0,p)
	var display:Dictionary=predictor.sample_player(p)
	check(absf(p.pos.x-6)<.01 and display.pos.distance_to(p.pos)<.15 and not display.roll.active,"two rolls converge under %d ms round trip without replay"%roundi(delay*2000.0/60.0))
