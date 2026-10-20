extends RefCounted
## Duckov's unmodified Character stats: 100 degrees / 37 m / 1.5 m.
const VIEW_ANGLE := 100.0
const VIEW_DISTANCE := 37.0
const SENSE_RADIUS := 1.5
const VISION_HEIGHT := 3.0
const EYE_HEIGHT := 1.0

static func contains(observer: Vector3, aim: Vector2, point: Vector3) -> bool:
	if absf(point.y-observer.y)>VISION_HEIGHT:return false
	var offset:=Vector2(point.x-observer.x,point.z-observer.z)
	var distance:=offset.length()
	if distance<=SENSE_RADIUS:return true
	return distance<=VIEW_DISTANCE and aim.normalized().dot(offset/distance)>=cos(deg_to_rad(VIEW_ANGLE*.5))
