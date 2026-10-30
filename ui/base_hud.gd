extends CanvasLayer
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
const INK := Color("e8ecdd")
const MUTED := Color("a8b7b2")
const GOLD := Color("f1d38b")
const TEAL := Color("5d9ba4")
const GREEN := Color("679b6e")
const PANEL := Color(0.10, 0.15, 0.17, 0.97)

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
var display_preferences_path:="user://display_preferences.cfg"
var _voice_label:Label
var _movement_speed_label:Label
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
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", INK)
	_root.theme = theme
	_build_menu()
	_build_hud()
	_build_inventory()
	_build_popup()
	_build_pause()
	_toast_label = _label(_root, "", Rect2(350, 125, 900, 46), 20, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_toast_label.add_theme_stylebox_override("normal", _style(Color(0.07, 0.12, 0.14, 0.92), Color("667d78"), 8, 1))
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
		var shade:=ColorRect.new();shade.color=Color(.025,.045,.055,.94)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_loading_panel.add_child(shade)
		_loading_title=_label(_loading_panel,"",Rect2(400,350,800,100),28,INK,HORIZONTAL_ALIGNMENT_CENTER)
		_button(_loading_panel,"⟦base_hud.004⟧",Rect2(650,500,300,64),func():action_requested.emit("menu",{}),TEAL,22)
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
	if not is_instance_valid(_root):
		return
	var p := _player()
	SoulPanel.sync(self)
	ContainerPanel.sync(self)
	var world_name: String = str(state.get("world","bunker"))
	Texts.bind(_world_label, {"bunker":"⟦base_hud.007⟧","surface":"⟦base_hud.008⟧","cave":"⟦base_hud.009⟧"}.get(world_name,"⟦base_hud.010⟧"), "text")
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
	var bag: Array = p.get("bag", [])
	var quick_kinds := ["rifle", "pistol", "medkit", "water"]
	for i in range(_quick_slots.size()):
		var quick_item: Dictionary = {}
		for item in bag:
			if item.get("kind", "") == quick_kinds[i]:
				quick_item = item
				break
		var weapon: Dictionary = p.get("equipment", {}).get("weapon", {})
		if weapon.get("kind", "") == quick_kinds[i]:
			quick_item = weapon
		_quick_slots[i].set_item(quick_item, _definition(quick_item))
	if _inventory.visible:
		_update_inventory()
	if is_instance_valid(_dialog) and _dialog_kind=="⟦base_hud.022⟧":preload("res://ui/inventory/camp_panel.gd").refresh(self)
	if is_instance_valid(_dialog) and _dialog_kind in ["⟦base_hud.023⟧","⟦base_hud.024⟧"]:preload("res://ui/inventory/item_shop.gd").refresh(self)

func update_movement_speed(speed:float) -> void:
	if not is_instance_valid(_movement_speed_label):return
	_movement_speed_label.visible=show_movement_speed and _in_game
	Texts.bind(_movement_speed_label,Texts.format("⟦settings.movement_speed_value⟧",speed),"text")

func set_show_movement_speed(value:bool) -> void:
	show_movement_speed=value
	if is_instance_valid(_movement_speed_label):_movement_speed_label.visible=value and _in_game
	var config:=ConfigFile.new()
	config.load(display_preferences_path)
	config.set_value("more","show_movement_speed",value)
	if config.save(display_preferences_path)!=OK:toast("⟦settings.more_save_failed⟧")

func _load_display_preferences() -> void:
	var config:=ConfigFile.new()
	if config.load(display_preferences_path)==OK:
		show_movement_speed=bool(config.get_value("more","show_movement_speed",false))

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
		_toast_label.position = Vector2(490,52) if _inventory.visible else Vector2(350,125)
		_toast_label.size = Vector2(760,44) if _inventory.visible else Vector2(900,46)
		if is_instance_valid(_dialog):_toast_label.position=Vector2(350,42)
		Texts.bind(_toast_label, text, "text")
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
	var top := _panel(_hud, Rect2(28,24,465,68), Color(0.05,0.11,0.14,0.76), Color(0.50,0.69,0.70,0.35), 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_label = _label(top, "⟦base_hud.007⟧", Rect2(18,7,210,29), 24, Color("f0e8c6"))
	_world_note = _label(top, "⟦base_hud.011⟧", Rect2(18,39,440,21), 14, Color("b2c7c2"))
	_network_label = _label(_hud, "⟦base_hud.013⟧", Rect2(560,30,1006,28), 16, Color("d4e4df"), HORIZONTAL_ALIGNMENT_RIGHT)
	_movement_speed_label=_label(_hud,"",Rect2(28,102,260,32),18,Color("a8e6d0"))
	_movement_speed_label.add_theme_constant_override("outline_size",4)
	_movement_speed_label.add_theme_color_override("font_outline_color",Color(0.03,0.08,0.10,0.9))
	_movement_speed_label.visible=false
	var hp_panel := _panel(_hud, Rect2(26,686,350,178), Color(0.05,0.10,0.12,0.84), Color(0.5,0.65,0.63,0.35), 10)
	hp_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label(hp_panel, "⟦base_hud.025⟧", Rect2(18,10,100,25), 21, INK)
	_label(hp_panel, "⟦base_hud.026⟧", Rect2(202,13,130,23), 14, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var keys := ["hp", "stamina", "hunger", "thirst", "san"]
	var names := ["⟦base_hud.027⟧", "⟦base_hud.028⟧", "⟦base_hud.029⟧", "⟦base_hud.030⟧", "⟦base_hud.san⟧"]
	var colors := [Color("cf8375"),Color("c3cb86"),Color("c9ab69"),Color("73b6c7"),Color("a577bf")]
	for i in range(keys.size()):
		_label(hp_panel,names[i],Rect2(18,44+i*24,65,22),14,MUTED)
		_bars[keys[i]] = _progress(hp_panel, Rect2(89,51+i*24,199,9), colors[i])
		_stat_labels[keys[i]] = _label(hp_panel,"100",Rect2(295,43+i*24,38,22),14,INK,HORIZONTAL_ALIGNMENT_RIGHT)
	for i in range(4):
		var slot: Control = Slot.new()
		slot.position = Vector2(620+i*75,791)
		slot.size = Vector2(65,65)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.container_name = "bag"
		slot.slot_index = i
		_hud.add_child(slot)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_quick_slots.append(slot)
		Keys.bind_hint(_label(_hud,"",Rect2(623+i*75,765,60,24),16,Color("d8dfc5"),HORIZONTAL_ALIGNMENT_CENTER), "⟦keys.single⟧", [["rifle", "pistol", "medkit", "water"][i]])
	_label(_hud,"⟦base_hud.031⟧",Rect2(617,861,290,22),13,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	var ammo := _panel(_hud, Rect2(1300,760,268,103), Color(0.05,0.10,0.12,0.84), Color(0.5,0.65,0.63,0.35), 10)
	ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label(ammo,"⟦base_hud.032⟧",Rect2(17,10,240,24),15,MUTED)
	_ammo_label = _label(ammo,"00",Rect2(16,35,75,54),42,INK)
	_reload_label = _label(ammo,"⟦base_hud.033⟧",Rect2(92,54,164,28),15,Color("c5cbbb"))
	var guide := _panel(_hud,Rect2(635,68,930,34),Color(0.03,0.07,0.10,0.72),Color(0.35,0.5,0.55,0.2),6)
	guide.mouse_filter=Control.MOUSE_FILTER_IGNORE
	Keys.bind_hint(_label(guide,"",Rect2(8,4,914,26),14,Color("c7d7d5"),HORIZONTAL_ALIGNMENT_CENTER), "⟦keys.hud_hint⟧", ["interact","reload","inventory","map"])
	_interaction = _label(_hud,"",Rect2(400,645,800,44),23,GOLD,HORIZONTAL_ALIGNMENT_CENTER)
	_interaction.add_theme_constant_override("outline_size",5)
	_interaction.add_theme_color_override("font_outline_color",Color(0.06,0.1,0.12,0.9))

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
	_pause_shade = _shade(_root,Color(0.02,0.04,0.06,0.66))
	_pause_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_panel = _panel(_root,Rect2(540,76,520,748),PANEL,Color("748f86"),16)
	_label(_pause_panel,"⟦base_hud.035⟧",Rect2(30,24,460,50),30,GOLD,HORIZONTAL_ALIGNMENT_CENTER)
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
	_shade(overlay,Color(0.025,0.055,0.075,0.77))
	_dialog = _panel(overlay,Rect2((Vector2(1600,900)-dialog_size)*0.5,dialog_size),Color("193239"),Color("72978e"),18)
	_dialog.set_meta("overlay",overlay)
	_label(_dialog,title,Rect2(32,22,dialog_size.x-105,50),31,GOLD)
	_button(_dialog,"×",Rect2(dialog_size.x-68,20,44,44),_dialog_close_pressed,Color("506d70"),28,10)
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
	button.add_theme_color_override("font_color",Color("f5f4e4"))
	button.add_theme_color_override("font_hover_color",Color.WHITE)
	button.add_theme_color_override("font_pressed_color",Color("f5efcf"))
	button.add_theme_stylebox_override("normal",_style(color,color.lightened(0.22),radius,1))
	button.add_theme_stylebox_override("hover",_style(color.lightened(0.13),Color("e7eac9"),radius,2))
	button.add_theme_stylebox_override("pressed",_style(color.darkened(0.2),color.lightened(0.35),radius,1))
	button.add_theme_stylebox_override("focus",_style(Color.TRANSPARENT,Color("f7dca0"),radius,2))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _panel(parent: Node, rect: Rect2, bg: Color, border: Color, radius: int = 10) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",_style(bg,border,radius,1))
	parent.add_child(panel)
	return panel

func _style(bg: Color, border: Color, radius: int = 8, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

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

func _progress(parent: Node, rect: Rect2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = rect.position
	bar.size = rect.size
	bar.show_percentage = false
	bar.value = 100
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background",_style(Color("283b3e"),Color.TRANSPARENT,3,0))
	bar.add_theme_stylebox_override("fill",_style(color,Color.TRANSPARENT,3,0))
	parent.add_child(bar)
	return bar

func _line_edit(parent: Node, text: String, rect: Rect2) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.position = rect.position
	edit.size = rect.size
	edit.add_theme_font_size_override("font_size",22)
	edit.add_theme_stylebox_override("normal",_style(Color("0e262d"),Color("6a8981"),8,1))
	edit.add_theme_stylebox_override("focus",_style(Color("132d32"),GOLD,8,2))
	parent.add_child(edit)
	return edit

func set_voice_status(text: String) -> void:
	if not is_instance_valid(_voice_label):
		_voice_label=_label(_hud,"",Rect2(560,105,1000,22),14,GOLD)
		_voice_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	Texts.bind(_voice_label, text, "text")

func open_item_shop(mode:String) -> void:
	preload("res://ui/inventory/item_shop.gd").open(self,mode)
