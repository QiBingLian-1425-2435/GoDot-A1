extends RefCounted
## Shared visual language for every 2D screen: a dark "field kit" slate with warm
## off-white text, amber highlights and soft drop shadows. Pure presentation;
## base_hud's helper functions and the root Theme both build on these styles.

const INK := Color("ece7d8")
const MUTED := Color("97a6a2")
const FAINT := Color("6d7c79")
const GOLD := Color("f0c46a")
const AMBER := Color("e3a74a")
const TEAL := Color("4a9a9c")
const GREEN := Color("67a86b")
const DANGER := Color("d4675d")
const SLATE := Color("101a1d")
const SLATE_2 := Color("172427")
const SLATE_3 := Color("203236")
const LINE := Color("33474a")
const LINE_LIGHT := Color("4f6866")

static func box(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 10, width: int = 1, shadow: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.corner_detail = 6
	style.anti_aliasing = true
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	if shadow > 0:
		style.shadow_color = Color(0, 0, 0, .42)
		style.shadow_size = shadow
		style.shadow_offset = Vector2(0, shadow * .3)
	return style

## Large floating surfaces (dialogs, inventory columns): slate with a lit top edge.
static func panel(bg: Color = Color(SLATE, .96), border: Color = LINE, radius: int = 14, shadow: int = 22) -> StyleBoxFlat:
	var style := box(bg, border, radius, 1, shadow)
	style.border_width_top = 2
	style.border_color = border
	return style

## HUD cards float over the 3D world: lighter shadow, more translucent.
static func hud_card(radius: int = 12) -> StyleBoxFlat:
	var style := box(Color(.045, .075, .085, .78), Color(1, 1, 1, .09), radius, 1, 10)
	style.shadow_color = Color(0, 0, 0, .28)
	return style

## Buttons: green means "confirm / go" and is filled; every other tint becomes a
## dark tinted button with a coloured rim, so screens read primary vs secondary.
static func button_styles(color: Color, radius: int = 9) -> Dictionary:
	var primary := absf(color.h - GREEN.h) < .04 and color.s > .25 and color.v > .5
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var pressed: StyleBoxFlat
	if primary:
		var fill := Color("4f8f55")
		normal = box(fill, fill.lightened(.18), radius, 1, 4)
		normal.border_width_bottom = 3
		normal.border_color = fill.lightened(.14)
		hover = box(fill.lightened(.1), Color("d9e9c6"), radius, 1, 6)
		hover.border_width_bottom = 3
		pressed = box(fill.darkened(.15), fill.lightened(.2), radius, 1, 1)
	else:
		var base := Color(color.darkened(.62), .94)
		normal = box(base, Color(color.lightened(.05), .75), radius, 1, 3)
		normal.border_width_bottom = 2
		hover = box(Color(color.darkened(.42), .97), color.lightened(.35), radius, 1, 5)
		hover.border_width_bottom = 2
		pressed = box(Color(color.darkened(.7), 1), color.lightened(.2), radius, 1, 0)
	var focus := box(Color.TRANSPARENT, Color(GOLD, .85), radius, 2)
	var disabled := box(Color(.08, .11, .12, .7), Color(1, 1, 1, .06), radius, 1)
	for style in [normal, hover, pressed, disabled]:
		style.content_margin_left = 14
		style.content_margin_right = 14
	return {"normal":normal, "hover":hover, "pressed":pressed, "focus":focus, "disabled":disabled, "primary":primary}

static func apply_button(button: Button, color: Color, radius: int = 9) -> void:
	var styles := button_styles(color, radius)
	for key in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(key, styles[key])
	button.add_theme_stylebox_override("hover_pressed", styles.pressed)
	var text := Color("f6f2e2") if styles.primary else Color("e1ebe6")
	button.add_theme_color_override("font_color", text)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("f5efcf"))
	button.add_theme_color_override("font_focus_color", text)
	button.add_theme_color_override("font_disabled_color", Color(MUTED, .55))

