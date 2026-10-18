extends CanvasLayer

signal action_requested(action: String, payload: Dictionary)

const INK := Color("e9e0cd")
const MUTED := Color("8ea5a3")
const GOLD := Color("dabb7a")
const TEAL := Color("8bc9b1")
const DANGER := Color("df947c")
var root: Control
var time_label: Label
var net_label: Label
var phase_label: Label
var pocket_label: Label
var weight_label: Label
var weight_bar
var team_box: VBoxContainer
var team_scroll: ScrollContainer
var item_box: VBoxContainer
var item_signature := ""
var team_signature := ""
var local_id := 1
var state: Dictionary = {}
var tab := "bag"
var lobby: Control
var raid: Control
var result: Control
var help_panel: Control
var modal_shade: ColorRect
var result_rows: VBoxContainer
var result_total: Label
var round_label: Label
var address: LineEdit
var network_info: Label
var map
var hint_title: Label
var hint_detail: Label
var hint_key: Label
var status_label: Label
var status_bar
var toast_label: Label
var toast_timer := 0.0
var possession_panel: Control
var possession_text: Label
var bag_tab: Button
var team_tab: Button
var alive_label: Label
var result_signature := ""
var identity_label: Label
var lobby_start: Button
var result_start: Button
var result_lobby: Button
var detach_button: Button
var transport_choice: OptionButton
var host_button: Button
var join_button: Button
var invite_button: Button
var copy_room_button: Button
var shown_room_code := ""

func _ready() -> void:
	root=Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.theme=make_theme()
	build_top()
	build_sidebar()
	build_bottom()
	build_modals()

func make_theme() -> Theme:
	var theme:=Theme.new()
	var font:=SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC","Arial"])
	theme.default_font=font
	theme.default_font_size=17
	theme.set_color("font_color","Label",INK)
	for type in ["normal","hover","pressed","disabled"]:
		var style:=panel_style(Color("28433f") if type=="hover" else Color("203633"),Color("6c7860") if type=="hover" else Color("465d52"),7)
		style.content_margin_left=16
		style.content_margin_right=16
		style.content_margin_top=10
		style.content_margin_bottom=10
		theme.set_stylebox(type,"Button",style)
	theme.set_color("font_color","Button",INK)
	theme.set_color("font_hover_color","Button",Color("fff2cd"))
	theme.set_color("font_disabled_color","Button",Color("50635f"))
	theme.set_stylebox("normal","LineEdit",panel_style(Color("12272a"),Color("47605c"),6))
	theme.set_color("font_color","LineEdit",INK)
	theme.set_constant("outline_size","Label",0)
	return theme

func panel_style(bg:Color,border:Color,radius:=12)->StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=bg
	style.border_color=border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color=Color(0.015,0.025,0.03,0.18)
	style.shadow_size=8
	return style

func panel(parent:Node,rect:Rect2,bg:=Color("172d30"),border:=Color("405652"),radius:=12)->Panel:
	var p:=Panel.new()
	p.position=rect.position
	p.size=rect.size
	p.add_theme_stylebox_override("panel",panel_style(bg,border,radius))
	parent.add_child(p)
	return p

func label(parent:Node,text:String,pos:Vector2,font_size:=18,color:=INK,width:=0.0)->Label:
	var l:=Label.new()
	l.text=text
	l.position=pos
	l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_color_override("font_color",color)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	if width>0:
		l.custom_minimum_size.x=width
	parent.add_child(l)
	return l

func button(parent:Node,text:String,pos:Vector2,sz:Vector2,act:String,payload:Dictionary={})->Button:
	var b:=Button.new()
	b.text=text
	b.position=pos
	b.size=sz
	b.focus_mode=Control.FOCUS_NONE
	b.pressed.connect(func():action_requested.emit(act,payload))
	parent.add_child(b)
	return b

func line(parent:Node,pos:Vector2,width:float)->void:
	var c:=ColorRect.new()
	c.color=Color("3b5150")
	c.position=pos
	c.size=Vector2(width,1)
	c.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)

