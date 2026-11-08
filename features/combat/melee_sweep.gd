extends RefCounted
## The visible slash and host hit checks share this footprint and active window.
const Items=preload("res://features/inventory/item_catalog.gd")
const START:=.24
const END:=.56
const FADE_END:=.76
const HALF_ANGLE:=deg_to_rad(70.0)
const INNER_RADIUS:=.15
static func angle(phase:float)->float:
	return lerpf(HALF_ANGLE,-HALF_ANGLE,smoothstep(START,END,phase))
static func reach(kind:String)->float:
	return float(Items.definition(kind).get("reach",0.0))
static func height(crouched:bool)->float:
	return .58 if crouched else .98
static func contains(offset:Vector2,kind:String,phase:float)->bool:
	var radius:=offset.length()
	if radius<INNER_RADIUS-.0001 or radius>reach(kind)+.0001 or phase<START:return false
	var bearing:=atan2(offset.x,-offset.y)
	return bearing<=HALF_ANGLE+.0001 and bearing>=angle(minf(phase,END))-.0001
