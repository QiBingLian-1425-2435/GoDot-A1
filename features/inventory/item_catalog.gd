extends RefCounted
## Read-only item definitions. Runtime stacks always live in Model state.
const DEFS := {
	"san_capsule": {"name":"失智胶囊（SAN 清零）","weight":0.02,"stack":1,"color":Color("a577bf"),"category":"food","description":"危险：SAN 立即归零并尸变，靠近队友会失控杀死队友。"},
	"revival_serum": {"name":"复活针","weight":0.2,"stack":3,"color":Color("70d9ac"),"category":"tool","description":"使最近的同层无遮挡尸变队友或灵魂遗体恢复 30 生命与 SAN。距离 2.4 米内使用，注意避开尸变者 0.9 米杀伤范围。"},
	"poison_capsule": {"name":"剧毒胶囊（服用致死）","weight":0.02,"stack":1,"color":Color("a577bf"),"category":"food","description":"危险：服用后生命立即归零，进入灵魂状态。装备留在遗体中，可由队友救援。"},
	"rifle": {"name":"巡林步枪", "weight":3.4, "stack":1, "color":Color("aab8a0"), "category":"weapon", "description":"基地训练用自动步枪。30发弹匣，R装填。", "magazine":30, "damage":34, "fire_interval":0.10, "reload_time":1.15},
	"pistol": {"name":"轻型手枪", "weight":1.1, "stack":1, "color":Color("b4bec5"), "category":"weapon", "description":"轻便的备用武器。12发弹匣。", "magazine":12, "damage":20, "fire_interval":0.16, "reload_time":0.85},
	"ammo": {"name":"通用训练弹", "weight":0.025, "stack":60, "color":Color("d5b26f"), "category":"ammo", "description":"两种训练武器共用的弹药。"},
	"medkit": {"name":"急救包", "weight":0.75, "stack":3, "color":Color("e78a75"), "category":"medical", "description":"恢复45点生命。"},
	"bandage": {"name":"绷带", "weight":0.15, "stack":5, "color":Color("e0dbc3"), "category":"medical", "description":"恢复18点生命。"},
	"water": {"name":"瓶装水", "weight":0.6, "stack":3, "color":Color("7cbfdd"), "category":"food", "description":"恢复40点水分。"},
	"canned_food": {"name":"午餐罐头", "weight":0.45, "stack":3, "color":Color("d7a56d"), "category":"food", "description":"恢复35点饱食。"},
	"scrap": {"name":"金属零件", "weight":0.3, "stack":20, "color":Color("929c9b"), "category":"material", "description":"工作台用4个零件制作1个急救包。"},
	"helmet": {"name":"巡护头盔", "weight":1.3, "stack":1, "color":Color("98a88a"), "category":"helmet", "description":"基础头部装备。"},
	"armor": {"name":"轻型护甲", "weight":4.0, "stack":1, "color":Color("8e9b86"), "category":"armor", "description":"基础躯干装备。"},
	"backpack": {"name":"旅行背包", "weight":0.8, "stack":1, "color":Color("b09b72"), "category":"backpack", "description":"舒适负重从28公斤提升到44公斤。"},
	"biscuits": {"name":"压缩饼干","weight":0.2,"stack":5,"color":Color("d2b46c"),"category":"food","description":"恢复30饱食，降低5水分。"},
	"juice": {"name":"果汁","weight":0.4,"stack":3,"color":Color("e9a04c"),"category":"food","description":"恢复30水分、10饱食。"},
	"energy_bar": {"name":"高能营养棒","weight":0.12,"stack":5,"color":Color("986eca"),"category":"food","description":"恢复55饱食、20耐力。"},
	"medical_box": {"name":"专业医疗箱","weight":1.5,"stack":1,"color":Color("cd6863"),"category":"medical","description":"治疗4秒后恢复80生命；切图或离房中断，不返还。"},
	"glowstick": {"name":"便携照明棒","weight":0.15,"stack":5,"color":Color("70d9ac"),"category":"tool","description":"在面前放置照明棒，照明60秒，不扩大视野。"},
	"lockpick": {"name":"简易开锁器","weight":0.1,"stack":5,"color":Color("b1bdc6"),"category":"tool","description":"消耗一个，开启2.4米内可触及的普通上锁容器。"},
	"smoke_grenade": {"name":"烟雾弹","weight":0.4,"stack":3,"color":Color("8da19b"),"category":"tool","description":"在面前投放直径6米、持续8秒的烟雾，遮挡视线，不阻挡子弹。"},
	"beacon": {"name":"队伍信标","weight":0.5,"stack":2,"color":Color("76b5e0"),"category":"tool","description":"放置全队可见的集合标记，持续60秒。"},
	"tape": {"name":"胶带","weight":0.1,"stack":10,"color":Color("c4b080"),"category":"material","description":"工具制作材料。"},
	"battery": {"name":"工业电池","weight":0.4,"stack":5,"color":Color("c5bc61"),"category":"material","description":"用于照明棒、医疗箱与电子设备制作。"},
	"circuit_board": {"name":"精密电路板","weight":0.15,"stack":5,"color":Color("77b49a"),"category":"material","description":"制作队伍信标的精密材料。"},
	"optical_parts": {"name":"光学组件","weight":0.2,"stack":3,"color":Color("8ea3d5"),"category":"material","description":"高级器件，可留存或向商人出售。"},
	"pocket_watch": {"name":"老式怀表","weight":0.15,"stack":1,"color":Color("cdb487"),"category":"valuable","description":"收藏品，可向基地商人出售。"},
	"gold_statue": {"name":"纯金雕像","weight":2.0,"stack":1,"color":Color("e3bd58"),"category":"valuable","description":"沉重且珍贵的探索战利品。"},
	"encrypted_core": {"name":"加密实验核心","weight":0.5,"stack":1,"color":Color("d96968"),"category":"valuable","description":"极稀有的实验设备；当前可出售，尚无研究任务。"}
}

