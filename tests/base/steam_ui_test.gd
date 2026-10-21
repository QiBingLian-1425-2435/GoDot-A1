extends SceneTree

var checks := 0
var events: Array[Dictionary] = []
var main: Node
var ui: CanvasLayer

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value:
		push_error("FAIL: " + description)
		quit(1)
		return
	checks += 1
	print("PASS: " + description)

func capture(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://artifacts/steam-validation/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(file))

func _run() -> void:
	main = load("res://app/main.tscn").instantiate()
	main.smoke=true
	main.elapsed=-100
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	ui = main.ui
	ui.action_requested.disconnect(main._on_action)
	ui.action_requested.connect(func(action: String, payload: Dictionary) -> void: events.append({"action":action,"payload":payload}))
	ui._reveal_menu()
	await capture("steam-menu.png")
	ui.update_steam({"available":false,"initialized":false,"pending":false,"status":"not available"})
	ui._open_steam()
	check(ui._steam_connect_button.disabled and ui._steam_host_button.disabled and ui._steam_join_button.disabled,"Native unavailable disables connection and room actions")
	check(ui._steam_status.text.contains("组件不可用") and ui._steam_ip_button==null,"Missing native has readable reason with no IP fallback")
	await capture("steam-unavailable.png")
	ui.update_steam({"available":true,"initialized":false,"pending":false,"status":"点击连接 Steam"})
	check(not ui._steam_connect_button.disabled and ui._steam_host_button.disabled,"Uninitialized native allows retry but blocks lobby actions")
	ui._steam_connect_button.pressed.emit()
	check(events[-1].action == "steam_connect" and ui._steam_back_button.text == "取消连接","Connect intent enters cancellable pending UI")
	ui.update_steam({"initialized":true,"pending":false,"persona":"测试鸭鸭","status":"Steam 已连接"})
	check(not ui._steam_host_button.disabled and ui._steam_persona.text.contains("测试鸭鸭"),"Initialized Steam allows host and shows persona")
	var lobbies := [{"id":"109775241011234567","name":"鸭鸭的地下基地","members":2,"limit":4},{"id":"109775241011234568","name":"好友队伍 · 已满","members":4,"limit":4},{"id":"109775241011234569","name":"名称很长的好友房间用于确认列表截断不会覆盖加入按钮和人数显示区域","members":1,"limit":4}]
	ui._steam_lobby_input.text = "109775241011234567"
	ui._steam_refresh_button.pressed.emit()
	check(events[-1].action == "steam_refresh" and ui._steam_refresh_button.disabled,"Refresh dispatches intent and disables duplicate refresh")
	ui.update_steam({"scanning":false,"lobbies":lobbies})
	check(ui._steam_lobby_list.get_child_count() == 3,"Room list shows server-provided friend entries")
	check(not ui._steam_lobby_buttons[0].disabled and ui._steam_lobby_buttons[1].disabled,"Available room join enabled and full room disabled")
	var input_id: int = ui._steam_lobby_input.get_instance_id()
	var row_id: int = ui._steam_lobby_list.get_child(0).get_instance_id()
	for i in range(120):
		ui.update_steam({"status":"Steam 已连接","lobbies":lobbies})
	check(ui._steam_lobby_input.get_instance_id() == input_id and ui._steam_lobby_input.text == "109775241011234567","Repeated updates retain input node and typed room ID")
	check(ui._steam_lobby_list.get_child(0).get_instance_id() == row_id,"Unchanged lobby list does not rebuild rows")
	await capture("steam-friend-list.png")
	var prior_count := events.size()
	ui._join_steam_lobby("1e09775241011234567")
	check(events.size() == prior_count and ui._steam_status.text.contains("只能包含数字"),"Non-digit Steam ID rejected with visible inline feedback")
	ui._join_steam_lobby("123")
	check(events.size() == prior_count,"Truncated Steam ID rejected before dispatch")
	ui._steam_lobby_buttons[0].pressed.emit()
	check(events[-1].action == "steam_join" and events[-1].payload.lobby_id is String and events[-1].payload.lobby_id == "109775241011234567","List join preserves full 64-bit Steam ID as decimal String")
	check(ui._steam_host_button.disabled and ui._steam_join_button.disabled and not ui._steam_lobby_input.editable,"Pending join locks conflicting controls")
	prior_count = events.size()
	ui._steam_action("steam_host")
	check(events.size() == prior_count,"Pending connection ignores duplicate action")
	await capture("steam-pending.png")
	ui._dialog_close_pressed()
	check(events[-1].action == "steam_cancel" and not is_instance_valid(ui._dialog),"Closing pending modal dispatches cancellation")
	ui.update_steam({"pending":false,"lobby_id":"109775241011234567","transport":"steam","status":"房间已创建"})
	ui.show_game()
	ui.toggle_pause()
	check(not ui._steam_invite_button.disabled and not ui._steam_copy_button.disabled,"Steam lobby enables explicit invite and copy actions")
	check(ui._steam_room_label.text.contains("109775241011234567"),"Pause screen displays complete room ID")
	ui._steam_invite_button.pressed.emit()
	check(events[-1].action == "steam_invite","Invite only emitted after explicit button action")
	ui._steam_copy_button.pressed.emit()
	check(events[-1].action == "steam_copy_lobby","Copy room ID dispatches intent")
	await capture("steam-pause.png")
	ui.update_steam({"transport":"enet","lobby_id":""})
	check(ui._steam_invite_button.disabled and ui._steam_copy_button.disabled,"IP session disables Steam room controls")
	ui.show_menu()
	ui._open_network()
	check(ui._join_address.text == "127.0.0.1" and ui._port_input.text == "24567","IP direct form remains available")
	ui._connect_action("join")
	check(events[-1].action == "join" and events[-1].payload.address == "127.0.0.1" and events[-1].payload.port == 24567,"IP direct join payload unchanged")
	ui._dialog_close_pressed()
	check(events[-1].action == "menu","IP cancellation retains existing behavior")
	ui.show_game()
	ui.toggle_inventory(true)
	check(ui._bag_slots.size() == 24 and ui._stash_slots.size() == 48 and ui.inventory_is_open(),"Inventory slots and opening behavior retained")
	print("UI_STEAM_CHECKS_PASSED=",checks)
	main.queue_free()
	await process_frame
	quit()
