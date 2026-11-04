extends RefCounted
const Items=preload("res://features/inventory/item_catalog.gd")
const ACTIONS=["rifle","pistol","quick_3","medkit","water","quick_6","quick_7","quick_8"]
const DEFAULTS=["rifle","pistol","","medkit","water","","",""]
const PATH="user://quick_slots.cfg"
static var kinds:Array=[]
static func ensure_loaded()->void:
 if not kinds.is_empty():return
 kinds=DEFAULTS.duplicate()
 var config:=ConfigFile.new()
 if config.load(PATH)!=OK:return
 var stored:Variant=config.get_value("quick","kinds",DEFAULTS)
 if stored is Array and stored.size()==8:
  for i in range(8):kinds[i]=stored[i] if stored[i] is String and (stored[i]=="" or allowed(stored[i])) else ""
static func allowed(kind:String)->bool:
 if not Items.DEFS.has(kind):return false
 var info:Dictionary=Items.definition(kind)
 return info.usable or info.category in ["weapon","helmet","armor"]
static func bind_slot(index:int,kind:String)->Error:
 ensure_loaded()
 if index<0 or index>=8 or (kind!="" and not allowed(kind)):return ERR_INVALID_PARAMETER
 var next:=kinds.duplicate();next[index]=kind
 var config:=ConfigFile.new();config.set_value("quick","kinds",next)
 var result:=config.save(PATH)
 if result==OK:kinds=next
 return result
static func resolve(player:Dictionary,index:int)->Dictionary:
 ensure_loaded()
 var kind:String=kinds[index]
 for slot in player.get("equipment",{}):
  var item:Dictionary=player.equipment[slot]
  if not item.is_empty() and item.get("kind","")==kind:return {"item":item,"equipped":true,"index":-1}
 var bag:Array=player.get("bag",[])
 for i in bag.size():
  if not bag[i].is_empty() and bag[i].get("kind","")==kind:return {"item":bag[i],"equipped":false,"index":i}
 return {}
