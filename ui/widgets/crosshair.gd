extends Control
var active := false
var aiming := false
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func _process(_delta:float)->void:
	queue_redraw()
func _draw()->void:
	if not active:
		return
	var p:=get_local_mouse_position()
	var gap:=5.0 if aiming else 10.0
	var c:=Color(1,0.94,0.7,0.9)
	for dir in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		draw_line(p+dir*gap,p+dir*(gap+7),Color(0,0,0,0.65),4)
		draw_line(p+dir*gap,p+dir*(gap+7),c,1.5)
	draw_circle(p,1.5,c)
