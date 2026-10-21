extends RefCounted
## Small player-only caps over verified concave pockets; keep visuals, shots and sight unchanged.
const SURFACE_POCKETS := [
	Vector3(421.58,1.025384,-176.7337), # Col_Rock_02_4 / 36989
	Vector3(506.0856,-2.123518,-193.8535), # Col_RopeFence_03_2 / 37853
	Vector3(283.1055,0.093955,-67.01224), # Col_Wall_FowBlock_2 / 38313
	Vector3(499.469,-0.214318,-201.4777), # Col_Wall_FowBlock_1 / 40681
	Vector3(205.2919,20.10182,-260.9907), # Col_Wall / 41017
	Vector3(272.8544,0.033599,-269.8618), # Col_Fence01_6 / 41180
	Vector3(200.2859,0.033599,-151.5483), # Col_Wall_FowBlock_1 / 42687
	Vector3(256.6284,0.029617,-206.3727), # Col_CableReel_01 / 43004
	Vector3(356.3938,-1.105349,-145.6842), # Tree root / slope pocket
	Vector3(535.2658,7.275398,-300.8445), # Tree root / slope pocket
	Vector3(338.5378,11.6751,-209.9206), # Tree root / slope pocket
	Vector3(371.3846,2.952548,-160.5901), # Tree root / slope pocket
	Vector3(272.346,-1.718925,-190.6836), # Tree root / slope pocket
]

static func build(parent: Node3D, zone: String) -> void:
	if zone!="surface":return
	for point in SURFACE_POCKETS:
		var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
		body.name="WalkabilityCap"
		body.position=point+Vector3(0,.65,0)
		var shape:=CapsuleShape3D.new();shape.radius=.45;shape.height=1.9
		var collision:=CollisionShape3D.new();collision.shape=shape
		body.add_child(collision);parent.add_child(body)

# Source lintels are slightly lower than the current 1.5 m character capsule.
# Preserve the original shot/vision collider and raise only its walking underside.
const DOOR_HEADROOM := {41152:1.94,41288:1.925,39014:1.925,39175:1.645,39336:1.645,40205:1.925,42698:1.925}
static func fit_door_headroom(body: StaticBody3D, source_id: int) -> void:
	if not DOOR_HEADROOM.has(source_id):return
	var source: CollisionShape3D=body.get_child(0)
	if not source.shape is BoxShape3D:return
	var axes: Array[Vector3]=[body.basis.x,body.basis.y,body.basis.z]
	var vertical:=0
	for i in range(1,3):
		if absf(axes[i].normalized().y)>absf(axes[vertical].normalized().y):vertical=i
	var size: Vector3=source.shape.size
	var center:=body.transform*source.position
	var bottom:=center.y-size[vertical]*axes[vertical].length()*.5
	var lift:=maxf(0,float(DOOR_HEADROOM[source_id])-bottom)
	if lift<=0 or lift>=size[vertical]*axes[vertical].length():return
	var walking:=StaticBody3D.new();walking.name="DoorHeadroom";walking.transform=body.transform
	walking.collision_layer=1;walking.collision_mask=0
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new()
	size[vertical]-=lift/axes[vertical].length();box.size=size;collision.shape=box
	collision.position=source.position+body.basis.inverse()*Vector3(0,lift*.5,0)
	walking.add_child(collision);body.get_parent().add_child(walking)
	body.collision_layer=body.collision_layer & ~1
