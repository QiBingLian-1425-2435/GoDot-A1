extends SceneTree
## Observable animation behavior tests. No simulation of Steam, damage or collision ownership.
const Actor = preload("res://features/player/base_actor.gd")
const DT := 1.0/60.0
const BONES := ["Root","Hips","Spine","Head","Tail","FootL","FootR","WingL","WingR","Gun","Pack"]
var assertions := 0
var failures: Array[String] = []
var actors: Array[Node3D] = []
func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
    assertions += 1
    if not condition:
        failures.append(message)
        print("FAIL: ", message)
func fixture(title: String="QA鸭"):
    var a = Actor.new()
    root.add_child(a)
    a.setup(Color("75834e"),title)
    a.set_process(false)
    actors.append(a)
    return a
func state() -> Dictionary:
    return {"id":1,"name":"QA鸭","pos":Vector2(2,3),"aim":Vector2.UP,"velocity":Vector2.ZERO,"sprint":false,"crouch":false,"ads":false,"shots":0,"reloading":false,"reload_progress":0.0,"anim_seq":0,"anim_action":"","anim_time":0.0,"anim_duration":0.0,"equipment":{"weapon":{"kind":"rifle","uid":"qa-rifle"},"helmet":{},"armor":{},"backpack":{"kind":"backpack"}}}
func step(a, data: Dictionary, count:int=1, local:bool=false) -> void:
    for i in count:a.update_actor(data,DT,local)
func pose(a,bone:String) -> Transform3D:
    var skeleton:Skeleton3D=a.get("skeleton")
    return skeleton.get_bone_pose(skeleton.find_bone(bone))
func global_pose(a,bone:String) -> Transform3D:
    var skeleton:Skeleton3D=a.get("skeleton")
    skeleton.force_update_all_bone_transforms()
    return skeleton.get_bone_global_pose(skeleton.find_bone(bone))
func delta_pose(a:Transform3D,b:Transform3D) -> float:
    if a.is_equal_approx(b):return 0.0
    return a.origin.distance_to(b.origin)+a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())
func bone_poses(a) -> Dictionary:
    var result:Dictionary={}
    for bone in BONES:result[bone]=pose(a,bone)
    return result
func run() -> void:
    var probe=fixture()
    var skeleton:Skeleton3D=probe.get("skeleton")
    check(skeleton!=null,"actor exposes real Skeleton3D")
    if skeleton==null:
        finish()
        return
    check(probe.get_node_or_null("Rig/Skeleton3D")==skeleton,"public skeleton belongs to stable Rig/Skeleton3D path")
    check(skeleton.get_bone_count()==11,"rig contains exactly eleven agreed bones")
    for bone in BONES:check(skeleton.find_bone(bone)>=0,"rig contains "+bone)
    if BONES.any(func(bone):return skeleton.find_bone(bone)<0):
        finish()
        return
    test_idle_and_authority()
    test_snapshot_locomotion()
    test_crouch_aim_transitions()
    test_shots_and_equipment()
    test_reload()
    test_action_sequence()
    test_instance_isolation()
    test_model_motion_contract()
    await test_npc_idle()
    finish()
func finish() -> void:
    for a in actors:
        if is_instance_valid(a):a.free()
    print("DUCKOV_ACTOR_ANIMATION_TEST: ",assertions," assertions, ",failures.size()," failed")
    quit(0 if failures.is_empty() else 1)
