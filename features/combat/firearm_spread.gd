extends RefCounted
## Degrees of half-angle. Authority changes heat only on accepted gunshots.
const LIMITS={"rifle":7.0,"pistol":5.0}
const GAIN={"rifle":.65,"pistol":.6}
const DELAY=.24
const RECOVERY=2.4

static func supported(kind:String)->bool:return LIMITS.has(kind)

static func shot(p:Dictionary,kind:String)->float:
	if not supported(kind):return 0.0
	var cone:float=minf(float(p.get("gun_bloom",0)),LIMITS[kind])
	p.gun_bloom=minf(LIMITS[kind],cone+GAIN[kind]);p.gun_bloom_wait=DELAY
	return deg_to_rad(cone)

static func tick(p:Dictionary,dt:float)->void:
	var wait:float=maxf(0,float(p.get("gun_bloom_wait",0)))
	p.gun_bloom_wait=maxf(0,wait-dt)
	p.gun_bloom=maxf(0,float(p.get("gun_bloom",0))-RECOVERY*maxf(0,dt-wait))

static func angle(p:Dictionary)->float:
	if not preload("res://features/combat/throwable_system.gd").held(p).is_empty():return 0.0
	var kind:String=p.get("equipment",{}).get("weapon",{}).get("kind","")
	return deg_to_rad(minf(float(p.get("gun_bloom",0)),LIMITS[kind])) if supported(kind) else 0.0
