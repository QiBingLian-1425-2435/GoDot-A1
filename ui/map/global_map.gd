extends Control
const Texts = preload("res://features/localization/game_text.gd")
## Local-only overview. It reads replicated player positions and never writes game state.

const MAP_CENTER := Vector2(390.0, -250.0)
const MAP_VERTICAL_SIZE := 600.0
const MAP_ASPECT := 16.0 / 9.0
const MAP_TILE_COLUMNS := 2
const MAP_TILE_ROWS := 2
const MAP_TILE_PATTERN := "res://assets/worlds/ground_zero/map_overview_%d_%d.png"
const SELF_COLOR := Color("f3d16f")
const TEAM_COLOR := Color("72d8df")
const MIN_ZOOM := 1.0
const MAX_ZOOM := 3.0
const ZOOM_STEP := 0.25
const MarkerLayer = preload("res://ui/map/global_map_markers.gd")

var _players: Dictionary = {}
var _local_id := 0
var _zone := ""
var _title: Label
var _map_rect: TextureRect
var _map_tiles: Array[TextureRect] = []
var _map_tiles_available := false
var _map_view: Control
var _map_content: Control
var _status: Label
var _markers: Control
var _font: SystemFont
var _zoom_label: Label
var _zoom := 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _last_pointer := Vector2.ZERO

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
	_title=_label(panel,"⟦global_map.001⟧",Rect2(30,18,1220,40),28,Color("e8ecdd"),HORIZONTAL_ALIGNMENT_CENTER)
	_map_view=Control.new()
	_map_view.position=Vector2(30,68);_map_view.size=Vector2(1220,686.25)
	_map_view.clip_contents=true;_map_view.mouse_filter=Control.MOUSE_FILTER_STOP
	_map_view.gui_input.connect(_on_map_input)
	panel.add_child(_map_view)
	_map_content=Control.new();_map_content.size=_map_view.size
	_map_content.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_map_view.add_child(_map_content)
	_map_rect=TextureRect.new()
	_map_rect.size=_map_view.size
	_map_rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_map_content.add_child(_map_rect)
	_load_map_texture()
	_markers=MarkerLayer.new()
	_markers.map=self;_markers.size=_map_view.size
	_markers.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_map_view.add_child(_markers)
	Texts.watch_draw(_markers)
	_status=_label(panel,"",Rect2(30,350,1220,34),20,Color("c7d4cf"),HORIZONTAL_ALIGNMENT_CENTER)
	var zoom_out:=_button(panel,"−",Rect2(30,776,42,30),_zoom_out)
	_zoom_label=_label(panel,"⟦format.global_map.001⟧",Rect2(78,779,58,26),14,Color("c7d4cf"),HORIZONTAL_ALIGNMENT_CENTER)
	var zoom_in:=_button(panel,"+",Rect2(142,776,42,30),_zoom_in)
	_button(panel,"⟦global_map.002⟧",Rect2(194,776,92,30),center_on_local)
	_label(panel,"⟦global_map.003⟧",Rect2(300,780,920,24),15,Color("a8b7b2"),HORIZONTAL_ALIGNMENT_RIGHT)
	_apply_view()
	visible=false

func set_state(players: Dictionary, local_id: int, zone: String) -> void:
	_players=players
	_local_id=local_id
	_zone=zone
	Texts.bind(_title, "⟦global_map.001⟧" if zone=="surface" else "⟦global_map.004⟧", "text")
	if is_instance_valid(_markers):_markers.queue_redraw()

func set_open(value: bool) -> void:
	visible=value
	_dragging=false
	if value:
		reset_view()
		if is_instance_valid(_markers):_markers.queue_redraw()

func is_open() -> bool:
	return visible

func world_to_map(pos: Vector2, rect: Rect2) -> Vector2:
	var normalized := Vector2(
		(pos.x-MAP_CENTER.x)/(MAP_VERTICAL_SIZE*MAP_ASPECT)+0.5,
		(pos.y-MAP_CENTER.y)/MAP_VERTICAL_SIZE+0.5)
	return rect.position+normalized*rect.size

func map_to_view(point: Vector2) -> Vector2:
	return _map_content.position+point*_zoom

func set_zoom(value: float, anchor: Vector2 = Vector2(-1,-1)) -> void:
	var previous:=_zoom
	_zoom=clampf(value,MIN_ZOOM,MAX_ZOOM)
	if _zoom>MIN_ZOOM:_ensure_tiles_loaded()
	if is_instance_valid(_map_view) and anchor.x>=0.0 and previous>0.0:
		var from_center:=anchor-_map_view.size*.5
		_pan=(_pan-from_center)*(_zoom/previous)+from_center
	_apply_view()

func reset_view() -> void:
	_zoom=1.0;_pan=Vector2.ZERO
	_apply_view()

func center_on_local() -> void:
	if not _players.has(_local_id):
		reset_view();return
	if _zoom<=1.0:_zoom=2.0
	_ensure_tiles_loaded()
	var point:=world_to_map(Vector2(_players[_local_id].get("pos",Vector2.ZERO)),Rect2(Vector2.ZERO,_map_content.size))
	_pan=(_map_content.size*.5-point)*_zoom
	_apply_view()

