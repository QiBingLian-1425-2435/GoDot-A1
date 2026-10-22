extends RefCounted
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
	ctx._label(ctx._menu_title, "ESCAPE FROM", Rect2(12,0,600,35), 27, ctx.GOLD)
	var title = ctx._label(ctx._menu_title, "逃离鸭科夫", Rect2(0,35,720,105), 86, Color("fff0b0"))
	title.add_theme_font_override("font", ctx._bold_font)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color("273942"))
	var en = ctx._label(ctx._menu_title, "D U C K O V", Rect2(9,143,650,62), 47, Color("f1db99"))
	en.add_theme_font_override("font", ctx._bold_font)
	ctx._label(ctx._menu_title, "基 地  ·  合 作 生 存", Rect2(13,214,520,30), 17, Color("a6c5c7"))
	ctx._menu_buttons = Control.new()
	ctx._menu_buttons.position = Vector2(112,382)
	ctx._menu_buttons.size = Vector2(340,410)
	ctx._menu_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctx._menu.add_child(ctx._menu_buttons)
	ctx._menu_button("继续游戏", 0, ctx.GREEN, func() -> void: ctx.action_requested.emit("solo", {}))
	ctx._menu_button("Steam 联机", 1, ctx.TEAL, ctx._open_steam)
	ctx._menu_button("设    置", 2, ctx.TEAL, ctx._open_settings)
	ctx._menu_button("操作指南", 3, ctx.TEAL, ctx._open_help)
	ctx._menu_button("退出游戏", 4, ctx.TEAL, func() -> void: ctx.action_requested.emit("quit", {}))
	ctx._press_screen = Button.new()
	ctx._press_screen.position = Vector2(104,405)
	ctx._press_screen.size = Vector2(600,200)
	ctx._press_screen.text = "—  点击屏幕继续  —"
	ctx._press_screen.add_theme_font_size_override("font_size", 25)
	ctx._press_screen.add_theme_color_override("font_color", Color("e1e7d8"))
	ctx._press_screen.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	ctx._press_screen.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	ctx._press_screen.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	ctx._press_screen.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	ctx._press_screen.pressed.connect(ctx._reveal_menu)
	ctx._menu.add_child(ctx._press_screen)
	ctx._label(ctx._menu, "欢迎回家，鸭鸭。", Rect2(114,836,700,30), 18, Color("c0cec8"))
	ctx._label(ctx._menu, "基地重制版   /   合作模式", Rect2(1120,842,420,26), 15, Color("9bb1b8"), HORIZONTAL_ALIGNMENT_RIGHT)

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
	ctx._dialog_panel("设置",Vector2(640,570))
	ctx._label(ctx._dialog,"主音量",Rect2(34,105,240,32),21,ctx.INK)
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
	ctx._label(ctx._dialog,"显示模式",Rect2(34,185,240,32),21,ctx.INK)
	var fullscreen = CheckButton.new()
	fullscreen.text = "全屏显示"
	fullscreen.position = Vector2(250,182)
	fullscreen.size = Vector2(340,42)
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(func(value: bool) -> void:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
		ctx.action_requested.emit("settings",{"fullscreen":value}))
	ctx._dialog.add_child(fullscreen)
	ctx._label(ctx._dialog,"弹药规则",Rect2(34,263,200,32),21,ctx.INK)
	var infinite = CheckButton.new()
	infinite.name = "InfiniteReserve"
	infinite.text = "无限备弹"
	infinite.position = Vector2(250,260)
	infinite.size = Vector2(340,42)
	infinite.button_pressed = ctx._state.get("infinite_reserve",false)
	infinite.disabled = ctx._mode in ["client","join"]
	infinite.toggled.connect(func(value: bool) -> void:
		ctx.action_requested.emit("set_infinite_reserve",{"enabled":value}))
	ctx._dialog.add_child(infinite)
	ctx._label(ctx._dialog,"房主设置，全队生效；仍需按 R 换弹。仅当前运行期间保留。",Rect2(34,320,570,50),16,ctx.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var voice_mute=CheckButton.new()
	voice_mute.name="VoiceMute"
	voice_mute.text="静音队伍语音（麦克风和收听）"
	voice_mute.position=Vector2(34,375);voice_mute.size=Vector2(570,42)
	voice_mute.button_pressed=ctx.voice_muted
	voice_mute.toggled.connect(func(value: bool) -> void:
		ctx.voice_muted=value;ctx.action_requested.emit("settings",{"voice_muted":value}))
	ctx._dialog.add_child(voice_mute)
	ctx._button(ctx._dialog,"完成",Rect2(170,479,300,54),ctx._close_dialog,ctx.GREEN,23)

static func _open_help(ctx) -> void:
	ctx._dialog_panel("操作指南",Vector2(720,712))
	var rows = [["Q（按住）","附近20米队伍语音"],["W / A / S / D","移动"],["鼠标","朝向 / 瞄准方向"],["Shift / C / 空格","冲刺 / 蹲下 / 翻滚"],["鼠标左键 / 右键","射击 / 瞄准"],["R / E","装填 / 互动"],["Tab / Esc","背包 / 菜单"],["1 / 2 · 4 / 5","换枪 · 医疗 / 饮水"],["拖动物品","移动、交换或装备"],["Ctrl 点击 / 右键","快速存取 / 物品操作"]]
	for i in range(rows.size()):
		ctx._label(ctx._dialog,rows[i][0],Rect2(34,95+i*48,290,37),19,ctx.GOLD)
		ctx._label(ctx._dialog,rows[i][1],Rect2(327,95+i*48,360,37),19,ctx.INK)
		ctx._line(ctx._dialog,Vector2(34,134+i*48),Vector2(652,1),Color(0.4,0.54,0.51,0.2))
	ctx._button(ctx._dialog,"知道了",Rect2(210,618,300,54),ctx._close_dialog,ctx.GREEN,23)
