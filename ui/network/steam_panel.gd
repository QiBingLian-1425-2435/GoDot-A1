extends RefCounted
## Migrated reference behavior; called only through the owning composition/model.

static func _open_steam(ctx) -> void:
	ctx._dialog_panel("Steam 联机",Vector2(960,760))
	ctx._dialog_kind = "steam"
	var status_panel = ctx._panel(ctx._dialog,Rect2(34,86,892,92),Color("112b32"),Color("486e6d"),10)
	ctx._steam_persona = ctx._label(status_panel,"",Rect2(18,9,856,27),19,ctx.GOLD)
	ctx._steam_status = ctx._label(status_panel,"",Rect2(18,39,856,44),17,ctx.MUTED)
	ctx._steam_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctx._steam_connect_button = ctx._button(ctx._dialog,"连接 / 重试 Steam",Rect2(34,195,258,48),func() -> void: ctx._steam_action("steam_connect"),ctx.TEAL,20)
	ctx._steam_host_button = ctx._button(ctx._dialog,"创建好友房间",Rect2(310,195,300,48),func() -> void: ctx._steam_action("steam_host"),ctx.GREEN,21)
	ctx._steam_ip_button = ctx._button(ctx._dialog,"IP 直连",Rect2(628,195,298,48),ctx._open_network,Color("506d70"),20)
	ctx._label(ctx._dialog,"通过房间号加入",Rect2(34,265,690,28),19,ctx.INK)
	ctx._steam_lobby_input = ctx._line_edit(ctx._dialog,"",Rect2(34,305,656,48))
	ctx._steam_lobby_input.placeholder_text = "粘贴好友发来的 Steam 房间号"
	ctx._steam_lobby_input.max_length = 20
	ctx._steam_lobby_input.text_submitted.connect(func(_text: String) -> void: ctx._join_steam_input())
	ctx._steam_join_button = ctx._button(ctx._dialog,"加入房间",Rect2(710,305,216,48),ctx._join_steam_input,ctx.TEAL,21)
	ctx._label(ctx._dialog,"好友房间",Rect2(34,380,630,34),21,ctx.INK)
	ctx._steam_refresh_button = ctx._button(ctx._dialog,"刷新列表",Rect2(748,374,178,42),func() -> void: ctx._steam_action("steam_refresh"),ctx.TEAL,18)
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
	ctx._label(ctx._dialog,"480 开发测试（Steam 显示 Spacewar） · 每间基地最多 5 人",Rect2(34,632,892,28),16,ctx.GOLD,HORIZONTAL_ALIGNMENT_CENTER)
	ctx._steam_back_button = ctx._button(ctx._dialog,"返回",Rect2(330,683,300,48),ctx._dialog_close_pressed,Color("506d70"),21)
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
	ctx._steam_persona.text = ("Steam 已连接" + ("  ·  " + persona if not persona.is_empty() else "")) if initialized else "Steam 尚未连接"
	var status = str(ctx._steam_info.get("status",""))
	if not available:
		status = "Steam 组件不可用。请使用完整发布包启动；当前仍可选择 IP 直连。"
	elif not initialized and not pending:
		status = "请启动并登录 Steam，再点击连接 / 重试。" + ("\n" + status if not status.is_empty() else "")
	elif status.is_empty():
		status = "正在连接基地…" if pending else "创建好友房间，或使用房间号加入好友的基地。"
	ctx._steam_status.text = status
	ctx._steam_persona.modulate = Color.WHITE if initialized else Color("d4b99c")
	ctx._steam_connect_button.disabled = not available or pending
	ctx._steam_host_button.disabled = not can_use
	ctx._steam_join_button.disabled = not can_use
	ctx._steam_lobby_input.editable = not pending
	ctx._steam_refresh_button.disabled = not can_use or scanning
	ctx._steam_refresh_button.text = "刷新中…" if scanning else "刷新列表"
	ctx._steam_ip_button.disabled = pending
	ctx._steam_back_button.text = "取消连接" if pending else "返回"
	var lobbies: Array = ctx._steam_info.get("lobbies",[])
	if lobbies != ctx._steam_lobbies_shown:
		ctx._rebuild_steam_lobbies(lobbies)
	for button in ctx._steam_lobby_buttons:
		button.disabled = not can_use or bool(button.get_meta("full",false))
	ctx._steam_empty_label.visible = lobbies.is_empty()
	ctx._steam_empty_label.text = "正在读取好友房间…" if scanning else ("暂无好友房间。可刷新列表，或请好友发送房间号。" if initialized else "连接 Steam 后可查看好友房间。")

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
		var room_name = str(entry.get("name","好友的基地"))
		var members = int(entry.get("members",0))
		var limit = maxi(int(entry.get("limit",4)),1)
		var row = Control.new()
		row.custom_minimum_size = Vector2(840,64)
		ctx._steam_lobby_list.add_child(row)
		var name_label = ctx._label(row,room_name,Rect2(12,0,590,29),19,ctx.INK)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.tooltip_text = room_name
		ctx._label(row,"房间号 %s  ·  %d / %d 人" % [lobby_id,members,limit],Rect2(12,31,636,25),14,ctx.MUTED)
		var join = ctx._button(row,"已满" if members >= limit else "加入",Rect2(694,8,144,46),ctx._join_steam_lobby.bind(lobby_id),ctx.TEAL,19)
		join.set_meta("full",members >= limit)
		ctx._steam_lobby_buttons.append(join)

static func _join_steam_input(ctx) -> void:
	if is_instance_valid(ctx._steam_lobby_input):
		ctx._join_steam_lobby(ctx._steam_lobby_input.text.strip_edges())

static func _join_steam_lobby(ctx, lobby_id: String) -> void:
	if not ctx._steam_ready() or bool(ctx._steam_info.get("pending",false)):
		return
	# Do not cast a SteamID to float, even when pasted from the clipboard.
	if lobby_id.length() < 17 or lobby_id.length() > 20:
		ctx._steam_input_error("请输入完整的 Steam 房间号（17–20 位数字）")
		return
	for character in lobby_id:
		if character < "0" or character > "9":
			ctx._steam_input_error("Steam 房间号只能包含数字")
			return
	ctx._steam_action("steam_join",{"lobby_id":lobby_id})

static func _steam_input_error(ctx, message: String) -> void:
	if is_instance_valid(ctx._steam_status):
		ctx._steam_status.text = message
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
		ctx._steam_info["status"] = "正在连接 Steam…" if action == "steam_connect" else ("正在创建好友房间…" if action == "steam_host" else "正在加入好友房间…")
	ctx._refresh_steam_controls()
	ctx.action_requested.emit(action,payload)

static func _refresh_steam_room(ctx) -> void:
	if not is_instance_valid(ctx._steam_room_label):
		return
	var lobby_id = str(ctx._steam_info.get("lobby_id",""))
	var in_room = str(ctx._steam_info.get("transport","offline")) == "steam" and not lobby_id.is_empty() and lobby_id != "0"
	ctx._steam_room_label.text = "Steam 房间号\n" + lobby_id if in_room else "当前未使用 Steam 房间"
	ctx._steam_invite_button.disabled = not in_room
	ctx._steam_copy_button.disabled = not in_room
	ctx._steam_invite_button.tooltip_text = "打开 Steam 好友邀请面板，由你选择好友" if in_room else "进入 Steam 房间后可邀请好友"
	ctx._steam_copy_button.tooltip_text = "复制房间号，发送给希望加入的好友" if in_room else "进入 Steam 房间后可复制房间号"
