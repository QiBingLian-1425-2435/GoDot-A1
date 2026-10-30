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
	check(toggle!=null and not toggle.button_pressed,"movement speed display defaults off")
	check(bonus!=null and int(bonus.get_item_metadata(bonus.selected))==150,"More exposes enhanced reward as default")
	ui.update_state({"players":{},"jump_chain_bonus":200},1,"client","")
	check(bonus.disabled and int(bonus.get_item_metadata(bonus.selected))==200,"client sees host reward but cannot edit it")
	ui.update_state({"players":{},"jump_chain_bonus":150},1,"offline","")
	check(not bonus.disabled,"solo player can edit chained-jump reward")
	var model=Model.new();model.add_player(1,"host")
	ui.action_requested.connect(func(action:String,payload:Dictionary)->void:
		if action=="set_jump_chain_bonus":model.command(1,action,payload))
	bonus.item_selected.emit(2)
	check(int(model.state.jump_chain_bonus)==200,"More selection reaches host-authoritative rule")
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
	ui.queue_free();await process_frame
	var restored=HUD.new();restored.display_preferences_path=path;root.add_child(restored)
	restored.show_game();restored.update_movement_speed(7.10)
	check(restored.show_movement_speed and restored._movement_speed_label.visible,"movement speed preference survives a new HUD instance")
	restored.queue_free();await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Texts.set_locale("zh_CN",false)
	print("MORE_SETTINGS checks=",checks," failures=",failures);quit(1 if failures else 0)
