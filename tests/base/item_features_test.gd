extends SceneTree
const Model=preload("res://features/base/base_model.gd")
const Items=preload("res://features/inventory/item_catalog.gd")
const Trade=preload("res://features/inventory/item_trade.gd")
const Field=preload("res://features/exploration/field_items.gd")
const Main=preload("res://app/main.gd")
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func fixture():
	var m=Model.new();m.add_player(1,"owner");m.add_player(2,"guest")
	m.stations=[{"kind":"trader","pos":Vector2.ZERO},{"kind":"workbench","pos":Vector2.ZERO}]
	m.state.players[1].pos=Vector2.ZERO
	return m
func fill(m,p,kind:String,count:=1):
	p.bag=m._empty_slots(24);p.bag[0]=m._item(kind,count)
func press_text(node:Node,text:String) -> bool:
	if node is Button and node.text==text:node.pressed.emit();return true
	for child in node.get_children():
		if press_text(child,text):return true
	return false
func capture(game,name:String):
	if DisplayServer.get_name()=="headless":return
	for i in range(3):await process_frame
	await RenderingServer.frame_post_draw
	var folder:=OS.get_environment("A1_TEST_ARTIFACTS")
	if folder.is_empty():folder=ProjectSettings.globalize_path("res://artifacts")
	DirAccess.make_dir_recursive_absolute(folder)
	check(game.get_viewport().get_texture().get_image().save_png(folder+"/items_"+name+".png")==OK,"screenshot "+name)