func build_top()->void:
	var top:=panel(root,Rect2(30,24,1540,84),Color(0.065,0.13,0.15,0.94),Color("52645b"))
	var badge:=panel(top,Rect2(18,15,52,52),Color("33433a"),GOLD,8)
	label(badge,"灯",Vector2(11,5),27,GOLD)
	label(top,"雾灯旅店",Vector2(86,10),28,INK)
	label(top,"THE LANTERN BELOW",Vector2(88,49),11,GOLD)
	line(top,Vector2(309,18),1)
	phase_label=label(top,"序章  /  最后一盏灯",Vector2(335,17),19,INK)
	round_label=label(top,"合作搜集 · 安全归来",Vector2(336,48),12,MUTED)
	net_label=label(top,"●  单人体验",Vector2(852,16),14,TEAL)
	alive_label=label(top,"准备进入旅店",Vector2(852,44),13,MUTED)
	label(top,"灯油剩余",Vector2(1062,16),12,MUTED)
	time_label=label(top,"06:00",Vector2(1060,32),29,GOLD)
	button(top,"玩法手册  ?",Vector2(1220,21),Vector2(142,42),"help")
	button(top,"房间",Vector2(1378,21),Vector2(136,42),"room")

func build_sidebar()->void:
	var side:=panel(root,Rect2(1240,130,330,754),Color(0.065,0.13,0.15,0.96),Color("536257"))
	label(side,"旅 人 手 记",Vector2(22,18),13,GOLD)
	label(side,"把灯火与收获带回来",Vector2(22,44),21,INK)
	line(side,Vector2(22,85),286)
	lobby=Control.new()
	lobby.position=Vector2(22,104)
	side.add_child(lobby)
	label(lobby,"01   搜索失落的遗物",Vector2.ZERO,18,INK)
	label(lobby,"价值与重量，决定你的行囊。",Vector2(0,31),13,MUTED)
	label(lobby,"02   留心巡夜者",Vector2(0,83),18,INK)
	label(lobby,"避开追逐，也别落下倒地的同伴。",Vector2(0,114),13,MUTED)
	label(lobby,"03   回到入口的灯下",Vector2(0,166),18,INK)
	label(lobby,"站稳 4 秒，锁定你的全部收获。",Vector2(0,197),13,MUTED)
	button(lobby,"点亮提灯 · 单人出发",Vector2(0,259),Vector2(286,52),"solo")
	label(lobby,"含 AI 同伴  /  一局约 6 分钟",Vector2(28,321),12,MUTED)
	transport_choice = OptionButton.new()
	transport_choice.position = Vector2(0, 340)
	transport_choice.size = Vector2(286, 34)
	transport_choice.add_item("Steam 联机 · 测试 App ID 480")
	transport_choice.add_item("ENet 局域网 · 开发验证")
	transport_choice.item_selected.connect(func(index): action_requested.emit("transport", {"transport": "steam" if index == 0 else "enet"}))
	lobby.add_child(transport_choice)
	host_button = button(lobby,"创建 Steam 好友房间",Vector2(0,384),Vector2(286,42),"host")
	address=LineEdit.new()
	address.position=Vector2(0,437)
	address.size=Vector2(187,42)
	address.placeholder_text="Steam 房间号"
	address.text=""
	lobby.add_child(address)
	join_button = button(lobby,"加入",Vector2(197,437),Vector2(89,42),"join")
	copy_room_button = button(lobby,"复制",Vector2(197,437),Vector2(89,42),"copy_room")
	copy_room_button.tooltip_text = "一键复制 Steam 房间号"
	invite_button = button(lobby,"邀请 Steam 好友",Vector2(0,489),Vector2(286,34),"invite")
	lobby_start=button(lobby,"全员出发",Vector2(0,535),Vector2(182,38),"start")
	button(lobby,"离开",Vector2(192,535),Vector2(94,38),"leave")
	network_info=label(lobby,"Steam 测试模式 · App ID 480",Vector2(0,588),12,MUTED)
	network_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	network_info.size=Vector2(286,60)
	raid=Control.new()
	raid.position=Vector2(22,100)
	side.add_child(raid)
	bag_tab=button(raid,"行囊",Vector2.ZERO,Vector2(137,40),"tab",{"tab":"bag"})
	team_tab=button(raid,"同行者",Vector2(149,0),Vector2(137,40),"tab",{"tab":"team"})
	weight_label=label(raid,"负重  0.0 / 12.0 kg",Vector2(0,56),15,INK)
	pocket_label=label(raid,"◇ 0",Vector2(209,56),16,GOLD)
	weight_bar=load("res://ui/widgets/meter.gd").new()
	weight_bar.position=Vector2(0,87)
	weight_bar.size=Vector2(286,5)
	weight_bar.max_value=12.0
	raid.add_child(weight_bar)
	var scroll:=ScrollContainer.new()
	scroll.position=Vector2(0,111)
	scroll.size=Vector2(292,298)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	raid.add_child(scroll)
	item_box=VBoxContainer.new()
	item_box.custom_minimum_size.x=280
	item_box.add_theme_constant_override("separation",8)
	scroll.add_child(item_box)
	team_scroll=ScrollContainer.new()
	team_scroll.position=Vector2(0,111)
	team_scroll.size=Vector2(292,250)
	team_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	raid.add_child(team_scroll)
	team_box=VBoxContainer.new()
	team_box.custom_minimum_size.x=280
	team_box.add_theme_constant_override("separation",8)
	team_scroll.add_child(team_box)
	detach_button=button(raid,"解除共享视角",Vector2(0,371),Vector2(286,38),"detach")
	detach_button.visible=false
	line(raid,Vector2(0,424),286)
	label(raid,"旅店平面图",Vector2(0,438),13,MUTED)
	label(raid,"◇ 撤离灯",Vector2(216,438),12,TEAL)
	map=load("res://ui/widgets/minimap.gd").new()
	map.position=Vector2(0,467)
	map.size=Vector2(286,154)
	raid.add_child(map)
	label(raid,"单层 · 镜头固定 · 家具可以绕行",Vector2(16,632),11,MUTED)

