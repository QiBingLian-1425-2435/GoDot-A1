extends "res://ui/widgets/item_slot.gd"
const Quick=preload("res://features/player/quick_slots.gd")
signal binding_requested(index:int,payload:Dictionary)
func _get_drag_data(_at:Vector2)->Variant:return null
func _can_drop_data(_at:Vector2,data:Variant)->bool:
 return data is Dictionary and data.get("duckov_item",false) and data.get("from","")=="bag" and Quick.allowed(str(data.get("kind","")))
func _drop_data(_at:Vector2,data:Variant)->void:
 if _can_drop_data(_at,data):binding_requested.emit(int(slot_index),data)
func _gui_input(event:InputEvent)->void:
 if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
  binding_requested.emit(int(slot_index),{});accept_event()

func set_item(value:Dictionary,info:Dictionary={})->void:
 super.set_item(value,info)
 if not value.is_empty():Texts.bind(self,str(info.get("name",""))+"\n⟦quick.drag_hint⟧","tooltip_text")
