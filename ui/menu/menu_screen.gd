extends RefCounted
const Texts = preload("res://features/localization/game_text.gd")
## Migrated reference behavior; called only through the owning composition/model.

static func _build_menu(ctx) -> void:
	ctx._menu = ctx._full_control(ctx._root)
	# Only translucent panels cover the world. The 3D security-camera backdrop stays visible.
	var left_fade = GradientTexture2D.new()
	var gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(0.025,0.055,0.095,0.72), Color(0.025,0.055,0.095,0.28),Color(0.025,0.055,0.095,0.0)])
	gradient.offsets = PackedFloat32Array([0.0,0.45,1.0])
	left_fade.gradient = gradient
	left_fade.fill_from = Vector2.ZERO
	left_fade.fill_to = Vector2.RIGHT
	var fade = TextureRect.new()
	fade.texture = left_fade
	fade.position = Vector2.ZERO
	fade.size = Vector2(1250,900)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctx._menu.add_child(fade)
	ctx._menu_title = Control.new()
	ctx._menu_title.position = Vector2(96,94)
	ctx._menu_title.size = Vector2(700,245)
	ctx._menu_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctx._menu.add_child(ctx._menu_title)
	ctx._label(ctx._menu_title, "⟦menu_screen.001⟧", Rect2(12,0,600,35), 27, ctx.GOLD)
	var title = ctx._label(ctx._menu_title, "⟦menu_screen.002⟧", Rect2(0,35,720,105), 86, Color("fff0b0"))
	title.add_theme_font_override("font", ctx._bold_font)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color("273942"))
	var en = ctx._label(ctx._menu_title, "⟦menu_screen.003⟧", Rect2(9,143,650,62), 47, Color("f1db99"))
	en.add_theme_font_override("font", ctx._bold_font)
	ctx._label(ctx._menu_title, "⟦menu_screen.004⟧", Rect2(13,214,520,30), 17, Color("a6c5c7"))
	ctx._menu_buttons = Control.new()
	ctx._menu_buttons.position = Vector2(112,382)
	ctx._menu_buttons.size = Vector2(340,410)
	ctx._menu_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctx._menu.add_child(ctx._menu_buttons)
	ctx._menu_button("⟦base_hud.037⟧", 0, ctx.GREEN, func() -> void: ctx.action_requested.emit("solo", {}))
	ctx._menu_button("⟦menu_screen.005⟧", 1, ctx.TEAL, ctx._open_steam)
	ctx._menu_button("⟦menu_screen.006⟧", 2, ctx.TEAL, ctx._open_settings)
	ctx._menu_button("⟦base_hud.039⟧", 3, ctx.TEAL, ctx._open_help)
	ctx._menu_button("⟦menu_screen.007⟧", 4, ctx.TEAL, func() -> void: ctx.action_requested.emit("quit", {}))
	ctx._press_screen = Button.new()
	ctx._press_screen.position = Vector2(104,405)
	ctx._press_screen.size = Vector2(600,200)
	Texts.bind(ctx._press_screen, "⟦menu_screen.008⟧", "text")
	ctx._press_screen.add_theme_font_size_override("font_size", 25)
	ctx._press_screen.add_theme_color_override("font_color", Color("e1e7d8"))
	ctx._press_screen.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	ctx._press_screen.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	ctx._press_screen.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	ctx._press_screen.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	ctx._press_screen.pressed.connect(ctx._reveal_menu)
	ctx._menu.add_child(ctx._press_screen)
	ctx._label(ctx._menu, "⟦menu_screen.009⟧", Rect2(114,836,700,30), 18, Color("c0cec8"))
	ctx._label(ctx._menu, "⟦menu_screen.010⟧", Rect2(1120,842,420,26), 15, Color("9bb1b8"), HORIZONTAL_ALIGNMENT_RIGHT)

static func _reveal_menu(ctx) -> void:
	ctx._menu_revealed = true
	ctx._press_screen.visible = false
	ctx._menu_buttons.visible = true

static func _menu_button(ctx, text: String, index: int, color: Color, callback: Callable) -> Button:
	var button = ctx._button(ctx._menu_buttons, text, Rect2(0,index*68,332,58), callback, color, 28, 16)
	button.add_theme_font_override("font", ctx._bold_font)
	button.add_theme_constant_override("outline_size", 2)
	button.add_theme_color_override("font_outline_color", color.darkened(0.24))
	return button

