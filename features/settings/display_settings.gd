extends Node
## Local window preferences; no shared gameplay state.
const PRESETS:Array[Vector2i]=[Vector2i(960,540),Vector2i(1280,720),Vector2i(1366,768),Vector2i(1440,810),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]
var settings_path:="user://video_settings.cfg"
var resolution:=Vector2i(1440,810)
var fullscreen:=false

func _ready()->void:
	var config:=ConfigFile.new()
	resolution=fit_resolution(get_window().size)
	fullscreen=is_fullscreen()
	if config.load(settings_path)!=OK:return
	var saved:Variant=config.get_value("display","resolution",resolution)
	if saved is Vector2i and saved.x>=960 and saved.y>=540:resolution=fit_resolution(saved)
	fullscreen=bool(config.get_value("display","fullscreen",false))
	if can_change_window():_apply()

static func can_change_window()->bool:
	return DisplayServer.get_name()!="headless" and not Engine.is_embedded_in_editor()

static func is_fullscreen()->bool:
	return DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]

static func available_size()->Vector2i:
	if DisplayServer.get_name()=="headless":return Vector2i(3840,2160)
	# Leave room for native borders and the title bar, also on a small screen.
	return (DisplayServer.screen_get_usable_rect().size-Vector2i(32,64)).max(Vector2i(640,360))

static func fit_resolution(value:Vector2i)->Vector2i:
	var limit:=available_size()
	var scale:=minf(1.0,minf(float(limit.x)/maxi(value.x,1),float(limit.y)/maxi(value.y,1)))
	return Vector2i(Vector2(value)*scale).max(Vector2i(640,360))

func options()->Array[Vector2i]:
	var result:Array[Vector2i]=[]
	var limit:=available_size()
	for value in PRESETS:
		if value.x<=limit.x and value.y<=limit.y:result.append(value)
	if not result.has(resolution):result.append(resolution)
	return result

func change(payload:Dictionary)->Error:
	if not can_change_window():return ERR_UNAVAILABLE
	if payload.has("resolution"):
		var value:Variant=payload.resolution
		if not value is Vector2i or not options().has(value):return ERR_INVALID_PARAMETER
		resolution=value
	fullscreen=bool(payload.get("fullscreen",is_fullscreen()))
	_apply()
	var config:=ConfigFile.new()
	config.set_value("display","resolution",resolution)
	config.set_value("display","fullscreen",fullscreen)
	return config.save(settings_path)

func _apply()->void:
	var window:=get_window()
	if fullscreen:
		window.mode=Window.MODE_FULLSCREEN
	else:
		window.mode=Window.MODE_WINDOWED
		window.borderless=false
		window.size=fit_resolution(resolution)
		var usable:=DisplayServer.screen_get_usable_rect(window.current_screen)
		window.position=usable.position+(usable.size-window.size)/2
