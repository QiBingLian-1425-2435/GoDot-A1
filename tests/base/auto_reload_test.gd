extends SceneTree
const Model = preload("res://features/base/base_model.gd")
const Main = preload("res://app/main.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1
func run():
	var m = Model.new(); m.add_player(1, "reload")
	var p: Dictionary = m.state.players[1]
	p.ammo = 0; p.magazines[p.equipment.weapon.uid] = 0
	check(m.command(1, "fire") and p.reloading, "empty trigger starts existing reload")
	check(p.shots == 0 and m.state.shots.is_empty() and p.ammo == 0, "reload request never creates a phantom shot")
	m.tick(.1)
	var remaining: float = p.reload_timer
	check(not m.command(1, "fire") and p.reload_timer == remaining, "held fire cannot restart reload timer")
	for i in range(16): m.tick(.1)
	check(not p.reloading and p.ammo == 30 and m._count(p.bag,"ammo") == 30, "auto reload waits and conserves reserve ammo")
	check(m.command(1,"fire") and p.ammo == 29 and p.shots == 1, "next held trigger fires after reload")
	p.fire_timer = 0; p.ammo = 0; p.bag = m._empty_slots(24)
	check(not m.command(1,"fire") and not p.reloading and p.ammo == 0, "no reserve means no automatic ammunition")
	p.bag[0] = m._item("ammo", 3)
	check(m.command(1,"fire"), "small reserve can start automatic reload")
	for i in range(17): m.tick(.1)
	check(p.ammo == 3 and m._count(p.bag,"ammo") == 0, "partial reserve loads exactly available rounds")
	p.ammo = 0; m.state.infinite_reserve = true
	check(m.command(1,"fire"), "infinite reserve also uses timed automatic reload")
	for i in range(17): m.tick(.1)
	check(p.ammo == 30 and p.bag[0].is_empty(), "infinite reserve creates no inventory ammo")
	p.equipment.weapon = {}; p.ammo = 0
	check(not m.command(1,"fire") and not p.reloading, "no weapon cannot reload")
	# Replay the existing held-fire intent cadence through the actual Session/Main HUD.
	var game = Main.new(); game.smoke = true; game.elapsed = -10000
	root.add_child(game); game.sound.muted = true
	game.set_process(false); game.set_physics_process(false); game.session.set_physics_process(false)
	game._start_solo(); game.session.set_physics_process(false)
	p = game.session.model.state.players[1]
	p.ammo = 1; p.magazines[p.equipment.weapon.uid] = 1
	p.bag = game.session.model._empty_slots(24); p.bag[0] = game.session.model._item("ammo", 5)
	check(not game.ui.is_blocking(), "gameplay is ready for repeated fire intents")
	for i in range(20):
		if i%3 == 0: game.session.send("fire")
		game.session.model.tick(.05)
		if p.reloading: break
	check(p.reloading and p.ammo == 0 and p.shots == 1, "repeated fire after last round starts reload")
	game._refresh_ui()
	check(game.ui._reload_label.text.contains("换弹") or game.ui._reload_label.text.contains("装填"), "HUD shows automatic reload")
	if DisplayServer.get_name() != "headless":
		await process_frame; await RenderingServer.frame_post_draw
		var folder := OS.get_environment("A1_TEST_ARTIFACTS")
		if folder.is_empty(): folder = ProjectSettings.globalize_path("res://artifacts")
		DirAccess.make_dir_recursive_absolute(folder)
		check(game.get_viewport().get_texture().get_image().save_png(folder + "/auto_reload.png") == OK, "capture automatic reload HUD")
	for i in range(45):
		game.session.model.tick(.05)
		if i%3 == 0: game.session.send("fire")
	check(p.shots > 1 and p.ammo < 5, "repeated fire intents resume firing after reload without R")
	game.queue_free(); await process_frame; await process_frame
	print("AUTO_RELOAD checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
