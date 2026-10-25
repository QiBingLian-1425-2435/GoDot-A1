extends SceneTree
const Session = preload("res://app/network/session.gd")
const Texts = preload("res://features/localization/game_text.gd")
const HUD = preload("res://ui/base_hud.gd")
const PORT := 29974
var session: Node
var ui: CanvasLayer
var guest := false
var run_id := ""
var child := -1
var checks := 0
var failures := 0
var messages: Array[String] = []
var rendered_messages: Array[String] = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	guest = args.size() > 0
	run_id = args[0] if guest else str(Time.get_ticks_usec())
	Engine.max_fps = 60
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", "guest " if guest else "host ", description)
	if not ok: failures += 1

func wait_for(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec()+12000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	return predicate.call()

func report_path() -> String:
	return "user://localization_network_"+run_id+".json"

func finish() -> void:
	if guest:
		var file := FileAccess.open(report_path(), FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures}))
		file.close()
	if child > 0 and OS.is_process_running(child): OS.kill(child)
	session.offline()
	session.queue_free()
	ui.queue_free()
	await process_frame
	print("LOCALIZATION_NETWORK ", "guest" if guest else "host", " checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func run() -> void:
	Texts.set_locale("en" if guest else "zh_CN", false)
	session = Session.new()
	root.add_child(session)
	ui = HUD.new()
	root.add_child(ui)
	session.notice.connect(func(value: String) -> void:
		messages.append(value);ui.toast(value);rendered_messages.append(ui._toast_label.text))
	if guest:
		check(session.join("127.0.0.1",PORT) == OK, "real ENet connection starts")
		if not await wait_for(func():return session.local_id > 1 and session.model.state.players.has(session.local_id)):
			check(false,"client admitted");await finish();return
		check(await wait_for(func():return session.model.state.get("locale_ready",false)), "authoritative test state received")
		var before: int = session.model.state.players[session.local_id].credits
		session.send("buy", {"kind":"medical_box","count":1})
		check(await wait_for(func():return not messages.is_empty()), "host rejection crosses RPC")
		check(ui._toast_label.text == "Not enough credits; need 2550", "Chinese host's numeric rejection renders in English HUD")
		check(Texts.OPEN in messages[-1], "wire notice preserves template and parameters")
		Texts.set_locale("zh_CN", false)
		check(ui._toast_label.text == "资金不足，需要2550基地币", "existing received notification switches to Chinese")
		Texts.set_locale("en", false)
		check(ui._toast_label.text == "Not enough credits; need 2550", "received notification switches back without a second RPC")
		check(session.model.state.players[session.local_id].credits == before, "rejected purchase preserves credits")
		session.send("camp_upgrade", {"facility":"medical","expected_level":0})
		check(await wait_for(func():return session.model.state.camp.medical == 1), "host-confirmed camp upgrade received")
		check(await wait_for(func():return ui._toast_label.text == "Medical Station upgraded to level 1; team Max Health +5"), "broadcast notification translates nested facility and stat names")
		await finish()
		return
	check(session.host(PORT) == OK, "Chinese host starts")
	session.model.stations = [{"kind":"trader","pos":Vector2.ZERO},{"kind":"camp_management","pos":Vector2.ZERO}]
	session.upgrade_checkpoint = func(_trial):return OK
	child = OS.create_process(OS.get_executable_path(), ["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",ProjectSettings.globalize_path("res://artifacts/localization_network_client.log"),"--script","res://tests/base/localization_network_test.gd","--",run_id])
	check(child > 0, "English client process starts")
	if not await wait_for(func():return session.model.state.players.size() == 2):
		check(false,"remote player joined");await finish();return
	for id in session.model.state.players:
		if int(id) == 1:continue
		var p: Dictionary = session.model.state.players[id]
		p.pos = Vector2.ZERO
		p.credits = 800
		p.bag = session.model._empty_slots(24)
		session.model._insert(p.bag, session.model._item("scrap",4))
		session.model._insert(p.bag, session.model._item("tape",2))
	session.model.state.locale_ready = true
	session._broadcast_snapshot(true)
	check(await wait_for(func():return FileAccess.file_exists(report_path())), "remote report received")
	if FileAccess.file_exists(report_path()):
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report_path()))
		check(report.failures == 0 and report.checks >= 10, "all remote localization assertions passed")
	check(Texts.locale() == "zh_CN", "client language does not change host language")
	check("医疗站已强化至1级，全队生命上限 +5" in rendered_messages, "host sees the same broadcast in Chinese")
	await finish()
