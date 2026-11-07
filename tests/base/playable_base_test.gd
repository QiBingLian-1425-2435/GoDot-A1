extends SceneTree
const Main=preload("res://app/main.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func run():
 var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game._start_solo()
 game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game.sound.muted=true
 await physics_frame;await physics_frame
 var m=game.session.model;var p:Dictionary=m.state.players[1]
 # Flood-fill the rule collision map with player clearance, starting at the spawn.
 var step:=.3;var origin:=Vector2(-11.4,-11.4);var visited:Dictionary={};var queue:Array[Vector2i]=[]
 var cell:Vector2i=Vector2i(((p.pos-origin)/step).round());queue.append(cell);visited[cell]=true
 var cursor:=0
 while cursor<queue.size():
  var current:Vector2i=queue[cursor];cursor+=1
  for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var next:Vector2i=current+direction
   if not visited.has(next) and m._free(origin+Vector2(next)*step):visited[next]=true;queue.append(next)

 check(game.world.get_script().resource_path.ends_with("playable_base.gd"),"new base is production Main world")
 check(m._free(p.pos),"spawn is clear")
 for station in m.stations:
  var reachable:=false
  for c in visited:
   if (origin+Vector2(c)*step).distance_to(station.pos)<.45:reachable=true;break
  check(reachable,"walkable route to: "+station.id)
  check(m._free(station.pos),"station approach is clear: "+station.id)
  p.pos=station.pos;p.aim=Vector2.UP
  game._update_actors(.1);game.vision.update(game,.1);game._update_interaction()
  check(game.nearest.get("id","")==station.id,"E selects correct station: "+station.id)
  match station.kind:
   "camp_management":
    p.credits=2000;m._insert(p.bag,m._item("scrap",4));m._insert(p.bag,m._item("tape",2))
    check(m.command(1,"camp_upgrade",{"facility":"medical","expected_level":0}) and m.state.camp.medical==1,"camp management upgrade")
   "medical":
    p.hp=50;check(m.command(1,"rest") and p.hp==p.max_hp,"medical heals")
   "ammo_supply":check(m.command(1,"resupply_ammo"),"ammo resupply")
   "range":
    m.state.targets[0].hp=0;check(m.command(1,"reset_targets") and m.state.targets[0].hp==100,"training resets")
   "workbench":
    m._insert(p.bag,m._item("scrap",4));check(m.command(1,"craft"),"workbench crafting")
   "trader":check(m.command(1,"buy_ammo"),"merchant purchase")
   "stash":
    game._interact();check(game.ui._stash_access,"warehouse access");game.ui.close_inventory()
 p.pos=Vector2(-1,4)
 var start:=Vector2(0,-10.8);var moved:Vector2=game.player_physics.solve(1,start,Vector2(0,-3))
 check(moved.y> -12,"actual physics blocks gate wall")
 game.camera_zoom=27;game._update_actors(.1)
 for i in range(20):game._update_camera(.1)
 game._refresh_ui();game.ui._toast_label.visible=false
 if DisplayServer.get_name()!="headless":
  for i in range(8):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://artifacts/playable_base_game.png")
 game.queue_free();await process_frame
 print("PLAYABLE_BASE failures=",failures);quit(1 if failures else 0)
