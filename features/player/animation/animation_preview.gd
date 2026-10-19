extends Node3D
## A standalone inspection scene using the same actor and AnimationTree as gameplay.
const Actor = preload("res://features/player/base_actor.gd")
const G = preload("res://features/geometry/geometry.gd")
const MODES := ["idle", "walk", "run", "crouch_idle", "crouch_walk", "aim", "fire", "reload", "drink", "heal", "pickup", "equip"]
const TITLES := ["待机 / 呼吸", "行走 / 摆步", "冲刺 / 重心前倾", "静止蹲伏", "蹲行", "瞄准 / 横移", "射击 / 后坐", "换弹 / 装填", "饮水 / 进食", "包扎 / 使用物品", "俯身 / 拾取", "切枪 / 交互"]
var actors: Array = []
var data: Array = []
var clock := 0.0
var paused := false
var camera: Camera3D
var frame := 0
var capture_dir := ""
var status: Label

func _ready() -> void:
	DisplayServer.window_set_title("鸭科夫基地 · 人物动作预览")
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("172627")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a9b9b0")
	env.ambient_light_energy = .4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-28,0)
	sun.light_color = Color("ffe9bb")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30,155,0)
	fill.light_color = Color("afdbdf")
	fill.light_energy = .25
	add_child(fill)
	G.box(self,Vector3(0,-.20,0),Vector3(30,.2,24),Color("233436"))
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.1
	add_child(camera)
	camera.position = Vector3(0,12,20)
	camera.look_at(Vector3(0,.5,.1))
	camera.current = true
	for i in range(MODES.size()):
		var at := Vector2((i%4-1.5)*3.8, (i/4-1)*4.5)
		G.box(self,Vector3(at.x,-.035,at.y),Vector3(3.25,.15,3.35),Color("354848"))
		G.box(self,Vector3(at.x,.05,at.y+1.68),Vector3(3.25,.03,.045),Color("b9ac7b"),.4)
		var actor := Actor.new()
		add_child(actor)
		actor.setup(Color("7c8a64"), "")
		actor.nameplate.visible = false
		actors.append(actor)
		data.append({"pos":at,"velocity":Vector2.ZERO,"aim":Vector2(-.40,1).normalized(),"equipment":{"weapon":{"kind":"rifle"},"backpack":{"kind":"backpack"},"helmet":{"kind":"helmet"},"armor":{"kind":"armor"}},"shots":0,"anim_seq":0})
		var title := G.text(self,TITLES[i],Vector3(at.x,.04,at.y+1.35),25,Color("e9dfba"))
		title.pixel_size = .011
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		title.no_depth_test = true
		title.outline_size = 4
		var number := G.text(self,"%02d"%(i+1),Vector3(at.x-1.3,.06,at.y-1.3),20,Color("819c98"))
		number.rotation_degrees.x = -90
	_build_ui()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--animation-capture="):
			capture_dir = arg.trim_prefix("--animation-capture=")
			DirAccess.make_dir_recursive_absolute(capture_dir)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",42)
	margin.add_theme_constant_override("margin_top",25)
	margin.add_theme_constant_override("margin_right",42)
	margin.add_theme_constant_override("margin_bottom",25)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "DUCKOV BASE   /   CHARACTER MOTION"
	eyebrow.add_theme_color_override("font_color",Color("b4b88d"))
	eyebrow.add_theme_font_size_override("font_size",15)
	column.add_child(eyebrow)
	var title := Label.new()
	title.text = "人物动作 · 战术鸭"
	title.add_theme_font_size_override("font_size",30)
	column.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	status = Label.new()
	status.text = "空格  暂停 / 继续      Enter  返回游戏      鼠标滚轮  缩放      Esc  退出预览"
	status.add_theme_font_size_override("font_size",17)
	status.add_theme_color_override("font_color",Color("bac7bf"))
	column.add_child(status)

func _process(delta: float) -> void:
	frame += 1
	if not paused: clock += delta
	for i in range(actors.size()):
		var state: Dictionary = data[i]
		var mode: String = MODES[i]
		var velocity := Vector2.ZERO
		state.crouch = mode.begins_with("crouch")
		state.sprint = mode == "run"
		state.ads = mode == "aim" or mode == "fire"
		if mode in ["walk", "run", "crouch_walk"]:
			velocity = Vector2(0, 6.1 if mode == "run" else 1.78 if mode == "crouch_walk" else 3.7)
		if mode == "aim": velocity = Vector2(2.2,0)
		state.velocity = velocity
		state.reloading = mode == "reload" and fmod(clock,2.3) < 1.6
		state.reload_progress = minf(fmod(clock,2.3)/1.6, 1)
		if mode == "fire": state.shots = int(clock*3.0)
		if mode in ["drink", "heal", "pickup", "equip"]:
			var event: String = mode
			if int(clock/3.0)%2 == 1:
				if mode == "drink": event = "eat"
				if mode == "equip": event = "interact"
			var duration: float = {"drink":1.3,"eat":1.3,"heal":1.5,"pickup":.65,"equip":.5,"interact":.8}[event]
			state.anim_seq = int(clock/3.0)+1
			state.anim_action = event
			state.anim_time = minf(fmod(clock,3),duration)
			state.anim_duration = duration
		actors[i].update_actor(state, 0 if paused else delta)
	if not capture_dir.is_empty() and frame%3 == 0 and frame <= 180:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_dir.path_join("frame_%03d.png"%frame))
	if not capture_dir.is_empty() and frame >= 181: get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: paused = not paused
			KEY_ENTER: get_tree().change_scene_to_file("res://app/main.tscn")
			KEY_ESCAPE: get_tree().quit()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: camera.size = maxf(8,camera.size-1)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera.size = minf(22,camera.size+1)