func test_idle_and_authority() -> void:
    var a=fixture("idle")
    var d=state()
    var original=d.duplicate(true)
    step(a,d,90)
    var before=bone_poses(a)
    step(a,d,25)
    var chest_change=delta_pose(before.Spine,pose(a,"Spine"))+delta_pose(before.Hips,pose(a,"Hips"))
    check(chest_change>0.0001,"stationary actor breathes through skeletal body poses")
    check(delta_pose(before.FootL,pose(a,"FootL"))<0.025,"idle feet stay planted while body breathes")
    check(str(a.get("animation_state"))!="","actor exposes nonempty locomotion state")
    check(d==original,"render animation never mutates authoritative snapshot dictionary")
    check(a.position.is_equal_approx(Vector3(d.pos.x,0,d.pos.y)),"actor root remains at authoritative world position")
    check(a.find_children("*","CollisionObject3D",true,false).is_empty(),"visual rig adds no gameplay collision body")
    var root_pose=pose(a,"Root")
    check(absf(root_pose.origin.x)<0.001 and absf(root_pose.origin.z)<0.001,"animation has no horizontal root motion")
    step(a,d,1,true)
    check(a.local_ring.visible,"local player marker follows public update local flag")
    step(a,d,1,false)
    check(not a.local_ring.visible,"remote player marker stays hidden")
func test_snapshot_locomotion() -> void:
    var a=fixture("snapshots")
    var d=state()
    step(a,d,30)
    d.velocity=Vector2(0,-3.0)
    var previous=pose(a,"FootL")
    var between_changes:=0
    var total_between:=0
    for frame in 240:
        if frame%4==0:d.pos+=d.velocity*(4*DT)
        step(a,d)
        var current=pose(a,"FootL")
        if frame>60 and frame%4!=0:
            total_between+=1
            if delta_pose(previous,current)>0.0001:between_changes+=1
        previous=current
    check(between_changes>total_between/2,"feet continue moving between 15 Hz snapshots at 60 Hz render (%d/%d)"%[between_changes,total_between])
    var walking_state:String=str(a.get("animation_state"))
    var walking_foot=pose(a,"FootL")
    d.velocity=Vector2(0,-5.0)
    d.sprint=true
    step(a,d,60)
    check(str(a.get("animation_state"))!=walking_state,"sprint selects a distinct locomotion state")
    check(delta_pose(walking_foot,pose(a,"FootL"))>0.001,"running has an observable leg pose")
    d.velocity=Vector2.ZERO
    d.sprint=false
    step(a,d,120)
    var stopped=bone_poses(a)
    step(a,d,30)
    check(delta_pose(stopped.FootL,pose(a,"FootL"))<0.01 and delta_pose(stopped.FootR,pose(a,"FootR"))<0.01,"stopping settles both feet instead of freezing a lifted step")
    var skeleton:Skeleton3D=a.get("skeleton")
    for bone in ["FootL","FootR"]:
        var index=skeleton.find_bone(bone)
        check(pose(a,bone).origin.distance_to(skeleton.get_bone_rest(index).origin)<0.025,"stopped "+bone+" settles near standing rest height")
func test_crouch_aim_transitions() -> void:
    var a=fixture("stances")
    var d=state()
    step(a,d,90)
    var standing_height=global_pose(a,"Head").origin.y
    var before=bone_poses(a)
    d.crouch=true
    step(a,d)
    var transition_distance=delta_pose(before.Hips,pose(a,"Hips"))
    check(transition_distance<0.20,"crouch transition blends without a one-frame body pop")
    step(a,d,90)
    check(global_pose(a,"Head").origin.y<standing_height-0.04,"stationary crouch lowers silhouette")
    var crouch_state:String=str(a.get("animation_state"))
    d.velocity=Vector2(0,-1.4)
    for i in 60:
        d.pos+=d.velocity*DT
        step(a,d)
    check(str(a.get("animation_state"))!=crouch_state,"moving crouch differs from stationary crouch")
    d.velocity=Vector2.ZERO
    d.crouch=false
    step(a,d,90)
    var hip_fire=bone_poses(a)
    d.ads=true
    step(a,d,60)
    var ads_change=delta_pose(hip_fire.WingL,pose(a,"WingL"))+delta_pose(hip_fire.WingR,pose(a,"WingR"))+delta_pose(hip_fire.Gun,pose(a,"Gun"))
    check(ads_change>0.015,"aiming changes gun and wing hold pose")
    d.aim=Vector2.RIGHT
    step(a,d,20)
    check(absf(wrapf(a.rotation.y+PI/2,-PI,PI))<0.03,"aim direction controls world facing without changing position")
