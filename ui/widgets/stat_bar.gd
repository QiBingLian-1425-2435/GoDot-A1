extends Control
## Slim rounded vital bar with a dim track, soft highlight and low-value warning.
## Exposes value/max_value like a ProgressBar so HUD code can assign directly.
var color := Color("cf8375")
var value := 100.0:
	set(v):
		if is_equal_approx(v,value):return
		value=v;queue_redraw()
var max_value := 100.0:
	set(v):
		if is_equal_approx(v,max_value):return
		max_value=v;queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var r := size.y * .5
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, .38)
	track.border_color = Color(1, 1, 1, .06)
	track.set_border_width_all(1)
	track.set_corner_radius_all(int(r))
	draw_style_box(track, Rect2(Vector2.ZERO, size))
	var ratio := clampf(value / maxf(max_value, .001), 0, 1)
	if ratio <= 0: return
	var fill := StyleBoxFlat.new()
	var tint := color
	if ratio < .25: tint = color.lerp(Color("e0574d"), .45)
	fill.bg_color = tint
	fill.set_corner_radius_all(int(r))
	var w := maxf(size.y, size.x * ratio)
	draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(w, size.y)))
	# top sheen
	var sheen := StyleBoxFlat.new()
	sheen.bg_color = Color(1, 1, 1, .18)
	sheen.set_corner_radius_all(int(r))
	draw_style_box(sheen, Rect2(Vector2(1, 1), Vector2(maxf(w - 2, 1), size.y * .42)))
