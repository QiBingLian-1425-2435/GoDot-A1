extends SceneTree
## Verifies the F6 map entry creates its own camera without a session.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var error := change_scene_to_file("res://worlds/lantern_inn/room.tscn")
	if error != OK:
		quit(1)
		return
	await create_timer(0.3).timeout
	if current_scene == null or root.get_camera_3d() == null:
		push_error("Map preview has no active camera")
		quit(1)
		return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		error = root.get_texture().get_image().save_png("res://artifacts/map_preview.png")
		if error != OK:
			quit(1)
			return
	print("MAP_PREVIEW_PASS: standalone map and active camera")
	quit(0)
