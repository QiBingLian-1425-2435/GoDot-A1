extends SceneTree
const Model=preload("res://features/base/base_model.gd")
const Director=preload("res://features/enemies/enemy_director.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func box(at:Vector3,size:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new();body.position=at;body.collision_layer=1
	var shape:=CollisionShape3D.new();var mesh:=BoxShape3D.new();mesh.size=size;shape.shape=mesh;body.add_child(shape);root.add_child(body)
	return body
func run():
	var floor_body=box(Vector3(0,-.14,0),Vector3(30,.2,30))
	var director=Director.new();root.add_child(director)
	await physics_frame;await physics_frame
	var m=Model.new();m.add_player(1,"shooter");m.state.world="surface";m.obstacles.clear()
	m.enemy_push=director.push_enemy;m.enemy_sight=func(_a,_b):return false
	var p:Dictionary=m.state.players[1];p.pos=Vector2(-3,0);p.height=0;p.aim=Vector2.RIGHT
	var e:Dictionary=m.Enemies.create(1,Vector3.ZERO,Vector2.LEFT);m.state.enemies[1]=e
	e.mode="windup";e.timer=.01;e.target=1
	check(m.command(1,"fire") and e.mode=="stagger" and e.hp<100,"confirmed shot interrupts windup and starts recoil")
	for i in range(16):m.Enemies.tick(m,1.0/60)
	check(e.pos.x>.60 and e.pos.x<.76 and absf(e.pos.y)<.01,"real capsule recoils about 0.69m along bullet direction")
	check(e.mode=="idle" and e.knockback==Vector2.ZERO and e.attack_seq==0,"recoil ends without completing cancelled melee")
	var wall=box(Vector3(.65,1,0),Vector3(.2,2,6))
	await physics_frame;await physics_frame
	e.pos=Vector2.ZERO;e.height=0;e.hp=100;p.fire_timer=0
	m.command(1,"fire")
	for i in range(16):m.Enemies.tick(m,1.0/60)
	check(e.pos.x<.25 and absf(e.pos.y)<.01,"wall stops physical recoil without AI sidestepping")
	wall.free();await physics_frame
	e.pos=Vector2.ZERO;e.hp=100;e.mode="idle";p.fire_timer=0
	m.shot_query=func(_a,_b):return {"position":Vector3(-2,.9,0)}
	m.command(1,"fire")
	check(e.hp==100 and e.mode=="idle","blocked bullet does not create recoil")
	m.shot_query=Callable();p.fire_timer=0;e.hp=1;m.command(1,"fire");m.Enemies.tick(m,.1)
	check(e.hp==0 and e.mode=="dead" and e.velocity==Vector2.ZERO,"lethal damage preserves death behavior")
	e.hp=100;e.pos=Vector2.ZERO
	m.Enemies.hit(e,Vector2.RIGHT);m.Enemies.hit(e,Vector2.LEFT)
	check(e.knockback==Vector2.LEFT*m.Enemies.HIT_SPEED,"successive hits replace impulse instead of stacking unlimited speed")
	director.queue_free();floor_body.queue_free();await process_frame
	print("KNOCKBACK failures=",failures);quit(1 if failures else 0)