## Root theme: covers the stock widgets the screens use directly.
static func build(font: Font, size: int = 20) -> Theme:
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = size
	theme.set_color("font_color", "Label", INK)
	# Buttons created without the helper (toggle rows, lists, steam lobbies).
	var styles := button_styles(TEAL)
	for key in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(key, "Button", styles[key])
	theme.set_stylebox("hover_pressed", "Button", styles.pressed)
	theme.set_color("font_color", "Button", Color("e1ebe6"))
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(MUTED, .55))
	# Drop-downs.
	var option := box(SLATE_2, LINE_LIGHT, 8, 1)
	option.content_margin_left = 12
	theme.set_stylebox("normal", "OptionButton", option)
	theme.set_stylebox("hover", "OptionButton", box(SLATE_3, Color(GOLD, .7), 8, 1))
	theme.set_stylebox("pressed", "OptionButton", box(SLATE, Color(GOLD, .85), 8, 1))
	theme.set_stylebox("focus", "OptionButton", box(Color.TRANSPARENT, Color(GOLD, .7), 8, 1))
	theme.set_stylebox("disabled", "OptionButton", box(Color(SLATE, .6), Color(LINE, .5), 8, 1))
	theme.set_color("font_color", "OptionButton", INK)
	theme.set_color("font_hover_color", "OptionButton", Color.WHITE)
	theme.set_constant("arrow_margin", "OptionButton", 10)
	# Text fields.
	var field := box(Color("0b1315"), LINE_LIGHT, 8, 1)
	field.content_margin_left = 12
	theme.set_stylebox("normal", "LineEdit", field)
	var field_focus := box(Color("0d171a"), GOLD, 8, 1)
	field_focus.content_margin_left = 12
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_stylebox("read_only", "LineEdit", box(Color(SLATE, .6), LINE, 8, 1))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", Color(MUTED, .7))
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_color("selection_color", "LineEdit", Color(TEAL, .45))
	# Toggles.
	theme.set_color("font_color", "CheckButton", INK)
	theme.set_color("font_hover_color", "CheckButton", Color.WHITE)
	theme.set_color("font_pressed_color", "CheckButton", Color("f6ead0"))
	theme.set_color("font_disabled_color", "CheckButton", Color(MUTED, .55))
	for key in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		theme.set_stylebox(key, "CheckButton", StyleBoxEmpty.new())
	theme.set_icon("checked", "CheckButton", switch_icon(true))
	theme.set_icon("unchecked", "CheckButton", switch_icon(false))
	theme.set_icon("checked_disabled", "CheckButton", switch_icon(true, true))
	theme.set_icon("unchecked_disabled", "CheckButton", switch_icon(false, true))
	# Sliders.
	theme.set_stylebox("slider", "HSlider", box(Color("0b1315"), LINE, 4, 1))
	var filled := box(AMBER, Color.TRANSPARENT, 4, 0)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD, Color.TRANSPARENT, 4, 0))
	theme.set_icon("grabber", "HSlider", knob_icon(INK))
	theme.set_icon("grabber_highlight", "HSlider", knob_icon(Color.WHITE))
	# Scroll bars: thin rails with a soft thumb.
	for bar in ["VScrollBar", "HScrollBar"]:
		var rail := box(Color(0, 0, 0, .25), Color.TRANSPARENT, 4, 0)
		rail.content_margin_left = 3; rail.content_margin_right = 3
		rail.content_margin_top = 3; rail.content_margin_bottom = 3
		theme.set_stylebox("scroll", bar, rail)
		theme.set_stylebox("grabber", bar, box(Color(LINE_LIGHT, .9), Color.TRANSPARENT, 4, 0))
		theme.set_stylebox("grabber_highlight", bar, box(Color(TEAL, .95), Color.TRANSPARENT, 4, 0))
		theme.set_stylebox("grabber_pressed", bar, box(GOLD, Color.TRANSPARENT, 4, 0))
	# Lists (workbench recipes, camp upgrades).
	var list := box(Color("0c1416"), LINE, 10, 1)
	list.content_margin_top = 8; list.content_margin_bottom = 8
	theme.set_stylebox("panel", "ItemList", list)
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("hovered", "ItemList", box(Color(TEAL, .18), Color.TRANSPARENT, 6, 0))
	theme.set_stylebox("selected", "ItemList", box(Color(AMBER, .22), Color(AMBER, .7), 6, 1))
	theme.set_stylebox("selected_focus", "ItemList", box(Color(AMBER, .26), Color(GOLD, .9), 6, 1))
	theme.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", INK)
	theme.set_color("font_selected_color", "ItemList", Color("fff3d6"))
	theme.set_color("font_hovered_color", "ItemList", Color.WHITE)
	theme.set_color("guide_color", "ItemList", Color(1, 1, 1, .04))
	theme.set_constant("v_separation", "ItemList", 8)
	theme.set_constant("h_separation", "ItemList", 8)
	# Context menus and tooltips.
	var popup := panel(Color(SLATE, .98), LINE_LIGHT, 10, 14)
	popup.content_margin_top = 8; popup.content_margin_bottom = 8
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", box(Color(AMBER, .22), Color(AMBER, .55), 6, 1))
	theme.set_stylebox("separator", "PopupMenu", box(LINE, Color.TRANSPARENT, 0, 0))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", Color("fff3d6"))
	theme.set_color("font_disabled_color", "PopupMenu", Color(MUTED, .55))
	theme.set_constant("v_separation", "PopupMenu", 10)
	theme.set_stylebox("panel", "PopupPanel", popup)
	var tip := box(Color(.05, .08, .09, .97), Color(GOLD, .45), 8, 1, 10)
	tip.content_margin_left = 12; tip.content_margin_right = 12
	tip.content_margin_top = 8; tip.content_margin_bottom = 8
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", INK)
	theme.set_font_size("font_size", "TooltipLabel", 16)
	# Plain progress bars (loot search).
	theme.set_stylebox("background", "ProgressBar", box(Color("0b1315"), LINE, 6, 1))
	theme.set_stylebox("fill", "ProgressBar", box(AMBER, Color.TRANSPARENT, 6, 0))
	theme.set_color("font_color", "ProgressBar", INK)
	theme.set_stylebox("panel", "Panel", panel())
	theme.set_stylebox("panel", "PanelContainer", panel())
	return theme

