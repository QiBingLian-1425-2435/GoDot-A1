extends RefCounted
## Text references stay language-neutral in definitions, saves and network messages.
## Only presentation boundaries call resolve/bind. Catalogs contain all authored copy.

const DIRECTORY := "res://features/localization/"
const SETTINGS_PATH := "user://language.cfg"
const GROUP := "localized_text"
const OPEN := "⟦"
const CLOSE := "⟧"
const MAX_DEPTH := 24
static var _loaded := false
static var _locale := "zh_CN"
static var _catalogs: Dictionary = {}
static var _locales: Dictionary = {}
static var _window_title := "⟦application.title⟧"
static var _printf: RegEx

static func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Localization catalog unavailable: " + path)
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	if not value is Dictionary:
		push_error("Invalid localization catalog: " + path)
		return {}
	return value

static func _ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	_printf = RegEx.new()
	_printf.compile("%%|%[-+0 #]*[0-9]*(?:\\.[0-9]+)?([sdf])")
	_locales = _read_json(DIRECTORY + "locales.json")
	for code in _locales:
		_catalogs[code] = _read_json(DIRECTORY + str(_locales[code].file))
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var saved := str(config.get_value("language", "locale", "zh_CN"))
		if _locales.has(saved): _locale = saved

static func locale() -> String:
	_ensure_loaded()
	return _locale

static func available_locales() -> Dictionary:
	_ensure_loaded()
	return _locales.duplicate(true)

static func set_locale(code: String, persist: bool = true) -> Error:
	_ensure_loaded()
	if not _locales.has(code): return ERR_INVALID_PARAMETER
	_locale = code
	var result := OK
	if persist:
		var config := ConfigFile.new()
		config.set_value("language", "locale", code)
		result = config.save(SETTINGS_PATH)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for node in tree.get_nodes_in_group(GROUP):
			_refresh_node(node)
	DisplayServer.window_set_title(resolve(_window_title))
	return result

static func set_window_title(expression: String) -> void:
	_window_title = expression
	DisplayServer.window_set_title(resolve(expression))

static func _pack(value: Dictionary) -> String:
	return OPEN + "!" + Marshalls.variant_to_base64(value) + CLOSE

static func format(template: String, arguments: Variant) -> String:
	# Defer printf until the receiving machine knows the display language.
	var args: Array = arguments if arguments is Array else [arguments]
	return _pack({"op":"format", "template":template, "args":args})

static func clip(value: String, length: int) -> String:
	return _pack({"op":"clip", "value":value, "length":length}) if OPEN in value else value.left(length)

static func literal(value: String) -> String:
	# External names must never be interpreted as authored text references.
	return OPEN + "=" + Marshalls.utf8_to_base64(value) + CLOSE if OPEN in value else value

static func resolve(value: String, depth: int = 0) -> String:
	if OPEN not in value: return value
	if depth >= MAX_DEPTH: return "[text recursion limit]"
	_ensure_loaded()
	var result := ""
	var start := 0
	while start < value.length():
		var at := value.find(OPEN, start)
		if at < 0:
			result += value.substr(start)
			break
		result += value.substr(start, at-start)
		var end := value.find(CLOSE, at+1)
		if end < 0:
			result += value.substr(at)
			break
		var token := value.substr(at+1, end-at-1)
		result += _resolve_token(token, depth+1)
		start = end+1
	return result

static func _resolve_token(token: String, depth: int) -> String:
	if token.begins_with("="):
		return Marshalls.base64_to_utf8(token.substr(1))
	if token.begins_with("!"):
		var message: Variant = Marshalls.base64_to_variant(token.substr(1), false)
		if not message is Dictionary: return "[invalid text message]"
		if message.get("op") == "clip":
			return resolve(str(message.get("value", "")), depth).left(int(message.get("length", 0)))
		if message.get("op") == "format" and message.get("args") is Array:
			var args: Array = []
			for argument in message.args:
				args.append(resolve(argument, depth) if argument is String else argument)
			var template := resolve(str(message.get("template", "")), depth)
			if _signature(template).size() != args.size(): return "[invalid text arguments]"
			return template % args
		return "[invalid text operation]"
	var fallback: Dictionary = _catalogs.get("zh_CN", {})
	var catalog: Dictionary = _catalogs.get(_locale, {})
	var text := str(catalog.get(token, ""))
	var source := str(fallback.get(token, "[missing:" + token + "]"))
	if text.is_empty() or _signature(text) != _signature(source): text = source
	return resolve(text, depth)

static func _signature(template: String) -> Array[String]:
	var result: Array[String] = []
	for match in _printf.search_all(template):
		if match.get_string() != "%%": result.append(match.get_string(1))
	return result

static func bind(node: Node, expression: String, property: String = "text") -> void:
	var bindings: Dictionary = node.get_meta("_localized_properties", {})
	if bindings.get(property) == expression: return
	bindings[property] = expression
	node.set_meta("_localized_properties", bindings)
	node.add_to_group(GROUP)
	node.set(property, resolve(expression))

static func add_item(node: Node, expression: String, id: int = -1) -> int:
	var index: int
	if node is ItemList:
		index = node.add_item(resolve(expression))
	else:
		index = node.item_count
		node.add_item(resolve(expression), id)
	_remember_item(node, index, expression)
	return index

static func set_item_text(node: Node, index: int, expression: String) -> void:
	node.set_item_text(index, resolve(expression))
	_remember_item(node, index, expression)

static func _remember_item(node: Node, index: int, expression: String) -> void:
	var items: Dictionary = node.get_meta("_localized_items", {})
	items[index] = expression
	node.set_meta("_localized_items", items)
	node.add_to_group(GROUP)

static func watch_draw(node: CanvasItem) -> void:
	node.add_to_group(GROUP)

static func _refresh_node(node: Node) -> void:
	var bindings: Dictionary = node.get_meta("_localized_properties", {})
	for property in bindings:
		node.set(property, resolve(bindings[property]))
	var items: Dictionary = node.get_meta("_localized_items", {})
	for index in items:
		if int(index) < int(node.item_count): node.set_item_text(index, resolve(items[index]))
	if node is CanvasItem: node.queue_redraw()
