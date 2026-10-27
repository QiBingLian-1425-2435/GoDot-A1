extends Node3D
## Read-only local presentation of host-owned search state; never reveals unseen boxes.
const Loot=preload("res://features/exploration/container_loot.gd")
const Texts=preload("res://features/localization/game_text.gd")
const LABELS={"searching":"⟦loot_marks.searching⟧","partial":"⟦loot_marks.partial⟧","searched":"⟦loot_marks.searched⟧","empty":"⟦loot_marks.empty⟧"}
var markers: Dictionary={}
var _world:=""

func clear() -> void:
	for label in markers.values():label.hide();label.queue_free()
	markers.clear()

func update(ctx) -> void:
	if not ctx.in_game or ctx.world_loading:
		clear();return
	if _world!=ctx.world_id:clear();_world=ctx.world_id
	var active: Dictionary={}
	for station in ctx.session.model.stations:
		if station.get("kind","")!="loot" or station.get("world","")!=ctx.world_id:continue
		var uid: String=station.uid
		var state: String=Loot.status(ctx.session.model.state,uid)
		if state=="unsearched":continue
		active[uid]=true
		if not markers.has(uid):
			var label:=Label3D.new();label.name="SearchedContainer"
			label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size=24;label.pixel_size=.014;label.outline_size=7
			label.shaded=false;label.no_depth_test=false
			add_child(label);markers[uid]=label
		var label: Label3D=markers[uid]
		var target: Dictionary=ctx.world.loot_target(uid) if ctx.world.has_method("loot_target") else {}
		var at:=Vector3(station.pos.x,float(station.get("height",0))+.9,station.pos.y)
		if target.get("bounds") is AABB:at.y=target.bounds.end.y+.25
		label.position=at
		Texts.bind(label,LABELS[state],"text")
		label.modulate=Color("a4b5b4") if state=="empty" else Color("82e2b1") if state=="searched" else Color("f0cf85")
		label.visible=false
		var points: Array=target.get("points",[at])
		var excluded: Array[RID]=[];excluded.assign(target.get("exclude",[]))
		for point in points:
			if ctx.vision.can_see(point,excluded):label.visible=true;break
	for uid in markers.keys():
		if not active.has(uid):markers[uid].queue_free();markers.erase(uid)
