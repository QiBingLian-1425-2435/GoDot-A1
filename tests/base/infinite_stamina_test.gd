extends SceneTree
const Model = preload("res://features/base/base_model.gd")
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")
func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("INFINITE STAMINA FAIL: " + description)

func run() -> void:
	var model = Model.new(); model.add_player(1,"体力测试鸭")
	var p: Dictionary = model.state.players[1]
	model.state.infinite_stamina = true
	p.stamina = 0.0; p.sprint_exhausted = false
	model.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true}); model.tick(0.1)
	check(p.sprint and is_equal_approx(p.stamina,100.0),"empty stamina can sprint without drain")
	model.command(1,"move",{"direction":Vector2.RIGHT,"roll_seq":1}); model.tick(0.01)
	check(p.roll.active and is_equal_approx(p.stamina,100.0),"empty stamina can roll without drain")
	model.state.infinite_stamina = false
	model.command(1,"move",{"direction":Vector2.RIGHT,"sprint":false}); model.tick(0.1)
	check(not p.infinite_stamina,"disabling setting clears runtime flag")
	print("INFINITE_STAMINA_TEST ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
