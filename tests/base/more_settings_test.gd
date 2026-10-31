extends SceneTree
const HUD=preload("res://ui/base_hud.gd")
const MenuScreen=preload("res://ui/menu/menu_screen.gd")
const Texts=preload("res://features/localization/game_text.gd")
const Model=preload("res://features/base/base_model.gd")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func run():
	var path:="user://more_settings_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var ui=HUD.new();ui.display_preferences_path=path;root.add_child(ui)
	ui.show_game();ui._open_settings()
	var more:Button=null
	for child in ui._dialog.get_children():
		if child is Button and child.text==Texts.resolve("⟦settings.more⟧"):more=child
	check(more!=null,"settings exposes More entry")
	more.pressed.emit()
	var toggle:CheckButton=ui._dialog.get_node_or_null("ShowMovementSpeed")
	var bonus:OptionButton=ui._dialog.get_node_or_null("JumpChainBonus")
	var max_speed:OptionButton=ui._dialog.get_node_or_null("JumpChainMaxSpeed")
	var reward_window:OptionButton=ui._dialog.get_node_or_null("JumpRewardWindow")
	check(toggle!=null and not toggle.button_pressed,"movement speed display defaults off")
	check(bonus!=null and int(bonus.get_item_metadata(bonus.selected))==150,"More exposes enhanced reward as default")
	check(max_speed!=null and int(max_speed.get_item_metadata(max_speed.selected))==18,"More exposes 18 m/s default cap")
	check(reward_window!=null and int(reward_window.get_item_metadata(reward_window.selected))==70,"More exposes 70 ms precision window")
	ui.update_state({"players":{},"jump_chain_bonus":200,"jump_chain_max_speed":30,"jump_reward_window_ms":130},1,"client","")
	check(bonus.disabled and max_speed.disabled and reward_window.disabled and int(max_speed.get_item_metadata(max_speed.selected))==30,"client sees host jump rules but cannot edit them")
	ui.update_state({"players":{},"jump_chain_bonus":150,"jump_chain_max_speed":18,"jump_reward_window_ms":70},1,"offline","")
	check(not bonus.disabled and not max_speed.disabled and not reward_window.disabled,"solo player can edit chained-jump rules")
	var model=Model.new();model.add_player(1,"host")
	ui.action_requested.connect(func(action:String,payload:Dictionary)->void:
		if action.begins_with("set_jump_"):model.command(1,action,payload))
	bonus.item_selected.emit(2)
	max_speed.item_selected.emit(3)
	reward_window.item_selected.emit(2)
	check(int(model.state.jump_chain_bonus)==200 and int(model.state.jump_chain_max_speed)==30 and int(model.state.jump_reward_window_ms)==100,"More selections reach host-authoritative rules")
	toggle.button_pressed=true
	ui.update_movement_speed(6.5934)
	check(ui._movement_speed_label.visible and ui._movement_speed_label.text.contains("6.59"),"enabled HUD shows precise movement speed")
	if DisplayServer.get_name()!="headless":
		await process_frame;await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/base_tests"))
		check(root.get_texture().get_image().save_png("res://artifacts/base_tests/more_settings_speed.png")==OK,"capture More setting and speed HUD")
	Texts.set_locale("en",false)
	check(toggle.text=="Show Movement Speed" and ui._movement_speed_label.text.contains("Movement Speed"),"More option and HUD switch language immediately")
	check(Texts.resolve("⟦settings.jump_chain_bonus⟧")=="Chained Jump Reward","reward setting switches language immediately")
	check(Texts.resolve("⟦settings.jump_chain_max_speed⟧")=="Maximum Chain Speed" and Texts.resolve("⟦settings.jump_reward_window⟧")=="Reward Timing Window","speed and timing settings switch language immediately")
	ui.queue_free();await process_frame
	var restored=HUD.new();restored.display_preferences_path=path;root.add_child(restored)
	restored.show_game();restored.update_movement_speed(7.10)
	check(restored.show_movement_speed and restored._movement_speed_label.visible,"movement speed preference survives a new HUD instance")
	restored.queue_free();await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Texts.set_locale("zh_CN",false)
	print("MORE_SETTINGS checks=",checks," failures=",failures);quit(1 if failures else 0)
