extends SceneTree
const InputController = preload("res://features/player/base_input.gd")
const Model = preload("res://features/base/base_model.gd")
const Session = preload("res://app/network/session.gd")
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ANIMATION MODEL FAIL: " + description)

func run() -> void:
	var model = Model.new(); model.add_player(1,"动画鸭")
	var p: Dictionary = model.state.players[1]
	check(p.velocity == Vector2.ZERO and p.anim_seq == 0 and p.anim_action == "","fresh player has neutral animation state")
	p.pos = Vector2.ZERO
	model.command(1,"move",{"direction":Vector2.RIGHT,"aim":Vector2.RIGHT})
	model.tick(0.1)
	check(p.velocity.is_equal_approx(Vector2(3.7,0)),"velocity records actual world units per second")
	var before: Vector2 = p.pos
	model.command(1,"move",{"direction":Vector2.ZERO,"crouch":true})
	model.tick(0.1)
	check(p.crouch and p.velocity == Vector2.ZERO and p.pos == before,"stationary crouch survives zero movement")
	model.command(1,"move",{"direction":Vector2.RIGHT,"crouch":true,"sprint":true})
	model.tick(0.1)
	check(p.crouch and not p.sprint and is_equal_approx(p.velocity.length(),3.7 * 0.48),"crouched velocity reflects reduced speed and suppresses sprint")
	model.command(1,"move",{"direction":Vector2.UP,"ads":true})
	model.tick(0.1)
	check(p.ads and is_equal_approx(p.velocity.length(),3.7 * 0.62),"ADS velocity reflects authoritative slowdown")
	for i in range(5): model.tick(0.1)
	check(p.velocity == Vector2.ZERO and not p.crouch and not p.ads,"stale input returns velocity and poses to neutral")
	model.obstacles.assign([Rect2(1,-2,1,4)])
	p.pos = Vector2(0.679,0)
	model.command(1,"move",{"direction":Vector2.RIGHT})
	model.tick(0.1)
	check(p.velocity == Vector2.ZERO,"pressing into a wall does not generate walking velocity")
	check(not InputController._footstep_state(p).moving,"held movement into a wall stays silent")
	model.command(1,"move",{"direction":Vector2(1,1)})
	model.tick(0.1)
	check(is_zero_approx(p.velocity.x) and p.velocity.y > 0,"wall slide reports only actual tangential velocity")
	check(InputController._footstep_state(p).moving,"actual tangential wall slide still produces footsteps")
	model.obstacles.clear()
	p.stamina = 1.5
	model.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true})
	model.tick(0.1)
	check(p.stamina == 0 and not p.sprint and p.sprint_exhausted,"exhausting stamina immediately falls back to walking")
	check(is_equal_approx(p.velocity.length(),3.7) and not InputController._footstep_state(p).sprint,"exhausted movement and footsteps use walking pace")
	for i in range(10):
		model.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true})
		model.tick(0.1)
	check(not p.sprint and p.stamina > 0,"holding sprint stays walking while stamina recovers")
	model.command(1,"move",{"direction":Vector2.RIGHT,"sprint":false}); model.tick(0.1)
	model.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true}); model.tick(0.1)
	check(p.sprint and not p.sprint_exhausted,"releasing sprint clears exhaustion lock")
	p.stamina = 100.0; p.sprint_exhausted = false
	for i in range(70):
		model.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true})
		model.tick(0.1)
	var recovered_while_held: float = p.stamina
	for i in range(10):
		model.command(1,"move",{"direction":Vector2.RIGHT,"sprint":true})
		model.tick(0.1)
	check(p.sprint_exhausted and not p.sprint and p.stamina > recovered_while_held,"a naturally depleted full bar recovers while sprint remains held")
	model.command(1,"move",{"direction":Vector2.ZERO})
	check(model.command(1,"use",{"index":2}),"water use succeeds")
	check(p.anim_seq == 1 and p.anim_action == "drink" and p.anim_time == 0 and is_equal_approx(p.anim_duration,1.3),"water starts drink event exactly once")
	model.tick(0.1)
	check(is_equal_approx(p.anim_time,0.1),"host advances event elapsed time")
	check(not model.command(1,"use",{"index":0}) and p.anim_seq == 1,"failed item action does not produce event")
	check(model.command(1,"use",{"index":3}) and p.anim_seq == 2 and p.anim_action == "eat" and p.anim_time == 0,"new event replaces preceding drink without queued playback")
	for i in range(20): model.tick(0.1)
	check(p.anim_seq == 2 and p.anim_action == "eat" and is_equal_approx(p.anim_time,p.anim_duration),"expired event retains type and sequence at its duration")
	p.hp = 10
	model.command(1,"use",{"index":1})
	check(p.anim_action == "heal" and p.anim_seq == 3 and is_equal_approx(p.anim_duration,1.5) and p.hp == 28,"bandage heal event preserves immediate gameplay settlement")
	model.command(1,"use",{"index":5})
	check(p.anim_action == "heal" and p.anim_seq == 4 and p.hp == 73,"medkit also produces heal event")
	p.hp = 100
	check(not model.command(1,"use",{"index":1}) and p.anim_seq == 4,"full health rejection does not restart heal")
	var uid: String = p.bag[4].uid
	model.command(1,"drop",{"index":4})
	check(p.anim_action == "pickup" and p.anim_seq == 5 and is_equal_approx(p.anim_duration,0.65),"drop uses pickup body action")
	check(not model.command(1,"drop",{"index":4}) and p.anim_seq == 5,"rejected empty-slot drop has no event")
	model.command(1,"pickup",{"uid":uid})
	check(p.anim_action == "pickup" and p.anim_seq == 6,"successful pickup increments action sequence")
	check(not model.command(1,"pickup",{"uid":uid}) and p.anim_seq == 6,"duplicate pickup cannot replay animation")
	model.command(1,"equip",{"index":6}); p = model.state.players[1]
	check(p.anim_action == "equip" and p.anim_seq == 7 and is_equal_approx(p.anim_duration,0.5),"weapon swap starts equip event")
	model.command(1,"unequip",{"slot":"weapon"}); p = model.state.players[1]
	check(p.anim_action == "equip" and p.anim_seq == 8,"weapon removal produces equip event")
	check(not model.command(1,"unequip",{"slot":"weapon"}) and p.anim_seq == 8,"empty weapon removal does not animate")
	model.command(1,"select_weapon"); p = model.state.players[1]
	check(p.anim_action == "equip" and p.anim_seq == 9,"weapon selection produces exactly one equip event")
	var event_seq := int(p.anim_seq)
	check(not model.command(1,"rest") and p.anim_seq == event_seq,"out-of-range station cannot animate")
	model.stations = [{"kind":"medical","pos":p.pos},{"kind":"workbench","pos":p.pos},{"kind":"trader","pos":p.pos},{"kind":"range","pos":p.pos}]
	for action in ["rest","craft","buy_ammo","reset_targets","train"]:
		event_seq = int(p.anim_seq)
		check(model.command(1,action) and p.anim_seq == event_seq + 1 and p.anim_action == "interact" and is_equal_approx(p.anim_duration,0.8),"station action animates after success: " + action)
	event_seq = int(p.anim_seq); p.credits = 0
	check(not model.command(1,"buy_ammo") and p.anim_seq == event_seq,"unaffordable purchase cannot animate")
	var file_path := "user://duckov_animation_model_test_profile.json"
	check(model.save_profile(file_path) == OK,"profile saved using test-only path")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	for field in ["velocity","anim_seq","anim_action","anim_time","anim_duration"]:
		check(not data.has(field),"profile omits transient " + field)
	model.command(1,"move",{"direction":Vector2.RIGHT,"crouch":true}); model.tick(0.1)
	check(model.load_profile(file_path) == OK,"test profile loads")
	check(p.velocity == Vector2.ZERO and p.anim_seq == 0 and p.anim_action == "" and not p.crouch,"profile load clears animation and input transients")
	model.tick(0.1)
	check(p.velocity == Vector2.ZERO,"profile load clears cached movement input")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	var session = Session.new(); root.add_child(session)
	session.model.command(1,"use",{"index":2})
	session.model.command(1,"move",{"direction":Vector2.RIGHT,"crouch":true})
	session.model.tick(0.1)
	session.offline()
	var local: Dictionary = session.model.state.players[1]
	check(local.anim_seq == 0 and local.anim_action == "" and local.anim_time == 0 and local.anim_duration == 0 and local.velocity == Vector2.ZERO,"offline lifecycle clears remembered local animation")
	check(not local.crouch and not local.ads and not local.reloading,"offline lifecycle clears movement and reload poses")
	check(session.has_method("use_steam_peer") and session.transport == "offline","Steam-compatible session interface remains intact")
	session.queue_free()
	await process_frame
	print("DUCKOV_ANIMATION_MODEL_TEST ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