func test_shots_and_equipment() -> void:
    var a=fixture("combat")
    var d=state()
    d.shots=17
    step(a,d)
    check(not a.flash.visible and not a.flash_light.visible,"joining a player with old shots does not replay muzzle flash")
    step(a,d,90)
    var before=pose(a,"Gun")
    d.shots+=1
    step(a,d)
    check(a.flash.visible and a.flash_light.visible,"new authoritative shot triggers muzzle flash and light")
    step(a,d,3)
    check(delta_pose(before,pose(a,"Gun"))>0.008,"new shot causes skeletal gun recoil")
    step(a,d,60)
    check(not a.flash.visible and not a.flash_light.visible,"shot flash expires without repeated snapshot retrigger")
    d.shots+=1
    step(a,d)
    d.equipment.weapon={}
    step(a,d)
    check(not a.weapon.visible and not a.flash.visible and not a.flash_light.visible,"unequipping weapon clears visible weapon, flash and light immediately")
    d.equipment.helmet={"kind":"helmet"}
    d.equipment.armor={"kind":"armor"}
    d.equipment.backpack={}
    step(a,d)
    check(a.helmet.visible and a.armor.visible and not a.backpack.visible,"equipment visibility follows authoritative slots")
    d.equipment.weapon={"kind":"pistol","uid":"qa-pistol"}
    step(a,d,45)
    check(a.weapon.visible,"pistol equipment restores weapon presentation")
    check(a.pistol_mesh.visible and not a.rifle_mesh.visible,"pistol equipment selects distinct geometry without rifle residue")
func test_reload() -> void:
    var a=fixture("reload")
    var d=state()
    step(a,d,90)
    var resting=bone_poses(a)
    d.reloading=true
    d.reload_progress=0.2
    step(a,d,15)
    var early=bone_poses(a)
    d.reload_progress=0.7
    step(a,d,15)
    var late=bone_poses(a)
    check(delta_pose(early.WingL,late.WingL)+delta_pose(early.Gun,late.Gun)>0.015,"reload pose follows progress rather than replaying start")
    d.reloading=false
    d.reload_progress=0.0
    step(a,d,90)
    check(delta_pose(resting.WingL,pose(a,"WingL"))+delta_pose(resting.Gun,pose(a,"Gun"))<0.12,"cancelled reload returns arm and weapon to hold pose")
    check(not str(a.get("action_state")).to_lower().contains("reload"),"cancelled reload clears action state")
func test_action_sequence() -> void:
    var a=fixture("actions")
    var d=state()
    step(a,d,60)
    d.anim_seq=1
    d.anim_action="heal"
    d.anim_duration=1.0
    d.anim_time=0.0
    step(a,d,12)
    var time_before:float=float(a.get("action_time"))
    var action_before:String=str(a.get("action_state"))
    step(a,d,12)
    check(not action_before.is_empty(),"fresh action sequence starts visible action")
    check(float(a.get("action_time"))>time_before+0.1,"same snapshot sequence continues action time rather than restarting every render frame")
    d.anim_time=1.0
    step(a,d,90)
    check(str(a.get("action_state")).is_empty() or str(a.get("action_state")) in ["none","idle"],"completed action returns to locomotion")
    d.anim_time=0.0
    step(a,d,20)
    check(str(a.get("action_state")).is_empty() or str(a.get("action_state")) in ["none","idle"],"stale completed sequence cannot restart after action finishes")
    d.anim_seq=2
    d.anim_time=0.65
    step(a,d)
    check(float(a.get("action_time"))>=0.64,"delayed active event starts at authoritative elapsed time")
    var late=fixture("late action")
    d.anim_seq=55
    d.anim_time=d.anim_duration
    step(late,d)
    check(str(late.get("action_state")).is_empty() or str(late.get("action_state")) in ["none","idle"],"late join does not replay already completed action")
