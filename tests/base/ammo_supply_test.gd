extends SceneTree
const Model = preload("res://features/base/base_model.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var model = Model.new()
	model.add_player(1,"host"); model.add_player(2,"client")
	model.stations = [{"kind":"ammo_supply","pos":Vector2(7.2,2.7)}]
	var p: Dictionary = model.state.players[2]
	check(not model.command(2,"resupply_ammo"),"reject distant player")
	p.pos = Vector2(7.2,2.7)
	model._consume(p.bag,"ammo",60)
	var credits: int = p.credits
	var magazine: int = p.ammo
	check(model.command(2,"resupply_ammo"),"empty reserve can refill")
	check(model._count(p.bag,"ammo") == 120,"reserve reaches 120")
	for item in p.bag:
		check(item.is_empty() or item.kind != "ammo" or item.count <= 60,"respect ammo stack limit")
	check(p.credits == credits and p.ammo == magazine,"free reserve only; reload remains separate")
	check(model._count(model.state.players[1].bag,"ammo") == 60,"other player unchanged")
	check(not model.command(2,"resupply_ammo") and model._count(p.bag,"ammo") == 120,"repeat does not overflow")
	model._consume(p.bag,"ammo",17)
	check(model.command(2,"resupply_ammo") and model._count(p.bag,"ammo") == 120,"partial stacks topped up")
	check(model.command(2,"reload"),"can reload supplied rounds")
	for i in range(20): model.tick(0.1)
	check(p.ammo == 30 and model._count(p.bag,"ammo") == 110,"reload consumes supplied reserve")
	for i in range(p.bag.size()): p.bag[i] = model._item("scrap",20)
	p.bag[0] = model._item("ammo",59)
	var before: Array = p.bag.duplicate(true)
	check(not model.command(2,"resupply_ammo") and p.bag == before,"full bag failure is atomic even with partial stack space")
	print("AMMO_SUPPLY_TEST failures=",failures)
	quit(0 if failures == 0 else 1)
