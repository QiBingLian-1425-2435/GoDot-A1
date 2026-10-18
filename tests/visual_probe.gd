extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://app/main.tscn").instantiate()
	root.add_child(game)
	game.session.start_solo()
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("user://demo_preview.png")
	print("PREVIEW ", error, " ", ProjectSettings.globalize_path("user://demo_preview.png"))
	game.queue_free()
	await process_frame
	quit(error)
