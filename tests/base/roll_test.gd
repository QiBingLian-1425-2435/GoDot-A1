extends SceneTree
# Legacy suite entry; Space now exercises physical jumping.
const Model=preload("res://features/base/base_model.gd")
const Local=preload("res://features/player/local_movement.gd")
const Main=preload("res://app/main.gd")
const Body=preload("res://features/player/player.tscn")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func box(parent,at:Vector3,size:Vector3):
	var b:=StaticBody3D.new();var c:=CollisionShape3D.new();var s:=BoxShape3D.new()
	s.size=size;c.shape=s;b.position=at;b.add_child(c);parent.add_child(b)
func run():
	var m=Model.new();m.add_player(1,"jump");var p:Dictionary=m.state.players[1]
	m.state.world="ground_zero"
	p.pos=Vector2.ZERO
	m.command(1,"move",{"direction":Vector2.ZERO,"roll_seq":1});m.tick(.01)
	check(p.roll.active and p.height>0 and p.pos==Vector2.ZERO and p.stamina==85,"standing jump rises without a forward dash and costs 15 stamina")
	check(not m.command(1,"fire") and not m.command(1,"reload"),"airborne action cannot bypass combat restrictions")
	var peak:=0.0
	for i in range(75):
		m.command(1,"move",{"direction":Vector2.ZERO,"roll_seq":1});m.tick(.01)
		peak=maxf(peak,p.height)
	check(peak>.65 and peak<.72 and p.height==0 and not p.roll.active,"jump follows gravity and lands once")
	m.command(1,"move",{"direction":Vector2.ZERO,"roll_seq":1});m.tick(.01)
	check(not p.roll.active,"holding the same request cannot bunny-hop")
	# Only a press in the final pre-landing reward window gains a tier.
	p.pos=Vector2.ZERO;p.stamina=100;p.roll=m.Movement.empty_roll()
	m.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":2});m.tick(.01)
	var first_jump_speed:float=p.roll.takeoff_speed
	var first_peak:=0.0
	while p.roll.active and p.roll.time<.49:
		m.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":2});m.tick(.01);first_peak=maxf(first_peak,p.height)
	m.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":3});m.tick(.01)
	check(p.roll.buffered and p.roll.buffer_reward,"final pre-landing press enters configured reward window")
	while p.roll.active and p.roll.time>.1:m.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":3});m.tick(.01)
	check(p.roll.active and p.roll.chain==1 and p.roll.takeoff_speed>first_jump_speed,"precise buffered re-jump gains speed and starts on landing")
	var enhanced_chain_speed:float=p.roll.takeoff_speed
	var chain_peak:=0.0
	while p.roll.active:
		m.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":3});m.tick(.01);chain_peak=maxf(chain_peak,p.height)
	check(chain_peak>first_peak+.05,"timed sprint re-jump earns extra height")
	# An earlier press still removes the landing hitch, but is not rewarded and
	# drops one existing tier as the configured negative outcome.
	p.pos=Vector2.ZERO;p.height=0;p.stamina=100;p.roll=m.Movement.empty_roll();p.roll.seen=10
	p.roll.chain=1
	m.Movement._start_jump(p,p.roll,{"direction":Vector2.RIGHT,"sprint":true},Vector2.RIGHT,true,0)
	for i in range(36):m.Movement.step(p,{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":10},.01,m.solve_motion.bind(1))
	m.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":12});m.tick(.01)
	var buffered_early:bool=bool(p.roll.buffered) and not bool(p.roll.buffer_reward)
	while p.roll.active and p.roll.time>.1:m.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":12});m.tick(.01)
	check(buffered_early and p.roll.active and p.roll.chain==0 and p.roll.time<=.1,"early input continues smoothly but loses one reward tier")
	while p.roll.active:m.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":12});m.tick(.01)
	check(not m.command(2,"set_jump_chain_bonus",{"value":4}) and not m.command(1,"set_jump_chain_bonus",{"value":5}),"only host and exact speed gain presets are accepted")
	check(m.command(1,"set_jump_chain_bonus",{"value":2}),"host selects stronger chained-jump speed gain")
	check(not m.command(1,"set_jump_chain_max_speed",{"value":20}) and m.command(1,"set_jump_chain_max_speed",{"value":30}),"host selects an exact higher speed cap")
	check(not m.command(1,"set_jump_reward_window",{"value":80}) and m.command(1,"set_jump_reward_window",{"value":500}),"host selects an exact precision window")
	p.jump_chain_bonus=m.state.jump_chain_bonus;p.jump_chain_max_speed=m.state.jump_chain_max_speed;p.jump_reward_window_ms=m.state.jump_reward_window_ms
	p.pos=Vector2.ZERO;p.height=0;p.stamina=100;p.roll=m.Movement.empty_roll();p.roll.chain=4
	m.Movement._start_jump(p,p.roll,{"direction":Vector2.RIGHT,"sprint":true},Vector2.RIGHT,true,0)
	check(p.roll.takeoff_speed>enhanced_chain_speed and p.roll.takeoff_speed<30.0,"maximum chain tier accumulates configured per-jump speed gain")
	while p.roll.active:m.Movement.step(p,{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":20},.01,m.solve_motion.bind(1))
	for i in range(20):m.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":3});m.tick(.01)
	check(p.roll.chain==0,"missing the landing window restores normal sprint speed")
	p.stamina=15;m.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":23});m.tick(.01)
	while p.roll.active:m.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":23});m.tick(.01)
	m.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":23});m.tick(.01)
	check(p.sprint_exhausted and not p.sprint and p.roll.chain==0,"exhausted stamina restores walking speed and clears jump reward")
	p.stamina=14;m.command(1,"move",{"direction":Vector2.ZERO,"roll_seq":24});m.tick(.01)
	check(not p.roll.active,"low stamina rejects jump")
	p.stamina=100;p.roll=m.Movement.empty_roll();p.roll.seen=24
	var predictor=Local.new();predictor.solver=m.solve_motion.bind(0);predictor.confirm(p)
	predictor.set_input({"direction":Vector2.RIGHT,"roll_seq":25});predictor.advance(.02,p)
	var display:Dictionary=predictor.sample_player(p)
	check(display.height>0 and display.pos.x>0 and p.height==0 and not p.roll.active,"client predicts jump height without mutating authority")
	var world:=Node3D.new();root.add_child(world)
	box(world,Vector3(0,-.1,0),Vector3(30,.2,30))
	box(world,Vector3(1,1.5,0),Vector3(.2,3,3))
	box(world,Vector3(0,1.8,5),Vector3(4,.2,4))
	box(world,Vector3(1,.2,-5),Vector3(1,.4,2))
	var body=Body.instantiate();world.add_child(body)
	await physics_frame;await physics_frame
	for lane in [0.0,5.0,-5.0]:
		p.pos=Vector2(-.5,lane);p.height=.04;p.stamina=100;p.roll=m.Movement.empty_roll()
		var peak_height:=.04
		for i in range(90):
			var input:Dictionary={"direction":Vector2.RIGHT if lane!=5.0 and i<35 else Vector2.ZERO,"roll_seq":4}
			m.Movement.step(p,input,.01,func(from,offset):return body.move_airborne(Vector3(from.x,p.height,from.y),offset,p.roll.get("vertical_delta",0)) if p.roll.active else body.move_spatial(Vector3(from.x,p.height,from.y),offset))
			peak_height=maxf(peak_height,p.height)
		check(not p.roll.active,"physical capsule lands in lane "+str(lane))
		if lane==0.0:check(p.pos.x<.59 and peak_height>.65,"jump cannot pass through a tall wall")
		if lane==5.0:check(peak_height<.23,"low ceiling cancels ascent")
		if lane==-5.0:check(p.pos.x>.6 and p.height>.4,"jump lands on a low platform")
	p.pos=Vector2(-.5,0);p.height=.04;p.stamina=100;p.roll=m.Movement.empty_roll();p.roll.chain=4
	p.jump_chain_bonus=4;p.jump_chain_max_speed=30
	m.Movement._start_jump(p,p.roll,{"direction":Vector2.RIGHT,"sprint":true},Vector2.RIGHT,true,0)
	var high_speed:float=p.roll.takeoff_speed
	for i in range(90):
		m.Movement.step(p,{"direction":Vector2.RIGHT,"sprint":true,"roll_seq":30},.01,func(from,offset):return body.move_airborne(Vector3(from.x,p.height,from.y),offset,p.roll.get("vertical_delta",0)) if p.roll.active else body.move_spatial(Vector3(from.x,p.height,from.y),offset))
	check(high_speed>10.0 and high_speed<30.0 and p.pos.x<.59,"high-speed airborne sweep cannot tunnel through thin wall")
	world.queue_free();await process_frame
	var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game.sound.muted=true
	game._start_solo();game.set_physics_process(false);game.session.set_physics_process(false)
	p=game.session.model.state.players[1]
	var key:=InputEventKey.new();key.physical_keycode=KEY_SPACE;key.pressed=true
	game._unhandled_input(key);game.session.send("move",{"direction":Vector2.ZERO,"aim":Vector2.UP})
	game.session.model.tick(.01);game._update_actors(.01)
	check(p.roll.active and p.height>0 and game.actors[1].animation_state=="jump","Space triggers authority jump and jump animation")
	check(game.actors[1].pivot.rotation.is_zero_approx(),"jump keeps body upright instead of rolling")
	game.camera_zoom=6
	for i in range(80):
		game.session.send("move",{"direction":Vector2.ZERO,"aim":Vector2.UP})
		game.session.model.tick(.01);game._update_actors(.01);game._update_camera(.1)
		if i==23 and DisplayServer.get_name()!="headless":
			await process_frame;await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://artifacts")
			check(root.get_texture().get_image().save_png("res://artifacts/jump_airborne.png")==OK,"capture visible jump apex")
	check(not p.roll.active and p.height<.05,"actual main returns to ground after jump")
	game.ui.toggle_inventory();game._unhandled_input(key)
	game.session.send("move",{"direction":Vector2.ZERO});game.session.model.tick(.01)
	check(not p.roll.active,"inventory blocks jump intent")
	game.queue_free();await process_frame;await process_frame
	print("JUMP checks=",checks," failures=",failures);quit(1 if failures else 0)