func library_fingerprint(library:AnimationLibrary) -> String:
    var values:Array=[]
    for name in library.get_animation_list():
        var animation:Animation=library.get_animation(name)
        values.append([name,animation.length,animation.loop_mode])
        for track in animation.get_track_count():
            values.append([animation.track_get_path(track),animation.track_get_type(track)])
            for key in animation.track_get_key_count(track):
                values.append([animation.track_get_key_time(track,key),animation.track_get_key_value(track,key)])
    return str(values)
func test_instance_isolation() -> void:
    var library:AnimationLibrary=load("res://features/player/animation/duck_animations.tres")
    check(library!=null,"animation resource is reusable AnimationLibrary")
    var original=library_fingerprint(library) if library!=null else ""
    var group:Array=[]
    for i in 4:
        var actor=fixture("isolation %d"%i)
        step(actor,state(),45)
        group.append(actor)
    var untouched=bone_poses(group[3])
    var d=state()
    d.velocity=Vector2(0,-4)
    d.sprint=true
    d.anim_seq=10
    d.anim_action="heal"
    d.anim_duration=1.0
    for frame in 100:
        step(group[0],d)
        var second=state()
        second.crouch=true
        step(group[1],second)
        var third=state()
        third.reloading=true
        third.reload_progress=0.55
        step(group[2],third)
    check(delta_pose(untouched.FootL,pose(group[3],"FootL"))+delta_pose(untouched.Hips,pose(group[3],"Hips"))+delta_pose(untouched.Gun,pose(group[3],"Gun"))<0.00001,"updating three actors cannot mutate fourth actor pose")
    check(group[0].skeleton!=group[1].skeleton and group[1].skeleton!=group[2].skeleton,"instances have separate skeleton state")
    if library!=null:check(library_fingerprint(library)==original,"running four actors does not mutate shared source animation tracks")
func test_model_motion_contract() -> void:
    var Model=load("res://features/base/base_model.gd")
    var model=Model.new()
    model.add_player(1,"state contract")
    model.command(1,"move",{"direction":Vector2.ZERO,"aim":Vector2.UP,"crouch":true})
    model.tick(DT)
    var data:Dictionary=model.state.players[1]
    check(bool(data.crouch),"authoritative model preserves crouch while stationary")
    check(data.get("velocity",Vector2.INF)==Vector2.ZERO,"stationary authoritative velocity is explicit zero")
    model.command(1,"move",{"direction":Vector2.RIGHT,"aim":Vector2.UP})
    model.tick(DT)
    check(Vector2(data.get("velocity",Vector2.ZERO)).length()>0,"model supplies persistent movement velocity for snapshot animation")
    var a=fixture("model authority")
    var original=data.duplicate(true)
    step(a,data,120)
    check(data==original,"two seconds of render updates leave model inventory, position and timers unchanged")


func test_npc_idle() -> void:
    var npc=fixture("autonomous NPC")
    var source=state()
    source.equipment.weapon={}
    npc.enable_idle(source)
    check(npc.is_processing(),"NPC idle opt-in enables independent process callback")
    source.pos=Vector2(99,99)
    await create_timer(0.30).timeout
    check(npc.position.distance_to(Vector3(2,0,3))<0.001,"NPC keeps a copy of idle configuration rather than mutable caller data")
    var before=bone_poses(npc)
    await create_timer(0.35).timeout
    check(delta_pose(before.Hips,pose(npc,"Hips"))+delta_pose(before.Spine,pose(npc,"Spine"))>0.0001,"NPC breathes autonomously without update_actor calls from game")
    npc.visible=false
    before=bone_poses(npc)
    await create_timer(0.20).timeout
    check(delta_pose(before.Hips,pose(npc,"Hips"))+delta_pose(before.Spine,pose(npc,"Spine"))<0.00001,"hidden NPC pauses decorative skeletal work")
    npc.visible=true
    await create_timer(0.25).timeout
    check(delta_pose(before.Hips,pose(npc,"Hips"))+delta_pose(before.Spine,pose(npc,"Spine"))>0.0001,"visible NPC resumes idle animation")
    npc.set_process(false)
