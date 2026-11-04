extends CanvasLayer
const Quick=preload("res://features/player/quick_slots.gd")
const QuickSlot=preload("res://ui/widgets/quick_slot.gd")
const Keys = preload("res://features/player/key_bindings.gd")
const KeyBindingsPanel = preload("res://ui/menu/key_bindings_panel.gd")
var _key_bindings_panel: Control
const Texts = preload("res://features/localization/game_text.gd")

const ContainerPanel = preload("res://ui/inventory/container_panel.gd")
const InventoryPanel = preload("res://ui/inventory/inventory_panel.gd")
const MenuScreen = preload("res://ui/menu/menu_screen.gd")
const SteamPanel = preload("res://ui/network/steam_panel.gd")
const Souls = preload("res://features/rescue/soul_rules.gd")
const SoulPanel = preload("res://ui/soul_panel.gd")
var _soul_panel: Control
var _soul_signature := ""
var _soul_status: Label

signal action_requested(action: String, payload: Dictionary)

const Items = preload("res://features/inventory/item_catalog.gd")
const Slot = preload("res://ui/widgets/item_slot.gd")
const Portrait = preload("res://ui/widgets/base_portrait.gd")
const UiTheme = preload("res://ui/widgets/ui_theme.gd")
const StatBar = preload("res://ui/widgets/stat_bar.gd")
const INK := UiTheme.INK
const MUTED := UiTheme.MUTED
const GOLD := UiTheme.GOLD
const TEAL := UiTheme.TEAL
const GREEN := UiTheme.GREEN
const PANEL := Color(0.063, 0.102, 0.114, 0.96)
const FAINT_TEXT := UiTheme.FAINT

var _loot_uid := ""
var _loot_dismissed_uid := ""
var _loot_selected := -1
var _loot_page := 0
var _loot_slots: Array = []
var _loot_buttons: Array = []
var _loot_bag: Array = []
var _loot_status: Label
var _loot_weight: Label
var _loot_detail: Label
var _loot_progress: ProgressBar
var _inventory_filter:="all"
var _sort_mode:="type"
var _shop_kind:=""
var _shop_mode:=""
var _shop_details:Label
var voice_muted:=false
var voice_always_on:=false
var show_movement_speed:=false
var show_jump_chain:=false
var display_preferences_path:="user://display_preferences.cfg"
var _voice_label:Label
var _movement_speed_label:Label
var _jump_chain_label:Label
var _root: Control
var _menu: Control
var _menu_buttons: Control
var _press_screen: Button
var _hud: Control
var _inventory: Control
var _dialog: Control
var _pause_panel: Control
var _pause_shade: ColorRect
var _popup: PopupMenu
var _context_data: Dictionary = {}
var _bag_slots: Array = []
var _stash_slots: Array = []
var _equip_slots: Dictionary = {}
var _quick_slots: Array = []
var _bars: Dictionary = {}
var _stat_labels: Dictionary = {}
var _inventory_stats: Dictionary = {}
var _state: Dictionary = {}
var _local_id := 1
var _mode := "solo"
var _status := ""
var _menu_revealed := false
var _in_game := false
var _stash_access := true
var _dialog_kind := ""
var _font: SystemFont
var _bold_font: SystemFont
var _interaction: Label
var _toast_label: Label
var _toast_timer := 0.0
var _network_label: Label
var _world_label: Label
var _world_note: Label
var _loading_panel: Control
var _loading_title: Label
var _ammo_label: Label
var _reload_label: Label
var _inventory_weight: Label
var _stash_note: Label
var _player_name: Label
var _credits_label: Label
var _details_name: Label
var _details_text: Label
var _portrait: Control
var _join_address: LineEdit
var _port_input: LineEdit
var _connection_text: Label
var _help_panel: Control
var _menu_title: Control
var _reticle: Control
var _connection_dispatched := false
var _steam_info: Dictionary = {"available":false,"initialized":false,"status":"⟦base_hud.001⟧","persona":"","app_id":480,"lobby_id":"","transport":"offline","pending":false,"scanning":false,"lobbies":[]}
var _steam_status: Label
var _steam_persona: Label
var _steam_connect_button: Button
var _steam_host_button: Button
var _steam_join_button: Button
var _steam_refresh_button: Button
var _steam_back_button: Button
var _steam_ip_button: Button
var _steam_lobby_input: LineEdit
var _steam_lobby_list: VBoxContainer
var _steam_empty_label: Label
var _steam_lobbies_shown: Array = []
var _steam_lobby_buttons: Array[Button] = []
var _steam_room_label: Label
var _steam_invite_button: Button
var _steam_copy_button: Button

