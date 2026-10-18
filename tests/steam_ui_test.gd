extends SceneTree
## Visible real-account host flow. Remote join/invite acceptance needs a second machine/account.
var game
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + text)
	else:
		print("PASS: " + text)

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	game = load("res://app/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.4).timeout
	check(game.hud.transport_choice.selected == 0, "Steam is the visible default transport")
	check(not game.hud.invite_button.get_global_rect().intersects(game.hud.copy_room_button.get_global_rect()), "invite and copy controls do not overlap")
	await click(game.hud.host_button)
	var deadline := Time.get_ticks_msec() + 30000
	while game.session.mode != "host" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(game.session.mode == "host" and game.session.transport == "steam", "mouse creates a real Steam host from the visible HUD")
	if game.session.mode == "host":
		await process_frame
		check(game.hud.host_button.disabled and not game.hud.copy_room_button.disabled, "connected HUD locks duplicate hosting and enables room sharing")
		check(game.hud.network_info.text.contains(str(game.session.steam.lobby_id)), "HUD displays the actual Steam lobby ID")
		check(game.hud.address.text == str(game.session.steam.lobby_id) and not game.hud.address.editable, "connected room code is visible in a read-only field")
		check(game.hud.copy_room_button.is_visible_in_tree() and not game.hud.join_button.visible, "copy replaces join immediately beside the room code")
		await click(game.hud.copy_room_button)
		check(DisplayServer.clipboard_get() == str(game.session.steam.lobby_id), "mouse click copies the exact Steam lobby ID to the system clipboard")
		check(game.hud.toast_label.text == "Steam 房间号已复制", "copy confirms success visibly")
		await RenderingServer.frame_post_draw
		var screenshot := ProjectSettings.globalize_path("user://steam_host.png")
		check(root.get_texture().get_image().save_png(screenshot) == OK, "visible Steam host screenshot: " + screenshot)
		check(game.hud.lobby_start.disabled, "Steam host cannot start a group raid before a second player joins")
		game.session.offline()
		await process_frame
		check(game.session.steam.lobby_id == 0 and not game.hud.host_button.disabled, "leaving restores a usable lobby")
		check(game.hud.address.text.is_empty() and game.hud.address.editable and game.hud.join_button.visible and not game.hud.copy_room_button.visible, "leaving clears the old room code and restores join input")
	game.queue_free()
	await process_frame
	print("STEAM_UI_TEST ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