func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed:set_zoom(_zoom+ZOOM_STEP,event.position)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed:set_zoom(_zoom-ZOOM_STEP,event.position)
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed and event.double_click:set_zoom(_zoom+ZOOM_STEP*2.0,event.position)
			_dragging=event.pressed;_last_pointer=event.position
		elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:reset_view()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_pan+=event.position-_last_pointer;_last_pointer=event.position
		_apply_view();accept_event()

func _zoom_in() -> void:
	set_zoom(_zoom+ZOOM_STEP)

func _zoom_out() -> void:
	set_zoom(_zoom-ZOOM_STEP)

func _apply_view() -> void:
	if not is_instance_valid(_map_content):return
	var limit:=_map_content.size*(_zoom-1.0)*.5
	_pan.x=clampf(_pan.x,-limit.x,limit.x);_pan.y=clampf(_pan.y,-limit.y,limit.y)
	_map_content.scale=Vector2.ONE*_zoom
	_map_content.position=_map_view.size*.5+_pan-_map_content.size*_zoom*.5
	if is_instance_valid(_zoom_label):Texts.bind(_zoom_label, Texts.format("⟦format.global_map.002⟧", roundi(_zoom*100.0)), "text")
	if is_instance_valid(_markers):_markers.queue_redraw()

func draw_markers(canvas: Control) -> void:
	if not visible or not is_instance_valid(_map_rect):return
	var map_rect:=Rect2(Vector2.ZERO,_map_rect.size)
	var view_rect:=Rect2(Vector2.ZERO,_map_view.size)
	if _map_tiles.is_empty() and _map_rect.texture==null:
		canvas.draw_rect(view_rect,Color("18272a"),true)
		for i in range(1,8):
			var x:=view_rect.position.x+view_rect.size.x*float(i)/8.0
			canvas.draw_line(Vector2(x,view_rect.position.y),Vector2(x,view_rect.end.y),Color(0.35,0.5,0.5,0.16),1)
		for i in range(1,5):
			var y:=view_rect.position.y+view_rect.size.y*float(i)/5.0
			canvas.draw_line(Vector2(view_rect.position.x,y),Vector2(view_rect.end.x,y),Color(0.35,0.5,0.5,0.16),1)
		Texts.bind(_status, "⟦global_map.005⟧", "text")
	else:Texts.bind(_status, "", "text")
	for id in _players:
		var player:Dictionary=_players[id]
		var point:=map_to_view(world_to_map(Vector2(player.get("pos",Vector2.ZERO)),map_rect))
		if not view_rect.has_point(point):continue
		var local:=int(id)==_local_id
		var color:=SELF_COLOR if local else TEAM_COLOR
		canvas.draw_circle(point,9.0 if local else 7.0,color)
		canvas.draw_circle(point,12.0 if local else 10.0,Color(color,0.28),false,2.0)
		var name:=str(player.get("name","⟦global_map.006⟧" if local else "⟦field_item_view.002⟧"))
		canvas.draw_string(_font, point+Vector2(14,6), Texts.resolve(name), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)

func _load_map_texture() -> void:
	var image_path := "res://assets/worlds/ground_zero/map_overview.png"
	if ResourceLoader.exists(image_path):_map_rect.texture=load(image_path)
	_map_tiles_available=true
	for row in range(MAP_TILE_ROWS):
		for column in range(MAP_TILE_COLUMNS):
			if not ResourceLoader.exists(MAP_TILE_PATTERN % [column,row]):_map_tiles_available=false

func _ensure_tiles_loaded() -> void:
	if not _map_tiles.is_empty() or not _map_tiles_available:return
	var tile_size:=Vector2(_map_rect.size.x/MAP_TILE_COLUMNS,_map_rect.size.y/MAP_TILE_ROWS)
	_map_rect.visible=false
	for row in range(MAP_TILE_ROWS):
		for column in range(MAP_TILE_COLUMNS):
			var tile:=TextureRect.new()
			tile.position=Vector2(column,row)*tile_size;tile.size=tile_size
			tile.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			tile.stretch_mode=TextureRect.STRETCH_SCALE
			tile.mouse_filter=Control.MOUSE_FILTER_IGNORE
			tile.texture=load(MAP_TILE_PATTERN % [column,row])
			_map_content.add_child(tile);_map_tiles.append(tile)

func _label(parent: Control, text: String, rect: Rect2, size: int, color: Color, align: int) -> Label:
	var label:=Label.new();Texts.bind(label, text, "text");label.position=rect.position;label.size=rect.size
	label.add_theme_font_override("font",_font);label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color);label.horizontal_alignment=align
	parent.add_child(label);return label

func _button(parent: Control, text: String, rect: Rect2, callback: Callable) -> Button:
	var button:=Button.new();Texts.bind(button, text, "text");button.position=rect.position;button.size=rect.size
	button.add_theme_font_override("font",_font);button.add_theme_font_size_override("font_size",14)
	button.pressed.connect(callback);parent.add_child(button);return button
