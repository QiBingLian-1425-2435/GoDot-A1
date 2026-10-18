extends SceneTree

const Model = preload("res://features/match/match_model.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func verify(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func advance(m, seconds: float) -> void:
	for step in ceili(seconds / 0.05):
		m.tick(0.05)

func _run() -> void:
	var m = Model.new()
	m.obstacles.assign(preload("res://worlds/lantern_inn/room.gd").obstacles())
	m.add_player(1, "Human")
	m.add_player(2, "Companion", true)
	m.start_round()
	m._monster_pause = 9999.0
	var human: Dictionary = m.get_player(1)
	var bot: Dictionary = m.get_player(2)
	advance(m, 3.0)
	verify(not bot.bag.is_empty(), "companion automatically collects nearby accessible loot")
	human.pos = Vector2(-8, -4)
	advance(m, 15.0)
	verify(bot.pos.distance_to(human.pos) < 3.8, "companion follows around the actual furniture obstacles")
	human.pos = bot.pos + Vector2(0.7, 0)
	human.status = "downed"
	human.hp = 0.0
	human.down_left = 22.0
	advance(m, 3.6)
	verify(human.status == "alive" and human.hp == 65.0, "companion holds rescue and restores a downed leader")
	human.pos = Model.EXTRACT_POSITION
	advance(m, 19.0)
	verify(human.status == "extracted" and bot.status == "extracted" and m.state.phase == "results", "companion follows extraction and never blocks the end of solo round")
	verify(m.state.total_banked > 0, "companion extraction banks collected items")
	print("COMPANION TEST: %d failures" % failures)
	quit(1 if failures > 0 else 0)