static func switch_icon(on: bool, disabled: bool = false) -> ImageTexture:
	var w := 46; var h := 24
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := Color(AMBER if on else Color("2b3b3e"))
	var knob := Color("fbf3dc") if on else Color("98a6a2")
	if disabled:
		track.a = .35; knob.a = .45
	for y in range(h):
		for x in range(w):
			# rounded track
			var cx := clampf(x, h * .5, w - h * .5)
			var d := Vector2(x + .5, y + .5).distance_to(Vector2(cx, h * .5))
			var a := clampf(h * .5 - d, 0, 1)
			var kx := w - h * .5 if on else h * .5
			var dk := Vector2(x + .5, y + .5).distance_to(Vector2(kx, h * .5))
			var ka := clampf(h * .5 - 3 - dk, 0, 1)
			var color := track
			color.a *= a
			color = color.lerp(knob, ka) if ka > 0 else color
			if ka > 0: color.a = maxf(color.a, ka * knob.a)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

static func knob_icon(color: Color) -> ImageTexture:
	var s := 22
	var image := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in range(s):
		for x in range(s):
			var d := Vector2(x + .5, y + .5).distance_to(Vector2(s * .5, s * .5))
			var ring := clampf(s * .5 - d, 0, 1)
			var inner := clampf(s * .5 - 4 - d, 0, 1)
			var c := Color(AMBER).lerp(color, inner)
			c.a = ring
			image.set_pixel(x, y, c)
	return ImageTexture.create_from_image(image)
