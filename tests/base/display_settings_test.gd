extends SceneTree
const Display=preload("res://features/settings/display_settings.gd")
const Texts=preload("res://features/localization/game_text.gd")
const Menu=preload("res://ui/menu/menu_screen.gd")
const PATH="res://artifacts/display_settings_test.cfg"
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1;print("PASS: " if value else "FAIL: ",label)
	if not value:failures+=1
func settle()->void:
	await create_timer(.25).timeout
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/display_"+name+".png")
func click(control:Control)->void:
	var at:=control.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=at;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.pressed=pressed
		root.push_input(event,true);await process_frame
	await settle()
func f11()->void:
	var key:=InputEventKey.new();key.keycode=KEY_F11;key.physical_keycode=KEY_F11;key.pressed=true
	root.push_input(key,true);await process_frame
	key.pressed=false;root.push_input(key,true);await settle()
func run()->void:
	if "--check-preference" in OS.get_cmdline_user_args():
		var prefs=Display.new();prefs.settings_path=PATH;root.add_child(prefs)
		check(prefs.fullscreen and prefs.resolution==Vector2i(1280,720),"fresh process restores both preferences")
		prefs.queue_free();await process_frame;quit(1 if failures else 0);return
	var original_mode:=root.mode;var original_size:=root.size;var original_position:=root.position
	var original_locale:=Texts.locale()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	check(Display.fit_resolution(Vector2i(99999,99999)).x<=Display.available_size().x,"oversized resolution stays on screen")
	var game=load("res://app/main.gd").new();game.smoke=true;game.elapsed=-10000;game.display_settings.settings_path=PATH
	root.add_child(game);game.set_process(false);game.set_physics_process(false)
	var ui=game.ui;ui._reveal_menu();ui._open_settings()
	Menu._open_audio_display_settings(ui);await settle()
	var select:OptionButton=ui._dialog.get_node("ResolutionSelect")
	var toggle:CheckButton=ui._dialog.get_node("FullscreenToggle")
	check(select.item_count>1,"start menu includes resolution choices")
	for i in select.item_count:
		var size:Vector2i=select.get_item_metadata(i)
		check(size.x<=Display.available_size().x and size.y<=Display.available_size().y,"resolution fits display usable area")
	for locale in ["zh_CN","en"]:
		Texts.set_locale(locale,false);await process_frame
		check(ui._dialog.get_node("DisplayHint").text==Texts.resolve("⟦settings.resolution_hint⟧"),"display hint switches locale")
		check(toggle.text==Texts.resolve("⟦menu_screen.013⟧"),"fullscreen label switches locale")
		await capture(locale)
	if Display.can_change_window():
		game._on_action("settings",{"fullscreen":false});await settle()
		var index:=-1
		for i in select.item_count:
			if select.get_item_metadata(i)==Vector2i(1280,720):index=i
		check(index>=0,"720p option exists on test display")
		if index>=0:select.select(index);select.item_selected.emit(index)
		await settle();check(root.size==Vector2i(1280,720),"resolution applies to real native window")
		await click(toggle)
		check(Display.is_fullscreen() and toggle.button_pressed,"actual checkbox click enters fullscreen")
		check(root.size==DisplayServer.screen_get_size(root.current_screen),"fullscreen covers native monitor")
		check(select.disabled,"window resolution clearly disabled while fullscreen")
		await capture("fullscreen")
		await click(toggle)
		check(not Display.is_fullscreen() and not toggle.button_pressed,"actual checkbox click exits fullscreen")
		check(root.size==Vector2i(1280,720) and not root.borderless,"restores selected window size and native frame")
		await f11();check(Display.is_fullscreen() and toggle.button_pressed,"F11 works on start menu and updates checkbox")
		await f11();check(not Display.is_fullscreen() and not toggle.button_pressed,"F11 toggles back without duplicate change")
		game._on_action("settings",{"fullscreen":true});await settle()
		game._start_solo();game.set_physics_process(false);game.session.set_physics_process(false)
		await f11();check(not Display.is_fullscreen(),"F11 still exits fullscreen during gameplay")
		await f11();check(Display.is_fullscreen(),"F11 still enters fullscreen during gameplay")
		var before:Dictionary=game.session.model.state.duplicate(true)
		check(game.display_settings.change({"resolution":Vector2i(-1,0)})==ERR_INVALID_PARAMETER,"invalid resolution refused")
		check(before==game.session.model.state,"local display settings never mutate room state")
		var pid:=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/display_settings_test.gd","--","--check-preference"])
		var deadline:=Time.get_ticks_msec()+10000
		while OS.is_process_running(pid) and Time.get_ticks_msec()<deadline:await process_frame
		check(not OS.is_process_running(pid) and OS.get_process_exit_code(pid)==0,"both settings survive process restart")
		if OS.is_process_running(pid):OS.kill(pid)
		game._on_action("settings",{"fullscreen":false});await settle()
	else:
		check(toggle.disabled and select.disabled,"unavailable native window controls are disabled")
		check(game.display_settings.change({"fullscreen":true})==ERR_UNAVAILABLE,"headless cannot pretend to change a native window")
	Texts.set_locale(original_locale,false)
	game.queue_free();await process_frame
	root.mode=original_mode
	if original_mode==Window.MODE_WINDOWED:root.size=original_size;root.position=original_position
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("DISPLAY_SETTINGS checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
