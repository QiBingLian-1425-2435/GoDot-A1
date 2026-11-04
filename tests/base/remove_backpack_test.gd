extends SceneTree
func _initialize():
 var m=load("res://features/base/base_model.gd").new();m.add_player(1,"test")
 var p:Dictionary=m.state.players[1]
 assert(not p.equipment.has("backpack") and not m.Items.DEFS.has("backpack"))
 var saved:Dictionary=m.Profile.capture(m,1)
 saved.equipment.backpack={"kind":"backpack","uid":"retired1","count":1}
 saved.bag[23]={"kind":"backpack","uid":"retired2","count":1}
 saved.stash[47]={"kind":"backpack","uid":"retired3","count":1}
 var credits:int=p.credits
 assert(m.Profile.valid(m,saved))
 assert(m.Profile.apply(m,saved,1)==OK)
 assert(p.bag[23].is_empty() and p.stash[47].is_empty() and not p.equipment.has("backpack"))
 assert(p.credits==credits and p.equipment.weapon.kind=="rifle" and p.max_weight==28)
 print("REMOVE_BACKPACK passed");quit()