func _ready() -> void:
	_load_display_preferences()
	layer = 20
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	_bold_font = SystemFont.new()
	_bold_font.font_names = _font.font_names
	_bold_font.font_weight = 700
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.theme = UiTheme.build(_font, 20)
	_build_menu()
	_build_hud()
	_build_inventory()
	_build_popup()
	_build_pause()
	_toast_label = _label(_root, "", Rect2(350, 160, 900, 46), 19, Color("f6e3b2"), HORIZONTAL_ALIGNMENT_CENTER)
	var toast_style := UiTheme.box(Color(0.045, 0.075, 0.085, 0.94), Color(UiTheme.GOLD, .55), 23, 1, 12)
	toast_style.border_width_left = 4
	_toast_label.add_theme_stylebox_override("normal", toast_style)
	_toast_label.z_index = 100
	_toast_label.visible = false
	show_menu()

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		_toast_label.visible = _toast_timer > 0.0
	if _press_screen and _press_screen.visible:
		_press_screen.modulate.a = 0.65 + sin(Time.get_ticks_msec() * 0.0025) * 0.25

func _input(event: InputEvent) -> void:
	if is_instance_valid(_key_bindings_panel) and _key_bindings_panel.capture(event):
		get_viewport().set_input_as_handled()
		return
	if not _in_game:
		if _press_screen.visible:
			if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
				_reveal_menu()
				get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and is_instance_valid(_dialog):
			_dialog_close_pressed()
			get_viewport().set_input_as_handled()

func show_menu() -> void:
	if is_instance_valid(_soul_panel): _soul_panel.hide()
	_in_game = false
	_menu.visible = true
	_hud.visible = false
	_inventory.visible = false
	_pause_panel.visible = false
	_pause_shade.visible = false
	_close_dialog()
	_popup.hide()
	_menu_buttons.visible = _menu_revealed
	_press_screen.visible = not _menu_revealed
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_game() -> void:
	_in_game = true
	_menu_revealed = true
	_menu.visible = false
	_hud.visible = true
	_inventory.visible = false
	_pause_panel.visible = false
	_pause_shade.visible = false
	_close_dialog()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func toggle_inventory(force_open: bool = false) -> void:
	if not _in_game:
		return
	_inventory.visible = true if force_open else not _inventory.visible
	_hud.visible = not _inventory.visible
	_pause_panel.visible = false
	_pause_shade.visible = false
	_popup.hide()
	if _inventory.visible:
		_close_dialog()
		_update_inventory()

func close_inventory() -> void:
	_inventory.visible = false
	_hud.visible = _in_game
	_popup.hide()
	if _dialog:
		_close_dialog()
	_pause_panel.visible = false
	_pause_shade.visible = false

func is_blocking() -> bool:
	return not _in_game or _inventory.visible or _pause_panel.visible or is_instance_valid(_dialog)

func inventory_is_open() -> bool:
	return _inventory.visible

func toggle_pause() -> void:
	if not _in_game:
		return
	if _inventory.visible or is_instance_valid(_dialog):
		close_inventory()
		return
	_pause_panel.visible = not _pause_panel.visible
	_pause_shade.visible = _pause_panel.visible

func set_stash_access(value: bool) -> void:
	_stash_access = value
	if _inventory:
		Texts.bind(_stash_note, "⟦base_hud.002⟧" if value else "⟦base_hud.003⟧", "text")
		for slot in _stash_slots:
			slot.locked = not value
			slot.modulate.a = 1.0 if value else 0.4

func set_world_loading(value: bool, title: String) -> void:
	if not is_instance_valid(_loading_panel):
		_loading_panel=_full_control(_root)
		var shade:=ColorRect.new();shade.color=Color(.02,.035,.042,.96)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_loading_panel.add_child(shade)
		var card:=_panel(_loading_panel,Rect2(500,330,600,250),UiTheme.SLATE,UiTheme.LINE,18)
		card.add_theme_stylebox_override("panel",UiTheme.panel(Color(UiTheme.SLATE,.97),UiTheme.LINE,18,30))
		_line(card,Vector2(40,38),Vector2(520,2),Color(UiTheme.AMBER,.8))
		_loading_title=_label(card,"",Rect2(30,62,540,64),27,INK,HORIZONTAL_ALIGNMENT_CENTER)
		var spinner:=preload("res://ui/widgets/loading_dots.gd").new()
		spinner.position=Vector2(270,130);spinner.size=Vector2(60,20);card.add_child(spinner)
		_button(card,"⟦base_hud.004⟧",Rect2(170,170,260,52),func():action_requested.emit("menu",{}),TEAL,20)
	Texts.bind(_loading_title, "⟦base_hud.005⟧"+title+"⟦base_hud.006⟧", "text")
	_loading_panel.visible=value

