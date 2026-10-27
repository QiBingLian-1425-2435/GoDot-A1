extends RefCounted
## Migrated reference behavior; called only through the owning composition/model.

static func save_profile(ctx, path: String, id: int = 1) -> Error:
	if path.is_empty() or not ctx.state.players.has(id): return ERR_INVALID_PARAMETER
	var data:=capture(ctx,id)
	data.camp=ctx.state.camp.duplicate()
	var file = FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data));file.flush()
	var result:=file.get_error();file.close()
	if result!=OK:return result
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))

static func load_profile(ctx, path: String, id: int = 1) -> Error:
	if not ctx.state.players.has(id): return ERR_INVALID_PARAMETER
	if not FileAccess.file_exists(path): return ERR_FILE_NOT_FOUND
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return FileAccess.get_open_error()
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK:return ERR_FILE_CORRUPT
	if not valid(ctx,parser.data):return ERR_FILE_CORRUPT
	var levels:Variant=parser.data.get("camp",ctx.Camp.initial())
	if not ctx.Camp.valid(levels):return ERR_FILE_CORRUPT
	ctx.state.camp=ctx.Camp.normalized(levels)
	return apply(ctx,parser.data,id)

static func capture(ctx, id: int) -> Dictionary:
	var p: Dictionary=ctx.state.players[id]
	return {"version":1,"appearance":ctx.Appearance.normalized(p.get("appearance",{})),"bag":p.bag,"stash":p.stash,"equipment":p.equipment,"magazines":p.magazines,"credits":p.credits,"hp":p.hp,"san":p.get("san",100),"hunger":p.hunger,"thirst":p.thirst,"stamina":p.stamina}.duplicate(true)

static func valid(ctx, data: Variant) -> bool:
	if not data is Dictionary or int(data.get("version",0)) != 1: return false
	if not data.get("bag") is Array or data.bag.size() != 24 or not data.get("stash") is Array or data.stash.size() != 48 or not data.get("equipment") is Dictionary: return false
	if data.has("appearance") and not ctx.Appearance.valid(data.appearance):return false
	var seen: Dictionary = {}
	for container in [data.bag,data.stash,data.equipment.values()]:
		for item in container:
			if not ctx._valid_saved_item(item,seen): return false
	for slot in ctx.EQUIPMENT:
		if not data.equipment.has(slot): return false
		if not data.equipment[slot].is_empty() and ctx.Items.definition(data.equipment[slot].kind).category != slot: return false
	if data.equipment.size() != 4: return false
	for key in ["hp","san","hunger","thirst","stamina","credits"]:
		var value: Variant=data.get(key,100)
		if (not value is int and not value is float) or not is_finite(float(value)):return false
	if data.has("magazines"):
		if not data.magazines is Dictionary:return false
		for value in data.magazines.values():
			if (not value is int and not value is float) or not is_finite(float(value)) or float(value)!=floor(float(value)):return false
	return true

static func apply(ctx, value: Variant, id: int) -> Error:
	if not ctx.state.players.has(id) or not valid(ctx,value):return ERR_FILE_CORRUPT
	var data: Dictionary=value.duplicate(true)
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
	p.appearance=ctx.Appearance.normalized(data.get("appearance",{}))
	p.bag = data.bag; p.stash = data.stash; p.equipment = data.equipment; p.magazines = magazines
	p.credits = clampi(int(data.get("credits",500)),0,999999)
	ctx.Camp.refresh_player(ctx,p)
	for stat in ["hp","san","hunger","thirst","stamina"]: p[stat] = clampf(float(data.get(stat,100)),0,float(p.get("max_"+stat,100)))
	p.ammo = int(magazines.get(p.equipment.weapon.get("uid",""),0)); p.reloading = false
	ctx.reset_transients(id)
	p.life = "alive";p.possessing = 0;p.rescue = {};p.corpse_uid = ""
	if (float(p.hp)<=0 or float(p.san)<=0) and ctx.state.get("world","bunker")=="bunker": ctx.Souls.revive(ctx,p)
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
