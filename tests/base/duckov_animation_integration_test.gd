extends SceneTree
## Real Main, physical keyboard events, live model state and animated Skeleton3D.
## Smoke mode prevents production profile access and Steam initialization.
const Main = preload("res://app/main.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ANIMATION INTEGRATION FAIL: " + description)

func frames(count: int) -> void:
	for i in range(count): await physics_frame
	await process_frame

func press(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: Key) -> void:
	press(code,true)
	await frames(2)
	press(code,false)
	await frames(2)

func bone_y(actor, bone: String) -> float:
	return actor.skeleton.get_bone_pose_position(actor.skeleton.find_bone(bone)).y

func bone_pose(actor, bone: String) -> Transform3D:
	return actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone(bone))

func count_kind(p: Dictionary, kind: String) -> int:
	var total := 0
	for item in p.bag:
		if item.get("kind","") == kind: total += int(item.count)
	return total

func run() -> void:
	game = Main.new()
	game.name = "AnimationIntegration"
	game.smoke = true; game.elapsed = -100.0; game.capture_mode = "base"
	root.add_child(game)
	await frames(10)
	check(game.in_game and game.smoke and game.actors.has(1),"real Main starts protected solo animation scene")
	var actor = game.actors[1]
	var p: Dictionary = game.session.model.state.players[1]
	check(actor.skeleton.get_bone_count() >= 11 and actor.motion.tree.active,"live actor has active skeletal animation graph")
	var standing_y := bone_y(actor,"Hips")
	await tap(KEY_C)
	await frames(16)
	check(p.crouch and p.velocity == Vector2.ZERO,"C toggles stationary crouch in authoritative model")
	check(actor.animation_state == "crouch_idle","stationary crouch reaches actor animation state")
	var crouch_y := bone_y(actor,"Hips")
	check(crouch_y < standing_y - 0.15,"crouch visibly lowers actual hip bone")
	await tap(KEY_C)
	await frames(16)
	check(not p.crouch and actor.animation_state == "idle","second C returns model and actor to idle standing")
	check(bone_y(actor,"Hips") > crouch_y + 0.15,"standing restores hip bone height")
	# Main reads physical key state; walking and running are checked on animated bones.
	press(KEY_D,true)
	await frames(15)
	check(p.velocity.length() > 3 and actor.animation_state == "walk","D moves the model and selects walk animation")
	var foot_before := bone_pose(actor,"FootL")
	await frames(8)
	var foot_after := bone_pose(actor,"FootL")
	check(foot_before.origin.distance_to(foot_after.origin) > 0.01 or foot_before.basis.get_rotation_quaternion().angle_to(foot_after.basis.get_rotation_quaternion()) > 0.02,"walk continuously changes the real foot bone")
	press(KEY_SHIFT,true)
	await frames(16)
	check(p.sprint and p.velocity.length() > 5 and actor.animation_state == "run","Shift plus movement selects authoritative sprint and run animation")
	foot_before = bone_pose(actor,"FootR")
	await frames(8)
	foot_after = bone_pose(actor,"FootR")
	check(foot_before.origin.distance_to(foot_after.origin) > 0.01 or foot_before.basis.get_rotation_quaternion().angle_to(foot_after.basis.get_rotation_quaternion()) > 0.02,"run continuously changes the real foot bone")
	press(KEY_D,false); press(KEY_SHIFT,false)
	await frames(25)
	check(p.velocity == Vector2.ZERO and actor.animation_state == "idle","released movement settles into idle")
	await tap(KEY_R)
	await frames(10)
	check(p.reloading and actor.action_state == "reload","R reaches live model reload and actor action")
	await frames(25)
	check(actor.held_props.reload.visible and not actor.magazine.visible,"reload exchanges the visible held magazine")
	await frames(80)
	check(not p.reloading and p.ammo == 30 and actor.action_state != "reload","reload finishes without sticky action")
	check(not actor.held_props.reload.visible and actor.magazine.visible,"reload restores weapon magazine and hides held prop")
	var water_before := count_kind(p,"water")
	await tap(KEY_5)
	await frames(10)
	check(p.anim_action == "drink" and count_kind(p,"water") == water_before - 1,"5 consumes water and creates authoritative drink event")
	check(actor.action_state == "drink" and actor.held_props.drink.visible,"drink event activates actor and visible bottle")
	await frames(90)
	check(actor.action_state.is_empty() and not actor.held_props.drink.visible,"drink action and bottle clear at completion")
	p.hp = 50.0
	var meds_before := count_kind(p,"medkit")
	await tap(KEY_4)
	await frames(10)
	check(p.anim_action == "heal" and p.hp == 95 and count_kind(p,"medkit") == meds_before - 1,"4 applies medical effect and heal event once")
	check(actor.action_state == "heal" and actor.held_props.heal.visible,"heal event shows the actual held medical prop")
	await frames(100)
	check(actor.action_state.is_empty() and not actor.held_props.heal.visible,"heal action and prop clear at completion")
	await tap(KEY_2)
	await frames(9)
	p = game.session.model.state.players[1]
	check(p.equipment.weapon.kind == "pistol" and actor.pistol_mesh.visible and not actor.rifle_mesh.visible,"2 switches model weapon and actual pistol geometry")
	check(actor.action_state == "equip","weapon swap plays equip action")
	await frames(30)
	await tap(KEY_1)
	await frames(9)
	p = game.session.model.state.players[1]
	check(p.equipment.weapon.kind == "rifle" and actor.rifle_mesh.visible and not actor.pistol_mesh.visible,"1 restores model rifle and actual rifle geometry")
	await frames(32)
	# Create a legal drop through the same authoritative Session, then pick it up via E.
	p.pos = Vector2(0,3)
	game.session.send("move",{"direction":Vector2.ZERO,"aim":Vector2.RIGHT})
	var uid := str(p.bag[4].uid)
	game.session.send("drop",{"index":4})
	await frames(45)
	check(game.session.model.state.drops.has(uid) and game.nearest.get("kind","") == "pickup","a legal nearby drop exposes the live E interaction")
	var seq_before := int(p.anim_seq)
	await tap(KEY_E)
	await frames(8)
	check(not game.session.model.state.drops.has(uid) and p.anim_seq == seq_before + 1 and p.anim_action == "pickup","E pickup settles ownership and creates one new action")
	check(actor.action_state == "pickup","E pickup reaches actor action state")
	# Let finite audio finish, stop each player, then free and wait for deferred audio cleanup.
	game.set_physics_process(false); game.set_process(false)
	for sound_player in game.sound.sounds.values(): sound_player.stop()
	game.sound.sounds.clear()
	await frames(15)
	game.queue_free(); actor = null; game = null
	await frames(15)
	print("DUCKOV_ANIMATION_INTEGRATION_TEST ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
