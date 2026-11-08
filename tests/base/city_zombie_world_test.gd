extends SceneTree
const Main=preload("res://app/main.gd")
var game
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1;print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func travel(destination:String):
 var m=game.session.model
 for route in m.stations:
  if route.get("destination","")!=destination:continue
  var p:Dictionary=m.state.players[1];p.pos=route.pos;p.height=route.get("height",0)
  check(m.command(1,"travel",{"route":route.uid}),"real route travel "+destination)
  game._sync_world()
  while game.world_loading:await process_frame
  await physics_frame;await physics_frame
  game.enemy_director.update(game,.016)
  return
 check(false,"missing route "+destination)
func run():
 game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game._start_solo();game.sound.muted=true
 game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false)
 var m=game.session.model;var first:Array[Vector2]=[]
 for visit in 2:
  await travel("city")
  check(m.state.enemies.size()==10 and m.state.enemies_seeded,"city seeds exactly ten zombies visit "+str(visit))
  var valid:=true;var points:Array[Vector2]=[];var probe=game.enemy_director.body_for(-1)
  for e in m.state.enemies.values():
   valid=valid and e.get("kind","")=="zombie" and e.hp==100 and probe.is_clear(m.Enemies.at(e)) and m.bounds.has_point(e.pos)
   points.append(e.pos)
  check(valid,"all ten spawn on clear city ground")
  if visit==0:first=points
  else:check(points!=first,"second visit samples fresh random positions")
  check(game.enemy_director.views.size()==10,"all confirmed zombie views created")
  var p:Dictionary=m.state.players[1]
  var chosen:Dictionary={};var player_at:=Vector3.ZERO
  for e in m.state.enemies.values():
   for i in 12:
    var dir:=Vector2.from_angle(TAU*i/12);var at:Vector3=m.Enemies.at(e)
    for j in 10:at=probe.move_spatial(at,dir*.3)
    if at.distance_to(m.Enemies.at(e))>2.8 and game.enemy_director.clear_sight(m.Enemies.at(e)+Vector3.UP,at+Vector3.UP):chosen=e;player_at=at;break
   if not chosen.is_empty():break
  check(not chosen.is_empty(),"city spawn has a real open approach")
  if not chosen.is_empty():
   for e in m.state.enemies.values():
    if e.id!=chosen.id:e.hp=0
   p.pos=Vector2(player_at.x,player_at.z);p.height=player_at.y;p.hp=100;chosen.aim=(p.pos-chosen.pos).normalized()
   var before:Vector2=chosen.pos
   for i in 35:
    m.tick(.1)
    if chosen.mode=="windup":break
   check(chosen.pos.distance_to(before)>.5 and chosen.mode=="windup","zombie physically chases toward player")
   for i in 6:m.tick(.1)
   check(p.hp==82,"city swing attacks player")
   chosen.hp=100;p.fire_timer=0;p.aim=(chosen.pos-p.pos).normalized()
   check(m.command(1,"fire") and chosen.hp==66 and chosen.mode=="stagger" and chosen.knockback==Vector2.ZERO,"city real gun hit pauses zombie")
   chosen.hp=100;chosen.mode="idle";chosen.timer=0
   p.equipment.weapon=m._item("baton",1);p.ammo=0;p.fire_timer=0
   m.command(1,"move",{"aim":p.aim,"ads":true});m.tick(.01)
   check(m.command(1,"fire"),"real city melee swing begins")
   for i in 28:
    m.command(1,"move",{"aim":p.aim,"ads":true});m.tick(.01)
    if chosen.hp<100:break
   check(chosen.hp==76 and chosen.mode=="stagger","real city melee pauses zombie")
   var push_start:Vector2=chosen.pos;m.tick(.05)
   check((Vector2(chosen.pos)-push_start).dot(p.aim)>0 and probe.is_clear(m.Enemies.at(chosen)),"city melee knockback follows collision-safe body")
   p.equipment.weapon=m._item("rifle",1);p.ammo=19
   game._update_actors(.1);game._update_camera(1);game.vision.update(game,.1);game.enemy_director.update(game,.1);game._refresh_ui()
   if DisplayServer.get_name()!="headless":
    await process_frame;await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://artifacts/city_zombie_visit_%d.png"%visit)
  await travel("bunker")
  check(m.state.enemies.is_empty() and game.enemy_director.views.is_empty() and game.enemy_director.bodies.is_empty(),"exit clears shared enemies and visual/physical nodes")
 game.queue_free();await process_frame
 print("CITY_ZOMBIE_WORLD ",checks," checks failures=",failures);quit(1 if failures else 0)
