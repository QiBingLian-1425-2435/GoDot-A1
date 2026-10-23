extends Control
## Local-only overview. It reads replicated player positions and never writes game state.

const MAP_CENTER := Vector2(390.0, -205.0)
const MAP_VERTICAL_SIZE := 760.0
const MAP_ASPECT := 16.0 / 9.0
const SELF_COLOR := Color("f3d16f")
const TEAM_COLOR := Color("72d8df")
const MarkerLayer = preload("res://ui/map/global_map_markers.gd")

var _players: Dictionary = {}
var _local_id := 0
var _zone := ""
var _title: Label
var _map_rect: TextureRect
var _status: Label
var _markers: Control
var _font: SystemFont

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	var shade := ColorRect.new()
	shade.color = Color(0.015,0.025,0.03,0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-640,-410)
	panel.size = Vector2(1280,820)
	var box := StyleBoxFlat.new()
	box.bg_color=Color("10191c");box.border_color=Color("658186")
	box.set_border_width_all(2);box.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel",box)
	add_child(panel)
	_title=_label(panel,"零号区全局地图",Rect2(30,18,1220,40),28,Color("e8ecdd"),HORIZONTAL_ALIGNMENT_CENTER)
	_map_rect=TextureRect.new()
	_map_rect.position=Vector2(30,68);_map_rect.size=Vector2(1220,686.25)
	_map_rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var image_path := "res://assets/worlds/ground_zero/map_overview.png"
	if ResourceLoader.exists(image_path):_map_rect.texture=load(image_path)
	panel.add_child(_map_rect)
	_markers=MarkerLayer.new()
	_markers.map=self;_markers.position=_map_rect.position;_markers.size=_map_rect.size
	_markers.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(_markers)
	_status=_label(panel,"",Rect2(30,350,1220,34),20,Color("c7d4cf"),HORIZONTAL_ALIGNMENT_CENTER)
	_label(panel,"M / Esc 关闭    金色：自己    青色：队友",Rect2(30,784,1220,24),15,Color("a8b7b2"),HORIZONTAL_ALIGNMENT_CENTER)
	visible=false

func set_state(players: Dictionary, local_id: int, zone: String) -> void:
	_players=players
	_local_id=local_id
	_zone=zone
	_title.text="零号区全局地图" if zone=="surface" else "神秘山洞地图"
	if is_instance_valid(_markers):_markers.queue_redraw()

func set_open(value: bool) -> void:
	visible=value
	if value and is_instance_valid(_markers):_markers.queue_redraw()

func is_open() -> bool:
	return visible

func world_to_map(pos: Vector2, rect: Rect2) -> Vector2:
	var normalized := Vector2(
		(pos.x-MAP_CENTER.x)/(MAP_VERTICAL_SIZE*MAP_ASPECT)+0.5,
		(pos.y-MAP_CENTER.y)/MAP_VERTICAL_SIZE+0.5)
	return rect.position+normalized*rect.size

func draw_markers(canvas: Control) -> void:
	if not visible or not is_instance_valid(_map_rect):return
	var rect:=Rect2(Vector2.ZERO,_map_rect.size)
	if _map_rect.texture==null:
		canvas.draw_rect(rect,Color("18272a"),true)
		for i in range(1,8):
			var x:=rect.position.x+rect.size.x*float(i)/8.0
			canvas.draw_line(Vector2(x,rect.position.y),Vector2(x,rect.end.y),Color(0.35,0.5,0.5,0.16),1)
		for i in range(1,5):
			var y:=rect.position.y+rect.size.y*float(i)/5.0
			canvas.draw_line(Vector2(rect.position.x,y),Vector2(rect.end.x,y),Color(0.35,0.5,0.5,0.16),1)
		_status.text="地图底图缺失，请运行地图还原或 tools/generate_global_map.py"
	else:_status.text=""
	for id in _players:
		var player:Dictionary=_players[id]
		var point:=world_to_map(Vector2(player.get("pos",Vector2.ZERO)),rect)
		if not rect.has_point(point):continue
		var local:=int(id)==_local_id
		var color:=SELF_COLOR if local else TEAM_COLOR
		canvas.draw_circle(point,9.0 if local else 7.0,color)
		canvas.draw_circle(point,12.0 if local else 10.0,Color(color,0.28),false,2.0)
		var name:=str(player.get("name","自己" if local else "队友"))
		canvas.draw_string(_font,point+Vector2(14,6),name,HORIZONTAL_ALIGNMENT_LEFT,-1,16,color)

func _label(parent: Control, text: String, rect: Rect2, size: int, color: Color, align: int) -> Label:
	var label:=Label.new();label.text=text;label.position=rect.position;label.size=rect.size
	label.add_theme_font_override("font",_font);label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color);label.horizontal_alignment=align
	parent.add_child(label);return label
