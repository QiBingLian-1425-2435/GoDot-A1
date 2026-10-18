extends Control

var snapshot: Dictionary = {}
var own_id := 1
var disabled := false

func update_map(state: Dictionary, player_id: int, hide_detail: bool) -> void:
	snapshot = state
	own_id = player_id
	disabled = hide_detail
	queue_redraw()

func at(p: Vector2) -> Vector2:
	return Vector2(12+(p.x+11)/22*(size.x-24),12+(p.y+8)/16*(size.y-24))

func _draw() -> void:
	draw_style_box(background(), Rect2(Vector2.ZERO,size))
	if disabled:
		return
	var rooms := [Rect2(-10,-7,9,6),Rect2(1,-7,9,6),Rect2(-10,0,9,7),Rect2(1,0,9,7)]
	for room in rooms:
		var a := at(room.position)
		var b := at(room.end)
		draw_rect(Rect2(a,b-a),Color("253e42"))
		draw_rect(Rect2(a,b-a),Color("52716a"),false,1)
	var ep := at(Vector2(8,5.5))
	draw_circle(ep,7,Color(0.45,0.75,0.63,0.12))
	draw_arc(ep,7,0,TAU,24,Color("8bd0ad"),1.2)
	for loot in snapshot.get("loot",[]):
		if loot.get("pos") is Vector2:
			draw_circle(at(loot.pos),2,Color("bd9a55"))
	for id in snapshot.get("players",{}):
		var p:Dictionary=snapshot.players[id]
		if p.get("status", "alive") in ["dead","extracted"]:
			continue
		var color := Color("e9ce82") if int(id)==own_id else Color("6fa7bd")
		if p.get("status", "") == "downed":
			color=Color("d87969")
		draw_circle(at(p.pos),4,color)
		if int(id)==own_id:
			draw_arc(at(p.pos),6,0,TAU,24,Color(color,0.5),1)
	var monster:Dictionary=snapshot.get("monster",{})
	var me:Dictionary=snapshot.get("players",{}).get(own_id,{})
	if not monster.is_empty() and not me.is_empty() and monster.get("pos",Vector2.ZERO).distance_to(me.get("pos",Vector2.ZERO)) < 5.5:
		var mp:=at(monster.pos)
		draw_colored_polygon(PackedVector2Array([mp+Vector2(0,-4),mp+Vector2(4,3),mp+Vector2(-4,3)]),Color("da8167"))

func background() -> StyleBoxFlat:
	var b:=StyleBoxFlat.new()
	b.bg_color=Color("14292e")
	b.border_color=Color("3d5555")
	b.set_border_width_all(1)
	b.set_corner_radius_all(8)
	return b
