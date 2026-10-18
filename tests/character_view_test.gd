extends SceneTree
## Exercise the actual snapshot adapter, both appearances and recovery lifecycle.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)

func run() -> void:
	var game = load("res://app/main.tscn").instantiate()
	root.add_child(game)
	game.session.start_solo()
	game.set_physics_process(false)
	game.session.set_physics_process(false)
	game.session.model._monster_pause = 999.0
	await process_frame
	await process_frame
	var a = game.actors[1]
	var b = game.actors[2]
	check(a.sprite == null and b.sprite == null, "players use meshes instead of picture sprites")
	check(a.model.skeleton != null and b.model.skeleton != null, "both appearances have real skeletons")
	check(not a.model.hooded and b.model.hooded, "short hair and hooded appearances wired")
	check(a.model.animation_tree != b.model.animation_tree, "actors own independent animation trees")
	var p: Dictionary = game.session.model.state.players[1]
	p.moving = true
	p.look = Vector2.LEFT
	p.pos += Vector2(-0.5, 0)
	await create_timer(0.4).timeout
	check((-a.model.basis.z).dot(Vector3.LEFT) > 0.95, "confirmed look turns the 3D model")
	p.status = "downed"
	p.hp = 0.0
	await create_timer(0.2).timeout
	check(a.model.current_action == &"downed", "downed snapshot plays lying pose")
	check(b.model.current_action != &"downed", "downed pose does not contaminate companion")
	p.status = "alive"
	p.hp = 65.0
	await create_timer(0.2).timeout
	check(a.model.current_action == &"get_up", "revived snapshot plays get up")
	p.status = "extracted"
	await process_frame
	await process_frame
	check(not a.visible, "extracted actor hidden")
	game.session.offline()
	game.session.start_solo()
	await process_frame
	await process_frame
	check(game.actors[1].visible, "new round restores visible actor")
	game.queue_free()
	await process_frame
	print("CHARACTER_VIEW_TEST failures=", failures)
	quit(1 if failures else 0)
