extends RefCounted
## Only the host writes these profiles. Network peer IDs never become save keys.
const Profile=preload("res://features/persistence/profile_store.gd")
var path:=""
var owner:=""
var profiles: Dictionary={}
var members: Dictionary={}

func begin(ctx, file_path: String, owner_key: String, legacy: String="") -> Error:
	if file_path.is_empty() or owner_key.is_empty():return ERR_INVALID_PARAMETER
	var saved: Dictionary={}
	if FileAccess.file_exists(file_path):
		var parser:=JSON.new()
		if parser.parse(FileAccess.get_file_as_string(file_path))!=OK:return ERR_FILE_CORRUPT
		var parsed: Variant=parser.data
		if not parsed is Dictionary or parsed.get("version")!=1 or parsed.get("owner")!=owner_key or not parsed.get("profiles") is Dictionary:return ERR_FILE_CORRUPT
		for key in parsed.profiles:
			if not key is String or key.is_empty() or not Profile.valid(ctx,parsed.profiles[key]):return ERR_FILE_CORRUPT
		if not parsed.profiles.has(owner_key):return ERR_FILE_CORRUPT
		saved=parsed.profiles
	elif FileAccess.file_exists(file_path+".bak"):
		return ERR_FILE_CORRUPT # Never silently roll back consumed items from an old backup.
	elif not legacy.is_empty() and FileAccess.file_exists(legacy):
		var error: Error=Profile.load_profile(ctx,legacy,1)
		if error!=OK:return error
	path=file_path;owner=owner_key;profiles=saved;members={}
	var result:=admit(ctx,1,owner_key)
	if result!=OK:return result
	return checkpoint(ctx)

func admit(ctx, id: int, identity: String) -> Error:
	if path.is_empty() or identity.is_empty() or identity in members.values():return ERR_UNAUTHORIZED
	if profiles.has(identity):
		var result: Error=Profile.apply(ctx,profiles[identity],id)
		if result!=OK:return result
	members[id]=identity
	profiles[identity]=Profile.capture(ctx,id)
	return OK

func checkpoint(ctx) -> Error:
	if path.is_empty():return OK
	for id in members:
		if ctx.state.players.has(id):profiles[members[id]]=Profile.capture(ctx,id)
	var absolute:=ProjectSettings.globalize_path(path)
	var result:=DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result!=OK:return result
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version":1,"owner":owner,"profiles":profiles}))
	file.flush();result=file.get_error();file.close()
	if result!=OK:return result
	if FileAccess.file_exists(path):
		result=DirAccess.copy_absolute(absolute,absolute+".bak")
		if result!=OK:return result
	return DirAccess.rename_absolute(absolute+".tmp",absolute)

func detach(ctx, id: int) -> Error:
	var result:=checkpoint(ctx)
	members.erase(id)
	return result

func clear() -> void:
	path="";owner="";profiles={};members={}
