extends Control
var active := false
var aiming := false
var spread_pixels:=0.0
var spread_target:=0.0
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func _process(delta:float)->void:
	spread_pixels=move_toward(spread_pixels,spread_target,delta*240)
	queue_redraw()

func set_accuracy(player:Dictionary,camera:Camera3D,at:Vector3)->void:
	var angle:float=preload("res://features/combat/firearm_spread.gd").angle(player)
	var origin:=Vector3(player.get("pos",Vector2.ZERO).x,at.y,player.get("pos",Vector2.ZERO).y)
	var direction:Vector2=player.get("aim",Vector2.UP)
	var side:=Vector3(-direction.y,0,direction.x)
	spread_target=camera.unproject_position(at).distance_to(camera.unproject_position(at+side*tan(angle)*origin.distance_to(at)))

func _draw()->void:
	if not active:
		return
	var p:=get_local_mouse_position()
	var gap:=(5.0 if aiming else 10.0)+spread_pixels
	var c:=Color(1,0.94,0.7,0.9)
	for dir in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		draw_line(p+dir*gap,p+dir*(gap+7),Color(0,0,0,0.65),4)
		draw_line(p+dir*gap,p+dir*(gap+7),c,1.5)
	draw_circle(p,1.5,c)
