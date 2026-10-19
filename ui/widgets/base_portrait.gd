extends Control

var equipment: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var s := minf(size.x / 220.0, size.y / 320.0)
	draw_set_transform(Vector2(size.x * 0.5, size.y * 0.51), 0.0, Vector2.ONE * s)
	# A soft pool of light makes the equipment silhouette readable on dark panels.
	draw_circle(Vector2(0,22), 95, Color(0.54,0.67,0.63,0.055))
	draw_circle(Vector2(0,22), 73, Color(0.54,0.67,0.63,0.04))
	_ellipse(Vector2(0,123),Vector2(66,12),Color(0,0,0,0.3))
	draw_line(Vector2(-20,77),Vector2(-22,111),Color("d49645"),13)
	draw_line(Vector2(20,77),Vector2(23,111),Color("d49645"),13)
	_ellipse(Vector2(-30,116),Vector2(24,9),Color("e6ac52"))
	_ellipse(Vector2(30,116),Vector2(24,9),Color("e6ac52"))
	_ellipse(Vector2(0,31),Vector2(57,66),Color("e5e6d8"))
	_ellipse(Vector2(-46,26),Vector2(18,39),Color("dddccc"))
	_ellipse(Vector2(46,26),Vector2(18,39),Color("d1d3c3"))
	draw_colored_polygon(PackedVector2Array([Vector2(-39,-23),Vector2(-17,-35),Vector2(18,-35),Vector2(40,-22),Vector2(43,66),Vector2(-43,66)]),Color("667e69"))
	draw_rect(Rect2(-32,-8,64,55),Color("7e9373"))
	draw_line(Vector2(0,-21),Vector2(0,65),Color("485a4c"),3)
	for x in [-28,7]:
		draw_rect(Rect2(x,15,21,25),Color("526956"))
		draw_rect(Rect2(x,15,21,5),Color("a1aa84"))
	draw_rect(Rect2(-44,53,88,10),Color("424b40"))
	draw_rect(Rect2(-7,52,14,13),Color("bcb386"))
	_ellipse(Vector2(0,-61),Vector2(45,48),Color("edeedc"))
	_ellipse(Vector2(12,-54),Vector2(39,34),Color("f3f0dd"))
	draw_circle(Vector2(-13,-64),4.5,Color("1c2b2e"))
	draw_circle(Vector2(17,-64),4.5,Color("1c2b2e"))
	_ellipse(Vector2(4,-42),Vector2(24,11),Color("e3a041"))
	draw_line(Vector2(-13,-42),Vector2(23,-42),Color("b57c35"),2)
	if not equipment.get("helmet", {}).is_empty():
		draw_arc(Vector2(0,-69),44,PI,TAU,32,Color("738467"),19)
		draw_rect(Rect2(-48,-81,96,13),Color("627259"))
		draw_line(Vector2(-25,-99),Vector2(-5,-108),Color("a1ac88"),5)
	if not equipment.get("weapon", {}).is_empty():
		draw_set_transform(Vector2(size.x * 0.5, size.y * 0.51 + 40*s),-0.38,Vector2.ONE*s)
		draw_rect(Rect2(-52,-8,90,14),Color("3c4644"))
		draw_rect(Rect2(29,-6,37,6),Color("1e292b"))
		draw_colored_polygon(PackedVector2Array([Vector2(-52,-8),Vector2(-70,-2),Vector2(-72,13),Vector2(-52,7)]),Color("7e7154"))
		draw_rect(Rect2(-8,5,11,21),Color("4b5650"))
	draw_set_transform(Vector2.ZERO)

func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(40):
		var angle := TAU * i / 40.0
		points.append(center + Vector2(cos(angle)*radius.x,sin(angle)*radius.y))
	draw_colored_polygon(points,color)
