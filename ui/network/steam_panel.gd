extends RefCounted
const Texts = preload("res://features/localization/game_text.gd")
## Migrated reference behavior; called only through the owning composition/model.

static func _open_steam(ctx) -> void:
	ctx._dialog_panel("⟦menu_screen.005⟧",Vector2(960,760))
	ctx._dialog_kind = "steam"
	var status_panel = ctx._panel(ctx._dialog,Rect2(34,86,892,92),Color("112b32"),Color("486e6d"),10)
	ctx._steam_persona = ctx._label(status_panel,"",Rect2(18,9,856,27),19,ctx.GOLD)
	ctx._steam_status = ctx._label(status_panel,"",Rect2(18,39,856,44),17,ctx.MUTED)
	ctx._steam_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctx._steam_connect_button = ctx._button(ctx._dialog,"⟦steam_panel.001⟧",Rect2(34,195,258,48),func() -> void: ctx._steam_action("steam_connect"),ctx.TEAL,20)
	ctx._steam_host_button = ctx._button(ctx._dialog,"⟦steam_panel.002⟧",Rect2(310,195,300,48),func() -> void: ctx._steam_action("steam_host"),ctx.GREEN,21)
	ctx._label(ctx._dialog,"⟦steam_panel.003⟧",Rect2(628,195,298,48),16,ctx.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctx._label(ctx._dialog,"⟦steam_panel.004⟧",Rect2(34,265,690,28),19,ctx.INK)
	ctx._steam_lobby_input = ctx._line_edit(ctx._dialog,"",Rect2(34,305,656,48))
	Texts.bind(ctx._steam_lobby_input, "⟦steam_panel.005⟧", "placeholder_text")
	ctx._steam_lobby_input.max_length = 20
	ctx._steam_lobby_input.text_submitted.connect(func(_text: String) -> void: ctx._join_steam_input())
	ctx._steam_join_button = ctx._button(ctx._dialog,"⟦steam_panel.006⟧",Rect2(710,305,216,48),ctx._join_steam_input,ctx.TEAL,21)
	ctx._label(ctx._dialog,"⟦steam_panel.007⟧",Rect2(34,380,630,34),21,ctx.INK)
	ctx._steam_refresh_button = ctx._button(ctx._dialog,"⟦steam_panel.008⟧",Rect2(748,374,178,42),func() -> void: ctx._steam_action("steam_refresh"),ctx.TEAL,18)
	var list_panel = ctx._panel(ctx._dialog,Rect2(34,431,892,184),Color("10272e"),Color("496966"),10)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(10,10)
	scroll.size = Vector2(872,164)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(scroll)
	ctx._steam_lobby_list = VBoxContainer.new()
	ctx._steam_lobby_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctx._steam_lobby_list.add_theme_constant_override("separation",8)
	scroll.add_child(ctx._steam_lobby_list)
	ctx._steam_empty_label = ctx._label(list_panel,"",Rect2(18,48,856,86),17,ctx.MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	ctx._steam_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctx._steam_lobbies_shown = []
	ctx._steam_lobby_buttons.clear()
	ctx._label(ctx._dialog,"⟦steam_panel.009⟧",Rect2(34,632,892,28),16,ctx.GOLD,HORIZONTAL_ALIGNMENT_CENTER)
	ctx._steam_back_button = ctx._button(ctx._dialog,"⟦steam_panel.010⟧",Rect2(330,683,300,48),ctx._dialog_close_pressed,Color("506d70"),21)
	ctx._refresh_steam_controls()

static func _steam_ready(ctx) -> bool:
	return bool(ctx._steam_info.get("available",false)) and bool(ctx._steam_info.get("initialized",false))

static func _refresh_steam_controls(ctx) -> void:
	if ctx._dialog_kind != "steam" or not is_instance_valid(ctx._steam_status):
		return
	var available = bool(ctx._steam_info.get("available",false))
	var initialized = ctx._steam_ready()
	var pending = bool(ctx._steam_info.get("pending",false))
	var scanning = bool(ctx._steam_info.get("scanning",false))
	var can_use = initialized and not pending
	var persona = str(ctx._steam_info.get("persona",""))
	Texts.bind(ctx._steam_persona, ("⟦steam_panel.011⟧" + ("  ·  " + persona if not persona.is_empty() else "")) if initialized else "⟦steam_panel.012⟧", "text")
	var status = str(ctx._steam_info.get("status",""))
	if not available:
		status = "⟦steam_panel.013⟧"
	elif not initialized and not pending:
		status = "⟦steam_panel.014⟧" + ("\n" + status if not status.is_empty() else "")
	elif status.is_empty():
		status = "⟦base_hud.017⟧" if pending else "⟦steam_panel.015⟧"
	Texts.bind(ctx._steam_status, status, "text")
	ctx._steam_persona.modulate = Color.WHITE if initialized else Color("d4b99c")
	ctx._steam_connect_button.disabled = not available or pending
	ctx._steam_host_button.disabled = not can_use
	ctx._steam_join_button.disabled = not can_use
	ctx._steam_lobby_input.editable = not pending
	ctx._steam_refresh_button.disabled = not can_use or scanning
	Texts.bind(ctx._steam_refresh_button, "⟦steam_panel.016⟧" if scanning else "⟦steam_panel.008⟧", "text")
	Texts.bind(ctx._steam_back_button, "⟦base_hud.060⟧" if pending else "⟦steam_panel.010⟧", "text")
	var lobbies: Array = ctx._steam_info.get("lobbies",[])
	if lobbies != ctx._steam_lobbies_shown:
		ctx._rebuild_steam_lobbies(lobbies)
	for button in ctx._steam_lobby_buttons:
		button.disabled = not can_use or bool(button.get_meta("full",false))
	ctx._steam_empty_label.visible = lobbies.is_empty()
	Texts.bind(ctx._steam_empty_label, "⟦steam_panel.017⟧" if scanning else ("⟦steam_panel.018⟧" if initialized else "⟦steam_panel.019⟧"), "text")

static func _rebuild_steam_lobbies(ctx, lobbies: Array) -> void:
	ctx._steam_lobbies_shown = lobbies.duplicate(true)
	for child in ctx._steam_lobby_list.get_children():
		ctx._steam_lobby_list.remove_child(child)
		child.queue_free()
	ctx._steam_lobby_buttons.clear()
	for entry in lobbies:
		if not entry is Dictionary:
			continue
		var lobby_id = str(entry.get("id",""))
		var room_name = str(entry.get("name","⟦steam_panel.020⟧"))
		var members = int(entry.get("members",0))
		var limit = maxi(int(entry.get("limit",4)),1)
		var row = Control.new()
		row.custom_minimum_size = Vector2(840,64)
		ctx._steam_lobby_list.add_child(row)
		var name_label = ctx._label(row,room_name,Rect2(12,0,590,29),19,ctx.INK)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		Texts.bind(name_label, room_name, "tooltip_text")
		ctx._label(row,Texts.format("⟦steam_panel.021⟧", [lobby_id,members,limit]),Rect2(12,31,636,25),14,ctx.MUTED)
		var locked: bool=not entry.get("join_allowed",true)
		var join = ctx._button(row,"⟦steam_panel.022⟧" if locked else ("⟦steam_panel.023⟧" if members >= limit else "⟦steam_panel.024⟧"),Rect2(694,8,144,46),ctx._join_steam_lobby.bind(lobby_id),ctx.TEAL,19)
		join.set_meta("full",members >= limit or locked)
		ctx._steam_lobby_buttons.append(join)

static func _join_steam_input(ctx) -> void:
	if is_instance_valid(ctx._steam_lobby_input):
		ctx._join_steam_lobby(ctx._steam_lobby_input.text.strip_edges())

static func _join_steam_lobby(ctx, lobby_id: String) -> void:
	if not ctx._steam_ready() or bool(ctx._steam_info.get("pending",false)):
		return
	# Do not cast a SteamID to float, even when pasted from the clipboard.
	if lobby_id.length() < 17 or lobby_id.length() > 20:
		ctx._steam_input_error("⟦steam_panel.025⟧")
		return
	for character in lobby_id:
		if character < "0" or character > "9":
			ctx._steam_input_error("⟦steam_panel.026⟧")
			return
	ctx._steam_action("steam_join",{"lobby_id":lobby_id})

static func _steam_input_error(ctx, message: String) -> void:
	if is_instance_valid(ctx._steam_status):
		Texts.bind(ctx._steam_status, message, "text")
	else:
		ctx.toast(message)

static func _steam_action(ctx, action: String, payload: Dictionary = {}) -> void:
	if bool(ctx._steam_info.get("pending",false)):
		return
	if action == "steam_connect":
		if not bool(ctx._steam_info.get("available",false)):
			return
	elif not ctx._steam_ready():
		return
	if action == "steam_refresh":
		if bool(ctx._steam_info.get("scanning",false)):
			return
		ctx._steam_info["scanning"] = true
	else:
		ctx._steam_info["pending"] = true
		ctx._steam_info["status"] = "⟦steam_panel.027⟧" if action == "steam_connect" else ("⟦steam_panel.028⟧" if action == "steam_host" else "⟦steam_panel.029⟧")
	ctx._refresh_steam_controls()
	ctx.action_requested.emit(action,payload)

static func _refresh_steam_room(ctx) -> void:
	if not is_instance_valid(ctx._steam_room_label):
		return
	var lobby_id = str(ctx._steam_info.get("lobby_id",""))
	var in_room = str(ctx._steam_info.get("transport","offline")) == "steam" and not lobby_id.is_empty() and lobby_id != "0"
	Texts.bind(ctx._steam_room_label, (("⟦steam_panel.030⟧" if ctx._steam_info.get("join_allowed",true) else "⟦steam_panel.031⟧") + lobby_id) if in_room else "⟦base_hud.041⟧", "text")
	ctx._steam_invite_button.disabled = not in_room or not ctx._steam_info.get("join_allowed",true)
	ctx._steam_copy_button.disabled = not in_room
	Texts.bind(ctx._steam_invite_button, "⟦steam_panel.032⟧" if in_room else "⟦steam_panel.033⟧", "tooltip_text")
	Texts.bind(ctx._steam_copy_button, "⟦steam_panel.034⟧" if in_room else "⟦steam_panel.035⟧", "tooltip_text")
