extends SceneTree
const Model=preload("res://features/base/base_model.gd")
const Main=preload("res://app/main.gd")
const Texts=preload("res://features/localization/game_text.gd")
var checks:=0
var failures:=0
class LootWorld extends Node3D:
	func loot_target(_uid: String) -> Dictionary:
		var excluded: Array[RID]=[]
		return {"points":[Vector3(-1,.5,4)],"exclude":excluded,"bounds":AABB(Vector3(-1.4,0,3.6),Vector3(.8,.7,.8))}
func _initialize():Engine.max_fps=60;call_deferred("run")
func check(ok: bool, label: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func advance(m, seconds: float):
	for i in range(ceili(seconds/.1)):m.tick(.1)
func render(game, name: String):
	game._update_actors(.1);game._update_camera(1);game.vision.update(game,.1)
	game.container_marks.update(game);game._update_interaction();game._refresh_ui()
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/base_tests"))
	check(root.get_texture().get_image().save_png("res://artifacts/base_tests/container_marks_"+name+".png")==OK,"capture "+name)
func run():
	var m=Model.new();m.add_player(1,"host");m.add_player(2,"guest");m.state.world="surface"
	m.stations=[{"kind":"loot","uid":"box","world":"surface","pos":Vector2.ZERO,"height":0,"locked":true}]
	m.loot_reachable=func(_uid,_from):return true
	var p: Dictionary=m.state.players[1];var q: Dictionary=m.state.players[2]
	p.pos=Vector2.ZERO;q.pos=Vector2.ZERO;p.bag=m._empty_slots(24);q.bag=m._empty_slots(24)
	p.bag[0]=m._item("lockpick",2)
	check(m.Loot.status(m.state,"box")=="unsearched","unopened box has no searched marker")
	check(not m.command(1,"loot_view",{"uid":"box"}) and m.state.containers.is_empty(),"view cannot create loot or bypass first lock")
	check(m.command(1,"search",{"uid":"box"}),"first search starts once")
	var box: Dictionary=m.state.containers.box;var original: Array=box.items.duplicate(true)
	check(m.Loot.status(m.state,"box")=="searching","started box immediately marked searching")
	m.tick(.1);var progress: float=box.progress;var next_uid: int=m._next_uid
	check(not m.command(1,"search",{"uid":"box"}) and not m.command(2,"search",{"uid":"box"}),"host rejects duplicate searches from both players")
	check(not m.command(1,"use",{"index":0}) and m._count(p.bag,"lockpick")==1,"using another lockpick cannot restart an existing box")
	check(box.items==original and box.progress==progress and m._next_uid==next_uid and m._count(p.bag,"lockpick")==1,"rejected searches cannot regenerate loot, restart time or consume key")
	check(m.command(2,"loot_view",{"uid":"box"}) and box.searcher==1,"teammate views original search without a second timer")
	m.command(1,"loot_close");m.command(2,"loot_close")
	check(m.Loot.status(m.state,"box")=="partial","closed unfinished search retains its marker")
	check(m.command(1,"loot_view",{"uid":"box"}),"view resumes original incomplete progress")
	advance(m,10)
	check(m.Loot.status(m.state,"box")=="searched" and box.revealed==box.items.size(),"completed search gets searched marker")
	m.command(1,"loot_close")
	check(not m.command(1,"search",{"uid":"box"}) and m.command(2,"loot_view",{"uid":"box"}),"completed box rejects searching but permits remaining-loot view")
	check(m.command(2,"loot_take",{"uid":"box","index":-1}) and m.Loot.status(m.state,"box")=="empty","taking remaining items changes marker to empty")
	var after: Dictionary=box.duplicate(true)
	m.WorldTravel.enter_world(m,"bunker",Vector3.ZERO);m.WorldTravel.enter_world(m,"surface",Vector3.ZERO)
	check(m.state.containers.box==after and m.Loot.status(m.state,"box")=="empty","map round trip keeps emptied box and marker")
	check(not m.command(1,"search",{"uid":"box"}) and m._next_uid==next_uid,"map change cannot reroll searched box")
	check(m.state.enemies.is_empty() and not m.state.enemies_seeded,"enemy encounter refresh remains independent")
	m.state.containers.legacy=true
	check(m.Loot.status(m.state,"legacy")=="empty","old exhausted boolean state stays searched and empty")

	Texts.set_locale("zh_cn",false)
	var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game._start_solo()
	var fixture=LootWorld.new();game.add_child(fixture);game.world=fixture
	var model=game.session.model;var gp: Dictionary=model.state.players[1]
	model.stations=[{"kind":"loot","uid":"ui_box","world":"bunker","pos":gp.pos,"height":0,"locked":false}]
	model.loot_reachable=func(_uid,_from):return true
	await render(game,"unsearched")
	check(game.container_marks.markers.is_empty() and game.nearest.kind=="loot","unsearched box offers first search without marker")
	game._interact();await render(game,"searching")
	check(game.nearest.kind=="loot_view" and game.container_marks.markers.ui_box.text==Texts.resolve("⟦loot_marks.searching⟧"),"actual first interaction changes prompt to view and adds world marker")
	advance(model,10);await render(game,"searched")
	check(game.container_marks.markers.ui_box.text==Texts.resolve("⟦loot_marks.searched⟧"),"completed marker appears in actual scene")
	game.ui.close_inventory();await render(game,"searched_world");game._interact()
	check(gp.loot_uid=="ui_box","E reopens existing remaining items through view intent")
	model.command(1,"loot_take",{"uid":"ui_box","index":-1});await render(game,"empty")
	check(game.container_marks.markers.ui_box.text==Texts.resolve("⟦loot_marks.empty⟧"),"empty marker updates after real inventory transfer")
	game.ui.close_inventory();await render(game,"empty_world")
	game.vision.enabled=true;game.vision.omniscient=false;game.vision.observer=Vector3(100,0,100)
	game.container_marks.update(game)
	check(not game.container_marks.markers.ui_box.visible,"searched marker cannot reveal a box outside local vision")
	Texts.set_locale("en",false);await render(game,"english")
	check(game.container_marks.markers.ui_box.text==Texts.resolve("⟦loot_marks.empty⟧"),"world marker updates with selected language")
	game._return_menu();check(game.container_marks.markers.is_empty(),"leaving clears local marker nodes")
	game.queue_free();await process_frame;await process_frame
	print("CONTAINER_MARKS checks=",checks," failures=",failures);quit(1 if failures else 0)
