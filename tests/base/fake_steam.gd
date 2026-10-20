extends RefCounted
signal lobby_created(result:int,id:int)
signal lobby_joined(id:int,permissions:int,locked:bool,response:int)
signal lobby_data_update(success:int,id:int,member:int)
signal lobby_chat_update(id:int,changed:int,making_change:int,state:int)
signal join_requested(id:int,friend:int)
signal overlay_toggled(active:bool,user:bool,app:int)
const MY_ID := 76561198000000001
const FRIEND_ID := 76561198000000002
var init_status := 0
var online := true
var overlay := false
var init_calls := 0
var shutdown_calls := 0
var relay_calls := 0
var callbacks := 0
var created: Array = []
var joined: Array = []
var left: Array = []
var requested: Array = []
var invites: Array = []
var joinable: Dictionary = {}
var rich: Dictionary = {}
var rooms: Dictionary = {}
var in_rooms: Dictionary = {}
var friends: Array = []
var friend_games: Dictionary = {}
var request_ok := true
var set_data_ok := true
var enforce_owner_membership := true
func steamInitEx(app:int,embed:bool) -> Dictionary:
    init_calls+=1
    return {"status":init_status,"verbal":"mock init error" if init_status else ""}
func loggedOn() -> bool: return online
func initRelayNetworkAccess() -> void: relay_calls+=1
func getSteamID() -> int: return MY_ID
func getPersonaName() -> String: return "测试鸭"
func run_callbacks() -> void: callbacks+=1
func steamShutdown() -> void: shutdown_calls+=1
func createLobby(kind:int,limit:int) -> void: created.append([kind,limit])
func joinLobby(id:int) -> void: joined.append(id)
func leaveLobby(id:int) -> void:
    left.append(id)
    in_rooms.erase(id)
func requestLobbyData(id:int) -> bool:
    requested.append(id)
    return request_ok
func setLobbyData(id:int,key:String,value:String) -> bool:
    if not set_data_ok:return false
    if not rooms.has(id):rooms[id]={"owner":MY_ID,"members":[MY_ID],"limit":5,"data":{}}
    rooms[id].data[key]=value
    return true
func getLobbyData(id:int,key:String) -> String:
    return str(rooms.get(id,{}).get("data",{}).get(key,""))
func setLobbyJoinable(id:int,value:bool) -> bool:
    joinable[id]=value
    return true
func getLobbyOwner(id:int) -> int:
    if enforce_owner_membership and not in_rooms.has(id):return 0
    return int(rooms.get(id,{}).get("owner",0))
func getNumLobbyMembers(id:int) -> int: return rooms.get(id,{}).get("members",[]).size()
func getLobbyMemberLimit(id:int) -> int: return int(rooms.get(id,{}).get("limit",0))
func getLobbyMemberByIndex(id:int,index:int) -> int: return rooms[id].members[index]
func clearRichPresence() -> void: rich.clear()
func setRichPresence(key:String,value:String) -> bool:
    rich[key]=value
    return true
func getFriendPersonaName(id:int) -> String: return "好友%d"%id
func isOverlayEnabled() -> bool: return overlay
func activateGameOverlayInviteDialog(id:int) -> void: invites.append(id)
func getFriendCount(flags:int) -> int: return friends.size()
func getFriendByIndex(index:int,flags:int) -> int: return friends[index]
func getFriendGamePlayed(id:int) -> Dictionary: return friend_games.get(id,{})
func populate(id:int,game:String,protocol:String,owner:int=FRIEND_ID) -> void:
    var config:=ConfigFile.new()
    config.load("res://app/network/steam_config.cfg")
    var build: String=str(config.get_value("steam","build_id","a1_ground_zero_dev_20261020"))
    rooms[id]={"owner":owner,"members":[owner],"limit":5,"data":{"game":game,"protocol":protocol,"build":build,"host_id":str(owner),"name":"好友基地"}}
func emit_created(id:int,result:int=1) -> void:
    if result==1:in_rooms[id]=true
    lobby_created.emit(result,id)
func emit_joined(id:int,response:int=1) -> void:
    if response==1:in_rooms[id]=true
    lobby_joined.emit(id,0,false,response)