static func _open_settings(ctx) -> void:
	ctx._dialog_panel("⟦base_hud.040⟧",Vector2(640,890))
	ctx._label(ctx._dialog,"⟦menu_screen.011⟧",Rect2(34,105,240,32),21,ctx.INK)
	var volume = HSlider.new()
	volume.position = Vector2(250,111)
	volume.size = Vector2(340,28)
	volume.min_value = 0
	volume.max_value = 100
	volume.value = db_to_linear(AudioServer.get_bus_volume_db(0))*100.0
	volume.value_changed.connect(func(value: float) -> void:
		AudioServer.set_bus_volume_db(0,linear_to_db(maxf(value/100.0,0.0001)))
		ctx.action_requested.emit("settings",{"volume":value/100.0}))
	ctx._dialog.add_child(volume)
	ctx._label(ctx._dialog,"⟦menu_screen.012⟧",Rect2(34,185,240,32),21,ctx.INK)
	var fullscreen = CheckButton.new()
	Texts.bind(fullscreen, "⟦menu_screen.013⟧", "text")
	fullscreen.position = Vector2(250,182)
	fullscreen.size = Vector2(340,42)
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(func(value: bool) -> void:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
		ctx.action_requested.emit("settings",{"fullscreen":value}))
	ctx._dialog.add_child(fullscreen)
	ctx._label(ctx._dialog,"⟦menu_screen.014⟧",Rect2(34,263,200,32),21,ctx.INK)
	var infinite = CheckButton.new()
	infinite.name = "InfiniteReserve"
	Texts.bind(infinite, "⟦menu_screen.015⟧", "text")
	infinite.position = Vector2(250,260)
	infinite.size = Vector2(340,42)
	infinite.button_pressed = ctx._state.get("infinite_reserve",false)
	infinite.disabled = ctx._mode in ["client","join"]
	infinite.toggled.connect(func(value: bool) -> void:
		ctx.action_requested.emit("set_infinite_reserve",{"enabled":value}))
	ctx._dialog.add_child(infinite)
	ctx._label(ctx._dialog,"⟦menu_screen.016⟧",Rect2(34,320,570,50),16,ctx.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctx._label(ctx._dialog,"⟦menu_screen.017⟧",Rect2(34,375,200,32),21,ctx.INK)
	var stamina = CheckButton.new()
	stamina.name = "InfiniteStamina"
	Texts.bind(stamina, "⟦menu_screen.018⟧", "text")
	stamina.position = Vector2(250,372)
	stamina.size = Vector2(340,42)
	stamina.button_pressed = ctx._state.get("infinite_stamina",false)
	stamina.disabled = ctx._mode in ["client","join"]
	stamina.toggled.connect(func(value: bool) -> void:
		ctx.action_requested.emit("set_infinite_stamina",{"enabled":value}))
	ctx._dialog.add_child(stamina)
	ctx._label(ctx._dialog,"⟦menu_screen.019⟧",Rect2(34,430,570,50),16,ctx.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var voice_mute=CheckButton.new()
	voice_mute.name="VoiceMute"
	Texts.bind(voice_mute, "⟦menu_screen.020⟧", "text")
	voice_mute.position=Vector2(34,485);voice_mute.size=Vector2(570,42)
	voice_mute.button_pressed=ctx.voice_muted
	voice_mute.toggled.connect(func(value: bool) -> void:
		ctx.voice_muted=value;ctx.action_requested.emit("settings",{"voice_muted":value}))
	ctx._dialog.add_child(voice_mute)
	var always_on=CheckButton.new()
	always_on.name="VoiceAlwaysOn"
	Texts.bind(always_on, "⟦settings.voice_always_on⟧", "text")
	always_on.position=Vector2(34,535);always_on.size=Vector2(570,42)
	always_on.button_pressed=ctx.voice_always_on
	always_on.toggled.connect(func(value: bool) -> void:
		ctx.action_requested.emit("settings",{"voice_always_on":value}))
	ctx._dialog.add_child(always_on)
	ctx._label(ctx._dialog,"⟦settings.language⟧",Rect2(34,602,200,32),21,ctx.INK)
	var language := OptionButton.new()
	language.name = "LanguageSelect"
	language.position = Vector2(250,598)
	language.size = Vector2(340,42)
	language.add_theme_font_size_override("font_size",21)
	var locales := Texts.available_locales()
	for code in locales:
		var index := Texts.add_item(language, str(locales[code].name))
		language.set_item_metadata(index, code)
		if code == Texts.locale(): language.select(index)
	language.item_selected.connect(func(index: int) -> void:
		if Texts.set_locale(str(language.get_item_metadata(index))) != OK:
			ctx.toast("⟦settings.language_save_failed⟧"))
	ctx._dialog.add_child(language)
	ctx._button(ctx._dialog,"⟦keys.title⟧",Rect2(34,660,276,42),ctx._open_key_bindings,ctx.TEAL,21)
	ctx._button(ctx._dialog,"⟦settings.more⟧",Rect2(328,660,276,42),func() -> void:_open_more_settings(ctx),ctx.TEAL,21)
	ctx._button(ctx._dialog,"⟦menu_screen.021⟧",Rect2(170,719,300,44),ctx._close_dialog,ctx.GREEN,23)
	for child in ctx._dialog.get_children():
		if child is Control and child.position.y >= 485:
			child.position.y += 100
	var credits := CheckButton.new()
	credits.name = "InfiniteCredits"
	Texts.bind(credits, "⟦settings.infinite_credits⟧", "text")
	credits.position = Vector2(34,485)
	credits.size = Vector2(570,42)
	credits.button_pressed = ctx._state.get("infinite_credits",false)
	credits.disabled = ctx._mode in ["client","join"]
	credits.toggled.connect(func(value: bool) -> void:
		ctx.action_requested.emit("set_infinite_credits",{"enabled":value}))
	ctx._dialog.add_child(credits)
	ctx._label(ctx._dialog,"⟦settings.infinite_credits_hint⟧",Rect2(34,535,570,48),16,ctx.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

static func _open_more_settings(ctx) -> void:
	ctx._dialog_panel("⟦settings.more⟧",Vector2(640,850))
	ctx._label(ctx._dialog,"⟦settings.more_hint⟧",Rect2(34,92,570,52),17,ctx.MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var speed:=CheckButton.new()
	speed.name="ShowMovementSpeed"
	Texts.bind(speed,"⟦settings.show_movement_speed⟧","text")
	speed.position=Vector2(34,168);speed.size=Vector2(570,44)
	speed.button_pressed=ctx.show_movement_speed
	speed.toggled.connect(ctx.set_show_movement_speed)
	ctx._dialog.add_child(speed)
	ctx._label(ctx._dialog,"⟦settings.show_movement_speed_hint⟧",Rect2(34,218,570,58),16,ctx.MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	ctx._label(ctx._dialog,"⟦settings.jump_chain_bonus⟧",Rect2(34,300,230,32),20,ctx.INK)
	var bonus:=OptionButton.new()
	bonus.name="JumpChainBonus";bonus.position=Vector2(300,294);bonus.size=Vector2(304,42)
	bonus.add_theme_font_size_override("font_size",20)
	for value in [100,150,200]:
		var index:=Texts.add_item(bonus,Texts.format("⟦settings.jump_chain_bonus_option⟧",value))
		bonus.set_item_metadata(index,value)
		if value==int(ctx._state.get("jump_chain_bonus",150)):bonus.select(index)
	bonus.disabled=ctx._mode in ["client","join"]
	bonus.item_selected.connect(func(index:int)->void:ctx.action_requested.emit("set_jump_chain_bonus",{"value":int(bonus.get_item_metadata(index))}))
	ctx._dialog.add_child(bonus)
	ctx._label(ctx._dialog,"⟦settings.jump_chain_bonus_hint⟧",Rect2(34,350,570,76),16,ctx.MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	ctx._label(ctx._dialog,"⟦settings.jump_chain_max_speed⟧",Rect2(34,444,250,32),20,ctx.INK)
	var max_speed:=OptionButton.new()
	max_speed.name="JumpChainMaxSpeed";max_speed.position=Vector2(300,438);max_speed.size=Vector2(304,42)
	max_speed.add_theme_font_size_override("font_size",20)
	for value in [12,18,24,30]:
		var index:=Texts.add_item(max_speed,Texts.format("⟦settings.jump_chain_max_speed_option⟧",value))
		max_speed.set_item_metadata(index,value)
		if value==int(ctx._state.get("jump_chain_max_speed",18)):max_speed.select(index)
	max_speed.disabled=ctx._mode in ["client","join"]
	max_speed.item_selected.connect(func(index:int)->void:ctx.action_requested.emit("set_jump_chain_max_speed",{"value":int(max_speed.get_item_metadata(index))}))
	ctx._dialog.add_child(max_speed)
	ctx._label(ctx._dialog,"⟦settings.jump_chain_max_speed_hint⟧",Rect2(34,490,570,58),16,ctx.MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	ctx._label(ctx._dialog,"⟦settings.jump_reward_window⟧",Rect2(34,570,250,32),20,ctx.INK)
	var reward_window:=OptionButton.new()
	reward_window.name="JumpRewardWindow";reward_window.position=Vector2(300,564);reward_window.size=Vector2(304,42)
	reward_window.add_theme_font_size_override("font_size",20)
	for value in [40,70,100,130]:
		var index:=Texts.add_item(reward_window,Texts.format("⟦settings.jump_reward_window_option⟧",value))
		reward_window.set_item_metadata(index,value)
		if value==int(ctx._state.get("jump_reward_window_ms",70)):reward_window.select(index)
	reward_window.disabled=ctx._mode in ["client","join"]
	reward_window.item_selected.connect(func(index:int)->void:ctx.action_requested.emit("set_jump_reward_window",{"value":int(reward_window.get_item_metadata(index))}))
	ctx._dialog.add_child(reward_window)
	ctx._label(ctx._dialog,"⟦settings.jump_reward_window_hint⟧",Rect2(34,616,570,86),16,ctx.MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	ctx._button(ctx._dialog,"⟦keys.back⟧",Rect2(170,752,300,48),ctx._open_settings,ctx.GREEN,22)

static func _open_help(ctx) -> void:
	ctx._open_key_bindings()
