extends Control
var value:float=0.0:
	set(v):
		value=v
		queue_redraw()
var max_value:float=100.0
var fill_color:=Color("8bc9b1")
func _draw()->void:
	var back:=StyleBoxFlat.new()
	back.bg_color=Color("314741")
	back.set_corner_radius_all(3)
	draw_style_box(back,Rect2(Vector2.ZERO,size))
	var front:=StyleBoxFlat.new()
	front.bg_color=fill_color
	front.set_corner_radius_all(3)
	draw_style_box(front,Rect2(Vector2.ZERO,Vector2(size.x*clampf(value/maxf(1,max_value),0,1),size.y)))
