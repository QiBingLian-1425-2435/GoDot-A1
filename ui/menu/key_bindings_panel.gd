extends Control
const Keys = preload("res://features/player/key_bindings.gd")
const Texts = preload("res://features/localization/game_text.gd")
var ctx
var waiting := ""
var buttons: Dictionary = {}
var status: Label

func build(hud) -> void:
	ctx = hud
	name = "KeyBindings"
	ctx._dialog.add_child(self)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(34,100)
	scroll.size = Vector2(732,470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",6)
	scroll.add_child(rows)
	for action in Keys.DEFAULTS:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var label := Label.new()
		label.custom_minimum_size = Vector2(380,40)
		Texts.bind(label, Keys.LABELS[action])
		row.add_child(label)
		var button: Button = ctx._button(row, Keys.display(action), Rect2(0,0,290,40), _listen.bind(action), ctx.TEAL,20)
		button.name = action
		button.custom_minimum_size = Vector2(290,40)
		button.focus_mode = Control.FOCUS_NONE
		buttons[action] = button
	status = ctx._label(self,"⟦keys.instructions⟧",Rect2(34,580,732,64),17,ctx.GOLD)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctx._button(self,"⟦keys.reset⟧",Rect2(34,656,340,50),_reset,ctx.TEAL,21)
	ctx._button(self,"⟦keys.back⟧",Rect2(426,656,340,50),ctx._open_settings,ctx.GREEN,21)

func _listen(action: String) -> void:
	waiting = action
	Texts.bind(status, Texts.format("⟦keys.listening⟧",Keys.LABELS[action]))

func capture(event: InputEvent) -> bool:
	if waiting.is_empty(): return false
	if not (event is InputEventKey or event is InputEventMouseButton): return false
	if not event.pressed or (event is InputEventKey and event.echo): return true
	var code := Keys.event_code(event)
	if code == KEY_ESCAPE:
		waiting = ""
		Texts.bind(status,"⟦keys.cancelled⟧")
		return true
	if not Keys.valid_code(code):
		Texts.bind(status,"⟦keys.invalid⟧")
		return true
	var other := Keys.conflict(waiting,code)
	if not other.is_empty():
		Texts.bind(status,Texts.format("⟦keys.conflict⟧",Keys.LABELS[other]))
		return true
	if Keys.assign(waiting,code) != OK:
		Texts.bind(status,"⟦keys.save_failed⟧")
		return true
	waiting = ""
	_refresh()
	Texts.bind(status,"⟦keys.saved⟧")
	return true

func _refresh() -> void:
	for action in buttons: Texts.bind(buttons[action],Keys.display(action))

func _reset() -> void:
	waiting = ""
	var result := Keys.reset_defaults()
	_refresh()
	Texts.bind(status,"⟦keys.saved⟧" if result == OK else "⟦keys.save_failed⟧")
