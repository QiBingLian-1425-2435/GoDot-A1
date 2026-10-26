extends SceneTree
const Model=preload("res://features/base/base_model.gd")
const Main=preload("res://app/main.gd")
const Voice=preload("res://features/voice/voice_rules.gd")
const Predictor=preload("res://features/player/local_movement.gd")
const InputController=preload("res://features/player/base_input.gd")
const Texts=preload("res://features/localization/game_text.gd")
var checks:=0
var failures:=0
func _initialize():Engine.max_fps=60;call_deferred("run")
func check(ok: bool, label: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func find_button(parent: Node, text: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text==text:return child
		var found:=find_button(child,text)
		if found!=null:return found
	return null
func render(game, label: String):
	game._update_actors(.1);game._update_camera(1);game.vision.update(game,.1);game.soul_view.update(game);game._refresh_ui()
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/base_tests"))
	check(root.get_texture().get_image().save_png("res://artifacts/base_tests/roaming_"+label+".png")==OK,"capture "+label)
func run():
	var m=Model.new();m.bounds=Rect2(-200,-200,400,400)
	for id in range(1,5):m.add_player(id,str(id))
	var p: Dictionary=m.state.players[1];var host: Dictionary=m.state.players[2]
	p.pos=Vector2.ZERO;p.hp=0;m.tick(.1)
	var body: Dictionary=m.state.corpses[p.corpse_uid]
	for speed in [2,4,6,8]:
		p.pos=Vector2.ZERO
		check(m.command(1,"soul_speed",{"speed":speed}),"accept exact speed "+str(speed))
		for i in range(10):m.command(1,"move",{"direction":Vector2.RIGHT});m.tick(.1)
		check(absf(p.pos.x-3.7*speed)<.001,"float speed is walking times "+str(speed))
	check(body.pos==Vector2.ZERO,"roaming never moves original corpse")
	for value in [0,1,3,10,4.0,"4",null]:check(not m.command(1,"soul_speed",{"speed":value}),"reject invalid speed "+str(value))
	check(not m.command(2,"soul_speed",{"speed":8}),"living player cannot select ghost speed")
	m.obstacles.assign([Rect2(-.1,-1,2,2)]);p.pos=Vector2.ZERO
	m.command(1,"move",{"direction":Vector2.RIGHT});m.tick(.1)
	check(p.pos.x>2,"ghost floats through solid obstacle")
	check(not InputController._footstep_state(p).moving,"floating emits no walking footsteps")
	var predictor=Predictor.new();predictor.solver=m.solve_motion.bind(0);predictor.confirm(p)
	predictor.set_input({"direction":Vector2.RIGHT});predictor.advance(.1,p)
	check(predictor.sample_player(p).pos.x>p.pos.x,"free ghost movement predicts immediately without collision")
	p.pos=Vector2.ZERO;host.pos=Vector2(2.401,0)
	check(not m.Souls.can_possess(m.state.players,1,2) and not m.command(1,"possess",{"target":2}),"host rejects out-of-range possession")
	host.pos=Vector2.ZERO;host.height=3
	check(not m.command(1,"possess",{"target":2}),"possession distance includes vertical separation")
	host.height=0
	host.pos=Vector2(2.4,0);check(m.command(1,"possess",{"target":2}),"possession accepted at exact distance boundary")
	m.state.players[3].pos=host.pos
	check(Voice.gain(m.state.players,1,2)==1 and Voice.gain(m.state.players,2,1)==1,"paired ghost and host hear each other")
	check(Voice.gain(m.state.players,1,3)==0 and Voice.gain(m.state.players,3,1)==0,"third living teammate cannot hear or speak to attached ghost")
	var other: Dictionary=m.state.players[4];other.hp=0;m.tick(.1);other.pos=host.pos;m.command(4,"possess",{"target":2})
	check(Voice.gain(m.state.players,1,4)==0 and Voice.gain(m.state.players,4,1)==0,"two ghosts on same host cannot hear each other")
	check(Voice.gain(m.state.players,2,3)==1,"living proximity voice remains available")
	host.pos=Vector2(100,90);m.tick(.1);m.command(1,"soul_wait")
	check(p.possessing==0 and p.pos==host.pos and body.pos==Vector2.ZERO,"detach starts roaming at host's current position")
	check(Voice.gain(m.state.players,1,2)==0 and Voice.gain(m.state.players,2,1)==0,"detach immediately cuts both voice directions")
	m.command(1,"move",{"direction":Vector2.RIGHT});m.tick(.1)
	check(p.pos.x>100,"detached soul resumes fast roaming")
	p.pos=Vector2(199.9,0);m.command(1,"move",{"direction":Vector2.RIGHT});m.tick(.1)
	check(p.pos.x<=200,"ghost remains inside current map bounds")
	m.Souls.revive(m,p)
	check(p.pos==body.pos and p.life=="alive","revival returns roaming soul to its physical corpse, never the sightseeing location")

	Texts.set_locale("zh_cn",false)
	var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game._start_solo()
	var model=game.session.model;model.add_player(2,"Nearby");model.add_player(3,"Far")
	var gp: Dictionary=model.state.players[1];gp.hp=0;model.tick(.1)
	model.state.players[2].pos=gp.pos+Vector2(1,0);model.state.players[3].pos=gp.pos+Vector2(12,0)
	await render(game,"free")
	check(game.soul_view.ghost.visible and not game.actors[1].visible,"owner sees distinct ghost mesh instead of living body")
	check(find_button(game.ui._soul_panel,Texts.resolve("⟦soul_panel.009⟧")+"Nearby")!=null and find_button(game.ui._soul_panel,Texts.resolve("⟦soul_panel.009⟧")+"Far")==null,"UI only offers nearby possession")
	check(game.vision.omniscient and game.vision.can_see(Vector3(0,100,1000)),"free soul sees all directions, heights and distances")
	check(game.soul_view._environment.ambient_light_energy>=1,"free soul gets bright environment")
	for speed in [4,6,8,2]:
		var b: Button=game.ui._soul_panel.get_node("SoulSpeed"+str(speed));b.pressed.emit();game._refresh_ui()
		check(int(gp.soul_speed)==speed,"real UI selects speed "+str(speed))
	var event:=InputEventKey.new();event.physical_keycode=KEY_A;event.keycode=KEY_A;event.pressed=true
	Input.parse_input_event(event.duplicate());Input.flush_buffered_events()
	var before: Vector2=gp.pos
	InputController._physics_process(game,.1);model.tick(.1)
	event.pressed=false;Input.parse_input_event(event.duplicate());Input.flush_buffered_events()
	check(gp.pos.distance_to(before)>.6 and not game.crosshair.active,"real movement key drives free soul without a weapon reticle")
	for i in range(3):game.session.send("move",{"direction":Vector2.LEFT});model.tick(.1)
	game.session.send("move",{"direction":Vector2.ZERO})
	await render(game,"floating")
	check(find_button(game.ui._soul_panel,Texts.resolve("⟦soul_panel.009⟧")+"Nearby")==null,"moving out of range removes the possession prompt")
	model.state.players[2].pos=gp.pos+Vector2(1,0);game._refresh_ui()
	var attach:=find_button(game.ui._soul_panel,Texts.resolve("⟦soul_panel.009⟧")+"Nearby");attach.pressed.emit()
	await render(game,"attached")
	check(not game.soul_view.ghost.visible and not game.vision.omniscient and game.soul_view._environment.ambient_light_energy<1,"attachment hides ghost and restores living vision and lighting")
	event.pressed=true;Input.parse_input_event(event.duplicate());Input.flush_buffered_events();InputController._physics_process(game,.1);model.tick(.1)
	event.pressed=false;Input.parse_input_event(event.duplicate());Input.flush_buffered_events()
	check(gp.pos==model.state.players[2].pos,"movement key cannot move or control attached teammate")
	find_button(game.ui._soul_panel,Texts.resolve("⟦soul_panel.008⟧")).pressed.emit()
	await render(game,"detached")
	check(game.soul_view.ghost.visible and game.vision.omniscient,"detach restores own floating avatar and panoramic vision")
	game.session.local_id=2;await render(game,"teammate")
	check(not game.soul_view.ghost.visible and not game.actors[1].visible,"living teammate sees neither remote ghost mesh nor hidden player body")
	game.session.local_id=1;Texts.set_locale("en",false);await render(game,"english")
	check(game.ui._soul_panel.get_node("SoulSpeed8")!=null,"speed controls survive language switch")
	game._return_menu();check(not game.soul_view.ghost.visible,"leaving session hides ghost avatar")
	game.queue_free();await process_frame;await process_frame
	print("SOUL_ROAMING checks=",checks," failures=",failures);quit(1 if failures else 0)
