extends SceneTree
const Texts = preload("res://features/localization/game_text.gd")
const Items = preload("res://features/inventory/item_catalog.gd")
const Camp = preload("res://features/base/camp_upgrades.gd")
const MenuScreen = preload("res://ui/menu/menu_screen.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", description)
	if not ok: failures += 1

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var folder := "res://artifacts/localization"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	check(root.get_texture().get_image().save_png(folder+"/"+name+".png") == OK, "capture " + name)

func unresolved(node: Node) -> Array[String]:
	var result: Array[String] = []
	for property in node.get_property_list():
		if property.name in ["text", "tooltip_text", "placeholder_text", "title", "ok_button_text"]:
			var value: Variant = node.get(property.name)
			if value is String and Texts.OPEN in value: result.append(str(node.name)+"."+property.name)
	if node is OptionButton or node is ItemList or node is PopupMenu:
		for i in range(node.item_count):
			if Texts.OPEN in node.get_item_text(i): result.append(str(node.name)+" item "+str(i))
	for child in node.get_children(): result.append_array(unresolved(child))
	return result

func run() -> void:
	if "--check-preference" in OS.get_cmdline_user_args():
		check(Texts.locale() == "en", "fresh process loads saved language")
		check(Texts.resolve("⟦base_hud.040⟧") == "Settings", "saved language renders translated text")
		print("LOCALIZATION_PREFERENCE checks=",checks," failures=",failures)
		quit(1 if failures else 0)
		return
	var original := Texts.locale()
	Texts.set_locale("zh_CN", false)
	check(Texts.resolve("⟦base_hud.040⟧") == "设置", "default Chinese catalog")
	var message := Texts.format("⟦camp_upgrades.014⟧", [Camp.DEFS.medical.name, 2, Camp.DEFS.medical.stat, 10, ""])
	check(Texts.resolve(message) == "医疗站已强化至2级，全队生命上限 +10", "nested names and numeric arguments in Chinese")
	Texts.set_locale("en", false)
	check(Texts.resolve(message) == "Medical Station upgraded to level 2; team Max Health +10", "same serialized host message renders in receiver language")
	check(Items.definition("medkit").name == "⟦item_catalog.013⟧", "item definitions remain language-neutral")
	check(Texts.resolve(Items.definition("medkit").name) == "First Aid Kit", "item name translated at presentation")
	check(Texts.resolve(Texts.clip("⟦session.002⟧", 4)) == "Trav", "deferred names clip after translation")
	check(Texts.resolve(Texts.literal("⟦base_hud.040⟧")) == "⟦base_hud.040⟧", "external names do not become translation keys")
	check(Texts.set_locale("unknown", false) == ERR_INVALID_PARAMETER and Texts.locale() == "en", "unknown locale preserves selected language")
	var translated: String = Texts._catalogs.en["base_hud.040"]
	Texts._catalogs.en.erase("base_hud.040")
	check(Texts.resolve("⟦base_hud.040⟧") == "设置", "missing translation falls back to Chinese")
	Texts._catalogs.en["base_hud.040"] = translated
	var template: String = Texts._catalogs.en["base_hud.015"]
	Texts._catalogs.en["base_hud.015"] = "Broken %s"
	check(Texts.resolve(Texts.format("⟦base_hud.015⟧", 3)) == "房主 · 3 人在线", "bad translation format falls back without printf failure")
	Texts._catalogs.en["base_hud.015"] = template
	check(Texts.resolve(Texts.format("⟦base_hud.015⟧", [])) == "[invalid text arguments]", "invalid argument count is contained")
	check(Texts.resolve("⟦not.a.key⟧") == "[missing:not.a.key]", "unknown key is visible for authoring diagnostics")
	Texts.set_locale("zh_CN", false)
	var main = load("res://app/main.tscn").instantiate()
	main.smoke = true
	main.elapsed = -100
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	var ui = main.ui
	ui._reveal_menu()
	check(unresolved(main).is_empty(), "menu and base contain no unresolved text references")
	Texts.set_locale("en", false)
	check(unresolved(main).is_empty(), "existing menu and 3D labels refresh to English")
	await capture("menu_en")
	main._start_solo()
	main._refresh_ui()
	ui.toggle_inventory()
	ui._inspect(main.session.model.state.players[1].equipment.weapon)
	check(ui._details_name.text.contains("Ranger Rifle"), "inventory details render English item names")
	check(unresolved(main).is_empty(), "inventory and item tooltips resolve text")
	await capture("inventory_en")
	ui.toggle_inventory()
	ui.open_item_shop("buy")
	check(unresolved(main).is_empty(), "shop list, buttons and tooltips resolve text")
	Texts.set_locale("zh_CN", false)
	check(unresolved(main).is_empty(), "open shop refreshes language in place")
	ui._close_dialog()
	ui._open_steam()
	ui._steam_lobby_input.text = "109775241011234567"
	Texts.set_locale("en", false)
	check(ui._steam_lobby_input.text == "109775241011234567", "language change preserves typed room ID")
	ui._close_dialog()
	preload("res://ui/inventory/camp_panel.gd").open(ui)
	check(ui._dialog.get_node("CampFacilities").get_item_text(0).contains("Medical Station"), "camp list and nested detail templates render in English")
	check(unresolved(main).is_empty(), "camp detail text resolves all templates")
	await capture("camp_en")
	ui._close_dialog()
	ui._open_help()
	check(unresolved(main).is_empty(), "controls guide resolves all labels")
	check(Texts.resolve("⟦keys.action.roll⟧")=="Jump","Space action is labelled Jump in English")
	await capture("help_en")
	Texts.set_locale("zh_CN",false)
	check(Texts.resolve("⟦keys.action.roll⟧")=="跳跃","open key bindings updates jump label to Chinese")
	await capture("help_zh")
	Texts.set_locale("en",false)
	ui._close_dialog()
	main.global_map.set_state({1:{"pos":Vector2(390,-205),"name":"⟦session.002⟧"}},1,"surface")
	main.global_map.set_open(true)
	check(main.global_map._title.text == "Ground Zero Map", "map title renders in English")
	await capture("map_en")
	Texts.set_locale("zh_CN", false)
	check(main.global_map._title.text == "零号区全局地图", "open map refreshes to Chinese")
	main.global_map.set_open(false)
	Texts.set_locale("en", false)
	ui._open_settings()
	MenuScreen._open_player_settings(ui)
	var language: OptionButton = ui._dialog.get_node("LanguageSelect")
	check(language.item_count == 2 and language.get_item_metadata(language.selected) == "en", "settings lists installed locales and selects current language")
	check(unresolved(main).is_empty(), "settings text resolves fully")
	await capture("settings_en")
	var before: Dictionary = main.session.model.state.duplicate(true)
	Texts.set_locale("zh_CN", false)
	check(main.session.model.state == before, "language preference does not mutate host state")
	check(unresolved(main).is_empty(), "all live display bindings refresh back to Chinese")
	ui._close_dialog()
	await capture("bunker_zh")
	Texts.set_locale("en", true)
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/base/localization_test.gd", "--", "--check-preference"])
	check(pid > 0, "spawn preference persistence check")
	var deadline := Time.get_ticks_msec()+10000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline: await process_frame
	check(pid > 0 and not OS.is_process_running(pid) and OS.get_process_exit_code(pid) == 0, "language preference survives a new process")
	if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
	Texts.set_locale(original, true)
	main.queue_free()
	await process_frame
	print("LOCALIZATION_TEST checks=",checks," failures=",failures)
	quit(1 if failures else 0)
