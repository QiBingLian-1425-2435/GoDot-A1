extends SceneTree
const Session = preload("res://app/network/session.gd")
const HUD = preload("res://ui/base_hud.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var session = Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	var model = session.model
	model.add_player(2,"client")
	var p: Dictionary = model.state.players[2]
	model._consume(p.bag,"ammo",60)
	check(not model.command(2,"reload"),"empty reserve rejects reload by default")
	check(not model.command(2,"set_infinite_reserve",{"enabled":true}),"client cannot enable")
	session.send("set_infinite_reserve",{"enabled":true})
	check(model.state.infinite_reserve,"host setting passes Session payload filtering")
	check(model.command(2,"reload"),"empty reserve can reload when enabled")
	check(p.ammo == 20 and p.reloading,"reload remains timed")
	for i in range(20): model.tick(0.1)
	check(p.ammo == 30 and model._count(p.bag,"ammo") == 0,"infinite reload fills magazine without inventory")
	check(not model.command(2,"reload"),"full magazine rejects reload")
	check(model.command(2,"fire") and p.ammo == 29,"fire still consumes magazine")
	check(not model.command(2,"set_infinite_reserve",{"enabled":false}) and model.state.infinite_reserve,"client cannot disable")
	session.send("set_infinite_reserve",{"enabled":false})
	check(not model.command(2,"reload"),"disabled mode restores empty reserve rejection")
	model._insert(p.bag,model._item("ammo",5))
	check(model.command(2,"reload"),"finite reload starts")
	for i in range(20): model.tick(0.1)
	check(p.ammo == 30 and model._count(p.bag,"ammo") == 4,"finite reload consumes actual inventory")
	var hud = HUD.new()
	root.add_child(hud)
	hud.update_state(model.state,1,"offline","")
	hud.action_requested.connect(session.send)
	hud._open_settings()
	var toggle = hud._dialog.get_node("InfiniteReserve")
	toggle.button_pressed = true
	check(model.state.infinite_reserve,"settings toggle reaches host model")
	hud.show_game()
	hud.update_state(model.state,1,"offline","")
	check(hud._reload_label.text.contains("∞"),"HUD displays infinite reserve")
	hud._close_dialog()
	hud.update_state(model.state,2,"client","")
	hud._open_settings()
	check(hud._dialog.get_node("InfiniteReserve").disabled,"client settings toggle is disabled")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await process_frame
		DirAccess.make_dir_recursive_absolute("res://artifacts/base_tests")
		root.get_texture().get_image().save_png("res://artifacts/base_tests/infinite_reserve.png")
	print("INFINITE_RESERVE failures=",failures)
	quit(0 if failures == 0 else 1)