func update_state(state: Dictionary, local_id: int, mode: String, status: String) -> void:
	_state = state
	_local_id = local_id
	_mode = mode
	_status = status
	if is_instance_valid(_dialog):
		var infinite = _dialog.get_node_or_null("InfiniteReserve")
		if infinite != null:
			infinite.set_pressed_no_signal(state.get("infinite_reserve",false))
			infinite.disabled = mode in ["client","join"]
		var stamina = _dialog.get_node_or_null("InfiniteStamina")
		if stamina != null:
			stamina.set_pressed_no_signal(state.get("infinite_stamina",false))
			stamina.disabled = mode in ["client","join"]
		var credits = _dialog.get_node_or_null("InfiniteCredits")
		if credits != null:
			credits.set_pressed_no_signal(state.get("infinite_credits",false))
			credits.disabled = mode in ["client","join"]
		var chain_bonus:OptionButton=_dialog.get_node_or_null("JumpChainBonus")
		if chain_bonus!=null:
			for index in range(chain_bonus.item_count):
				if int(chain_bonus.get_item_metadata(index))==int(state.get("jump_chain_bonus",1)):chain_bonus.select(index)
			chain_bonus.disabled=mode in ["client","join"]
		for spec in [["JumpChainMaxSpeed","jump_chain_max_speed",18],["JumpRewardWindow","jump_reward_window_ms",70]]:
			var option:OptionButton=_dialog.get_node_or_null(spec[0])
			if option!=null:
				for index in range(option.item_count):
					if int(option.get_item_metadata(index))==int(state.get(spec[1],spec[2])):option.select(index)
				option.disabled=mode in ["client","join"]
	if not is_instance_valid(_root):
		return
	var p := _player()
	SoulPanel.sync(self)
	ContainerPanel.sync(self)
	var world_name: String = str(state.get("world","bunker"))
	Texts.bind(_world_label, {"bunker":"⟦base_hud.007⟧","surface":"⟦base_hud.008⟧","cave":"⟦base_hud.009⟧","city":"⟦base_hud.city⟧"}.get(world_name,"⟦base_hud.010⟧"), "text")
	Texts.bind(_world_note, "⟦base_hud.011⟧" if world_name=="bunker" else "⟦base_hud.012⟧", "text")
	var player_count := _players().size()
	var session_name := "⟦base_hud.013⟧" if world_name=="bunker" else "⟦base_hud.014⟧"
	if mode == "host":
		session_name = Texts.format("⟦base_hud.015⟧", player_count)
	elif mode == "client" or mode == "join":
		session_name = Texts.format("⟦base_hud.016⟧", player_count)
	Texts.bind(_network_label, session_name + ("  |  " + status if not status.is_empty() else ""), "text")
	if is_instance_valid(_connection_text):
		Texts.bind(_connection_text, status if not status.is_empty() else "⟦base_hud.017⟧", "text")
	if p.is_empty():
		return
	for key in ["hp", "stamina", "hunger", "thirst", "san"]:
		var value := float(p.get(key, 100.0))
		_bars[key].max_value = float(p.get("max_"+key,100))
		_bars[key].value = value
		Texts.bind(_stat_labels[key], Texts.format("⟦format.base_hud.001⟧", roundi(value)), "text")
	Texts.bind(_ammo_label, Texts.format("⟦format.base_hud.002⟧", int(p.get("ammo", 0))), "text")
	var reserve := 0
	for item in p.get("bag", []):
		if item.get("kind", "") == "ammo":
			reserve += int(item.get("count", 1))
	Texts.bind(_reload_label, Texts.format("⟦base_hud.018⟧", int(float(p.get("reload_progress", 0.0)) * 100.0)) if p.get("reloading", false) else (Texts.format("⟦base_hud.019⟧", Keys.display("reload")) if state.get("infinite_reserve",false) else Texts.format("⟦base_hud.020⟧", [reserve, Keys.display("reload")])), "text")
	if not p.get("pending_use",{}).is_empty():Texts.bind(_reload_label, Texts.format("⟦base_hud.021⟧", maxf(0,float(p.pending_use.remaining))), "text")
	_update_quick_slots(p)
	if _inventory.visible:
		_update_inventory()
	if is_instance_valid(_dialog) and _dialog_kind=="⟦base_hud.022⟧":preload("res://ui/inventory/camp_panel.gd").refresh(self)
	if is_instance_valid(_dialog) and _dialog_kind in ["⟦base_hud.023⟧","⟦base_hud.024⟧"]:preload("res://ui/inventory/item_shop.gd").refresh(self)

