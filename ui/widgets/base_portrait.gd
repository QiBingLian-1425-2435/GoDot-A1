extends Control
## Isolated preview of the confirmed player; never mutates gameplay state.
const Actor=preload("res://features/player/base_actor.gd")
var actor:Node3D
var viewport:SubViewport
var player:Dictionary={}

func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 var container:=SubViewportContainer.new()
 container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 container.stretch=true;container.mouse_filter=Control.MOUSE_FILTER_IGNORE
 add_child(container)
 viewport=SubViewport.new();viewport.size=Vector2i(220,320)
 viewport.own_world_3d=true;viewport.transparent_bg=true;viewport.msaa_3d=Viewport.MSAA_4X
 container.add_child(viewport)
 var environment:=WorldEnvironment.new();environment.environment=Environment.new()
 environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.45
 viewport.add_child(environment)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-35,0);light.light_energy=1.4;viewport.add_child(light)
 var camera:=Camera3D.new();viewport.add_child(camera)
 camera.position=Vector3(1.9,1.45,-3.8);camera.look_at(Vector3(0,.85,0))
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.15
 actor=Actor.new();actor.human_enabled=true;viewport.add_child(actor);actor.setup(Color("71804f"),"")
 actor.nameplate.visible=false

func set_player(value:Dictionary)->void:
 player=value.duplicate(true)
 player.pos=Vector2.ZERO;player.height=0.0;player.velocity=Vector2.ZERO;player.aim=Vector2.UP
 player.roll={};player.reloading=false;player.crouch=false;player.sprint=false
 player.anim_action="";player.anim_time=0.0;player.anim_duration=0.0

func _process(delta:float)->void:
 var shown:bool=is_visible_in_tree() and not player.is_empty()
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
 if shown:
  actor.update_actor(player,delta,false)
  actor.local_ring.visible=false