func build_bottom()->void:
	var self_card:=panel(root,Rect2(30,790,277,94),Color(0.06,0.12,0.14,0.93),Color("52645b"))
	var emblem:=panel(self_card,Rect2(14,15,60,60),Color("374941"),Color("a28f63"),30)
	label(emblem,"旅",Vector2(16,11),24,GOLD)
	identity_label=label(self_card,"阿烬  /  寻灯人",Vector2(88,14),16,INK)
	status_label=label(self_card,"状态良好",Vector2(88,40),12,TEAL)
	status_bar=load("res://ui/widgets/meter.gd").new()
	status_bar.position=Vector2(88,69)
	status_bar.size=Vector2(167,5)
	status_bar.max_value=100
	status_bar.value=100
	self_card.add_child(status_bar)
	var prompt:=panel(root,Rect2(450,804,610,80),Color(0.06,0.12,0.14,0.92),Color("536257"))
	var keybox:=panel(prompt,Rect2(16,17,45,45),Color("33443a"),GOLD,7)
	hint_key=label(keybox,"E",Vector2(14,7),22,GOLD)
	hint_title=label(prompt,"灯火还在，旅途便能继续。",Vector2(78,12),17,INK)
	hint_detail=label(prompt,"准备好后，从右侧点亮你的提灯。",Vector2(78,43),12,MUTED)
	var foot:=panel(root,Rect2(30,907,1540,62),Color(0.05,0.10,0.12,0.96),Color("384e49"),9)
	label(foot,"W A S D   移动",Vector2(23,19),14,INK)
	label(foot,"E   拾取 / 长按救援",Vector2(207,19),14,INK)
	label(foot,"Tab   行囊与队伍",Vector2(454,19),14,INK)
	label(foot,"F1   手册",Vector2(689,19),14,INK)
	label(foot,"M   静音",Vector2(814,19),14,INK)
	label(foot,"一起深入，也一起回来。",Vector2(971,19),14,GOLD)
	label(foot,"DEMO  /  0.1",Vector2(1393,22),11,MUTED)
	toast_label=label(root,"",Vector2(340,139),17,GOLD)
	toast_label.add_theme_color_override("font_shadow_color",Color("0c1a20"))
	toast_label.add_theme_constant_override("shadow_offset_x",2)
	toast_label.add_theme_constant_override("shadow_offset_y",2)
	possession_panel=panel(root,Rect2(400,690,650,89),Color("253c38"),GOLD)
	possession_text=label(possession_panel,"队友请求共享你的视角",Vector2(18,13),16,INK)
	button(possession_panel,"接受",Vector2(398,24),Vector2(106,42),"possession_accept")
	button(possession_panel,"拒绝 / 解除",Vector2(516,24),Vector2(116,42),"detach")
	possession_panel.visible=false

