extends SceneTree
const Model=preload("res://features/base/base_model.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func fixture():
 var m=Model.new()
 for id in [1,2]:
  m.add_player(id,"test");m.state.players[id].pos=Vector2.ZERO
 m.stations=[{"kind":"travel","uid":"bunker_to_city","world":"bunker","destination":"city","pos":Vector2.ZERO,"height":0,"spawn":Vector3(10,0,10)}]
 return m
func run():
 var m=fixture();var request={"route":"bunker_to_city"}
 m.state.players[1].pos=Vector2(8,0)
 check(not m.command(1,"travel",request) and m.state.departure_ready.is_empty(),"distant request cannot ready")
 m.state.players[1].pos=Vector2.ZERO
 check(m.command(1,"travel",request) and m.state.departure_ready.get(1,false) and m.state.world=="bunker","one ready member stays in base")
 check(m.command(1,"travel",request) and not m.state.departure_ready.get(1,false),"second press cancels readiness")
 m.command(1,"travel",request)
 check(m.command(2,"travel",request) and m.state.world=="city" and m.state.world_revision==1,"last member starts party city travel once")
 check(m.state.departure_ready.is_empty() and not m.command(2,"travel",request) and m.state.world_revision==1,"travel clears readiness and rejects stale requests")
 m=fixture();m.command(1,"travel",request);m.add_player(3,"new")
 check(m.state.departure_ready.is_empty(),"new member resets departure consent")
 m.command(1,"travel",request);m.remove_player(3)
 check(m.state.departure_ready.is_empty(),"disconnect resets consent without unexpected travel")
 m=fixture();m.travel_validator=func(_destination):return false
 check(not m.command(1,"travel",request) and m.state.departure_ready.is_empty(),"missing city cannot mark ready")
 m=fixture();m.remove_player(2)
 check(m.command(1,"travel",request) and m.state.world=="city","solo enters city with one press")
 print("DEPARTURE_READY failures=",failures);quit(1 if failures else 0)
