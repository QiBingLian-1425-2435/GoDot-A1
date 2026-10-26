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
	ctx._dialog_panel("⟦base_hud.040⟧",Vector2(640,790))
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
	ctx._button(ctx._dialog,"⟦keys.title⟧",Rect2(34,660,570,42),ctx._open_key_bindings,ctx.TEAL,21)
	ctx._button(ctx._dialog,"⟦menu_screen.021⟧",Rect2(170,719,300,44),ctx._close_dialog,ctx.GREEN,23)

static func _open_help(ctx) -> void:
	ctx._open_key_bindings()
