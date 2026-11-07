extends SceneTree
const Movement=preload("res://features/player/movement_rules.gd")
const Model=preload("res://features/base/base_model.gd")
var failures:=0
func check(ok:bool,label:String):
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func fixture()->Dictionary:
 var m=Model.new();m.add_player(1,"test");var p:Dictionary=m.state.players[1].duplicate(true);p.pos=Vector2.ZERO;p.weight=0;p.infinite_stamina=true;return p
func speed(direction:Vector2,aim:Vector2,sprint:bool=true)->float:
 var p:=fixture();Movement.step(p,{"direction":direction,"aim":aim,"sprint":sprint},.1,func(at,offset):return at+offset);return p.velocity.length()
func _initialize():call_deferred("run")
func run():
 check(is_equal_approx(speed(Vector2.UP,Vector2.UP,false),1.85),"forward walk reduced by half")
 var forward:=speed(Vector2.UP,Vector2.UP);var backward:=speed(Vector2.DOWN,Vector2.UP)
 check(is_equal_approx(forward,6.105) and is_equal_approx(backward,forward*.7),"backward sprint is seventy percent of forward")
 check(is_equal_approx(speed(Vector2.RIGHT,Vector2.UP),forward),"side sprint unchanged")
 var diagonal:=speed(Vector2(1,1).normalized(),Vector2.UP)
 check(diagonal>backward and diagonal<forward,"diagonal retreat blends slowdown")
 check(is_equal_approx(speed(Vector2.DOWN,Vector2.UP,false),1.85),"backward walk reduced by half")
 check(is_equal_approx(speed(Vector2.DOWN,Vector2.DOWN),forward),"same-frame aim selects forward speed")
 var original:=fixture();var host:Dictionary=original.duplicate(true)
 var predictor=load("res://features/player/local_movement.gd").new();predictor.infinite_stamina=true;predictor.solver=func(at,offset):return at+offset;predictor.confirm(original)
 var input={"direction":Vector2.DOWN,"aim":Vector2.UP,"sprint":true}
 for i in range(12):
  Movement.step(host,input,1.0/60,func(at,offset):return at+offset)
  predictor.set_input(input);predictor.advance(1.0/60,original)
 var predicted:Dictionary=predictor.sample_player(original)
 check(Vector2(predicted.pos).distance_to(host.pos)<.03,"local prediction matches authoritative backward movement")
 predictor.solver=Callable()
 predictor=null
 print("BACKWARD_SPRINT failures=",failures);call_deferred("quit",1 if failures else 0)