func build_modals()->void:
	modal_shade=ColorRect.new()
	modal_shade.color=Color(0.015,0.035,0.045,0.79)
	modal_shade.size=Vector2(1600,1000)
	root.add_child(modal_shade)
	modal_shade.visible=false
	help_panel=panel(root,Rect2(380,192,840,615),Color("172d30"),GOLD)
	label(help_panel,"旅人手册",Vector2(40,30),31,GOLD)
	label(help_panel,"一盏灯的时间，带所有人回家。",Vector2(40,83),18,INK)
	line(help_panel,Vector2(40,127),760)
	var content:=["WASD / 方向键　移动。可绕家具避开巡夜者。","E　靠近遗物拾取；行囊中的 ↓ 将物品丢给队友。","长按 E　靠近倒地同伴，持续 3 秒救起。","负重　最多 12 kg；超重会拒绝拾取，物品留在原地。","撤离　回到右前方绿色灯圈，站稳 4 秒；走出即中断。","倒地与死亡　22 秒内无人救援则留下尸体与物品。","附身实验　死亡后向活人请求共享视角，由对方接受。","联机　同一局域网，创建房间并分享 IP；房主统一开局。"]
	for i in range(content.size()):
		label(help_panel,content[i],Vector2(40,155+i*39),16,INK if i%2==0 else MUTED)
	label(help_panel,"查看手册时对局继续。语音请使用现有群语音。",Vector2(40,507),13,MUTED)
	button(help_panel,"我知道了 · 继续旅途",Vector2(438,540),Vector2(360,46),"close_help")
	help_panel.visible=false
	result=panel(root,Rect2(400,187,800,627),Color("172d30"),GOLD)
	label(result,"灯 火 已 归",Vector2(40,27),16,GOLD)
	label(result,"这一程，收获多少？",Vector2(40,65),32,INK)
	result_total=label(result,"0",Vector2(40,129),48,GOLD)
	label(result,"本局全队带回价值",Vector2(42,194),13,MUTED)
	line(result,Vector2(40,233),720)
	result_rows=VBoxContainer.new()
	result_rows.position=Vector2(40,254)
	result_rows.size=Vector2(720,240)
	result_rows.add_theme_constant_override("separation",10)
	result.add_child(result_rows)
	result_start=button(result,"再探一局",Vector2(40,536),Vector2(347,52),"start")
	result_lobby=button(result,"返回准备",Vector2(405,536),Vector2(354,52),"lobby")
	result.visible=false

