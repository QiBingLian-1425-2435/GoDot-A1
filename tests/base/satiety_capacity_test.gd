extends SceneTree
const Model = preload("res://features/base/base_model.gd")
const Main = preload("res://app/main.gd")
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1
func run():
	var m = Model.new()
	m.add_player(1,"owner")
	var p: Dictionary = m.state.players[1]
	var backpack: Dictionary = p.equipment.backpack.duplicate(true)
	for equipped in [false,true]:
		p.equipment.backpack = backpack if equipped else {}
		for pair in [[100,1.0],[50,1.0],[25,.75],[0,.5],[-10,.5],[150,1.0]]:
			p.hunger = pair[0]
			m._update_weight(p)
			check(is_equal_approx(p.max_weight, (44.0 if equipped else 28.0)*pair[1]), "capacity boundary backpack=%s satiety=%s" % [equipped,pair[0]])
	p.hunger=50.0005
	m.tick(.1)
	check(p.hunger<50 and p.max_weight<44,"natural hunger decay updates capacity in same tick")
	p.bag=m._empty_slots(24)
	for i in range(16): p.bag[i]=m._item("gold_statue",1)
	p.bag[16]=m._item("energy_bar",1)
	p.hunger=0
	m.tick(.1)
	check(p.max_weight==22 and p.weight>22 and m._count(p.bag,"gold_statue")==16,"falling capacity retains all carried items")
	m.command(1,"move",{"direction":Vector2.RIGHT,"aim":Vector2.RIGHT})
	m.tick(.1)
	var slow:float=p.velocity.length()
	check(slow<3.7 and slow>0,"hunger-induced overload reduces walking speed")
	check(m.command(1,"use",{"index":16}) and p.max_weight==44,"eating immediately restores carrying capacity")
	m.tick(.1)
	check(is_equal_approx(p.velocity.length(),3.7),"eating removes overload slowdown")
	p.hunger=0;m._update_weight(p)
	m.stations=[{"kind":"medical","pos":p.pos}]
	check(m.command(1,"rest") and p.max_weight==44,"rest restores capacity without waiting for tick")
	p.hunger=25;m._update_weight(p)
	var restored=Model.new();restored.add_player(1,"restored")
	check(m.Profile.apply(restored,m.Profile.capture(m,1),1)==OK and restored.state.players[1].max_weight==33,"loading an existing profile derives capacity from saved satiety")
	var game=Main.new();game.smoke=true;game.elapsed=-10000
	root.add_child(game);game.sound.muted=true;game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game._start_solo()
	var actual:Dictionary=game.session.model.state.players[1]
	actual.hunger=25;game.session.model._update_weight(actual)
	game._refresh_ui();game.ui.toggle_inventory(true)
	check(game.ui._inventory_weight.text.contains("33.0") and game.ui._inventory_weight.text.contains("饥饿"),"inventory shows reduced capacity and hunger reason")
	check(game.ui._inventory_weight.tooltip_text.contains("50%"),"capacity tooltip explains lower bound and recovery")
	if DisplayServer.get_name()!="headless":
		for i in range(3): await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://artifacts")
		check(game.get_viewport().get_texture().get_image().save_png("res://artifacts/satiety_capacity.png")==OK,"visible inventory screenshot")
	actual.hunger=85;game.session.model._update_weight(actual);game._refresh_ui()
	check(not game.ui._inventory_weight.text.contains("饥饿") and game.ui._inventory_weight.text.contains("44.0"),"inventory clears hunger warning when fed")
	game.queue_free();await process_frame;await process_frame
	print("SATIETY_CAPACITY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