const TYPES := {"food":"食品饮料","medical":"医疗用品","tool":"工具道具","material":"制作材料","valuable":"贵重物品","equipment":"武器装备"}
const VALUES := {"san_capsule":10,"revival_serum":100,"poison_capsule":10,"rifle":900,"pistol":350,"ammo":2,"medkit":180,"bandage":25,"water":30,"canned_food":45,"scrap":18,"helmet":250,"armor":800,"backpack":200,"biscuits":35,"juice":120,"energy_bar":380,"medical_box":850,"glowstick":150,"lockpick":550,"smoke_grenade":650,"beacon":1600,"tape":40,"battery":180,"circuit_board":620,"optical_parts":1800,"pocket_watch":2400,"gold_statue":6800,"encrypted_core":18000}
const EFFECTS := {"san_capsule":{"san":-100},"poison_capsule":{"hp":-1000},"medkit":{"hp":45},"bandage":{"hp":18},"water":{"thirst":40},"canned_food":{"hunger":35},"biscuits":{"hunger":30,"thirst":-5},"juice":{"thirst":30,"hunger":10},"energy_bar":{"hunger":55,"stamina":20},"medical_box":{"hp":80}}
const TIERS := ["普通","优良","稀有","史诗","珍贵","至宝"]
const COLORS := [Color("c5ccc9"),Color("73bc81"),Color("639ee5"),Color("b183df"),Color("edc65c"),Color("ed7474")]
static var _definitions: Dictionary={}

static func definition(kind: String) -> Dictionary:
	if _definitions.has(kind):return _definitions[kind]
	var result: Dictionary=DEFS.get(kind,{"name":"未知物品","weight":0.0,"stack":1,"color":Color.GRAY,"category":"unknown","description":""}).duplicate(true)
	result.value=int(VALUES.get(kind,0))
	result.rarity=tier(result.value)
	result.rarity_name=TIERS[result.rarity];result.rarity_color=COLORS[result.rarity]
	result.item_type="equipment" if result.category in ["weapon","ammo","helmet","armor","backpack"] else result.category
	result.type_name=TYPES.get(result.item_type,"未知类型")
	result.sellable=kind!="ammo" and DEFS.has(kind)
	result.buy_price=2 if kind=="ammo" else result.value*3
	result.effects=EFFECTS.get(kind,{})
	result.usable=EFFECTS.has(kind) or result.category=="tool"
	_definitions[kind]=result
	return result

static func tier(value: int) -> int:
	if value>=10000:return 5
	if value>=3000:return 4
	if value>=1000:return 3
	if value>=300:return 2
	if value>=100:return 1
	return 0

static func details(item: Dictionary) -> String:
	var info:=definition(str(item.get("kind","")))
	var count:=int(item.get("count",1))
	return "%s · %s\n%s\n单件 %.2f kg · 数量 %d · 总重 %.2f kg\n回收单价 %d · 整组 %d · 每公斤 %.0f"%[info.type_name,info.rarity_name,info.description,info.weight,count,float(info.weight)*count,info.value,int(info.value)*count,float(info.value)/maxf(.001,float(info.weight))]+("\n训练弹不可出售" if not info.sellable else "")

static func weight(bag: Array) -> float:
	var total := 0.0
	for item in bag:
		if item is Dictionary and not item.is_empty():
			total += float(definition(str(item.get("kind", ""))).weight) * int(item.get("count", 0))
	return total