func update_view(snapshot:Dictionary,player_id:int,mode:String,connection:String,network:Dictionary={})->void:
	state=snapshot
	local_id=player_id
	var phase:String=state.get("phase","lobby")
	var players:Dictionary=state.get("players",{})
	var me:Dictionary=players.get(local_id,{})
	var secs:=maxi(0,int(ceil(float(state.get("time_left",360)))))
	time_label.text="%02d:%02d"%[secs/60,secs%60]
	time_label.add_theme_color_override("font_color",DANGER if secs<60 else GOLD)
	var is_steam: bool = network.get("transport", "steam") == "steam"
	var busy: bool = network.get("busy", false)
	transport_choice.select(0 if is_steam else 1)
	transport_choice.disabled = mode != "offline" or busy
	host_button.text = "创建 Steam 好友房间" if is_steam else "创建局域网房间"
	host_button.disabled = mode != "offline" or busy
	join_button.disabled = mode != "offline" or busy
	address.editable = mode == "offline" and not busy
	address.placeholder_text = "Steam 房间号" if is_steam else "房主局域网 IP"
	invite_button.visible = is_steam
	var room_code: String = str(network.get("lobby_id", "")) if is_steam else ""
	var has_room_code := not room_code.is_empty()
	copy_room_button.visible = has_room_code
	join_button.visible = not has_room_code
	address.add_theme_font_size_override("font_size", 14 if has_room_code else 17)
	if has_room_code:
		address.text = room_code
		address.tooltip_text = "Steam 房间号 · 点击右侧复制后发给好友"
	elif not shown_room_code.is_empty():
		address.text = ""
		address.tooltip_text = ""
	shown_room_code = room_code
	invite_button.disabled = mode != "host" or network.get("lobby_id", "").is_empty()
	copy_room_button.disabled = network.get("lobby_id", "").is_empty()
	var prefix := "Steam" if network.get("active", "offline") == "steam" else "局域网"
	net_label.text="●  " + {"offline":"单人体验 · AI 同伴","host":prefix+"房主","client":prefix+"同行"}.get(mode,"准备中")
	var living:=0
	for p in players.values():
		if p.get("status", "alive") in ["alive","downed"]:
			living+=1
	alive_label.text="%d 位旅人  ·  %d 人行动中"%[players.size(),living] if phase!="lobby" else "%d / 5 位旅人 · 等待出发"%players.size()
	phase_label.text="序章  /  最后一盏灯" if phase=="lobby" else "雾灯旅店  /  遗物回收"
	round_label.text="第 %02d 次行动  ·  搜索 / 避险 / 撤离"%int(state.get("round",1)) if phase!="lobby" else "合作搜集 · 安全归来"
	lobby.visible=phase=="lobby"
	raid.visible=phase!="lobby"
	var names:PackedStringArray=[]
	for p in players.values():
		names.append(p.get("name","旅人"))
	var detail: String = str(network.get("steam_status", connection)) if is_steam and mode == "offline" else connection
	network_info.text=detail+"\n旅人："+" / ".join(names)
	lobby_start.disabled=mode=="client" or players.size()<2
	lobby_start.text="等待房主出发" if mode=="client" else "全员出发"
	result_start.disabled=mode=="client"
	result_lobby.disabled=mode=="client"
	result_start.text="等待房主开启下一局" if mode=="client" else "再探一局"
	result.visible=phase=="results"
	modal_shade.visible=help_panel.visible or result.visible
	if me.is_empty():
		return
	var status:String=me.get("status","alive")
	identity_label.text=me.get("name","阿烬")+"  /  寻灯人"
	status_label.text={"alive":"状态良好 · 避开巡夜者","downed":"等待救援 · %d 秒"%int(me.get("down_left",0)),"dead":"已化作幽灵 · 等待同伴","extracted":"已安全撤离 · 等待队伍"}.get(status,status)
	if status=="alive" and float(me.get("hp",100))<60:
		status_label.text="身负轻伤 · 留意危险"
	status_label.add_theme_color_override("font_color",DANGER if status=="downed" else TEAL)
	status_bar.value=float(me.get("hp",100))
	var weight:=0.0
	var value:=0
	for item in me.get("bag",[]):
		weight+=float(item.get("weight",0))
		value+=int(item.get("value",0))
	weight_label.text="负重  %.1f / %.0f kg"%[weight,float(me.get("capacity",12))]
	weight_bar.value=weight
	pocket_label.text="◇ %d"%value
	map.update_map(state,local_id,status in ["dead","extracted"])
	item_box.get_parent().visible=tab=="bag"
	team_box.visible=tab=="team"
	team_scroll.visible=tab=="team"
	var attached:bool=int(me.get("possessing",0))!=0
	for p in players.values():
		if int(p.get("possessing",0))==local_id:
			attached=true
	detach_button.visible=tab=="team" and attached
	bag_tab.modulate=Color.WHITE if tab=="bag" else Color("889e98")
	team_tab.modulate=Color.WHITE if tab=="team" else Color("889e98")
	var signature:=str(me.get("bag",[]))+status
	if signature!=item_signature:
		item_signature=signature
		refresh_items(me)
	var tsig:=str(players.keys())+status
	for p in players.values():
		tsig+=str(p.get("status",""))+str(int(p.get("hp",0)))+str(p.get("possessing",0))
	if tsig!=team_signature:
		team_signature=tsig
		refresh_team(players,me)
	possession_panel.visible=int(me.get("request_from",0))!=0 and status=="alive"
	if possession_panel.visible:
		var req:Dictionary=players.get(int(me.request_from),{})
		possession_text.text=req.get("name","同伴")+"请求附身观战\n只共享视角，不接管操作。"
	if phase=="results" and result_signature!=str(state.get("round",0))+str(players):
		result_signature=str(state.get("round",0))+str(players)
		refresh_results(players)
	update_hint(me,phase)

