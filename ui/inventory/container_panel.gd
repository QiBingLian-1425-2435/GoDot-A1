extends RefCounted
const Texts = preload("res://features/localization/game_text.gd")
const Loot = preload("res://features/exploration/container_loot.gd")

static func sync(ctx) -> void:
	var uid := str(ctx._player().get("loot_uid", ""))
	if uid.is_empty():
		ctx._loot_dismissed_uid = ""
		if not ctx._loot_uid.is_empty(): ctx._close_dialog()
		return
	if not ctx._in_game or uid == ctx._loot_dismissed_uid:
		return
	if ctx._loot_uid != uid or not is_instance_valid(ctx._dialog):
		ctx.close_inventory()
		open(ctx, uid)
	refresh(ctx)

static func icon(ctx, parent: Control, position: Vector2, size: Vector2):
	var slot = ctx.Slot.new()
	slot.position = position
	slot.size = size
	parent.add_child(slot)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot

static func open(ctx, uid: String) -> void:
	var box: Dictionary = ctx._state.get("containers", {}).get(uid, {})
	ctx._dialog_panel("⟦main.016⟧" if box.get("title", "") == "⟦main.015⟧" else "⟦container_panel.001⟧", Vector2(1160, 730))
	ctx._loot_uid = uid
	ctx._loot_selected = -1
	ctx._loot_page = 0
	ctx._loot_slots = []; ctx._loot_bag = []; ctx._loot_buttons = []
	ctx._label(ctx._dialog, "⟦container_panel.002⟧", Rect2(32, 86, 470, 36), 24, ctx.INK)
	ctx._loot_weight = ctx._label(ctx._dialog, "", Rect2(32, 128, 470, 30), 18, ctx.MUTED)
	for i in range(24):
		ctx._loot_bag.append(icon(ctx, ctx._dialog, Vector2(32 + i % 6 * 75, 180 + i / 6 * 75), Vector2(68, 68)))
	ctx._label(ctx._dialog, "⟦container_panel.003⟧" if box.get("title", "") == "⟦main.015⟧" else "⟦container_panel.004⟧", Rect2(530, 86, 580, 36), 24, ctx.INK)
	ctx._loot_status = ctx._label(ctx._dialog, "⟦container_panel.005⟧", Rect2(530, 128, 590, 32), 18, ctx.GOLD)
	ctx._loot_progress = ProgressBar.new()
	ctx._loot_progress.position = Vector2(530, 166)
	ctx._loot_progress.size = Vector2(570, 15)
	ctx._loot_progress.show_percentage = false
	ctx._dialog.add_child(ctx._loot_progress)
	for i in range(6):
		var button := Button.new()
		button.position = Vector2(530 + i % 3 * 193, 200 + i / 3 * 126)
		button.size = Vector2(180, 116)
		button.name = "ContainerSlot%d" % i
		ctx._dialog.add_child(button)
		var slot = icon(ctx, button, Vector2(8, 8), Vector2(80, 80))
		var label = ctx._label(button, "", Rect2(7, 88, 166, 25), 15, ctx.INK, HORIZONTAL_ALIGNMENT_CENTER)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.pressed.connect(func(): ctx._loot_selected = ctx._loot_page*6+i; refresh(ctx))
		button.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
				ctx._loot_selected = ctx._loot_page*6+i; take(ctx, false))
		ctx._loot_slots.append({"icon": slot, "label": label})
		ctx._loot_buttons.append(button)
	ctx._button(ctx._dialog,"⟦container_panel.006⟧",Rect2(530,442,274,30),func():ctx._loot_page=maxi(0,ctx._loot_page-1);refresh(ctx),ctx.TEAL,16)
	ctx._button(ctx._dialog,"⟦container_panel.007⟧",Rect2(824,442,274,30),func():ctx._loot_page=mini(maxi(0,ceili(box.items.size()/6.0)-1),ctx._loot_page+1);refresh(ctx),ctx.TEAL,16)
	ctx._loot_detail = ctx._label(ctx._dialog, "⟦container_panel.008⟧", Rect2(530, 466, 590, 115), 17, ctx.MUTED)
	ctx._loot_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctx._button(ctx._dialog, "⟦container_panel.009⟧", Rect2(530, 590, 274, 48), func(): take(ctx, false), ctx.GREEN, 20)
	ctx._button(ctx._dialog, "⟦container_panel.010⟧", Rect2(824, 590, 274, 48), func(): take(ctx, true), ctx.TEAL, 20)
	ctx._label(ctx._dialog, "⟦container_panel.011⟧", Rect2(32, 510, 460, 90), 18, ctx.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctx._button(ctx._dialog, "⟦camp_panel.003⟧", Rect2(430, 660, 300, 45), ctx._close_dialog, ctx.TEAL, 20)

static func take(ctx, all_items: bool) -> void:
	var box: Dictionary = ctx._state.get("containers", {}).get(ctx._loot_uid, {})
	if box.is_empty(): return
	var payload := {"uid": ctx._loot_uid, "index": -1}
	if not all_items:
		var i: int = ctx._loot_selected
		if i < 0 or i >= int(box.revealed) or box.items[i].is_empty(): return
		payload.index = i
		payload.item_uid = box.items[i].uid
	ctx.action_requested.emit("loot_take", payload)

static func refresh(ctx) -> void:
	var box: Dictionary = ctx._state.get("containers", {}).get(ctx._loot_uid, {})
	if box.is_empty(): return
	var p: Dictionary = ctx._player()
	Texts.bind(ctx._loot_weight, Texts.format("⟦container_panel.012⟧", [float(p.get("weight", 0)), float(p.get("max_weight", 28))]), "text")
	for i in range(ctx._loot_bag.size()):
		var item: Dictionary = p.bag[i] if i < p.bag.size() else {}
		ctx._loot_bag[i].set_item(item, ctx.Items.definition(item.kind) if not item.is_empty() else {})
	var remaining := 0
	for index in range(int(box.revealed)):
		if not box.items[index].is_empty(): remaining += 1
	for i in range(ctx._loot_slots.size()):
		var slot_index: int = ctx._loot_page*6+i
		var part: Dictionary = ctx._loot_slots[i]
		var exists: bool = slot_index < box.items.size()
		var known: bool = exists and slot_index < int(box.revealed)
		var item: Dictionary = box.items[slot_index] if known else {}
		part.icon.set_item(item, ctx.Items.definition(item.kind) if not item.is_empty() else {})
		Texts.bind(part.label, "⟦container_panel.013⟧" if not exists else "⟦container_panel.014⟧" if known and item.is_empty() else str(ctx.Items.definition(item.kind).name) if known else "⟦container_panel.015⟧" if slot_index == int(box.revealed) else "⟦container_panel.016⟧", "text")
		ctx._loot_buttons[i].disabled = not known or item.is_empty()
		Texts.bind(ctx._loot_buttons[i], ctx.Items.details(item) if not item.is_empty() else "", "tooltip_text")
		part.icon.selected = slot_index == ctx._loot_selected
	var complete: bool = int(box.revealed) >= box.items.size()
	var owner: int = int(box.searcher)
	Texts.bind(ctx._loot_status, ("⟦container_panel.017⟧" if remaining == 0 else Texts.format("⟦container_panel.018⟧", remaining)) if complete else ("⟦container_panel.019⟧" if owner == ctx._local_id else "⟦container_panel.020⟧") + Texts.format("⟦format.container_panel.001⟧", [int(box.revealed), box.items.size()]), "text")
	ctx._loot_progress.value = 100 if complete else clampf(float(box.progress) / Loot.SEARCH_SECONDS * 100, 0, 100)
	var selected: int = ctx._loot_selected
	if selected >= 0 and selected < int(box.revealed) and not box.items[selected].is_empty():
		var item: Dictionary = box.items[selected]
		Texts.bind(ctx._loot_detail, str(ctx.Items.definition(item.kind).name) + "\n" + ctx.Items.details(item), "text")
	else:
		Texts.bind(ctx._loot_detail, "⟦container_panel.021⟧", "text")
