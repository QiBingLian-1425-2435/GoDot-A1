extends RefCounted
## Local preferences only; shared gameplay remains host-authoritative.
const Texts = preload("res://features/localization/game_text.gd")
const PATH := "user://key_bindings.cfg"
const DEFAULTS := {
	"move_up": [KEY_W], "move_down": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"voice": [KEY_Q], "sprint": [KEY_SHIFT], "crouch": [KEY_C], "roll": [KEY_SPACE],
	"fire": [-MOUSE_BUTTON_LEFT], "aim": [-MOUSE_BUTTON_RIGHT],
	"interact": [KEY_E], "rescue": [KEY_F], "reload": [KEY_R],
	"inventory": [KEY_TAB, KEY_I], "map": [KEY_M], "rifle": [KEY_1], "pistol": [KEY_2],
	"medkit": [KEY_4], "water": [KEY_5], "save": [KEY_F5], "fullscreen": [KEY_F11]
}
const LABELS := {
	"voice": "⟦keys.action.voice⟧",
	"move_up": "⟦keys.action.move_up⟧", "move_down": "⟦keys.action.move_down⟧",
	"move_left": "⟦keys.action.move_left⟧", "move_right": "⟦keys.action.move_right⟧",
	"sprint": "⟦keys.action.sprint⟧", "crouch": "⟦keys.action.crouch⟧", "roll": "⟦keys.action.roll⟧",
	"fire": "⟦keys.action.fire⟧", "aim": "⟦keys.action.aim⟧", "interact": "⟦keys.action.interact⟧",
	"rescue": "⟦keys.action.rescue⟧", "reload": "⟦keys.action.reload⟧", "inventory": "⟦keys.action.inventory⟧",
	"map": "⟦keys.action.map⟧", "rifle": "⟦keys.action.rifle⟧", "pistol": "⟦keys.action.pistol⟧",
	"medkit": "⟦keys.action.medkit⟧", "water": "⟦keys.action.water⟧", "save": "⟦keys.action.save⟧",
	"fullscreen": "⟦keys.action.fullscreen⟧"
}
const MOUSE_LABELS := {1: "⟦keys.mouse_1⟧", 2: "⟦keys.mouse_2⟧", 3: "⟦keys.mouse_3⟧", 8: "⟦keys.mouse_8⟧", 9: "⟦keys.mouse_9⟧"}
static var _loaded := false
static var _values: Dictionary = {}

static func ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	_values = DEFAULTS.duplicate(true)
	var config := ConfigFile.new()
	if config.load(PATH) != OK: return
	var candidate := DEFAULTS.duplicate(true)
	for action in DEFAULTS:
		var value: Variant = config.get_value("bindings", action, DEFAULTS[action])
		if not value is Array or value.is_empty() or value.size() > 2: return
		for code in value:
			if not code is int or not valid_code(code): return
		candidate[action] = value
	var used := {}
	for action in candidate:
		for code in candidate[action]:
			if used.has(code): return
			used[code] = true
	_values = candidate

static func valid_code(code: int) -> bool:
	return code in [-1, -2, -3, -8, -9] or (code > 0 and code < KEY_SPECIAL and not OS.get_keycode_string(code).is_empty()) or (code >= KEY_SPECIAL and code <= KEY_KP_9 and code != KEY_ESCAPE)

static func event_code(event: InputEvent) -> int:
	if event is InputEventKey: return int(event.physical_keycode if event.physical_keycode else event.keycode)
	if event is InputEventMouseButton: return -int(event.button_index)
	return 0

static func matches(action: String, event: InputEvent) -> bool:
	ensure_loaded()
	return event_code(event) in _values.get(action, [])

static func held(action: String) -> bool:
	ensure_loaded()
	for code in _values.get(action, []):
		if code > 0 and Input.is_physical_key_pressed(code): return true
		if code < 0 and Input.is_mouse_button_pressed(-code): return true
	return false

static func conflict(action: String, code: int) -> String:
	ensure_loaded()
	for other in _values:
		if other != action and code in _values[other]: return other
	return ""

static func assign(action: String, code: int) -> Error:
	ensure_loaded()
	if not DEFAULTS.has(action) or not valid_code(code) or not conflict(action, code).is_empty(): return ERR_INVALID_PARAMETER
	var candidate := _values.duplicate(true)
	candidate[action] = [code]
	return _save(candidate)

static func reset_defaults() -> Error:
	return _save(DEFAULTS.duplicate(true))

static func _save(candidate: Dictionary) -> Error:
	var config := ConfigFile.new()
	for action in candidate: config.set_value("bindings", action, candidate[action])
	var result := config.save(PATH)
	if result == OK:
		_loaded = true
		_values = candidate
		refresh_hints()
	return result

static func display(action: String) -> String:
	ensure_loaded()
	var names := PackedStringArray()
	for code in _values.get(action, []): names.append(MOUSE_LABELS[-code] if code < 0 else OS.get_keycode_string(code))
	return " / ".join(names)

static func bind_hint(node: Node, template: String, actions: Array) -> void:
	node.set_meta("key_hint", [template, actions])
	node.add_to_group("key_hints")
	_update_hint(node)

static func _update_hint(node: Node) -> void:
	var data: Array = node.get_meta("key_hint")
	var values := []
	for action in data[1]: values.append(display(action))
	Texts.bind(node, Texts.format(data[0], values))

static func refresh_hints() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		for node in tree.get_nodes_in_group("key_hints"): _update_hint(node)
