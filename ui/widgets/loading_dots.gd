extends Control
## Three pulsing amber dots for loading cards.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _process(_delta: float) -> void:
	if is_visible_in_tree(): queue_redraw()
func _draw() -> void:
	var t := Time.get_ticks_msec() * .004
	for i in range(3):
		var k := .5 + .5 * sin(t - i * .9)
		draw_circle(Vector2(size.x * .5 + (i - 1) * 18, size.y * .5), 4.0 + k * 2.0, Color(.94, .77, .42, .35 + .65 * k))
