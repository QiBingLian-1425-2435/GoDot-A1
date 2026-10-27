extends RefCounted
const PARTS := ["hair","skin","shirt","pants"]
static func defaults(gender: String = "male") -> Dictionary:
	return {"gender":gender,"hair":"#38271e" if gender=="male" else "#29242c","skin":"#efb68e","shirt":"#657443" if gender=="male" else "#5c7485","pants":"#b6a382" if gender=="male" else "#45454b"}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=5 or value.get("gender","") not in ["male","female"]:return false
	for part in PARTS:
		var color:Variant=value.get(part)
		if not color is String or color.length()!=7 or not color.begins_with("#"):return false
		for c in color.substr(1).to_lower():
			if not c in "0123456789abcdef":return false
	return true

static func normalized(value: Variant) -> Dictionary:
	return value.duplicate(true) if valid(value) else defaults()