func clear_box(box:Node)->void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func refresh_items(me:Dictionary)->void:
	clear_box(item_box)
	var bag:Array=me.get("bag",[])
	if bag.is_empty():
		var empty:=Control.new()
		empty.custom_minimum_size=Vector2(280,245)
		item_box.add_child(empty)
		label(empty,"◇",Vector2(115,38),42,Color("62776b"))
		label(empty,"行囊里还空着",Vector2(68,109),18,INK)
		label(empty,"靠近发光遗物，按 E 收入行囊。",Vector2(10,148),13,MUTED)
		label(empty,"只有成功撤离，才算真正带回。",Vector2(11,173),13,MUTED)
		return
	for item in bag:
		var row:=Panel.new()
		row.custom_minimum_size=Vector2(280,64)
		row.add_theme_stylebox_override("panel",panel_style(Color("233b3b"),Color("3d5550"),7))
		item_box.add_child(row)
		var col:=Color(str(item.get("color","dabb7a")))
		label(row,"◇",Vector2(11,11),25,col)
		label(row,item.get("name","遗物"),Vector2(46,7),16,INK)
		label(row,"%.1f kg   ·   ◇ %d"%[float(item.get("weight",0)),int(item.get("value",0))],Vector2(46,36),12,MUTED)
		var b:=button(row,"↓",Vector2(235,12),Vector2(35,38),"drop",{"item_id":item.get("id",0)})
		b.tooltip_text="丢到脚边，让同伴拾取"
		b.disabled=me.get("status","alive")!="alive"

func refresh_team(players:Dictionary,me:Dictionary)->void:
	clear_box(team_box)
	for id in players:
		var p:Dictionary=players[id]
		var row:=Panel.new()
		row.custom_minimum_size=Vector2(286,67)
		row.add_theme_stylebox_override("panel",panel_style(Color("233b3b"),Color("3d5550"),7))
		team_box.add_child(row)
		label(row,p.get("name","旅人")+(" · AI" if p.get("bot",false) else ""),Vector2(12,7),16,INK)
		var status:String=p.get("status","alive")
		label(row,{"alive":"同行中","downed":"倒地 · 急需救援","dead":"幽灵 · 无法拾取","extracted":"已撤离 · 收获锁定"}.get(status,status),Vector2(12,36),12,DANGER if status=="downed" else MUTED)
		if int(me.get("possessing",0))==int(id):
			button(row,"解除",Vector2(190,13),Vector2(84,38),"detach")
		elif me.get("status","")=="dead" and status=="alive" and int(id)!=local_id:
			button(row,"请求附身",Vector2(174,13),Vector2(100,38),"possession_request",{"target":int(id)})
		else:
			label(row,"%d"%int(p.get("hp",0))+" HP",Vector2(218,21),12,TEAL)

