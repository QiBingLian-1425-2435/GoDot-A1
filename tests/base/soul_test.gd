extends SceneTree
const Model = preload("res://features/base/base_model.gd")
const Voice = preload("res://features/voice/voice_rules.gd")
const Main = preload("res://app/main.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1; print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures += 1
func advance(m, seconds: float):
	for i in range(ceili(seconds/.1)): m.tick(.1)
func button(parent: Node, text: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text==text: return child
		var found := button(child,text)
		if found!=null: return found
	return null
func capture(game, name: String):
	if DisplayServer.get_name()=="headless": return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/base_tests"))
	await process_frame; await RenderingServer.frame_post_draw
	check(game.get_viewport().get_texture().get_image().save_png("res://artifacts/base_tests/soul_"+name+".png")==OK,"save "+name+" screenshot")
func run():
	var m = Model.new();m.add_player(1,"ghost");m.add_player(2,"rescuer");m.add_player(3,"other")
	m.state.world="surface" # Exploration rescue retains 30 HP; camp now restores living members.
	var p: Dictionary = m.state.players[1];var r: Dictionary = m.state.players[2]
	var stored_gun: Dictionary = m._item("pistol",1)
	p.stash[47]=stored_gun;p.magazines[stored_gun.uid]=7
	p.hp=0;m.tick(.1)
	var uid: String = p.corpse_uid
	var body: Dictionary = m.state.corpses[uid]
	var items: Array = m.state.containers[uid].items
	var rifle: Dictionary = {}
	for item in items:
		if item.kind=="rifle": rifle=item
	check(p.life=="soul" and m._count(p.bag,"ammo")==0 and p.equipment.weapon.is_empty(),"zero HP immediately becomes soul and moves carried inventory")
	check(not rifle.is_empty() and int(rifle.magazine)==20,"corpse preserves equipped gun UID and loaded ammunition")
	check(int(p.magazines.get(stored_gun.uid,0))==7 and p.stash[47].uid==stored_gun.uid,"death preserves stash weapon and its loaded ammunition")
	advance(m,1);check(m.state.corpses.size()==1,"death is idempotent")
	var old: Vector2 = p.pos
	for action in ["fire","reload","rest","unstuck","buy","use","transfer","search","travel"]:
		check(not m.command(1,action,{"direction":Vector2.RIGHT}),"soul rejects "+action)
	check(m.command(1,"move",{"direction":Vector2.RIGHT}),"free soul accepts movement intent")
	m.tick(.1);check(p.pos!=old and body.pos==old,"soul roams while corpse remains at death position")
	m.command(1,"move",{"direction":Vector2.ZERO});p.pos=old
	check(not m.command(2,"possess",{"target":3}) and not m.command(1,"possess",{"target":1}) and not m.command(1,"possess",{"target":99}),"only souls can possess living teammates")
	r.pos=Vector2(100,100)
	check(Voice.gain(m.state.players,1,2)==0,"waiting soul cannot use living voice")
	check(not m.command(1,"possess",{"target":2}),"distant possession rejected")
	r.pos=p.pos+Vector2(.5,0)
	check(m.command(1,"possess",{"target":2}) and Voice.gain(m.state.players,1,2)==1,"nearby possession connects private voice")
	check(Voice.gain(m.state.players,2,1)==1,"possessed soul hears host")
	check(m.command(2,"release_soul") and p.possessing==0,"living host can release attached soul")
	p.pos=m.state.players[3].pos
	m.command(1,"possess",{"target":3});m.remove_player(3);m.tick(.1)
	check(p.possessing==0,"disconnect clears possession")
	r.pos=Vector2(100,100)
	check(not m.command(2,"rescue",{"target":1}),"distant rescue rejected")
	r.pos=body.pos+Vector2(.5,0);r.height=3
	check(not m.command(2,"rescue",{"target":1}),"other floor rescue rejected")
	r.height=body.height;m.rescue_reachable=func(_a,_b):return false
	check(not m.command(2,"search",{"uid":uid}) and not m.command(2,"rescue",{"target":1}),"wall blocks corpse search and rescue")
	m.rescue_reachable=func(_a,_b):return true
	check(m.command(2,"search",{"uid":uid}),"teammate can search corpse")
	check(not m.command(2,"loot_take",{"uid":uid,"index":0,"item_uid":items[0].uid}),"undiscovered corpse item cannot be taken")
	advance(m,50)
	var rifle_uid: String = rifle.uid
	var rifle_index := items.find(rifle)
	var payload := {"uid":uid,"index":rifle_index,"item_uid":rifle_uid}
	check(m.command(2,"loot_take",payload) and int(r.magazines[rifle_uid])==20,"search takes equipment once, preserving magazine")
	check(not m.command(2,"loot_take",payload),"replayed take cannot duplicate equipment")
	check(m.command(2,"rescue",{"target":1}),"rescue starts from reachable corpse")
	advance(m,1);check(p.life=="soul","rescue needs full channel")
	m.command(2,"move",{"direction":Vector2.RIGHT});advance(m,.2)
	check(r.rescue.is_empty() and p.life=="soul","moving cancels rescue")
	m.command(2,"move",{"direction":Vector2.ZERO});r.pos=body.pos+Vector2(.5,0)
	m.command(2,"rescue",{"target":1});advance(m,3.1)
	check(p.life=="alive" and p.hp==30 and p.pos==body.pos,"completed rescue revives at original body")
	check(p.equipment.weapon.is_empty() and items[rifle_index].is_empty(),"rescue never duplicates previously looted gear")
	p.bag[0]=m._item("poison_capsule",1);p.hp=100
	check(m.command(1,"use",{"index":0}) and p.hp==0 and p.life=="soul","consuming lethal item dies even with full stats")
	check(m.state.corpses.size()==2,"second death creates independent corpse")
	m.command(1,"possess",{"target":2});r.hp=0;m.tick(.1)
	check(p.possessing==0 and Voice.gain(m.state.players,1,2)==0,"possessed teammate death clears voice and attachment")
	check(m.command(1,"return_camp") and p.hp==30 and r.hp==30 and p.life=="alive","all-dead party can recover in camp")
	# A new visit discards bodies and never restores carried gear or attachments.
	m.state.world="surface";p.hp=0;m.tick(.1)
	var field_uid: String = p.corpse_uid
	m.command(1,"possess",{"target":2})
	m.WorldTravel.enter_world(m,"cave",Vector3.ZERO)
	check(p.possessing==0 and p.life=="soul" and not m.world_cache.surface.has("corpses"),"travel detaches soul and discards corpse cache")
	m.WorldTravel.enter_world(m,"surface",Vector3.ZERO)
	check(not m.state.corpses.has(field_uid) and p.corpse_uid=="","returning to map cannot restore old corpse")
	m.WorldTravel.enter_world(m,"bunker",Vector3.ZERO)
	check(p.life=="alive" and p.hp==30,"party return to camp recovers remaining souls")

	var game = Main.new();game.smoke=true;game.elapsed=-10000
	root.add_child(game);game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game._start_solo()
	game.session.model.add_player(2,"救援队友")
	var gp: Dictionary = game.session.model.state.players[1]
	gp.hp=0;game.session.model.tick(.1);game._refresh_ui();game._update_actors(.1);game._update_camera(1);game.vision.update(game,.1);game.soul_view.update(game)
	check(game.ui._soul_panel.visible and button(game.ui._soul_panel,"附身 救援队友")!=null,"actual soul choice UI lists living teammate")
	await capture(game,"waiting")
	button(game.ui._soul_panel,"附身 救援队友").pressed.emit();game._refresh_ui()
	check(gp.possessing==2,"actual UI emits possession intent")
	game.session.model.state.players[2].pos=Vector2(8,4);game._update_actors(1);game._update_camera(1)
	check(absf(game.camera_focus.x-8*.76)<.1,"camera follows possessed teammate")
	await capture(game,"possessed")
	button(game.ui._soul_panel,"等待救援 / 解除附身").pressed.emit();check(gp.possessing==0,"wait button detaches")
	game.session.model.state.players[2].hp=0;game.session.model.tick(.1);game._refresh_ui()
	check(button(game.ui._soul_panel,"全队返回营地")!=null,"all-dead UI offers recovery")
	await capture(game,"all_dead")
	button(game.ui._soul_panel,"全队返回营地").pressed.emit();game._refresh_ui()
	check(gp.life=="alive" and not game.ui._soul_panel.visible,"camp recovery closes soul UI")
	# Fill a corpse beyond the old six-item container limit and exercise the UI.
	for i in range(24):gp.bag[i]=game.session.model._item("helmet",1)
	gp.hp=0;game.session.model.tick(.1)
	game.session.local_id=2;game.session.model.state.players[2].pos=gp.pos+Vector2(.5,0)
	game.session.send("search",{"uid":gp.corpse_uid})
	advance(game.session.model,40);game._refresh_ui()
	check(game.ui._loot_slots.size()==6 and button(game.ui._dialog,"下一页")!=null,"large corpse opens paged container UI")
	button(game.ui._dialog,"下一页").pressed.emit()
	check(game.ui._loot_page==1,"corpse equipment beyond six slots is accessible")
	await capture(game,"loot_page")
	game.ui._loot_selected=6
	game.ui.ContainerPanel.take(game.ui,false);game._refresh_ui()
	check(game.session.model.state.containers[gp.corpse_uid].items[6].is_empty(),"paged corpse selection takes correct actual item")
	game.ui.close_inventory();game._update_interaction()
	check(game.nearest.get("kind","")=="corpse","actual world interaction identifies corpse")
	var event := InputEventKey.new();event.physical_keycode=KEY_F;event.keycode=KEY_F;event.pressed=true
	game._unhandled_input(event)
	check(not game.session.model.state.players[2].rescue.is_empty(),"F starts rescue through actual input adapter")
	advance(game.session.model,3.1);game._refresh_ui()
	check(gp.life=="alive" and gp.hp==float(gp.get("max_hp",100)),"actual scene rescue is followed by mainline camp recovery")
	game.queue_free();await process_frame;await process_frame
	print("SOUL checks=",checks," failures=",failures);quit(1 if failures else 0)
