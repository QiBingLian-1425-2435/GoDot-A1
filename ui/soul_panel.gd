extends RefCounted

static func sync(ctx) -> void:
	var p: Dictionary = ctx._player()
	var undead: bool = ctx.Souls.zombie(p)
	var soul: bool = p.get("life","alive")=="soul"
	var targets: Array = []
	for id in ctx._players():
		if id!=ctx._local_id and ctx.Souls.alive(ctx._players()[id]): targets.append([id,ctx._players()[id].name])
	var attached := false
	for member in ctx._players().values():
		if int(member.get("possessing",0))==ctx._local_id: attached=true
	var signature := str([undead,soul,targets,p.get("possessing",0),not p.get("rescue",{}).is_empty(),attached])
	if signature != ctx._soul_signature:
		ctx._soul_signature = signature
		if is_instance_valid(ctx._soul_panel): ctx._soul_panel.hide();ctx._soul_panel.queue_free()
		ctx._soul_panel = ctx._panel(ctx._root,Rect2(1080,190,480,440) if soul or undead else Rect2(1120,190,440,130),ctx.PANEL,ctx.TEAL)
		if undead:
			ctx._label(ctx._soul_panel,"尸变 · 已死亡",Rect2(24,16,420,40),28,ctx.GOLD)
			ctx._label(ctx._soul_panel,"可移动，靠近队友 0.9 米会失控杀死队友。\n无法互动、语音、拾取或撤离。\n让队友在安全距离使用复活针。",Rect2(24,68,430,110),19,ctx.INK)
			ctx._button(ctx._soul_panel,"自杀，进入灵魂状态",Rect2(24,210,432,48),func():ctx.action_requested.emit("suicide",{}),ctx.TEAL,20)
		elif soul:
			ctx._label(ctx._soul_panel,"灵魂状态",Rect2(24,16,420,40),28,ctx.GOLD)
			var target: Dictionary = ctx._players().get(int(p.get("possessing",0)),{})
			ctx._label(ctx._soul_panel,"附身中："+str(target.get("name",""))+" · 可语音" if not target.is_empty() else "等待队友救援 · 遗体保留背包与装备",Rect2(24,64,440,32),17,ctx.INK)
			ctx._button(ctx._soul_panel,"等待救援 / 解除附身",Rect2(24,108,432,42),func():ctx.action_requested.emit("soul_wait",{}),ctx.TEAL,18)
			for i in range(targets.size()):
				var id: int = targets[i][0]
				ctx._button(ctx._soul_panel,"附身 "+str(targets[i][1]),Rect2(24,162+i*50,432,42),func():ctx.action_requested.emit("possess",{"target":id}),ctx.GREEN,18)
			if targets.is_empty():
				ctx._label(ctx._soul_panel,"全队已失去行动能力。\n可返回营地恢复，遗留装备留在原地。",Rect2(24,170,430,70),18,ctx.MUTED)
				ctx._button(ctx._soul_panel,"全队返回营地",Rect2(24,270,432,48),func():ctx.action_requested.emit("return_camp",{}),ctx.GREEN,20)
		else:
			ctx._soul_status = ctx._label(ctx._soul_panel,"",Rect2(20,12,400,32),20,ctx.GOLD)
			ctx._button(ctx._soul_panel,"取消救援" if not p.get("rescue",{}).is_empty() else "解除队友附身",Rect2(20,64,400,42),func():ctx.action_requested.emit("rescue_cancel" if not p.get("rescue",{}).is_empty() else "release_soul",{}),ctx.TEAL,18)
	ctx._soul_panel.visible = ctx._in_game and (undead or soul or attached or not p.get("rescue",{}).is_empty()) and not ctx._pause_panel.visible
	if soul or undead:
		ctx._inventory.hide(); ctx._popup.hide()
		if is_instance_valid(ctx._dialog):ctx._close_dialog()
	elif not p.get("rescue",{}).is_empty(): ctx._soul_status.text = "救援中 %.1f 秒 · 移动会取消" % maxf(0,float(p.rescue.remaining))
	elif attached: ctx._soul_status.text = "有灵魂队友附身 · 可共同语音"
