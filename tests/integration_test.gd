extends SceneTree

var game
var failures:=0
var checks:=0

func _initialize()->void:
	if DisplayServer.get_name() == "headless":
		push_error("integration_test requires a visible window for mouse/keyboard input; use migration_test for headless scene checks")
		quit(1)
		return
	root.size = Vector2i(1600, 1000)
	call_deferred("run")

func check(ok:bool,message:String)->void:
	checks+=1
	if ok:
		print("PASS: "+message)
	else:
		failures+=1
		push_error("FAIL: "+message)

func click_button(text:String)->void:
	var found:Array=[]
	find_buttons(game.hud.root,text,found)
	if found.is_empty():
		check(false,"button exists: "+text)
		return
	var b:Button=found[0]
	check(b.is_visible_in_tree() and not b.disabled,"button actionable: "+text)
	var point:Vector2=b.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new()
	motion.position=point
	root.push_input(motion, true) # Coordinates above are already viewport-local, independent of window stretch.
	for pressed in [true,false]:
		var e:=InputEventMouseButton.new()
		e.position=point
		e.button_index=MOUSE_BUTTON_LEFT
		e.pressed=pressed
		root.push_input(e, true)
		await process_frame

func find_buttons(node:Node,text:String,out:Array)->void:
	if node is Button and node.text==text:
		out.append(node)
	for child in node.get_children():
		find_buttons(child,text,out)

func key(code:Key,pressed:bool)->void:
	var e:=InputEventKey.new()
	e.keycode=code
	e.physical_keycode=code
	e.pressed=pressed
	Input.parse_input_event(e)

func screenshot(file:String)->void:
	if DisplayServer.get_name()=="headless":
		return
	await RenderingServer.frame_post_draw
	var error:=root.get_texture().get_image().save_png("res://artifacts/"+file)
	check(error==OK,"captured "+file)

func run()->void:
	game=load("res://app/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.3).timeout
	check(game.session.model.state.phase=="lobby","startup shows actual lobby")
	await screenshot("lobby.png")
	await click_button("点亮提灯 · 单人出发")
	await create_timer(0.2).timeout
	check(game.session.model.state.phase=="raid","mouse click starts playable solo raid")
	if game.session.model.state.phase != "raid":
		game.queue_free()
		quit(1)
		return
	check(game.actors.size()==2,"actual player and AI visuals instantiated")
	var model=game.session.model
	model._monster_pause=999.0
	var me:Dictionary=model.state.players[1]
	model.state.players[2].bot=false
	me.pos=Vector2(-4,4)
	await create_timer(0.1).timeout
	var before:Vector2=me.pos
	key(KEY_D,true)
	await create_timer(0.4).timeout
	key(KEY_D,false)
	await create_timer(0.1).timeout
	check(me.pos.distance_to(before)>0.7,"WASD input traverses actual main scene")
	me.pos=model.state.loot[0].pos
	await create_timer(0.1).timeout
	key(KEY_E,true)
	await process_frame
	key(KEY_E,false)
	await create_timer(0.2).timeout
	check(me.bag.size()==1,"E pickup input updates authoritative bag")
	check(game.hud.item_box.get_child_count()==1,"HUD renders inventory row")
	await click_button("↓")
	await create_timer(0.2).timeout
	check(me.bag.is_empty(),"UI drop button transfers ground item")
	key(KEY_E,true)
	await process_frame
	key(KEY_E,false)
	await create_timer(0.15).timeout
	key(KEY_TAB,true)
	key(KEY_TAB,false)
	await create_timer(0.15).timeout
	check(game.hud.tab=="team","Tab switches to teammate controls")
	key(KEY_TAB,true)
	key(KEY_TAB,false)
	me.pos=Vector2(0.5,1.2)
	model.state.players[2].pos=Vector2(-1,2.3)
	await create_timer(0.3).timeout
	await screenshot("demo.png")
	key(KEY_F1,true)
	key(KEY_F1,false)
	await process_frame
	check(game.hud.help_panel.visible,"F1 opens readable manual")
	await click_button("我知道了 · 继续旅途")
	check(not game.hud.help_panel.visible,"manual dismiss button restores scene")
	model._die(me,"integration test death")
	await create_timer(0.2).timeout
	game.hud.set_tab("team")
	await create_timer(0.2).timeout
	await click_button("请求附身")
	check(model.state.players[2].request_from==1,"possession UI requests consent")
	model.command(2,"possession_accept")
	await create_timer(0.2).timeout
	check(game.hud.detach_button.visible,"accepted spectator can access detach control")
	await click_button("解除共享视角")
	check(me.possessing==0,"spectator detach UI works")
	model.state.players[2].pos=Vector2(8,5.5)
	await create_timer(4.3).timeout
	check(model.state.phase=="results","last acting player extraction shows results")
	check(game.hud.result.visible,"results overlay visible")
	await screenshot("results.png")
	await click_button("再探一局")
	await create_timer(0.2).timeout
	check(model.state.phase=="raid" and model.state.round==2,"replay button starts clean second round")
	check(model.state.corpses.is_empty(),"replay clears rendered corpses")
	print("INTEGRATION_TEST ",checks," checks; ",failures," failures")
	game.queue_free()
	await process_frame
	quit(1 if failures>0 else 0)
