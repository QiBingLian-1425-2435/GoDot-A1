extends SceneTree
const Model = preload("res://features/base/base_model.gd")
const Main = preload("res://app/main.gd")
const Texts = preload("res://features/localization/game_text.gd")
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures += 1
func run():
	var m=Model.new();m.add_player(1,"host");m.add_player(2,"guest")
	m.stations=[{"kind":"trader","pos":Vector2.ZERO},{"kind":"camp_management","pos":Vector2.ZERO}]
	for p in m.state.players.values():p.pos=Vector2.ZERO;p.credits=0;p.bag=m._empty_slots(24)
	check(not m.state.infinite_credits,"disabled by default")
	check(not m.command(2,"set_infinite_credits",{"enabled":true}),"guest cannot enable")
	check(not m.command(1,"set_infinite_credits",{"enabled":1}),"invalid payload refused")
	check(not m.command(1,"buy",{"kind":"scrap","count":1}),"normal purchases require money")
	check(m.command(1,"set_infinite_credits",{"enabled":true}),"host enables")
	check(not m.command(2,"set_infinite_credits",{"enabled":false}) and m.state.infinite_credits,"guest cannot disable")
	for id in [1,2]:
		check(m.command(id,"buy",{"kind":"scrap","count":4}) and m.state.players[id].credits==0,"zero balance team purchase is free")
	var p:Dictionary=m.state.players[1]
	check(m.command(1,"buy_ammo") and p.credits==0,"legacy ammunition purchase is free")
	check(not m.command(1,"camp_upgrade",{"facility":"medical","expected_level":0}),"materials still required")
	m._insert(p.bag,m._item("tape",2))
	check(m.command(1,"camp_upgrade",{"facility":"medical","expected_level":0}) and p.credits==0 and m._count(p.bag,"scrap")==0 and m._count(p.bag,"tape")==0,"upgrade waives credits and consumes materials")
	m.command(1,"set_infinite_credits",{"enabled":false})
	check(not m.command(1,"buy",{"kind":"scrap","count":1}) and p.credits==0,"disable restores normal cost without changing balance")
	var game=Main.new();game.smoke=true;game.elapsed=-10000
	root.add_child(game);game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false)
	game._start_solo();game.ui._open_settings()
	for locale in ["zh_CN","en"]:
		Texts.set_locale(locale,false)
		var toggle:CheckButton=game.ui._dialog.get_node("InfiniteCredits")
		check(toggle.text==("无限金币" if locale=="zh_CN" else "Unlimited Credits"),"localized setting "+locale)
		toggle.button_pressed=true
		check(game.session.model.state.get("infinite_credits",false),"settings intent reaches authority")
		if DisplayServer.get_name()!="headless":
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			game.get_viewport().get_texture().get_image().save_png("res://artifacts/infinite_credits_"+locale+".png")
		game.ui.update_state(game.session.model.state,1,"client","")
		check(toggle.disabled,"guest setting is read only")
		game.ui.update_state(game.session.model.state,1,"offline","")
		toggle.button_pressed=false
	game.queue_free();await process_frame;await process_frame
	print("INFINITE_CREDITS failures=",failures);quit(1 if failures else 0)
