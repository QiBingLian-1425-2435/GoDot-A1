extends Control

var map: Control

func _draw() -> void:
	if is_instance_valid(map):map.draw_markers(self)