func update_movement_speed(speed:float) -> void:
	if not is_instance_valid(_movement_speed_label):return
	_movement_speed_label.visible=show_movement_speed and _in_game
	Texts.bind(_movement_speed_label,Texts.format("⟦settings.movement_speed_value⟧",speed),"text")

func update_jump_chain(chain:int) -> void:
	if not is_instance_valid(_jump_chain_label):return
	_jump_chain_label.visible=show_jump_chain and _in_game and chain>0
	Texts.bind(_jump_chain_label,Texts.format("⟦settings.jump_chain_value⟧",chain),"text")

func set_show_movement_speed(value:bool) -> void:
	show_movement_speed=value
	if is_instance_valid(_movement_speed_label):_movement_speed_label.visible=value and _in_game
	var config:=ConfigFile.new()
	config.load(display_preferences_path)
	config.set_value("more","show_movement_speed",value)
	if config.save(display_preferences_path)!=OK:toast("⟦settings.more_save_failed⟧")

func set_show_jump_chain(value:bool) -> void:
	show_jump_chain=value
	if is_instance_valid(_jump_chain_label):_jump_chain_label.visible=value and _in_game
	var config:=ConfigFile.new();config.load(display_preferences_path);config.set_value("more","show_jump_chain",value)
	if config.save(display_preferences_path)!=OK:toast("⟦settings.more_save_failed⟧")

func _load_display_preferences() -> void:
	var config:=ConfigFile.new()
	if config.load(display_preferences_path)==OK:
		show_movement_speed=bool(config.get_value("more","show_movement_speed",false))
		show_jump_chain=bool(config.get_value("more","show_jump_chain",false))

func set_interaction(text: String) -> void:
	if _interaction:
		Texts.bind(_interaction, text, "text")
		_interaction.visible = not text.is_empty()

func update_steam(info: Dictionary) -> void:
	# IDs remain decimal strings throughout the UI; networking owns validation and joining.
	_steam_info.merge(info, true)
	_refresh_steam_controls()
	_refresh_steam_room()

