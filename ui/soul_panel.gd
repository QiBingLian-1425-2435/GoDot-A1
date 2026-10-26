extends RefCounted
const Texts = preload("res://features/localization/game_text.gd")

static func sync(ctx) -> void:
	var p: Dictionary = ctx._player()
	var undead: bool = ctx.Souls.zombie(p)
	var soul: bool = p.get("life","alive")=="soul"
	var targets: Array = []
	var living_count := 0
	for id in ctx._players():
		if ctx.Souls.alive(ctx._players()[id]):living_count+=1
		if ctx.Souls.can_possess(ctx._players(),ctx._local_id,int(id)): targets.append([id,ctx._players()[id].name])
	var attached := false
	for member in ctx._players().values():
		if int(member.get("possessing",0))==ctx._local_id: attached=true
	var signature := str([undead,soul,targets,living_count,p.get("possessing",0),p.get("soul_speed",2),not p.get("rescue",{}).is_empty(),attached])
	if signature != ctx._soul_signature:
		ctx._soul_signature = signature
		if is_instance_valid(ctx._soul_panel): ctx._soul_panel.hide();ctx._soul_panel.queue_free()
		ctx._soul_panel = ctx._panel(ctx._root,Rect2(1080,190,480,510) if soul or undead else Rect2(1120,190,440,130),ctx.PANEL,ctx.TEAL)
		if undead:
			ctx._label(ctx._soul_panel,"⟦soul_panel.001⟧",Rect2(24,16,420,40),28,ctx.GOLD)
			ctx._label(ctx._soul_panel,"⟦soul_panel.002⟧",Rect2(24,68,430,110),19,ctx.INK)
			ctx._button(ctx._soul_panel,"⟦soul_panel.003⟧",Rect2(24,210,432,48),func():ctx.action_requested.emit("suicide",{}),ctx.TEAL,20)
		elif soul:
			ctx._label(ctx._soul_panel,"⟦soul_panel.004⟧",Rect2(24,16,420,40),28,ctx.GOLD)
			var target: Dictionary = ctx._players().get(int(p.get("possessing",0)),{})
			ctx._label(ctx._soul_panel,"⟦soul_panel.005⟧"+str(target.get("name",""))+"⟦soul_panel.006⟧" if not target.is_empty() else "⟦soul_panel.007⟧",Rect2(24,64,440,32),17,ctx.INK)
			ctx._button(ctx._soul_panel,"⟦soul_panel.008⟧",Rect2(24,108,432,42),func():ctx.action_requested.emit("soul_wait",{}),ctx.TEAL,18)
			for i in range(targets.size()):
				var id: int = targets[i][0]
				ctx._button(ctx._soul_panel,"⟦soul_panel.009⟧"+str(targets[i][1]),Rect2(24,254+i*50,432,42),func():ctx.action_requested.emit("possess",{"target":id}),ctx.GREEN,18)
			if ctx.Souls.free_soul(p):
				for i in range(ctx.Souls.SOUL_SPEEDS.size()):
					var speed: int=ctx.Souls.SOUL_SPEEDS[i]
					var b: Button=ctx._button(ctx._soul_panel,str(speed)+"×",Rect2(24+i*110,162,102,38),func():ctx.action_requested.emit("soul_speed",{"speed":speed}),ctx.TEAL,18)
					b.name="SoulSpeed"+str(speed);b.disabled=int(p.get("soul_speed",2))==speed
				ctx._label(ctx._soul_panel,"⟦soul_roaming.controls⟧",Rect2(24,207,432,44),16,ctx.MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			if living_count==0:
				ctx._label(ctx._soul_panel,"⟦soul_panel.010⟧",Rect2(24,262,430,70),18,ctx.MUTED)
				ctx._button(ctx._soul_panel,"⟦soul_panel.011⟧",Rect2(24,350,432,48),func():ctx.action_requested.emit("return_camp",{}),ctx.GREEN,20)
		else:
			ctx._soul_status = ctx._label(ctx._soul_panel,"",Rect2(20,12,400,32),20,ctx.GOLD)
			ctx._button(ctx._soul_panel,"⟦soul_panel.012⟧" if not p.get("rescue",{}).is_empty() else "⟦soul_panel.013⟧",Rect2(20,64,400,42),func():ctx.action_requested.emit("rescue_cancel" if not p.get("rescue",{}).is_empty() else "release_soul",{}),ctx.TEAL,18)
	ctx._soul_panel.visible = ctx._in_game and (undead or soul or attached or not p.get("rescue",{}).is_empty()) and not ctx._pause_panel.visible
	if soul or undead:
		ctx._inventory.hide(); ctx._popup.hide()
		if is_instance_valid(ctx._dialog):ctx._close_dialog()
	elif not p.get("rescue",{}).is_empty(): Texts.bind(ctx._soul_status, Texts.format("⟦soul_panel.014⟧", maxf(0,float(p.rescue.remaining))), "text")
	elif attached: Texts.bind(ctx._soul_status, "⟦soul_panel.015⟧", "text")
