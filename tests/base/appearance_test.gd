extends SceneTree
const Main=preload("res://app/main.gd")
const Rules=preload("res://features/player/appearance_rules.gd")
const Texts=preload("res://features/localization/game_text.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(value:bool,label:String):
	print("PASS: " if value else "FAIL: ",label)
	if not value:failures+=1
func run():
	var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game)
	game.profile_path="user://appearance_test_%s.json"%Time.get_ticks_usec()
	game._start_solo();game.sound.muted=true
	game.session.set_physics_process(false);game.set_physics_process(false)
	var m=game.session.model;var p:Dictionary=m.state.players[1]
	check(Rules.valid(Rules.defaults()),"defaults are valid")
	var bad:=Rules.defaults();bad.skin="javascript:invalid"
	check(not m.command(1,"appearance",bad),"invalid color rejected by authority")
	var selected:=Rules.defaults("female");selected.hair="#663322";selected.shirt="#aa3355"
	check(m.command(1,"appearance",selected),"authority accepts own appearance")
	var saved:Dictionary=m.Profile.capture(m,1)
	check(saved.appearance==selected,"profile captures appearance")
	game._update_actors(.016)
	check(game.actors[1].human_visual.gender=="female","player uses female Blender model")
	check(game.actors[1].human_visual.meshes.size()>20,"imported body parts replace duck visuals")
	check(m.Profile.apply(m,saved,1)==OK and p.appearance==selected,"saved appearance restores exactly")
	var legacy:Dictionary=saved.duplicate(true);legacy.erase("appearance")
	check(m.Profile.valid(m,legacy),"older profiles without appearance remain valid")
	m.add_player(2,"other");game._update_actors(.016)
	check(game.actors[2].human_visual.current!=selected,"other player appearance is independent")
	for part in Rules.PARTS:
		check(game.actors[1].human_visual.materials[part][0].albedo_color.is_equal_approx(Color(selected[part])),"material color matches "+part)

	check(game.actors[1].human_visual.materials.has("hair") and game.actors[1].human_visual.materials.has("shirt"),"separate editable materials imported")
	game.ui._open_appearance()
	var panel=game.ui._dialog.get_node("AppearancePanel")
	check(panel.draft==selected,"Esc appearance editor starts from confirmed selection")
	panel.get_node("pants").color_changed.emit(Color("#3366cc"))
	check(panel.draft.pants=="#3366cc" and panel.draft.hair==selected.hair,"color picker changes only its selected body part")
	await process_frame;await process_frame
	check(p.appearance.pants!=panel.draft.pants,"preview does not mutate gameplay state before apply")
	for gender in ["male","female"]:
		panel.draft=Rules.defaults(gender)
		panel.get_node("Gender").select(0 if gender=="male" else 1)
		for part in Rules.PARTS:panel.get_node(part).color=Color(panel.draft[part])
		for i in range(12):await process_frame
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://artifacts/humans")
			root.get_texture().get_image().save_png("res://artifacts/humans/appearance_%s.png"%gender)
	# Human parts follow the same gameplay animation graph and independent gear.
	for gender in ["male","female"]:
		panel.draft=Rules.defaults(gender)
		panel.get_node("Gender").select(0 if gender=="male" else 1)
		for part in Rules.PARTS:panel.get_node(part).color=Color(panel.draft[part])
		for action in ["walk","run","crouch","reload","jump"]:
			panel.preview_data.velocity=Vector2(0,-3.7) if action in ["walk","run","crouch"] else Vector2.ZERO
			panel.preview_data.sprint=action=="run";panel.preview_data.crouch=action=="crouch"
			panel.preview_data.reloading=action=="reload";panel.preview_data.reload_progress=.5
			panel.preview_data.roll={"active":true,"time":.28} if action=="jump" else {}
			for frame in range(20):panel.actor.update_actor(panel.preview_data.merged({"appearance":panel.draft},true),.016,true)
			var finite:=true
			for mesh in panel.actor.human_visual.meshes:finite=finite and mesh.global_transform.is_finite()
			check(finite,"human animation transforms valid: "+gender+" "+action)
			if DisplayServer.get_name()!="headless":
				panel.set_process(false)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://artifacts/humans/%s_%s.png"%[gender,action])
				panel.set_process(true)
		panel.preview_data.roll={};panel.preview_data.velocity=Vector2.ZERO;panel.preview_data.reloading=false;panel.preview_data.crouch=false
		panel.actor.human_visual.set_helmet(true)
		var hair_hidden:=true
		for mesh in panel.actor.human_visual.meshes:
			if "hair" in str(mesh.name) or "fringe" in str(mesh.name):hair_hidden=hair_hidden and not mesh.visible
		check(hair_hidden,"head equipment hides hair: "+gender)
		panel.actor.human_visual.set_helmet(false)
	Texts.set_locale("en",false)
	await process_frame
	check(Texts.resolve("⟦appearance.title⟧")=="Appearance" and panel.draft.gender=="female","language switch preserves appearance draft")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/humans/appearance_en.png")
	Texts.set_locale("zh_CN",false)
	# Apply through the actual menu signal route and verify immediate solo save.
	var applied:Dictionary=panel.draft.duplicate(true)
	game.smoke=false
	panel.get_node("ApplyAppearance").pressed.emit()
	game.smoke=true
	check(p.appearance==applied,"actual menu button applies confirmed choice")
	check(FileAccess.file_exists(game.profile_path),"apply immediately saves local profile")
	var fresh=preload("res://features/base/base_model.gd").new();fresh.add_player(1,"restored")
	check(fresh.load_profile(game.profile_path,1)==OK and fresh.state.players[1].appearance==applied,"appearance persists across a new model load")
	var store=preload("res://features/persistence/room_store.gd").new()
	var room_path:String=game.profile_path+".room"
	check(store.begin(m,room_path,"host")==OK and store.admit(m,2,"guest")==OK,"appearance room store opens")
	m.state.players[2].appearance=selected.duplicate(true)
	check(store.checkpoint(m)==OK,"room checkpoints guest appearance")
	var next_store=preload("res://features/persistence/room_store.gd").new()
	fresh.add_player(3,"reconnected")
	check(next_store.begin(fresh,room_path,"host")==OK and next_store.admit(fresh,3,"guest")==OK and fresh.state.players[3].appearance==selected,"same guest identity restores appearance under a different peer ID")
	for path in [game.profile_path,room_path,room_path+".bak"]:DirAccess.remove_absolute(path)

	game.ui._close_dialog()
	p.aim=Vector2.DOWN
	m.state.players[2].pos=p.pos+Vector2(1.8,0)
	m.state.players[2].aim=Vector2.DOWN
	game.camera_zoom=7
	game._update_actors(.016)
	for i in range(20):game._update_camera(.1)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/humans/player_in_game.png")
	m.Souls.die(m,p);game.soul_view.update(game)
	check(m.state.corpses[p.corpse_uid].appearance==applied and game.soul_view.bodies[p.corpse_uid].human_visual.gender=="female","corpse retains the selected human appearance")
	game.queue_free();await process_frame;await process_frame
	print("APPEARANCE failures=",failures);quit(1 if failures else 0)