func toast(text: String) -> void:
	if _toast_label:
		_toast_label.position = Vector2(490,52) if _inventory.visible else Vector2(350,160)
		_toast_label.size = Vector2(760,44) if _inventory.visible else Vector2(900,46)
		if is_instance_valid(_dialog):_toast_label.position=Vector2(350,42)
		Texts.bind(_toast_label, text, "text")
		# Pill hugs its text, centred on the original slot.
		var centre := _toast_label.position.x + _toast_label.size.x * 0.5
		var limit := _toast_label.size.x
		var text_width := _font.get_string_size(_toast_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		_toast_label.size.x = clampf(text_width + 84.0, 260.0, limit)
		_toast_label.position.x = centre - _toast_label.size.x * 0.5
		_toast_label.visible = true
		_toast_timer = 3.8

func _build_menu() -> void:
	MenuScreen._build_menu(self)

func _reveal_menu() -> void:
	MenuScreen._reveal_menu(self)

func _menu_button(text: String, index: int, color: Color, callback: Callable) -> Button:
	return MenuScreen._menu_button(self, text, index, color, callback)

func _build_hud() -> void:
	_hud = _full_control(_root)
	# Location card: amber spine, big area name, small status line.
	var top := _hud_card(_hud, Rect2(28,24,430,74))
	_line(top,Vector2(0,14),Vector2(4,46),UiTheme.AMBER)
	_world_label = _label(top, "⟦base_hud.007⟧", Rect2(22,8,300,32), 25, Color("f6e3b2"))
	_world_label.add_theme_font_override("font", _bold_font)
	_world_note = _label(top, "⟦base_hud.011⟧", Rect2(22,42,400,22), 14, MUTED)
	_network_label = _label(_hud, "⟦base_hud.013⟧", Rect2(560,28,1012,26), 15, Color("d4e0dc"), HORIZONTAL_ALIGNMENT_RIGHT)
	_network_label.add_theme_constant_override("outline_size",4)
	_network_label.add_theme_color_override("font_outline_color",Color(0,0,0,.55))
	# Vitals card.
	var hp_panel := _hud_card(_hud, Rect2(26,694,362,178))
	_label(hp_panel, "⟦base_hud.025⟧", Rect2(20,10,170,28), 20, INK).add_theme_font_override("font", _bold_font)
	_label(hp_panel, "⟦base_hud.026⟧", Rect2(200,13,142,23), 13, FAINT_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_line(hp_panel,Vector2(20,42),Vector2(322,1),Color(1,1,1,.07))
	_movement_speed_label=_label(_hud,"",Rect2(28,102,260,32),18,Color("a8e6d0"))
	_movement_speed_label.add_theme_constant_override("outline_size",4)
	_movement_speed_label.add_theme_color_override("font_outline_color",Color(0.03,0.08,0.10,0.9))
	_movement_speed_label.visible=false
	var keys := ["hp", "stamina", "hunger", "thirst", "san"]
	var names := ["⟦base_hud.027⟧", "⟦base_hud.028⟧", "⟦base_hud.029⟧", "⟦base_hud.030⟧", "⟦base_hud.san⟧"]
	var colors := [Color("e07a6b"),Color("c8d27e"),Color("e0b25e"),Color("68b9d0"),Color("ad7fd0")]
	for i in range(keys.size()):
		var y := 52+i*24
		var dot := Panel.new();dot.position=Vector2(20,y+7);dot.size=Vector2(8,8);dot.mouse_filter=Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel",UiTheme.box(colors[i],Color.TRANSPARENT,4,0));hp_panel.add_child(dot)
		_label(hp_panel,names[i],Rect2(34,y,62,22),14,MUTED)
		var bar := StatBar.new();bar.color=colors[i];bar.position=Vector2(98,y+6);bar.size=Vector2(196,10)
		hp_panel.add_child(bar);_bars[keys[i]] = bar
		_stat_labels[keys[i]] = _label(hp_panel,"100",Rect2(298,y,44,22),15,INK,HORIZONTAL_ALIGNMENT_RIGHT)
	_build_quick_bar(_hud,Vector2(480,770),false)
	_label(_hud,"⟦base_hud.031⟧",Rect2(602,854,316,18),12,FAINT_TEXT,HORIZONTAL_ALIGNMENT_CENTER)
	# Weapon card: big magazine count.
	var ammo := _hud_card(_hud, Rect2(1290,766,282,106))
	_line(ammo,Vector2(0,16),Vector2(4,74),UiTheme.AMBER)
	_label(ammo,"⟦base_hud.032⟧",Rect2(22,10,240,22),14,MUTED)
	_ammo_label = _label(ammo,"00",Rect2(20,34,96,58),50,Color("fbf0d2"))
	_ammo_label.add_theme_font_override("font", _bold_font)
	_reload_label = _label(ammo,"⟦base_hud.033⟧",Rect2(110,52,160,28),15,Color("c9d2c4"))
	# Control hints: a quiet pill under the status line.
	var guide := _hud_card(_hud,Rect2(640,62,932,30),15)
	guide.add_theme_stylebox_override("panel",UiTheme.box(Color(.03,.05,.06,.55),Color(1,1,1,.05),15,1))
	Keys.bind_hint(_label(guide,"",Rect2(8,2,916,26),13,Color("b9c9c6"),HORIZONTAL_ALIGNMENT_CENTER), "⟦keys.hud_hint⟧", ["interact","reload","inventory","map"])
	# Interaction prompt: floating pill above the player.
	_interaction = _label(_hud,"",Rect2(500,640,600,48),21,Color("fbe6b0"),HORIZONTAL_ALIGNMENT_CENTER)
	var prompt := UiTheme.box(Color(.04,.065,.075,.88),Color(UiTheme.GOLD,.6),24,1,10)
	prompt.content_margin_left=22;prompt.content_margin_right=22
	_interaction.add_theme_stylebox_override("normal",prompt)
	_interaction.visible=false

func _hud_card(parent: Node, rect: Rect2, radius: int = 12) -> Panel:
	var card := _panel(parent, rect, Color.TRANSPARENT, Color.TRANSPARENT, radius)
	card.add_theme_stylebox_override("panel", UiTheme.hud_card(radius))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card

func _build_inventory() -> void:
	InventoryPanel._build_inventory(self)

func _make_slot(parent: Control, container: String, index: int, pos: Vector2, slot_size: Vector2) -> Control:
	return InventoryPanel._make_slot(self, parent, container, index, pos, slot_size)

func _build_popup() -> void:
	InventoryPanel._build_popup(self)

func _slot_action(action: String, payload: Dictionary) -> void:
	InventoryPanel._slot_action(self, action, payload)

func _quick_transfer(payload: Dictionary) -> void:
	InventoryPanel._quick_transfer(self, payload)

func _context_selected(id: int) -> void:
	InventoryPanel._context_selected(self, id)

func _inspect(item: Dictionary) -> void:
	InventoryPanel._inspect(self, item)

func _update_inventory() -> void:
	InventoryPanel._update_inventory(self)

func _build_pause() -> void:
	_pause_shade = _shade(_root,Color(0.015,0.03,0.04,0.72))
	_pause_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_panel = _panel(_root,Rect2(540,76,520,748),PANEL,UiTheme.LINE_LIGHT,18)
	_line(_pause_panel,Vector2(200,20),Vector2(120,3),UiTheme.AMBER)
	_label(_pause_panel,"⟦base_hud.035⟧",Rect2(30,28,460,48),30,GOLD,HORIZONTAL_ALIGNMENT_CENTER).add_theme_font_override("font",_bold_font)
	_label(_pause_panel,"⟦base_hud.036⟧",Rect2(30,82,460,27),16,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	_button(_pause_panel,"⟦base_hud.037⟧",Rect2(65,124,390,54),toggle_pause,GREEN,23)
	_button(_pause_panel,"⟦base_hud.038⟧",Rect2(65,190,390,48),func() -> void: action_requested.emit("save",{}),TEAL,21)
	_button(_pause_panel,"⟦base_hud.039⟧",Rect2(65,250,390,48),_open_help,TEAL,21)
	_button(_pause_panel,"⟦base_hud.040⟧",Rect2(65,310,390,48),_open_settings,TEAL,21)
	_button(_pause_panel,"⟦appearance.title⟧",Rect2(65,370,390,48),_open_appearance,TEAL,21)
	_steam_room_label = _label(_pause_panel,"⟦base_hud.041⟧",Rect2(30,424,460,34),17,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	_steam_room_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_steam_invite_button = _button(_pause_panel,"⟦base_hud.042⟧",Rect2(65,466,390,42),func() -> void: action_requested.emit("steam_invite",{}),TEAL,21)
	_steam_copy_button = _button(_pause_panel,"⟦base_hud.043⟧",Rect2(65,516,390,42),func() -> void: action_requested.emit("steam_copy_lobby",{}),TEAL,21)
	_button(_pause_panel,"⟦base_hud.044⟧",Rect2(65,572,390,48),func() -> void: action_requested.emit("unstuck",{}),TEAL,21)
	_label(_pause_panel,"⟦base_hud.045⟧",Rect2(30,627,460,24),15,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	_button(_pause_panel,"⟦base_hud.046⟧",Rect2(65,660,390,48),func() -> void: action_requested.emit("menu",{}),Color("64716f"),21)
	_refresh_steam_room()

func _open_steam() -> void:
	SteamPanel._open_steam(self)

func _steam_ready() -> bool:
	return SteamPanel._steam_ready(self)

func _refresh_steam_controls() -> void:
	SteamPanel._refresh_steam_controls(self)

func _rebuild_steam_lobbies(lobbies: Array) -> void:
	SteamPanel._rebuild_steam_lobbies(self, lobbies)

func _join_steam_input() -> void:
	SteamPanel._join_steam_input(self)

func _join_steam_lobby(lobby_id: String) -> void:
	SteamPanel._join_steam_lobby(self, lobby_id)

func _steam_input_error(message: String) -> void:
	SteamPanel._steam_input_error(self, message)

func _steam_action(action: String, payload: Dictionary = {}) -> void:
	SteamPanel._steam_action(self, action, payload)

func _refresh_steam_room() -> void:
	SteamPanel._refresh_steam_room(self)

func _open_network() -> void:
	_dialog_panel("⟦base_hud.047⟧",Vector2(680,600))
	_label(_dialog,"⟦base_hud.048⟧",Rect2(34,84,610,30),19,MUTED)
	_label(_dialog,"⟦base_hud.049⟧",Rect2(34,145,190,28),18,INK)
	_join_address = _line_edit(_dialog,"127.0.0.1",Rect2(34,184,612,49))
	Texts.bind(_join_address, "⟦base_hud.050⟧", "placeholder_text")
	_label(_dialog,"⟦base_hud.051⟧",Rect2(34,252,180,28),18,INK)
	_port_input = _line_edit(_dialog,"24567",Rect2(34,290,200,49))
	_label(_dialog,"⟦base_hud.052⟧",Rect2(34,363,612,65),16,MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(_dialog,"⟦base_hud.053⟧",Rect2(34,454,292,60),func() -> void: _connect_action("host"),GREEN,24)
	_button(_dialog,"⟦base_hud.054⟧",Rect2(346,454,300,60),func() -> void: _connect_action("join"),TEAL,24)
	_label(_dialog,"⟦base_hud.055⟧",Rect2(34,539,612,27),15,Color("90aaa2"),HORIZONTAL_ALIGNMENT_CENTER)

func _connect_action(action: String) -> void:
	var port_text := _port_input.text.strip_edges()
	if not port_text.is_valid_int() or int(port_text) < 1024 or int(port_text) > 65535:
		toast("⟦base_hud.056⟧")
		return
	var address := _join_address.text.strip_edges()
	if action == "join" and address.is_empty():
		toast("⟦base_hud.057⟧")
		return
	var payload := {"port":int(port_text)}
	if action == "join":
		payload["address"] = address
	_dialog_panel("⟦base_hud.058⟧",Vector2(600,340))
	_dialog_kind = "connection"
	_connection_dispatched = true
	_connection_text = _label(_dialog,"⟦base_hud.059⟧" if action == "host" else Texts.format("⟦session.008⟧", [address,int(port_text)]),Rect2(34,104,532,86),21,INK,HORIZONTAL_ALIGNMENT_CENTER)
	_connection_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(_dialog,"⟦base_hud.060⟧",Rect2(130,235,340,55),_cancel_connection,Color("617c7b"),22)
	action_requested.emit(action,payload)

func _cancel_connection() -> void:
	action_requested.emit("menu",{})
	show_menu()

func _open_appearance() -> void:
	_dialog_panel("⟦appearance.title⟧",Vector2(880,710))
	preload("res://ui/menu/appearance_panel.gd").new().build(self)

func _open_settings() -> void:
	MenuScreen._open_settings(self)

func _open_key_bindings() -> void:
	_dialog_panel("⟦keys.title⟧", Vector2(800,740))
	_key_bindings_panel = KeyBindingsPanel.new()
	_key_bindings_panel.build(self)

func _open_help() -> void:
	MenuScreen._open_help(self)

func _dialog_panel(title: String, dialog_size: Vector2) -> void:
	_close_dialog()
	var overlay := _full_control(_root,Control.MOUSE_FILTER_STOP)
	overlay.name = "DialogOverlay"
	_shade(overlay,Color(0.015,0.03,0.04,0.74))
	_dialog = _panel(overlay,Rect2((Vector2(1600,900)-dialog_size)*0.5,dialog_size),PANEL,UiTheme.LINE_LIGHT,18)
	_dialog.set_meta("overlay",overlay)
	_line(_dialog,Vector2(32,30),Vector2(4,34),UiTheme.AMBER)
	var heading := _label(_dialog,title,Rect2(46,22,dialog_size.x-120,50),29,Color("f6e3b2"))
	heading.add_theme_font_override("font",_bold_font)
	_line(_dialog,Vector2(32,76),Vector2(dialog_size.x-64,1),Color(1,1,1,.08))
	_button(_dialog,"×",Rect2(dialog_size.x-64,24,40,40),_dialog_close_pressed,Color("5f7476"),26,20)
	_dialog_kind = title

func _dialog_close_pressed() -> void:
	if _dialog_kind == "connection":
		_cancel_connection()
	elif _dialog_kind == "steam" and bool(_steam_info.get("pending",false)):
		action_requested.emit("steam_cancel",{})
		_close_dialog()
	else:
		_close_dialog()

func _close_dialog() -> void:
	_key_bindings_panel = null
	if not _loot_uid.is_empty():
		var closing := _loot_uid
		_loot_uid = ""
		_loot_dismissed_uid = closing
		action_requested.emit("loot_close", {"uid": closing})
	if is_instance_valid(_dialog):
		var overlay: Node = _dialog.get_meta("overlay",null)
		if is_instance_valid(overlay):
			overlay.queue_free()
		else:
			_dialog.queue_free()
	_dialog = null
	_connection_text = null
	_dialog_kind = ""

func _players() -> Dictionary:
	return _state.get("players",{})

func _player() -> Dictionary:
	var players := _players()
	return players.get(_local_id,players.get(str(_local_id),{}))

func _definition(item: Dictionary) -> Dictionary:
	return {} if item.is_empty() else Items.definition(str(item.get("kind","")))

func _full_control(parent: Node, filter: int = Control.MOUSE_FILTER_IGNORE) -> Control:
	var control := Control.new()
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = filter
	parent.add_child(control)
	return control

func _label(parent: Node, text: String, rect: Rect2, font_size: int = 20, color: Color = INK, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	Texts.bind(label, text, "text")
	label.position = rect.position
	label.size = rect.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, rect: Rect2, callback: Callable, color: Color = TEAL, font_size: int = 20, radius: int = 10) -> Button:
	var button := Button.new()
	Texts.bind(button, text, "text")
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size",font_size)
	UiTheme.apply_button(button, color, mini(radius, int(rect.size.y*.5)))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _panel(parent: Node, rect: Rect2, bg: Color, border: Color, radius: int = 10) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Opaque panels become lifted slate cards; translucent ones keep their tint.
	var lifted := bg.a > .9
	panel.add_theme_stylebox_override("panel",UiTheme.panel(bg if not lifted else Color(bg,.97), border if border.a < .99 else Color(border.darkened(.3),.9), radius, 18 if lifted else 8))
	parent.add_child(panel)
	return panel

func _style(bg: Color, border: Color, radius: int = 8, border_width: int = 1) -> StyleBoxFlat:
	return UiTheme.box(bg, border, radius, border_width)

func _shade(parent: Node, color: Color) -> ColorRect:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = color
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)
	return shade

func _line(parent: Node, pos: Vector2, line_size: Vector2, color: Color = Color("465f59")) -> void:
	var line := ColorRect.new()
	line.position = pos
	line.size = line_size
	line.color = color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func _progress(parent: Node, rect: Rect2, color: Color) -> Control:
	var bar := StatBar.new()
	bar.position = rect.position
	bar.size = rect.size
	bar.color = color
	parent.add_child(bar)
	return bar

func _line_edit(parent: Node, text: String, rect: Rect2) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.position = rect.position
	edit.size = rect.size
	edit.add_theme_font_size_override("font_size",22)
	parent.add_child(edit)
	return edit

func set_voice_status(text: String) -> void:
	if not is_instance_valid(_voice_label):
		_voice_label=_label(_hud,"",Rect2(560,105,1000,22),14,GOLD)
		_voice_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	Texts.bind(_voice_label, text, "text")

func open_item_shop(mode:String) -> void:
	preload("res://ui/inventory/item_shop.gd").open(self,mode)

func _build_quick_bar(parent:Control,at:Vector2,editable:bool)->void:
	_hud_card(parent,Rect2(at,Vector2(640,104)),14)
	for i in range(8):
		var slot=QuickSlot.new();slot.position=at+Vector2(14+i*77,22);slot.size=Vector2(65,65);slot.slot_index=i
		parent.add_child(slot);slot.mouse_filter=Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
		slot.binding_requested.connect(_bind_quick);_quick_slots.append(slot)
		var cap:=_label(parent,"",Rect2(at+Vector2(6+i*77,8),Vector2(24,22)),13,GOLD)
		cap.mouse_filter=Control.MOUSE_FILTER_IGNORE
		Keys.bind_hint(cap,"⟦keys.single⟧",[Quick.ACTIONS[i]])
func _bind_quick(index:int,payload:Dictionary)->void:
	var kind:=""
	var p:Dictionary=_player()
	if not payload.is_empty():
		var bag:Array=p.get("bag",[]);var from:int=int(payload.get("index",-1))
		if from<0 or from>=bag.size() or bag[from].get("uid")!=payload.get("uid"):return
		kind=str(bag[from].get("kind",""))
	if Quick.bind_slot(index,kind)!=OK:toast("⟦quick.save_failed⟧");return
	_update_quick_slots(p)
func _update_quick_slots(p:Dictionary)->void:
	for slot in _quick_slots:
		var selected:Dictionary=Quick.resolve(p,int(slot.slot_index))
		var item:Dictionary=selected.get("item",{})
		slot.set_item(item,_definition(item))
		if item.is_empty():Texts.bind(slot,"⟦quick.empty_hint⟧","tooltip_text")
