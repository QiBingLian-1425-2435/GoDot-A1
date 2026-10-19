extends RefCounted
## Migrated reference behavior; called only through the owning composition/model.

static func save_profile(ctx, path: String, id: int = 1) -> Error:
	if path.is_empty() or not ctx.state.players.has(id): return ERR_INVALID_PARAMETER
	var p: Dictionary = ctx.state.players[id]
	var data = {"version":1,"bag":p.bag,"stash":p.stash,"equipment":p.equipment,"magazines":p.magazines,"credits":p.credits,"hp":p.hp,"hunger":p.hunger,"thirst":p.thirst}
	var file = FileAccess.open(path,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	return OK

static func load_profile(ctx, path: String, id: int = 1) -> Error:
	if not ctx.state.players.has(id): return ERR_INVALID_PARAMETER
	if not FileAccess.file_exists(path): return ERR_FILE_NOT_FOUND
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return FileAccess.get_open_error()
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or int(data.get("version",0)) != 1: return ERR_FILE_CORRUPT
	if not data.get("bag") is Array or data.bag.size() != 24 or not data.get("stash") is Array or data.stash.size() != 48 or not data.get("equipment") is Dictionary: return ERR_FILE_CORRUPT
	var seen: Dictionary = {}
	for container in [data.bag,data.stash,data.equipment.values()]:
		for item in container:
			if not ctx._valid_saved_item(item,seen): return ERR_FILE_CORRUPT
	for slot in ctx.EQUIPMENT:
		if not data.equipment.has(slot): return ERR_FILE_CORRUPT
		if not data.equipment[slot].is_empty() and ctx.Items.definition(data.equipment[slot].kind).category != slot: return ERR_FILE_CORRUPT
	if data.equipment.size() != 4: return ERR_FILE_CORRUPT
	var p: Dictionary = ctx.state.players[id]
	# Reissue local UIDs so a profile can never collide with another current player.
	var old_magazines: Dictionary = data.get("magazines",{}) if data.get("magazines",{}) is Dictionary else {}
	var magazines: Dictionary = {}
	for container in [data.bag,data.stash,data.equipment.values()]:
		for item in container:
			if item.is_empty(): continue
			var old_uid = str(item.uid)
			var replacement = ctx._item(item.kind,int(item.count))
			item.uid = replacement.uid; item.count = replacement.count
			if ctx.Items.definition(item.kind).category == "weapon": magazines[item.uid] = clampi(int(old_magazines.get(old_uid,0)),0,int(ctx.Items.definition(item.kind).magazine))
	p.bag = data.bag; p.stash = data.stash; p.equipment = data.equipment; p.magazines = magazines
	p.credits = clampi(int(data.get("credits",500)),0,999999)
	for stat in ["hp","hunger","thirst"]: p[stat] = clampf(float(data.get(stat,100)),0,100)
	p.ammo = int(magazines.get(p.equipment.weapon.get("uid",""),0)); p.reloading = false
	ctx.reset_transients(id)
	ctx._update_weight(p)
	return OK

static func _valid_saved_item(ctx, item: Variant, seen: Dictionary) -> bool:
	if not item is Dictionary: return false
	if item.is_empty(): return true
	if not item.get("kind") is String or not ctx.Items.DEFS.has(item.kind) or not item.get("uid") is String: return false
	var count: Variant = item.get("count")
	if not count is float and not count is int: return false
	if not is_finite(float(count)) or float(count) != floor(float(count)) or count < 1 or count > int(ctx.Items.definition(item.kind).stack): return false
	if seen.has(item.uid): return false
	seen[item.uid] = true
	return true
