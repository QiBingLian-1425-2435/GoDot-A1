extends SceneTree
const Session=preload("res://app/network/session.gd")
const PORT=29987
var session
var client:=false
var child:=-1
var failures:=0
func _initialize():
	client="--client" in OS.get_cmdline_user_args();Engine.max_fps=60;call_deferred("run")
func check(ok:bool,label:String):
	print("PASS: " if ok else "FAIL: ","client " if client else "host ",label)
	if not ok:failures+=1
func wait_for(test:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+12000
	while not test.call() and Time.get_ticks_msec()<deadline:await process_frame
	return test.call()
func player()->Dictionary:return session.model.state.players.get(session.local_id,{})
func run():
	session=Session.new();root.add_child(session)
	if client:
		check(session.join("127.0.0.1",PORT)==OK,"connect")
		var ready:=await wait_for(func():return session.model.state.get("enemies",{}).size()==10)
		check(ready,"hostile state received")
		if ready:
			check(await wait_for(func():return player().get("hp",100)<100),"host chase and melee damage reach guest")
			check(session._received_enemy_serial>0 and Vector2(session.model.state.enemies[1].pos).length()>1,"compact enemy movement arrives over real transport")
			check(await wait_for(func():return session._enemy_serials.size()==10),"all ten enemies receive batched motion over real transport")
			for i in range(3):
				var direction:Vector2=(session.model.state.enemies[1].pos-player().pos).normalized()
				session.send("move",{"direction":Vector2.ZERO,"aim":direction})
				await create_timer(.12).timeout
				session.send("fire",{"enemy_hp":0,"damage":9999})
				if i==0:
					check(await wait_for(func():
						var e:Dictionary=session.model.state.enemies[1]
						return e.mode=="stagger" and Vector2(e.velocity).is_zero_approx()
					),"host confirms gun pause without knockback over real transport")
				await create_timer(.18).timeout
			check(await wait_for(func():return session.model.state.enemies[1].hp==0),"remote shots kill hostile on host and synchronize death")
			check(player().ammo==17,"exactly three real rifle rounds consumed")
			session.send("hold_throwable",{"index":-1})
			check(await wait_for(func():return session.model.state.get("zombie_stage",0)==2),"host prepares melee encounter")
			session.send("move",{"aim":Vector2.UP,"ads":true});await create_timer(.12).timeout;session.send("fire")
			check(await wait_for(func():
				var e:Dictionary=session.model.state.enemies.get(1,{})
				return not e.is_empty() and e.hp==76 and e.mode=="stagger" and Vector2(e.velocity).dot(Vector2(e.pos)-Vector2(player().pos))>0
			),"remote melee damages, staggers and knocks zombie away")
			check(await wait_for(func():return session.model.state.world=="bunker"),"host leaves city")
			check(session.model.state.enemies.is_empty(),"client clears old city zombies")
		var f=FileAccess.open("user://city_zombie_network_result.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures}));f.close()
	else:
		DirAccess.remove_absolute("user://city_zombie_network_result.json")
		check(session.host(PORT)==OK,"listen")
		child=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",ProjectSettings.globalize_path("res://artifacts/city_zombie_network_client.log"),"--script","res://tests/base/city_zombie_network_test.gd","--","--client"])
		var joined:=await wait_for(func():return session.model.state.players.size()==2)
		check(joined,"guest admitted")
		if joined:
			var m=session.model;m.enemy_sight=func(_a,_b):return true
			m.enemy_move=func(_id,at,offset):return at+Vector3(offset.x,0,offset.y)
			m.enemy_push=m.enemy_move
			m.state.world="city";m.state.world_revision+=1;m.state.players[1].pos=Vector2(20,20)
			for id in m.state.players:
				if id!=1:m.state.players[id].pos=Vector2(0,-4);m.state.players[id].height=0
			m.state.enemies[1]=m.Enemies.create_zombie(1,Vector3.ZERO,Vector2.UP);m.state.enemies_seeded=true
			for id in range(2,11):m.state.enemies[id]=m.Enemies.create_zombie(id,Vector3(100+id*8,0,100),Vector2.UP)
			session._broadcast_snapshot(true)
			var budget_ok:=true
			for batch in session._enemy_batches():budget_ok=budget_ok and var_to_bytes([batch,1,1,1]).size()<1200
			check(budget_ok,"all hostile packets stay below transport budget")
		if joined:
			check(await wait_for(func():return session.model.state.enemies[1].hp==0),"host observes remote kill")
			var m=session.model
			check(await wait_for(func():
				for id in m.state.players:
					if id!=1 and m.state.players[id].has("held_throwable"):return true
				return false
			),"client acknowledged gun result before next encounter")
			m.state.enemies[1]=m.Enemies.create_zombie(1,Vector3.ZERO,Vector2.UP)
			for id in m.state.players:
				if id==1:continue
				var p:Dictionary=m.state.players[id];p.pos=Vector2(0,1);p.height=0;p.fire_timer=0;p.equipment.weapon=m._item("baton",1);p.ammo=0
			m.state.zombie_stage=2;session._broadcast_snapshot(true)
			check(await wait_for(func():return m.state.enemies[1].hp==76),"host confirms melee damage")
			await create_timer(.5).timeout
			preload("res://features/exploration/world_travel.gd").enter_world(m,"bunker",Vector3.ZERO);session._broadcast_snapshot(true)
		var done:=await wait_for(func():return FileAccess.file_exists("user://city_zombie_network_result.json"))
		check(done,"remote report received")
		if done:check(int(JSON.parse_string(FileAccess.get_file_as_string("user://city_zombie_network_result.json")).failures)==0,"all remote assertions pass")
		if child>0 and OS.is_process_running(child):OS.kill(child)
	session.offline();session.queue_free();await process_frame
	print("CITY_ZOMBIE_NETWORK failures=",failures);quit(1 if failures else 0)
