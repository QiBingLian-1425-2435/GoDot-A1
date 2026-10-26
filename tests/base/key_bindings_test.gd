extends SceneTree
const Keys = preload("res://features/player/key_bindings.gd")
const Texts = preload("res://features/localization/game_text.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)
func key(code: int, down: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = down
	Input.parse_input_event(event)
	await process_frame
func tap(code: int) -> void:
	await key(code)
	await key(code,false)
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/key_bindings"))
	check(root.get_texture().get_image().save_png("res://artifacts/key_bindings/"+name+".png") == OK,"capture "+name)
func run() -> void:
	if "--preference-child" in OS.get_cmdline_user_args():
		check(Keys.display("crouch") == "V","new process loads saved binding")
		quit(1 if failures else 0)
		return
	var existed := FileAccess.file_exists(Keys.PATH)
	var original := FileAccess.get_file_as_bytes(Keys.PATH) if existed else PackedByteArray()
	check(Keys.reset_defaults() == OK,"save defaults")
	check(Keys.display("inventory") == "Tab / I","default aliases")
	check(Keys.assign("crouch",KEY_W) == ERR_INVALID_PARAMETER,"reject conflicts")
	check(Keys.assign("crouch",KEY_ESCAPE) == ERR_INVALID_PARAMETER,"reserve Escape")
	check(Keys.assign("crouch",-MOUSE_BUTTON_WHEEL_UP) == ERR_INVALID_PARAMETER,"reserve wheel")
	check(Keys.valid_code(KEY_KP_0),"numpad keys supported")
	var main = load("res://app/main.tscn").instantiate()
	main.smoke = true; main.elapsed = -100
	root.add_child(main)
	main._start_solo()
	main.set_process(false); main.set_physics_process(false); main.session.set_physics_process(false)
	main._refresh_ui()
	var hud = main.ui
	hud._open_settings()
	var entry: Button
	for node in hud._dialog.get_children():
		if node is Button and node.text == Texts.resolve("⟦keys.title⟧"): entry = node
	check(entry != null,"settings entry")
	entry.pressed.emit()
	var panel = hud._key_bindings_panel
	check(panel.buttons.size() == 21 and panel.buttons.has("voice"),"all common actions listed")
	var before: Dictionary = main.session.model.state.duplicate(true)
	panel.buttons.crouch.pressed.emit()
	await tap(KEY_W)
	check(panel.waiting == "crouch" and Keys.display("crouch") == "C","conflict capture keeps binding")
	await tap(KEY_ESCAPE)
	check(panel.waiting.is_empty() and is_instance_valid(hud._dialog),"Escape cancels without closing panel")
	panel.buttons.crouch.pressed.emit()
	await tap(KEY_V)
	check(Keys.display("crouch") == "V" and panel.waiting.is_empty(),"capture saves new binding")
	check(main.session.model.state == before and not main.crouched,"capture leaves shared state unchanged")
	await capture("bindings_zh")
	var locale := Texts.locale()
	Texts.set_locale("en",false)
	check(panel.buttons.fire.text == "Mouse Left","live mouse label localization")
	await capture("bindings_en")
	Texts.set_locale(locale,false)
	var pid := OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",ProjectSettings.globalize_path("res://artifacts/key_bindings_child.log"),"--script","res://tests/base/key_bindings_test.gd","--","--preference-child"])
	var deadline := Time.get_ticks_msec()+10000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline: await process_frame
	check(pid > 0 and not OS.is_process_running(pid) and OS.get_process_exit_code(pid) == 0,"persistence across processes")
	if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
	hud._close_dialog()
	await tap(KEY_C)
	check(not main.crouched,"old key inactive")
	await tap(KEY_V)
	check(main.crouched,"new key controls gameplay")
	hud._open_settings()
	await tap(KEY_V)
	check(main.crouched,"settings block gameplay")
	hud._close_dialog()
	check(Keys.assign("inventory",KEY_K) == OK,"rebind inventory")
	await tap(KEY_TAB)
	check(not hud._inventory.visible,"old alias inactive")
	await tap(KEY_K)
	check(hud._inventory.visible,"new key opens inventory")
	await tap(KEY_ESCAPE)
	check(not hud._inventory.visible,"fixed Escape closes inventory")
	hud._open_key_bindings()
	panel = hud._key_bindings_panel
	panel.buttons.aim.pressed.emit()
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE; mouse.pressed = true
	Input.parse_input_event(mouse)
	await process_frame
	check(Keys.matches("aim",mouse),"mouse capture updates mapping")
	mouse.pressed = false; Input.parse_input_event(mouse)
	panel._reset()
	check(Keys.display("crouch") == "C" and Keys.display("inventory") == "Tab / I","restore defaults and aliases")
	check(panel.buttons.crouch.text == "C","restore refreshes panel")
	hud._close_dialog(); main.crouched = false
	check(Keys.assign("move_up",KEY_UP) == OK and Keys.assign("sprint",KEY_B) == OK,"rebind continuous actions")
	await key(KEY_W)
	check(not Keys.held("move_up"),"old movement key inactive")
	await key(KEY_W,false)
	await key(KEY_UP); await key(KEY_B)
	check(Keys.held("move_up") and Keys.held("sprint"),"held polling uses new bindings")
	main._physics_process(0.016)
	check(main.session.model._inputs[1].sprint and main.session.model._inputs[1].direction.length()>0,"host receives remapped movement intent")
	hud._open_settings(); main._physics_process(0.016)
	check(not main.session.model._inputs[1].sprint and main.session.model._inputs[1].direction == Vector2.ZERO,"modal blocks continuous movement")
	await key(KEY_UP,false); await key(KEY_B,false)
	hud._close_dialog()
	check(Keys.assign("fire",KEY_H) == OK,"rebind fire to keyboard")
	await key(KEY_H)
	check(main.trigger_held,"fire press arms trigger")
	await key(KEY_H,false)
	check(not main.trigger_held,"fire release clears trigger")
	var broken := ConfigFile.new()
	broken.set_value("bindings","crouch",[KEY_W]); broken.save(Keys.PATH)
	Keys._loaded = false
	check(Keys.display("crouch") == "C","conflicting saved config falls back to defaults")
	if existed:
		var file := FileAccess.open(Keys.PATH,FileAccess.WRITE)
		file.store_buffer(original); file.close()
	else: DirAccess.remove_absolute(Keys.PATH)
	Keys._loaded = false
	main.queue_free(); await process_frame
	print("KEY_BINDINGS_TEST checks=",checks," failures=",failures)
	quit(1 if failures else 0)
