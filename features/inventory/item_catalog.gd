extends RefCounted
const Texts = preload("res://features/localization/game_text.gd")
## Read-only item definitions. Runtime stacks always live in Model state.
const DEFS := {
	"san_capsule": {"name":"⟦item_catalog.001⟧","weight":0.02,"stack":1,"color":Color("a577bf"),"category":"food","description":"⟦item_catalog.002⟧"},
	"revival_serum": {"name":"⟦item_catalog.003⟧","weight":0.2,"stack":3,"color":Color("70d9ac"),"category":"tool","description":"⟦item_catalog.004⟧"},
	"poison_capsule": {"name":"⟦item_catalog.005⟧","weight":0.02,"stack":1,"color":Color("a577bf"),"category":"food","description":"⟦item_catalog.006⟧"},
	"rifle": {"name":"⟦item_catalog.007⟧", "weight":3.4, "stack":1, "color":Color("aab8a0"), "category":"weapon", "description":"⟦item_catalog.008⟧", "magazine":30, "damage":34, "fire_interval":0.10, "reload_time":1.15},
	"pistol": {"name":"⟦item_catalog.009⟧", "weight":1.1, "stack":1, "color":Color("b4bec5"), "category":"weapon", "description":"⟦item_catalog.010⟧", "magazine":12, "damage":20, "fire_interval":0.16, "reload_time":0.85},
	"ammo": {"name":"⟦item_catalog.011⟧", "weight":0.025, "stack":60, "color":Color("d5b26f"), "category":"ammo", "description":"⟦item_catalog.012⟧"},
	"medkit": {"name":"⟦item_catalog.013⟧", "weight":0.75, "stack":3, "color":Color("e78a75"), "category":"medical", "description":"⟦item_catalog.014⟧"},
	"bandage": {"name":"⟦item_catalog.015⟧", "weight":0.15, "stack":5, "color":Color("e0dbc3"), "category":"medical", "description":"⟦item_catalog.016⟧"},
	"water": {"name":"⟦item_catalog.017⟧", "weight":0.6, "stack":3, "color":Color("7cbfdd"), "category":"food", "description":"⟦item_catalog.018⟧"},
	"canned_food": {"name":"⟦item_catalog.019⟧", "weight":0.45, "stack":3, "color":Color("d7a56d"), "category":"food", "description":"⟦item_catalog.020⟧"},
	"scrap": {"name":"⟦item_catalog.021⟧", "weight":0.3, "stack":20, "color":Color("929c9b"), "category":"material", "description":"⟦item_catalog.022⟧"},
	"helmet": {"name":"⟦item_catalog.023⟧", "weight":1.3, "stack":1, "color":Color("98a88a"), "category":"helmet", "description":"⟦item_catalog.024⟧"},
	"armor": {"name":"⟦item_catalog.025⟧", "weight":4.0, "stack":1, "color":Color("8e9b86"), "category":"armor", "description":"⟦item_catalog.026⟧"},
	"backpack": {"name":"⟦item_catalog.027⟧", "weight":0.8, "stack":1, "color":Color("b09b72"), "category":"backpack", "description":"⟦item_catalog.028⟧"},
	"biscuits": {"name":"⟦item_catalog.029⟧","weight":0.2,"stack":5,"color":Color("d2b46c"),"category":"food","description":"⟦item_catalog.030⟧"},
	"juice": {"name":"⟦item_catalog.031⟧","weight":0.4,"stack":3,"color":Color("e9a04c"),"category":"food","description":"⟦item_catalog.032⟧"},
	"energy_bar": {"name":"⟦item_catalog.033⟧","weight":0.12,"stack":5,"color":Color("986eca"),"category":"food","description":"⟦item_catalog.034⟧"},
	"medical_box": {"name":"⟦item_catalog.035⟧","weight":1.5,"stack":1,"color":Color("cd6863"),"category":"medical","description":"⟦item_catalog.036⟧"},
	"glowstick": {"name":"⟦item_catalog.037⟧","weight":0.15,"stack":5,"color":Color("70d9ac"),"category":"tool","description":"⟦item_catalog.038⟧"},
	"lockpick": {"name":"⟦item_catalog.039⟧","weight":0.1,"stack":5,"color":Color("b1bdc6"),"category":"tool","description":"⟦item_catalog.040⟧"},
	"smoke_grenade": {"name":"⟦item_catalog.041⟧","weight":0.4,"stack":3,"color":Color("8da19b"),"category":"tool","description":"⟦item_catalog.042⟧"},
	"beacon": {"name":"⟦item_catalog.043⟧","weight":0.5,"stack":2,"color":Color("76b5e0"),"category":"tool","description":"⟦item_catalog.044⟧"},
	"tape": {"name":"⟦item_catalog.045⟧","weight":0.1,"stack":10,"color":Color("c4b080"),"category":"material","description":"⟦item_catalog.046⟧"},
	"battery": {"name":"⟦item_catalog.047⟧","weight":0.4,"stack":5,"color":Color("c5bc61"),"category":"material","description":"⟦item_catalog.048⟧"},
	"circuit_board": {"name":"⟦item_catalog.049⟧","weight":0.15,"stack":5,"color":Color("77b49a"),"category":"material","description":"⟦item_catalog.050⟧"},
	"optical_parts": {"name":"⟦item_catalog.051⟧","weight":0.2,"stack":3,"color":Color("8ea3d5"),"category":"material","description":"⟦item_catalog.052⟧"},
	"pocket_watch": {"name":"⟦item_catalog.053⟧","weight":0.15,"stack":1,"color":Color("cdb487"),"category":"valuable","description":"⟦item_catalog.054⟧"},
	"gold_statue": {"name":"⟦item_catalog.055⟧","weight":2.0,"stack":1,"color":Color("e3bd58"),"category":"valuable","description":"⟦item_catalog.056⟧"},
	"encrypted_core": {"name":"⟦item_catalog.057⟧","weight":0.5,"stack":1,"color":Color("d96968"),"category":"valuable","description":"⟦item_catalog.058⟧"}
}

