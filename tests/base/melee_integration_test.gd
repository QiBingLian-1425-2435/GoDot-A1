extends SceneTree
const Main=preload("res://app/main.gd")
const Controller=preload("res://features/player/base_input.gd")
const Keys=preload("res://features/player/key_bindings.gd")
const Texts=preload("res://features/localization/game_text.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func run():
	var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game._start_solo();game.sound.muted=true
	game.set_process(false);game.set_physics_process(false);game.set_process_input(false);game.set_process_unhandled_input(false);game.session.set_physics_process(false)
	Keys.ensure_loaded();var bindings:Dictionary=Keys._values.duplicate(true);Keys._values=Keys.DEFAULTS.duplicate(true)
	var m=game.session.model;var p:Dictionary=m.state.players[1]
	m.state.infinite_credits=true
	for station in m.stations:
		if station.kind=="trader":p.pos=station.pos
	for kind in ["fire_axe","crowbar","baseball_bat","baton","machete","katana"]:
		game.ui.action_requested.emit("buy",{"kind":kind,"count":1})
		check(m._count(p.bag,kind)==1,kind+" bought through existing UI intent")
	var index:=-1
	for i in p.bag.size():
		if p.bag[i].get("kind","")=="fire_axe":index=i
	game.ui.action_requested.emit("equip",{"index":index});p=m.state.players[1]
	check(p.equipment.weapon.kind=="fire_axe","inventory equips melee")
	game._refresh_ui()
	check(game.ui._ammo_label.text==Texts.resolve("⟦combat.melee.label⟧") and not p.reloading,"HUD identifies melee without ammo count")
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
	Controller._unhandled_input(game,press)
	check(not game.trigger_held,"unarmed aim click does not latch later melee attacks")
	Controller._input(game,release)
	check(p.get("melee_chain",0)==0 and not game.trigger_held,"left click without aim cannot start melee")
	m.command(1,"move",{"ads":true});Controller._fire_pressed(game,"fire_axe",true)
	check(p.get("melee_chain",0)==1,"aim plus attack intent starts melee")
	for i in 50:m.tick(.02)
	check(p.melee_chain==1,"released trigger does not repeat")
	for i in 140:
		Controller._physics_process(game,.02)
		m.command(1,"move",{"ads":true})
		m.tick(.02)
	check(p.melee_chain==1 and not game.trigger_held,"holding the attack button does not repeat melee")
	Controller._fire_pressed(game,"fire_axe",true)
	check(p.melee_chain==2,"a fresh click starts the next single attack")
	game.ui.toggle_inventory(true)
	var count:int=p.melee_chain
	Controller._unhandled_input(game,press)
	for i in 60:Controller._physics_process(game,.02);m.tick(.02)
	check(p.melee_chain<=count+1 and not game.trigger_held,"inventory blocks continuing held attacks")
	for locale in ["zh_CN","en"]:
		Texts.set_locale(locale,false);game._refresh_ui()
		check(game.ui._ammo_label.text==Texts.resolve("⟦combat.melee.label⟧"),locale+" melee HUD translates live")
		if DisplayServer.get_name()!="headless":
			for i in 4:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/melee_inventory_%s.png"%locale)
	game.ui.close_inventory();Texts.set_locale("zh_CN",false);Keys._values=bindings
	game.queue_free();await process_frame;await process_frame
	print("MELEE_INTEGRATION failures=",failures);quit(0 if failures==0 else 1)