func run():
	check(Items.DEFS.size()==26,"all twenty design items plus six original equipment/ammo definitions")
	for pair in [[99,0],[100,1],[299,1],[300,2],[999,2],[1000,3],[2999,3],[3000,4],[9999,4],[10000,5]]:check(Items.tier(pair[0])==pair[1],"value boundary "+str(pair[0]))
	check(Items.definition("helmet").category=="helmet" and Items.definition("helmet").item_type=="equipment","equipment slots stay compatible with type classification")
	check(Items.definition("gold_statue").rarity==4 and Items.definition("encrypted_core").rarity==5,"gold/red valuables")
	for kind in Trade.RECIPES:
		var input_cost:=0
		for material in Trade.RECIPES[kind]:input_cost+=int(Items.definition(material).buy_price)*int(Trade.RECIPES[kind][material])
		check(input_cost>=int(Items.definition(kind).value),"no buy/craft/sell money loop: "+kind)
	var m=fixture();var p:Dictionary=m.state.players[1]
	p.credits=10000;var cash:int=p.credits
	check(m.command(1,"buy",{"kind":"juice","count":1,"price":0}) and p.credits==cash-360,"host derives buy price instead of trusting payload")
	check(m.command(1,"buy",{"kind":"helmet","count":1}) and m._count(p.bag,"helmet")==1,"basic equipment can be repurchased after sale")
	check(not m.command(1,"buy",{"kind":"gold_statue","count":1}),"valuable trophies cannot be purchased")
	check(not m.command(1,"buy",{"kind":"water","count":-1}),"negative purchase rejected")
	p.pos=Vector2(10,0);cash=p.credits
	check(not m.command(1,"buy",{"kind":"water","count":1}) and p.credits==cash,"distant purchase does not debit")
	p.pos=Vector2.ZERO;fill(m,p,"encrypted_core");cash=p.credits
	check(not m.command(1,"sell",{"count":1,"index":0,"uid":"forged"}) and p.credits==cash,"stale/forged item UID cannot sell another item")
	check(m.command(1,"sell",{"count":1,"index":0,"uid":p.bag[0].uid}) and p.credits==cash+18000 and p.bag[0].is_empty(),"selling one red trophy removes it exactly once")
	for kind in ["scrap","tape","battery","circuit_board","optical_parts"]:
		fill(m,p,kind,3);p.credits=100000;cash=p.credits
		var uid:String=p.bag[0].uid
		check(m.command(1,"sell",{"index":0,"uid":uid,"count":2}) and p.bag[0].count==1 and p.bag[0].uid==uid and p.credits==cash+2*int(Items.definition(kind).value),"partial material sale preserves UID: "+kind)
		check(m.command(1,"buy",{"kind":kind,"count":2}) and m._count(p.bag,kind)==3,"material purchase: "+kind)
		var unchanged:Array=p.bag.duplicate(true);var funds:int=p.credits
		for invalid in [0,-1,4,1.5,"1",null]:
			check(not m.command(1,"sell",{"index":0,"uid":uid,"count":invalid}) and p.bag==unchanged and p.credits==funds,"invalid sale atomic: "+str(invalid))
		p.credits=999999
		check(not m.command(1,"sell",{"index":0,"uid":uid,"count":1}) and p.bag==unchanged and p.credits==999999,"credit ceiling rejects sale")
		p.credits=funds;p.pos=Vector2(10,0)
		check(not m.command(1,"sell",{"index":0,"uid":uid,"count":1}) and p.bag==unchanged and p.credits==funds,"distant sale rejected")
		p.pos=Vector2.ZERO;m.state.world="surface"
		check(not m.command(1,"sell",{"index":0,"uid":uid,"count":1}) and not m.command(1,"buy",{"kind":kind,"count":1}) and p.bag==unchanged and p.credits==funds,"field trade rejected")
		m.state.world="bunker"
		check(m.command(1,"sell",{"index":0,"uid":uid,"count":3}) and p.bag[0].is_empty(),"full material sale")
	fill(m,p,"ammo",60);cash=p.credits
	check(not m.command(1,"sell",{"count":1,"index":0,"uid":p.bag[0].uid}) and p.credits==cash and p.bag[0].count==60,"free training ammunition cannot be sold")
	p.bag=m._empty_slots(24)
	for i in range(24):p.bag[i]=m._item("gold_statue",1)
	var before:Array=p.bag.duplicate(true);cash=p.credits
	check(not m.command(1,"buy",{"kind":"water","count":1}) and p.bag==before and p.credits==cash,"full bag purchase is atomic")
	fill(m,p,"scrap",10);p.bag[1]=m._item("tape",2);before=p.bag.duplicate(true)
	check(not m.command(1,"craft_item",{"kind":"lockpick"}) and p.bag==before,"missing ingredient consumes nothing")
	p.bag[1].count=3
	check(m.command(1,"craft_item",{"kind":"lockpick"}) and m._count(p.bag,"lockpick")==1 and m._count(p.bag,"scrap")==0,"tool crafting uses its exact recipe")
	fill(m,p,"biscuits");p.hunger=50;p.thirst=20
	check(m.command(1,"use",{"index":0}) and p.hunger==80 and p.thirst==15,"food applies both positive and negative effects")
	fill(m,p,"juice");p.hunger=90;p.thirst=90
	check(m.command(1,"use",{"index":0}) and p.hunger==100 and p.thirst==100,"multi-stat juice clamps at 100")
	fill(m,p,"energy_bar");p.hunger=20;p.stamina=30
	check(m.command(1,"use",{"index":0}) and p.hunger==75 and p.stamina==50,"energy bar restores hunger and stamina")
	fill(m,p,"water");p.thirst=100
	check(not m.command(1,"use",{"index":0}) and not p.bag[0].is_empty(),"full stat refuses consumable without losing it")
	fill(m,p,"medical_box");p.hp=10
	check(m.command(1,"use",{"index":0}) and p.hp==10 and not p.pending_use.is_empty(),"professional medical box starts a timed heal")
	for i in range(41):m.tick(.1)
	check(p.hp==90 and p.pending_use.is_empty(),"professional medical box heals after four host seconds")
	fill(m,p,"smoke_grenade",3)
	m.field_placement=func(_from,_to):return {}
	check(not m.command(1,"use",{"index":0}) and p.bag[0].count==3,"blocked placement does not consume tool")
	m.field_placement=Callable()
	check(m.command(1,"use",{"index":0}) and m.state.field_effects.size()==1,"smoke consumes one item and creates confirmed effect")
	check(Field.blocks_sight(m.state.field_effects,Vector3(0,1,0),Vector3(0,1,-8)),"smoke blocks target sight")
	check(not Field.blocks_sight(m.state.field_effects,Vector3(20,1,0),Vector3(20,1,-8)),"smoke does not block a ray that misses it")
	check(m.command(1,"use",{"index":0}) and not m.command(1,"use",{"index":0}) and p.bag[0].count==1,"per-player concurrent effect cap preserves rejected item")
	for i in range(81):m.tick(.1)
	check(m.state.field_effects.is_empty(),"smoke expires at eight host seconds")
	fill(m,p,"beacon");check(m.command(1,"use",{"index":0}) and m.state.field_effects[0].kind=="beacon","beacon placement")
	fill(m,p,"glowstick");check(m.command(1,"use",{"index":0}) and m.state.field_effects.size()==2,"lightstick placement")
	m.state.field_effects=[];m.state.world="surface"
	var station:Dictionary={"kind":"loot","uid":"loot_test","pos":Vector2(1,0),"height":0.0,"world":"surface","locked":true}
	m.stations=[station];fill(m,p,"lockpick",2)
	m.loot_reachable=func(_uid,_from):return false
	check(not m.command(1,"search",{"uid":"loot_test"}) and p.bag[0].count==2,"wall/obscured container rejects without spending lockpick")
	m.loot_reachable=func(_uid,_from):return true
	p.height=4
	check(not m.command(1,"search",{"uid":"loot_test"}),"different floor cannot unlock container")
	p.height=0
	check(m.command(1,"use",{"index":0}) and p.bag[0].count==1 and m.state.containers.has("loot_test") and p.loot_uid=="loot_test","using lockpick opens reachable locked container for timed search")
	var guest:Dictionary=m.state.players[2];guest.pos=Vector2.ZERO;guest.bag[0]=m._item("lockpick",1)
	check(m.command(2,"search",{"uid":"loot_test"}) and guest.bag[0].count==1 and m.state.drops.is_empty(),"second player shares existing contents without spending another lockpick")
	m.state.world="bunker";m.state.field_effects=[];fill(m,p,"gold_statue");p.bag[1]=m._item("encrypted_core",1);p.bag[2]=m._item("energy_bar",2)
	var inventory_value:=0
	for item in p.bag:
		if not item.is_empty():inventory_value+=int(Items.definition(item.kind).value)*int(item.count)
	check(m.command(1,"sort",{"container":"bag","mode":"value"}) and p.bag[0].kind=="encrypted_core","sort by total stack value")
	check(m.command(1,"sort",{"container":"bag","mode":"density"}) and p.bag[0].kind=="encrypted_core","sort by value per kilogram")
	var captured:Dictionary=m.Profile.capture(m,1)
	var loaded=fixture();check(loaded.Profile.apply(loaded,captured,1)==OK and loaded._count(loaded.state.players[1].bag,"encrypted_core")==1,"new items survive profile save/load with fresh UIDs")
	var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game.sound.muted=true;game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game._start_solo()
	var player:Dictionary=game.session.model.state.players[1];player.bag=game.session.model._empty_slots(24)
	var kinds:Array=[]
	for kind in Items.DEFS:
		if Items.definition(kind).item_type!="equipment":kinds.append(kind)
	for i in range(kinds.size()):player.bag[i]=game.session.model._item(kinds[i],1)
	game._refresh_ui();game.ui.toggle_inventory(true)
	game.ui._toast_label.visible=false
	game.ui._inspect(player.bag[kinds.find("encrypted_core")])
	check(game.ui._details_name.text.contains("至宝") and game.ui._details_text.text.contains("18000"),"inventory shows rarity, type and value")
	await capture(game,"inventory")
	var filter=game.ui._inventory.find_child("ItemTypeFilter",true,false)
	filter.select(4);filter.item_selected.emit(4)
	var all_materials:=true
	for slot in game.ui._bag_slots:
		if not slot.item.is_empty() and slot.definition.item_type!="material":all_materials=false
	check(all_materials and game.ui._bag_slots[0].slot_index>0,"type filter shows materials with original inventory indices")
	filter.select(0);filter.item_selected.emit(0);game.ui.close_inventory()
	player.pos=Vector2(-5,-2.6);player.credits=10000;game._update_interaction();game._interact()
	check(game.ui._dialog_kind=="基地商人","E at actual trader opens shop")
	var shop=game.ui._dialog.find_child("ShopItems",true,false)
	for i in range(shop.item_count):
		if shop.get_item_metadata(i)=="glowstick":shop.select(i);shop.item_selected.emit(i)
	var existing:int=game.session.model._count(player.bag,"glowstick")
	check(press_text(game.ui._dialog,"购买1件") and game.session.model._count(player.bag,"glowstick")==existing+1,"shop button buys real item through session")
	game._refresh_ui();check(game.ui._shop_details.text.contains("9550"),"shop funds update after host confirmation")
	await capture(game,"shop")
	game.ui._close_dialog();player.pos=Vector2(-9,2.2);game._update_interaction();game._interact()
	check(game.ui._dialog_kind=="工作台制作","E at workbench opens recipe list")
	await capture(game,"recipes")
	game.ui._close_dialog();player.pos=Vector2(-1,4);player.aim=Vector2.UP
	var idx:=kinds.find("glowstick");game.session.send("use",{"index":idx});game.field_item_view.update(game)
	check(game.field_item_view.nodes.size()==1,"confirmed lightstick produces a real light node")
	game._return_menu();check(game.field_item_view.nodes.is_empty(),"leaving room clears field visuals")
	game.queue_free();await process_frame;await process_frame
	print("ITEM_FEATURES checks=",checks," failures=",failures);quit(1 if failures else 0)
