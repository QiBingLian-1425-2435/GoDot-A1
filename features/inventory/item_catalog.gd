extends RefCounted
## Read-only item definitions. Runtime stacks always live in Model state.
const DEFS := {
	"rifle": {"name":"巡林步枪", "weight":3.4, "stack":1, "color":Color("aab8a0"), "category":"weapon", "description":"基地训练用半自动步枪。30发弹匣，R装填。", "magazine":30, "damage":34},
	"pistol": {"name":"轻型手枪", "weight":1.1, "stack":1, "color":Color("b4bec5"), "category":"weapon", "description":"轻便的备用武器。12发弹匣。", "magazine":12, "damage":20},
	"ammo": {"name":"通用训练弹", "weight":0.025, "stack":60, "color":Color("d5b26f"), "category":"ammo", "description":"两种训练武器共用的弹药。"},
	"medkit": {"name":"急救包", "weight":0.75, "stack":3, "color":Color("e78a75"), "category":"medical", "description":"恢复45点生命。"},
	"bandage": {"name":"绷带", "weight":0.15, "stack":5, "color":Color("e0dbc3"), "category":"medical", "description":"恢复18点生命。"},
	"water": {"name":"瓶装水", "weight":0.6, "stack":3, "color":Color("7cbfdd"), "category":"food", "description":"恢复40点水分。"},
	"canned_food": {"name":"午餐罐头", "weight":0.45, "stack":3, "color":Color("d7a56d"), "category":"food", "description":"恢复35点饱食。"},
	"scrap": {"name":"金属零件", "weight":0.3, "stack":20, "color":Color("929c9b"), "category":"material", "description":"工作台用4个零件制作1个急救包。"},
	"helmet": {"name":"巡护头盔", "weight":1.3, "stack":1, "color":Color("98a88a"), "category":"helmet", "description":"基础头部装备。"},
	"armor": {"name":"轻型护甲", "weight":4.0, "stack":1, "color":Color("8e9b86"), "category":"armor", "description":"基础躯干装备。"},
	"backpack": {"name":"旅行背包", "weight":0.8, "stack":1, "color":Color("b09b72"), "category":"backpack", "description":"舒适负重从28公斤提升到44公斤。"}
}

static func definition(kind: String) -> Dictionary:
	return DEFS.get(kind, {"name":"未知物品", "weight":0.0, "stack":1, "color":Color.GRAY, "category":"unknown", "description":""})

static func weight(bag: Array) -> float:
	var total := 0.0
	for item in bag:
		if item is Dictionary and not item.is_empty():
			total += float(definition(str(item.get("kind", ""))).weight) * int(item.get("count", 0))
	return total
