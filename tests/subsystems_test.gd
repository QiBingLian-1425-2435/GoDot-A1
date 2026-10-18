extends SceneTree
## Targeted migration boundaries absent from the original model suite.
const Model = preload("res://features/match/match_model.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func fixture():
	var model = Model.new()
	model.add_player(1, "Host")
	model.add_player(42, "Peer")
	model.start_round()
	model.get_player(42).pos = Vector2(-9, 7)
	return model

func run() -> void:
	var model = fixture()
	var player: Dictionary = model.get_player(1)
	player.pos = Vector2(3, 0)
	model.state.monster.pos = Vector2.ZERO
	model.tick(0.1)
	check(model.state.monster.mode == "chase" and model.state.monster.target == 1, "monster selects visible living target outside safe exit")
	player.pos = Model.EXTRACT_POSITION
	model.tick(0.1)
	check(model.state.monster.mode == "search", "monster searches last seen position after losing target")
	for step in 26:
		model.tick(0.1)
	check(model.state.monster.mode == "patrol", "monster resumes patrol when search expires")
	model = fixture()
	player = model.get_player(1)
	player.pos = Vector2(0.5, 0)
	model.state.monster.pos = Vector2.ZERO
	model.tick(0.1)
	check(player.hp == 66.0, "monster hit reaches the rescue/health subsystem")
	model.tick(0.1)
	check(player.hp == 66.0, "monster cooldown prevents damage every frame")
	player.hp = 1.0
	player.invulnerable = 0.0
	model._monster_hit_cooldown = 0.0
	model.tick(0.1)
	check(player.status == "downed" and player.down_left == Model.BLEED_SECONDS, "lethal monster hit enters timed downed state")
	model.tick(0.1)
	check(model.state.monster.mode == "recover", "monster pauses after downing a player")
	model = fixture()
	model._monster_pause = 999.0
	player = model.get_player(1)
	var peer: Dictionary = model.get_player(42)
	player.pos = Vector2.ZERO
	peer.pos = Vector2(1, 0)
	player.status = "downed"
	player.down_left = Model.BLEED_SECONDS
	for step in 10:
		model.command(42, "interact")
		model.tick(0.1)
	check(player.revive_progress > 0.9, "continuous interaction advances rescue")
	model.command(42, "move", {"direction": Vector2.ZERO, "interact": false})
	model.tick(0.1)
	check(player.revive_progress == 0.0 and player.status == "downed", "releasing interaction resets incomplete rescue")
	model._die(player, "fixture")
	model.command(1, "possession_request", {"target": 42})
	model.command(42, "possession_decline")
	check(peer.request_from == 0 and player.possessing == 0, "declined possession leaves no shared view")
	model.command(1, "possession_request", {"target": 42})
	model.command(42, "possession_accept")
	model.remove_player(42)
	check(player.possessing == 0 and peer.request_from == 0, "target disconnect cleans shared view across rescue and possession")
	var first = fixture()
	var second = fixture()
	first.state.loot[0].value = 999
	check(second.state.loot[0].value == 45 and Model.ITEM_TYPES[0].value == 45, "per-round item instances do not mutate shared definitions or another match")
	print("SUBSYSTEMS_TEST ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
