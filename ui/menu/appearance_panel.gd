extends Control
const Rules=preload("res://features/player/appearance_rules.gd")
const Texts=preload("res://features/localization/game_text.gd")
const LABELS=["⟦appearance.hair⟧","⟦appearance.skin⟧","⟦appearance.shirt⟧","⟦appearance.pants⟧"]
const Actor=preload("res://features/player/base_actor.gd")
var ctx
var draft:Dictionary={}
var actor:Node3D
var preview_data:Dictionary={}

func build(hud) -> void:
	ctx=hud;name="AppearancePanel"
	draft=Rules.normalized(ctx._player().get("appearance",{}))
	ctx._dialog.add_child(self)
	var viewport_container:=SubViewportContainer.new()
	viewport_container.position=Vector2(26,100);viewport_container.size=Vector2(420,510)
	add_child(viewport_container)
	var viewport:=SubViewport.new();viewport.size=Vector2i(420,510)
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("26353e")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.45
	viewport.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-35,0);light.light_energy=1.4;viewport.add_child(light)
	var camera:=Camera3D.new();viewport.add_child(camera)
	camera.position=Vector3(1.9,1.45,-3.8);camera.look_at(Vector3(0,.85,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.05
	actor=Actor.new();actor.human_enabled=true;viewport.add_child(actor);actor.setup(Color("71804f"),"")
	actor.nameplate.visible=false
	preview_data=ctx._player().duplicate(true)
	preview_data.pos=Vector2.ZERO;preview_data.height=0.0;preview_data.velocity=Vector2.ZERO;preview_data.aim=Vector2.UP
	preview_data.roll={};preview_data.reloading=false
	ctx._label(self,"⟦appearance.gender⟧",Rect2(485,110,280,32),22,ctx.INK)
	var gender:=OptionButton.new();gender.name="Gender";gender.position=Vector2(485,150);gender.size=Vector2(340,44)
	Texts.add_item(gender,"⟦appearance.male⟧");Texts.add_item(gender,"⟦appearance.female⟧")
	gender.select(0 if draft.gender=="male" else 1);add_child(gender)
	gender.item_selected.connect(func(index:int):draft.gender="male" if index==0 else "female")
	for i in range(Rules.PARTS.size()):
		var part:String=Rules.PARTS[i]
		ctx._label(self,LABELS[i],Rect2(485,224+i*77,180,32),21,ctx.INK)
		var picker:=ColorPickerButton.new();picker.name=part;picker.position=Vector2(680,220+i*77);picker.size=Vector2(145,46)
		picker.edit_alpha=false;picker.color=Color(draft[part]);add_child(picker)
		picker.color_changed.connect(func(color:Color):draft[part]="#"+color.to_html(false))
	ctx._button(self,"⟦appearance.cancel⟧",Rect2(485,610,160,48),ctx._close_dialog,ctx.TEAL,22)
	var apply_button=ctx._button(self,"⟦appearance.apply⟧",Rect2(665,610,160,48),func():ctx.action_requested.emit("appearance",draft.duplicate(true));ctx._close_dialog(),ctx.GREEN,22)
	apply_button.name="ApplyAppearance"

func _process(delta:float) -> void:
	if is_instance_valid(actor):
		preview_data.appearance=draft
		actor.update_actor(preview_data,delta,false)
		actor.local_ring.visible=false