const TYPES := {"food":"⟦item_catalog.059⟧","medical":"⟦item_catalog.060⟧","tool":"⟦item_catalog.061⟧","material":"⟦item_catalog.062⟧","valuable":"⟦item_catalog.063⟧","equipment":"⟦item_catalog.064⟧"}
const VALUES := {"san_capsule":10,"revival_serum":100,"poison_capsule":10,"rifle":900,"pistol":350,"ammo":2,"medkit":180,"bandage":25,"water":30,"canned_food":45,"scrap":18,"helmet":250,"armor":800,"backpack":200,"biscuits":35,"juice":120,"energy_bar":380,"medical_box":850,"glowstick":150,"lockpick":550,"smoke_grenade":650,"beacon":1600,"tape":40,"battery":180,"circuit_board":620,"optical_parts":1800,"pocket_watch":2400,"gold_statue":6800,"encrypted_core":18000}
const EFFECTS := {"san_capsule":{"san":-100},"poison_capsule":{"hp":-1000},"medkit":{"hp":45},"bandage":{"hp":18},"water":{"thirst":40},"canned_food":{"hunger":35},"biscuits":{"hunger":30,"thirst":-5},"juice":{"thirst":30,"hunger":10},"energy_bar":{"hunger":55,"stamina":20},"medical_box":{"hp":80}}
const TIERS := ["⟦item_catalog.065⟧","⟦item_catalog.066⟧","⟦item_catalog.067⟧","⟦item_catalog.068⟧","⟦item_catalog.069⟧","⟦item_catalog.070⟧"]
const COLORS := [Color("c5ccc9"),Color("73bc81"),Color("639ee5"),Color("b183df"),Color("edc65c"),Color("ed7474")]
static var _definitions: Dictionary={}

static func definition(kind: String) -> Dictionary:
	if _definitions.has(kind):return _definitions[kind]
	var result: Dictionary=DEFS.get(kind,{"name":"⟦item_catalog.071⟧","weight":0.0,"stack":1,"color":Color.GRAY,"category":"unknown","description":""}).duplicate(true)
	result.value=int(VALUES.get(kind,0))
	result.rarity=tier(result.value)
	result.rarity_name=TIERS[result.rarity];result.rarity_color=COLORS[result.rarity]
	result.item_type="equipment" if result.category in ["weapon","ammo","helmet","armor","backpack"] else result.category
	result.type_name=TYPES.get(result.item_type,"⟦item_catalog.072⟧")
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
	return Texts.format("⟦item_catalog.073⟧", [info.type_name,info.rarity_name,info.description,info.weight,count,float(info.weight)*count,info.value,int(info.value)*count,float(info.value)/maxf(.001,float(info.weight))])+("⟦item_catalog.074⟧" if not info.sellable else "")

static func weight(bag: Array) -> float:
	var total := 0.0
	for item in bag:
		if item is Dictionary and not item.is_empty():
			total += float(definition(str(item.get("kind", ""))).weight) * int(item.get("count", 0))
	return total
