extends SceneTree
const Model = preload("res://features/base/base_model.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1
func _initialize() -> void:
	var m = Model.new()
	m.state.camp.medical = 3
	m.state.camp.training = 3
	for id in [1, 2]:
		m.add_player(id, "tester")
		var p: Dictionary = m.state.players[id]
		p.hp = 10.0; p.stamina = 5.0; p.hunger = 0.0; p.thirst = 2.0; p.san = 3.0
	m.tick(0.1)
	for p in m.state.players.values():
		check(p.hp == 115 and p.stamina == 115 and p.hunger == 100 and p.thirst == 100 and p.san == 100, "camp restores every living member to upgraded limits")
		check(p.max_weight == 44, "satiety restores carrying capacity in same tick")
	m.command(1, "move", {"direction": Vector2.RIGHT, "sprint": true})
	m.tick(0.1)
	check(m.state.players[1].stamina == 115, "camp keeps stamina full while sprinting")
	m.state.world = "ground_zero"
	var p: Dictionary = m.state.players[1]
	p.hp = 10.0; p.stamina = 5.0; p.hunger = 25.0; p.thirst = 20.0; p.san = 30.0
	m.tick(0.1)
	check(p.hp == 10 and p.san == 30 and p.hunger < 25 and p.thirst < 20 and p.stamina < 115, "exploration retains damage and survival consumption")
	m.state.world = "bunker"
	m.tick(0.1)
	check(p.hp == 115 and p.hunger == 100 and p.san == 100, "return to camp restores automatically")
	m.Souls.die(m, p)
	m.tick(0.1)
	check(p.life == "soul" and p.hp == 0, "recovery preserves soul and corpse rules")
	print("CAMP_RECOVERY failures=", failures)
	quit(1 if failures else 0)
