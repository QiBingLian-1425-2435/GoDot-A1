extends RefCounted
const Camp=preload("res://features/base/camp_upgrades.gd")
const Items=preload("res://features/inventory/item_catalog.gd")
static func open(ctx) -> void:
	ctx._dialog_panel("营地建设",Vector2(1060,740))
	ctx._dialog.set_meta("revision",int(ctx._state.get("world_revision",0)))
	ctx._dialog.set_meta("facility","medical")
	ctx._dialog.set_meta("confirmed",false)
	var list:=ItemList.new();list.name="CampFacilities";list.position=Vector2(30,100);list.size=Vector2(275,440);list.add_theme_font_size_override("font_size",23);ctx._dialog.add_child(list)
	for key in Camp.DEFS:
		var index:=list.add_item(Camp.DEFS[key].name);list.set_item_metadata(index,key)
	var detail=ctx._label(ctx._dialog,"",Rect2(335,100,690,390),20,ctx.INK);detail.name="CampDetails";detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var button=ctx._button(ctx._dialog,"准备升级",Rect2(335,520,690,52),func():submit(ctx),ctx.GREEN,22);button.name="CampUpgrade"
	ctx._label(ctx._dialog,"消耗你的基地币与随身材料；收益全队共享，进度保留在当前房主的营地。",Rect2(30,596,1000,48),18,ctx.GOLD).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	ctx._button(ctx._dialog,"关闭  [Esc]",Rect2(375,665,310,45),ctx._close_dialog,ctx.TEAL,20)
	list.item_selected.connect(func(index:int):ctx._dialog.set_meta("facility",list.get_item_metadata(index));ctx._dialog.set_meta("confirmed",false);refresh(ctx))
	list.select(0);refresh(ctx)
static func refresh(ctx) -> void:
	if not is_instance_valid(ctx._dialog) or ctx._dialog_kind!="营地建设":return
	if ctx._state.get("world","bunker")!="bunker" or int(ctx._state.get("world_revision",0))!=int(ctx._dialog.get_meta("revision",-1)):
		ctx._close_dialog();return
	var levels:Dictionary=ctx._state.get("camp",Camp.initial())
	var p:Dictionary=ctx._player()
	var key:String=ctx._dialog.get_meta("facility")
	var definition:Dictionary=Camp.DEFS[key]
	var level:int=levels[key]
	var list:ItemList=ctx._dialog.get_node("CampFacilities")
	for i in range(list.item_count):
		var facility:String=list.get_item_metadata(i)
		list.set_item_text(i,"%s  %d / 3"%[Camp.DEFS[facility].name,levels[facility]])
	var text:="%s · 强化 %d / 3\n全队%s：+%d%s\n"%[definition.name,level,definition.stat,level*int(definition.step)," kg" if key=="logistics" else ""]
	var button:Button=ctx._dialog.get_node("CampUpgrade")
	button.disabled=true
	if level>=3:
		text+="\n设施已满级\n\n升级不补充当前生命或耐力，负重加成与背包装备叠加。"
		button.text="已满级";ctx._dialog.set_meta("confirmed",false)
	else:
		var cost:Dictionary=definition.costs[level]
		var cash:int=p.get("credits",0)
		var holdings:Dictionary={}
		var reason:="基地币不足" if cash<int(cost.credits) else ""
		text+="升级后%s：+%d%s\n\n基地币：%d / %d\n升级后余额：%d\n\n所需材料（背包持有 / 需要）："%[definition.stat,(level+1)*int(definition.step)," kg" if key=="logistics" else "",cash,cost.credits,maxi(0,cash-int(cost.credits))]
		for kind in cost.items:
			var count:=0
			for item in p.get("bag",[]):
				if item.get("kind")==kind:count+=int(item.count)
			holdings[kind]=count
			text+="\n%s：%d / %d"%[Items.definition(kind).name,count,cost.items[kind]]
			if count<int(cost.items[kind]):reason="材料不足，请先准备随身材料"
		var stamp:Array=[key,level,cash,holdings]
		if stamp!=ctx._dialog.get_meta("stamp",[]):ctx._dialog.set_meta("confirmed",false)
		ctx._dialog.set_meta("stamp",stamp)
		button.disabled=not reason.is_empty()
		button.text="确认消耗并升级" if ctx._dialog.get_meta("confirmed",false) else "准备升级"
		text+="\n\n"+(reason if not reason.is_empty() else "请再次确认上述消耗。升级后当前生命、耐力不变。" if ctx._dialog.get_meta("confirmed",false) else "资源充足，可升级。")
	ctx._dialog.get_node("CampDetails").text=text
static func submit(ctx) -> void:
	refresh(ctx)
	if not is_instance_valid(ctx._dialog):return
	var button:Button=ctx._dialog.get_node("CampUpgrade")
	if button.disabled:return
	if not ctx._dialog.get_meta("confirmed",false):
		ctx._dialog.set_meta("confirmed",true);refresh(ctx);return
	var stamp:Array=ctx._dialog.get_meta("stamp")
	ctx._dialog.set_meta("confirmed",false)
	ctx.action_requested.emit("camp_upgrade",{"facility":stamp[0],"expected_level":int(stamp[1])})
	refresh(ctx)