func refresh_results(players:Dictionary)->void:
	clear_box(result_rows)
	var total:=0
	for p in players.values():
		total+=int(p.get("result_value",0))
		var row:=Control.new()
		row.custom_minimum_size=Vector2(720,40)
		result_rows.add_child(row)
		label(row,p.get("name","旅人"),Vector2.ZERO,18,INK)
		label(row,"安全归来" if p.get("status","")=="extracted" else "未能归来 · 遗留价值 %d"%int(p.get("lost_value",0)),Vector2(202,2),14,TEAL if p.get("status","")=="extracted" else DANGER)
		label(row,"◇  %d"%int(p.get("result_value",0)),Vector2(614,0),20,GOLD)
	result_total.text="◇ %d"%total

func update_hint(me:Dictionary,phase:String)->void:
	hint_key.text="E"
	if phase=="lobby":
		hint_title.text="灯火还在，旅途便能继续。"
		hint_detail.text="准备好后，从右侧点亮你的提灯。"
		return
	var status:String=me.get("status","alive")
	if status=="downed":
		hint_key.text="!"
		hint_title.text="你倒下了，等待同伴救援。"
		hint_detail.text="倒计时 %d 秒 · 同伴靠近并长按 E 可以将你救起。"%int(me.get("down_left",0))
		return
	if status in ["dead","extracted"]:
		hint_key.text="○"
		hint_title.text="收获已经锁定，等待同伴归来。" if status=="extracted" else "幽灵无法拾取 · 可请求附身观战"
		hint_detail.text="打开「同行者」查看队伍；最后一名旅人结束后统一结算。"
		return
	var ep:float=me.get("extract_progress",0.0)
	if ep>0:
		hint_key.text="◷"
		hint_title.text="提灯正在回应你…… %.1f / 4.0 秒"%ep
		hint_detail.text="留在绿色灯圈内即可撤离；离开会中断。"
		return
	var pos:Vector2=me.get("pos",Vector2.ZERO)
	for p in state.get("players",{}).values():
		if p.get("status","")=="downed" and p.get("pos",Vector2.ZERO).distance_to(pos)<1.9:
			hint_title.text="长按 E · 救起 "+p.get("name","同伴")
			hint_detail.text="持续 3 秒完成救援 · %.1f / 3.0"%float(p.get("revive_progress",0))
			return
	var nearest:Dictionary={}
	var dist:=1.8
	for item in state.get("loot",[]):
		var d:float=item.get("pos",Vector2.ZERO).distance_to(pos)
		if d<dist:
			dist=d
			nearest=item
	if not nearest.is_empty():
		hint_title.text="拾取 · "+nearest.get("name","遗物")
		hint_detail.text="%.1f kg  /  价值 %d  ·  收入行囊后需成功撤离。"%[float(nearest.get("weight",0)),int(nearest.get("value",0))]
		return
	for corpse in state.get("corpses",[]):
		if corpse.get("pos",Vector2.ZERO).distance_to(pos)<1.8 and not corpse.get("items",[]).is_empty():
			hint_title.text="搜取同伴遗留的行囊"
			hint_detail.text="按 E 接手物品；仍然受你的负重上限限制。"
			return
	hint_title.text="搜索旅店深处的遗物"
	hint_detail.text="高价值遗物藏在深处 · 危险时绕开家具，返回绿色灯圈。"

func toast(text:String)->void:
	toast_label.text=text
	toast_timer=4.5

func toggle_help(open:bool)->void:
	help_panel.visible=open
	modal_shade.visible=open or result.visible

func set_tab(value:String)->void:
	tab=value

func _process(delta:float)->void:
	toast_timer=maxf(0,toast_timer-delta)
	toast_label.modulate.a=minf(1,toast_timer)
