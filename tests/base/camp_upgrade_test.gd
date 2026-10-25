extends SceneTree
const Texts = preload("res://features/localization/game_text.gd")
const Model=preload("res://features/base/base_model.gd")
const Session=preload("res://app/network/session.gd")
const Main=preload("res://app/main.gd")
const Prediction=preload("res://features/player/local_movement.gd")
var checks:=0
var failures:=0
var folder:="user://camp_test_"+str(Time.get_ticks_usec())
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func fixture():
	var m=Model.new();m.add_player(1,"owner");m.add_player(2,"guest")
	m.stations=[{"kind":"camp_management","pos":Vector2.ZERO},{"kind":"medical","pos":Vector2.ZERO}]
	for p in m.state.players.values():p.pos=Vector2.ZERO
	return m
func supply(m,p,cost):
	p.credits=int(cost.credits)+50;p.bag=m._empty_slots(24)
	for kind in cost.items:m._insert(p.bag,m._item(kind,int(cost.items[kind])))
func upgrade(m,key,level,id:=1):return m.command(id,"camp_upgrade",{"facility":key,"expected_level":level})
func write_json(path:String,data):
	var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
func capture(game,label:String):
	if DisplayServer.get_name()=="headless":return
	for i in range(3):await process_frame
	await RenderingServer.frame_post_draw
	var output:=OS.get_environment("A1_TEST_ARTIFACTS")
	if output.is_empty():output=ProjectSettings.globalize_path("res://artifacts/camp_upgrades")
	DirAccess.make_dir_recursive_absolute(output)
	check(game.get_viewport().get_texture().get_image().save_png(output+"/camp_"+label+".png")==OK,"capture "+label)
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var m=fixture();var p:Dictionary=m.state.players[1]
	check(m.state.camp==m.Camp.initial(),"new camp has no bonuses")
	var total:=0
	for key in m.Camp.DEFS:
		for level in range(3):
			var cost:Dictionary=m.Camp.DEFS[key].costs[level];total+=int(cost.credits)
			for kind in cost.items:total+=int(cost.items[kind])*int(m.Items.definition(kind).buy_price)
			supply(m,p,cost);p.hp=73;p.stamina=42
			check(upgrade(m,key,level),"upgrade "+key+" "+str(level+1))
			check(p.credits==50 and p.bag.all(func(item):return item.is_empty()),"exact upgrade cost")
			check(p.hp==73 and p.stamina==42,"upgrade does not refill current stats")
			check(m.state.players[2].get("max_hp")==p.max_hp and m.state.players[2].get("max_stamina")==p.max_stamina and m.state.players[2].max_weight==p.max_weight,"team receives same bonus")
			var credits:int=p.credits
			check(not upgrade(m,key,level) and p.credits==credits,"stale level cannot charge again")
		check(not upgrade(m,key,3),"max level rejected")
	check(total==56330,"all nine upgrades cost 56330 including bought materials")
	check(p.max_hp==115 and p.max_stamina==115 and p.max_weight==47,"max level attributes")
	for i in range(10):m.Camp.refresh_player(m,p)
	check(p.max_weight==47,"recalculation does not stack bonuses")
	p.equipment.backpack={};m._update_weight(p);check(p.max_weight==31,"backpack removal retains camp bonus")
	p.hp=100;p.bag[0]=m._item("bandage",1)
	check(m.command(1,"use",{"index":0}) and p.hp==115,"healing reaches upgraded hp limit")
	p.hp=100;p.bag[0]=m._item("medical_box",1);m.command(1,"use",{"index":0})
	for i in range(41):m.tick(.1)
	check(p.hp==115,"timed medical box reaches upgraded limit")
	p.stamina=100
	for i in range(20):m.tick(.1)
	check(p.stamina==115,"stamina recovery reaches upgraded limit")
	m.state.infinite_stamina=true;p.stamina=0;m.tick(.1)
	check(p.stamina==115,"infinite stamina respects upgraded maximum")
	p.hp=1;p.stamina=1;check(m.command(1,"rest") and p.hp==115 and p.stamina==115,"medical rest uses upgraded limits")
	m.add_player(3,"late")
	check(m.state.players[3].max_hp==115 and m.state.players[3].max_weight==47,"late player inherits camp")
	var prediction=Prediction.new()
	prediction.solver=func(from,offset):return from+offset
	prediction.confirm(p);prediction.advance(.1,p)
	check(prediction._state.max_stamina==115,"prediction reads upgraded stamina")
	m.state.camp=m.Camp.initial();m.Camp.refresh_all(m);prediction.confirm(p)
	check(p.hp==100 and p.stamina==100 and p.max_weight==28 and prediction._state.max_stamina==100,"lower camp clamps stats and resets prediction cap")
	m=fixture();p=m.state.players[1]
	var cost:Dictionary=m.Camp.DEFS.medical.costs[0]
	supply(m,p,cost)
	var before:Array=p.bag.duplicate(true);var cash:int=p.credits
	for bad in [-1,1,1.5,"0",null]:check(not upgrade(m,"medical",bad) and p.bag==before and p.credits==cash,"invalid level refused "+str(bad))
	p.pos=Vector2(10,0);check(not upgrade(m,"medical",0) and p.bag==before,"distant upgrade refused");p.pos=Vector2.ZERO
	m.state.world="surface";check(not upgrade(m,"medical",0) and p.credits==cash,"field upgrade refused");m.state.world="bunker"
	m.world_ready=false;check(not upgrade(m,"medical",0),"loading upgrade refused");m.world_ready=true
	p.credits=0;check(not upgrade(m,"medical",0) and p.bag==before,"insufficient money is atomic");p.credits=cash
	p.bag[0]={};before=p.bag.duplicate(true);check(not upgrade(m,"medical",0) and p.credits==cash and p.bag==before,"missing material does not consume other resources")
	var session=Session.new();session.model=fixture();session.upgrade_checkpoint=func(_trial):return ERR_CANT_CREATE
	p=session.model.state.players[1];supply(session.model,p,cost);before=p.bag.duplicate(true)
	session.send("camp_upgrade",{"facility":"medical","expected_level":0})
	check(session.model.state.camp.medical==0 and p.bag==before and p.credits==850,"save failure rolls back all assets and level")
	session.upgrade_checkpoint=func(trial):return trial.save_profile(folder+"/solo.json",1)
	session.send("camp_upgrade",{"facility":"medical","expected_level":0})
	check(session.model.state.camp.medical==1 and p.credits==50,"save success publishes upgrade")
	var solo=fixture();check(solo.load_profile(folder+"/solo.json")==OK and solo.state.camp.medical==1 and solo.state.players[1].credits==50,"solo camp persists")
	solo.state.players[1].hp=105;solo.save_profile(folder+"/high_hp.json")
	var high=fixture();check(high.load_profile(folder+"/high_hp.json")==OK and high.state.players[1].hp==105,"profile load preserves health above old 100 ceiling")
	var legacy:Dictionary=solo.Profile.capture(solo,1);write_json(folder+"/legacy.json",legacy)
	check(solo.load_profile(folder+"/legacy.json")==OK and solo.state.camp.medical==0,"old solo profile defaults to unupgraded")
	legacy.camp={"medical":4,"training":0,"logistics":0};write_json(folder+"/bad.json",legacy)
	check(solo.load_profile(folder+"/bad.json")==ERR_FILE_CORRUPT,"invalid saved level rejected")
	check(session.configure_room(folder+"/room.json","owner",func(id):return str(id))==OK and session.model.state.camp.medical==0,"new room does not import personal camp")
	p=session.model.state.players[1];supply(session.model,p,cost);session.send("camp_upgrade",{"facility":"medical","expected_level":0})
	var restored=Session.new()
	check(restored.configure_room(folder+"/room.json","owner",func(id):return str(id))==OK and restored.model.state.camp.medical==1 and restored.model.state.players[1].credits==50,"room reopen restores level and payer assets together")
	var disk:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/room.json"));disk.erase("camp");write_json(folder+"/old_room.json",disk)
	var old=Session.new();check(old.configure_room(folder+"/old_room.json","owner",func(id):return str(id))==OK and old.model.state.camp.medical==0,"old room defaults to unupgraded")
	disk.camp={"medical":0,"training":-1,"logistics":0};write_json(folder+"/bad_room.json",disk)
	check(old.configure_room(folder+"/bad_room.json","owner",func(id):return str(id))==ERR_FILE_CORRUPT,"invalid room camp rejected")
	var good_path:String=session.room_store.path
	var cache_before:Dictionary=session.room_store.profiles.duplicate(true)
	var disk_before:=FileAccess.get_file_as_string(good_path)
	write_json(folder+"/blocked",{})
	session.room_store.path=folder+"/blocked/room.json"
	p=session.model.state.players[1];supply(session.model,p,session.model.Camp.DEFS.training.costs[0]);before=p.bag.duplicate(true);cash=p.credits
	session.send("camp_upgrade",{"facility":"training","expected_level":0})
	check(session.model.state.camp.training==0 and p.bag==before and p.credits==cash and session.room_store.profiles==cache_before and FileAccess.get_file_as_string(good_path)==disk_before,"real filesystem save failure preserves state, cache and prior disk")
	session.room_store.path=good_path
	session.offline();check(session.model.state.camp.medical==0,"leaving host room restores separate personal camp")
	session.free();restored.free();old.free()
	var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game.sound.muted=true;game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game._start_solo()
	var player:Dictionary=game.session.model.state.players[1];player.pos=Vector2(-1,-1.9);supply(game.session.model,player,cost)
	game._refresh_ui();game._update_interaction();game._interact()
	check(Texts.resolve(game.ui._dialog_kind)=="营地建设","E at actual camp terminal opens construction panel")
	var button:Button=game.ui._dialog.get_node("CampUpgrade")
	button.pressed.emit();check(button.text=="确认消耗并升级" and game.session.model.state.camp.medical==0,"first click previews cost only")
	await capture(game,"confirm")
	button.pressed.emit();game._refresh_ui()
	check(game.session.model.state.camp.medical==1 and player.credits==50 and game.ui._bars.hp.max_value==105,"confirmed upgrade changes actual rules and HUD")
	check(button.disabled,"next tier disabled without resources")
	var training_cost:Dictionary=game.session.model.Camp.DEFS.training.costs[0]
	supply(game.session.model,player,training_cost)
	var facilities:ItemList=game.ui._dialog.get_node("CampFacilities")
	facilities.select(1);facilities.item_selected.emit(1);button.pressed.emit()
	player.credits-=1;game._refresh_ui()
	check(button.text=="准备升级" and game.session.model.state.camp.training==0,"changed assets require fresh confirmation")

	game.session.model.state.camp={"medical":3,"training":3,"logistics":3};game.session.model.Camp.refresh_all(game.session.model);game._refresh_ui()
	check(button.text=="已满级" and button.disabled,"max tier UI")
	await capture(game,"max")
	game.session.model.state.world_revision+=1;game._refresh_ui();check(not is_instance_valid(game.ui._dialog),"map change closes upgrade panel")
	game._return_menu()
	game.smoke=false;game.profile_path=folder+"/bad.json";game.legacy_profile_path=folder+"/bad.json"
	var corrupt_before:=FileAccess.get_file_as_string(game.profile_path)
	game._start_solo()
	check(not game.in_game and FileAccess.get_file_as_string(game.profile_path)==corrupt_before,"corrupt solo camp blocks entry without overwriting save")
	game.smoke=true
	game.queue_free();await process_frame;await process_frame
	print("CAMP_UPGRADE checks=",checks," failures=",failures);quit(1 if failures else 0)
