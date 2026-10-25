extends SceneTree
const Model = preload("res://features/base/base_model.gd")
const Voice = preload("res://features/voice/voice_rules.gd")
const Prediction = preload("res://features/player/local_movement.gd")
const Main = preload("res://app/main.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks+=1; print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures+=1
func button(parent: Node, text: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text==text: return child
		var found := button(child,text)
		if found!=null: return found
	return null
func run():
	var m = Model.new();m.add_player(1,"undead");m.add_player(2,"teammate")
	var p: Dictionary=m.state.players[1];var r: Dictionary=m.state.players[2]
	p.pos=Vector2.ZERO;r.pos=Vector2(4,0)
	check(p.san==100,"new player has full SAN")
	p.bag[20]=m._item("san_capsule",1)
	var gun_uid: String=p.equipment.weapon.uid
	check(m.command(1,"use",{"index":20}) and p.life=="zombie" and p.hp==0 and p.san==0,"SAN item immediately zombifies with zero HP")
	check(not m.Souls.alive(p) and m.Souls.mobile(p),"zombie counts as dead but mobile")
	check(m.state.corpses.is_empty() and p.equipment.weapon.uid==gun_uid,"zombie retains inaccessible gear until soul death")
	for action in ["fire","reload","use","drop","pickup","equip","unequip","transfer","split","sort","search","loot_take","rest","door","travel","unstuck","buy","rescue","possess","soul_wait","return_camp"]:
		check(not m.command(1,action,{"target":2,"index":0,"direction":Vector2.RIGHT}),"zombie rejects "+action)
	check(Voice.gain(m.state.players,1,2)==0 and Voice.gain(m.state.players,2,1)==0,"zombie cannot send or receive voice")
	p.possessing=2
	check(m.Souls.observer_id(m.state.players,1)==1 and not Voice.can_speak(m.state.players,1),"stale possession cannot grant zombie voice or camera")
	p.possessing=0
	check(not m.enemy_damage(1,100) and m.enemy_targets()==[r],"enemy authority excludes zombie targets and rejects damage")
	check(not m.change_san(1,100),"SAN healing cannot bypass resurrection")
	check(m.command(1,"move",{"direction":Vector2.RIGHT}),"zombie move accepted")
	m.tick(.1);check(p.pos.x>0 and p.life=="zombie","zero HP zombie moves and never automatically becomes soul")
	var prediction=Prediction.new();prediction.solver=func(a,b):return a+b
	prediction.confirm(p);prediction.set_input({"direction":Vector2.RIGHT});prediction.advance(.1,p)
	check(prediction.sample_player(p).pos.x>p.pos.x,"client predicts zombie movement despite zero HP")
	m.command(1,"move",{"direction":Vector2.ZERO})
	m.world_ready=false;r.pos=p.pos
	m.tick(.1);check(r.life=="alive","loading pauses zombie attacks")
	m.world_ready=true;m.rescue_reachable=func(_a,_b):return false
	m.tick(.1);check(r.life=="alive","walls block automatic kill")
	m.rescue_reachable=Callable();r.height=3
	m.tick(.1);check(r.life=="alive","other floor blocks automatic kill")
	r.height=0;r.pos=p.pos+Vector2(1.1,0)
	m.tick(.1);check(r.life=="alive","outside contact radius is safe")
	check(not m.WorldTravel.enter_world(m,"bunker",Vector3.ZERO) and m.state.world_revision==0,"party travel cannot carry zombie to extraction")
	r.bag[20]=m._item("revival_serum",2)
	m.rescue_reachable=func(_a,_b):return false
	check(not m.command(2,"use",{"index":20}) and r.bag[20].count==2,"wall blocks resurrection without consuming item")
	m.rescue_reachable=Callable();r.height=3
	check(not m.command(2,"use",{"index":20}) and r.bag[20].count==2,"other floor blocks resurrection without consuming item")
	r.height=0;r.pos=p.pos+Vector2(3,0)
	check(not m.command(2,"use",{"index":20}) and r.bag[20].count==2,"distant resurrection consumes nothing")
	r.pos=p.pos+Vector2(1.1,0)
	check(m.command(2,"use",{"index":20}) and p.life=="alive" and p.hp==30 and p.san==30,"teammate resurrection item restores life and SAN from safe range")
	check(r.bag[20].count==1 and p.equipment.weapon.uid==gun_uid,"resurrection consumes exactly one item and preserves original gear")
	check(not m.command(2,"use",{"index":20}) and r.bag[20].count==1,"repeated use on living party consumes nothing")
	check(m.change_san(1,-30) and p.life=="zombie","authority SAN loss zombifies")
	r.pos=p.pos+Vector2(.5,0);m.tick(.1)
	check(r.life=="soul" and r.hp==0,"contact automatically kills teammate")
	var corpses: int=m.state.corpses.size();m.tick(.1)
	check(m.state.corpses.size()==corpses,"contact does not repeatedly duplicate victim corpses")
	check(not m.command(2,"return_camp"),"all-dead shortcut cannot extract remaining zombie")
	var death_pos: Vector2=p.pos
	check(m.command(1,"suicide") and p.life=="soul" and p.pos==death_pos,"zombie suicide becomes stationary soul at current location")
	var uid: String=p.corpse_uid
	check(m.state.corpses.has(uid) and p.equipment.weapon.is_empty(),"suicide transfers retained gear to one corpse")
	check(not m.command(1,"suicide") and m.state.corpses.size()==corpses+1,"duplicate suicide cannot create extra corpse")
	check(m.command(1,"return_camp") and p.life=="alive" and p.san==30,"souls can recover after zombie has suicided")
	p.san=61
	var profile: Dictionary=m.Profile.capture(m,1)
	check(m.Profile.apply(m,profile,1)==OK and p.san==61,"profile saves and restores SAN")
	profile.erase("san")
	check(m.Profile.apply(m,profile,1)==OK and p.san==100,"older profile without SAN defaults to full")
	profile.san=NAN
	check(not m.Profile.valid(m,profile),"profile rejects nonfinite SAN")
	check(m.enemy_damage(2,1000) and r.life=="soul","enemy authority still kills living players")
	m.Souls.revive(m,r)
	check(not m.command(1,"suicide"),"living players cannot use zombie-only suicide shortcut")
	# HP death takes precedence if both resources are depleted.
	p.hp=0;p.san=0;m.tick(.1);check(p.life=="soul","simultaneous zero HP and SAN remains ordinary death")
	# Actual Main and HUD integration, not only isolated rules.
	var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game._start_solo()
	var gp: Dictionary=game.session.model.state.players[1]
	game.session.model.change_san(1,-100)
	game._refresh_ui();game._update_actors(.1);game.soul_view.update(game);game._update_interaction()
	check(game.ui._soul_panel.visible and button(game.ui._soul_panel,"自杀，进入灵魂状态")!=null,"actual HUD shows zombie suicide action")
	check(game.actors[1].visible and game.actors[1].nameplate.text.contains("尸变"),"zombie remains visible and labelled")
	check(game.nearest.is_empty() and game.ui._bars.san.value==0,"zombie has no interaction target and SAN meter is empty")
	var origin: Vector2=gp.pos
	var key := InputEventKey.new();key.physical_keycode=KEY_D;key.pressed=true
	Input.parse_input_event(key);Input.flush_buffered_events()
	game._physics_process(.1);game.session.model.tick(.1)
	var release: InputEventKey=key.duplicate();release.pressed=false
	Input.parse_input_event(release);Input.flush_buffered_events()
	check(Vector2(gp.pos).distance_to(origin)>.05,"actual zombie HUD permits physical movement input")
	var tab := InputEventKey.new();tab.physical_keycode=KEY_TAB;tab.pressed=true
	game._unhandled_input(tab)
	check(not game.ui.inventory_is_open(),"zombie input cannot open inventory")
	if DisplayServer.get_name()!="headless":
		await process_frame;await RenderingServer.frame_post_draw
		check(game.get_viewport().get_texture().get_image().save_png("res://artifacts/base_tests/zombie_visible.png")==OK,"capture visible zombie HUD")
	button(game.ui._soul_panel,"自杀，进入灵魂状态").pressed.emit();game._refresh_ui()
	check(gp.life=="soul","actual UI sends suicide intent through Session")
	game.queue_free();await process_frame
	print("ZOMBIE_TEST checks=",checks," failures=",failures);quit(1 if failures else 0)
