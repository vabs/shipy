class_name UITheme
extends RefCounted
## Code-built UI Theme (docs/SPEC.md §7): rounded cream cards, navy translucent bars, chunky coral / teal
## buttons, Fredoka font. Sized for a 1920x1080 base viewport.
##
## API
##   UITheme.build() -> Theme           # cached; set `control.theme = UITheme.build()` on a root Control
##   UITheme.font() / font_bold() -> Font
##
## Theme type variations (set `control.theme_type_variation = &"..."`):
##   Label:          TitleLabel (34) | HeaderLabel (26) | SmallLabel (18, muted) | PillLabel (20, cream)
##                   OnDark (cream) | OnDarkTitle | OnDarkSmall | MoneyLabel (sun yellow) | WarningLabel (coral)
##   PanelContainer: CardPanel (cream card) | NavyBar (navy, rounded bottom) | NavyBarBottom (rounded top)
##                   PillPanel (navy pill) | PillPanelLight (cream pill) | PlatePanel (inset sand plate)
##                   SkyPanel (soft translucent white) | TooltipPanel is the built-in tooltip type
##   Button:         PrimaryButton (coral) | SecondaryButton (teal) | GhostButton (transparent on navy)
##                   IconButton (round cream) | IconButtonDark (round navy, pressed = sun) | TabButton (toggle pill)
##                   DangerButton (dark coral) | SunButton (yellow)
##   ProgressBar:    MintBar | CoralBar | SunBar | TealBar
##   Also styled: Button, OptionButton, CheckBox, CheckButton, HSlider/VSlider, ScrollBars, LineEdit, TextEdit,
##   TabBar/TabContainer, PopupMenu, PopupPanel, ItemList, HSeparator/VSeparator, TooltipPanel/TooltipLabel,
##   RichTextLabel, Panel, PanelContainer, ProgressBar.

const U := preload("res://src/render/art/art_util.gd")

const TEXT_INK := Color("1E2433")
const TEXT_MUTED := Color("6B7792")
const TEXT_ON_DARK := Color("FFF8EC")
const CARD := Color("FFF8EC")
const CARD_EDGE := Color("EBDDC3")
const PLATE := Color("F5E9D3")
const BAR_NAVY := Color(0.1686, 0.2275, 0.3333, 0.965)

const R_CARD: int = 16
const R_BTN: int = 12
const R_SMALL: int = 8

static var _theme: Theme = null


static func font() -> Font:
	return U.font()


static func font_bold() -> Font:
	return U.font_bold()


static func build() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 22
	_labels(t)
	_panels(t)
	_buttons(t)
	_toggles(t)
	_sliders(t)
	_progress(t)
	_scrollbars(t)
	_inputs(t)
	_tabs(t)
	_popups(t)
	_misc(t)
	_theme = t
	return t


# ==== style factories ============================================================================
static func flat(bg: Color, radius: int = 12, border: Color = Color(0, 0, 0, 0), bw: int = 0,
		shadow: Color = Color(0, 0, 0, 0), shadow_size: int = 0, shadow_off: Vector2 = Vector2(0, 2),
		margins: Vector4 = Vector4(-1, -1, -1, -1)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 10
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.shadow_color = shadow
	sb.shadow_size = shadow_size
	sb.shadow_offset = shadow_off
	sb.anti_aliasing = true
	if margins.x >= 0.0:
		sb.content_margin_left = margins.x
	if margins.y >= 0.0:
		sb.content_margin_top = margins.y
	if margins.z >= 0.0:
		sb.content_margin_right = margins.z
	if margins.w >= 0.0:
		sb.content_margin_bottom = margins.w
	return sb


static func empty(margins: Vector4 = Vector4(0, 0, 0, 0)) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = margins.x
	sb.content_margin_top = margins.y
	sb.content_margin_right = margins.z
	sb.content_margin_bottom = margins.w
	return sb


## Chunky "lip" button face: only the bottom border is drawn (darker edge) so it reads as a raised toy key.
static func chunky(face: Color, edge: Color, lip: int, radius: int, shadow_size: int, shadow_off: float,
		pad: Vector4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = face
	sb.border_color = edge
	sb.border_width_bottom = lip
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 10
	sb.anti_aliasing = true
	if shadow_size > 0:
		sb.shadow_color = Color(0.1, 0.14, 0.26, 0.30)
		sb.shadow_size = shadow_size
		sb.shadow_offset = Vector2(0, shadow_off)
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	return sb


# ==== labels =====================================================================================
static func _label_var(t: Theme, name: StringName, size: int, color: Color, bold: bool = true) -> void:
	t.set_type_variation(name, &"Label")
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)
	if bold:
		t.set_font("font", name, font_bold())


static func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", TEXT_INK)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_font_size("font_size", "Label", 22)
	_label_var(t, &"TitleLabel", 34, TEXT_INK)
	_label_var(t, &"HeaderLabel", 26, TEXT_INK)
	_label_var(t, &"SmallLabel", 18, TEXT_MUTED, false)
	_label_var(t, &"PillLabel", 20, TEXT_ON_DARK)
	_label_var(t, &"OnDark", 22, TEXT_ON_DARK, false)
	_label_var(t, &"OnDarkTitle", 34, TEXT_ON_DARK)
	_label_var(t, &"OnDarkSmall", 18, Color("C9D3E8"), false)
	_label_var(t, &"MoneyLabel", 26, Palette.SUN)
	_label_var(t, &"WarningLabel", 22, Palette.CORAL_DARK)
	t.set_color("default_color", "RichTextLabel", TEXT_INK)
	t.set_font("normal_font", "RichTextLabel", font())
	t.set_font("bold_font", "RichTextLabel", font_bold())
	t.set_font_size("normal_font_size", "RichTextLabel", 22)
	t.set_font_size("bold_font_size", "RichTextLabel", 22)


# ==== panels =====================================================================================
static func _panels(t: Theme) -> void:
	var card := flat(CARD, R_CARD, CARD_EDGE, 2, Color(0.1, 0.14, 0.26, 0.22), 14, Vector2(0, 5), Vector4(18, 14, 18, 14))
	t.set_stylebox("panel", "Panel", flat(CARD, R_CARD, CARD_EDGE, 2, Color(0.1, 0.14, 0.26, 0.22), 14, Vector2(0, 5)))
	t.set_stylebox("panel", "PanelContainer", card)
	t.set_type_variation(&"CardPanel", &"PanelContainer")
	t.set_stylebox("panel", "CardPanel", card)

	var bar := flat(BAR_NAVY, 22, Color(1, 1, 1, 0.08), 0, Color(0.05, 0.08, 0.16, 0.30), 12, Vector2(0, 4), Vector4(22, 10, 22, 12))
	bar.corner_radius_top_left = 0
	bar.corner_radius_top_right = 0
	t.set_type_variation(&"NavyBar", &"PanelContainer")
	t.set_stylebox("panel", "NavyBar", bar)
	var bar_b := flat(BAR_NAVY, 22, Color(1, 1, 1, 0.08), 0, Color(0.05, 0.08, 0.16, 0.30), 12, Vector2(0, -4), Vector4(22, 12, 22, 10))
	bar_b.corner_radius_bottom_left = 0
	bar_b.corner_radius_bottom_right = 0
	t.set_type_variation(&"NavyBarBottom", &"PanelContainer")
	t.set_stylebox("panel", "NavyBarBottom", bar_b)

	t.set_type_variation(&"PillPanel", &"PanelContainer")
	t.set_stylebox("panel", "PillPanel", flat(Color(0.12, 0.17, 0.27, 0.78), 22, Color(1, 1, 1, 0.10), 2, Color(0, 0, 0, 0.0), 0, Vector2.ZERO, Vector4(14, 5, 18, 5)))
	t.set_type_variation(&"PillPanelLight", &"PanelContainer")
	t.set_stylebox("panel", "PillPanelLight", flat(CARD, 22, CARD_EDGE, 2, Color(0.1, 0.14, 0.26, 0.16), 6, Vector2(0, 3), Vector4(14, 5, 18, 5)))
	t.set_type_variation(&"PlatePanel", &"PanelContainer")
	t.set_stylebox("panel", "PlatePanel", flat(PLATE, R_BTN + 2, Color("E8D8BA"), 2, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(12, 10, 12, 10)))
	t.set_type_variation(&"SkyPanel", &"PanelContainer")
	t.set_stylebox("panel", "SkyPanel", flat(Color(1, 1, 1, 0.28), R_CARD, Color(1, 1, 1, 0.45), 2, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(14, 10, 14, 10)))

	# Built-in tooltip type
	t.set_stylebox("panel", "TooltipPanel", flat(Color(0.1176, 0.1412, 0.2, 0.96), 10, Color(1, 1, 1, 0.14), 2, Color(0, 0, 0, 0.25), 8, Vector2(0, 3), Vector4(14, 8, 14, 9)))
	t.set_color("font_color", "TooltipLabel", TEXT_ON_DARK)
	t.set_font_size("font_size", "TooltipLabel", 19)
	t.set_font("font", "TooltipLabel", font())
	t.set_constant("outline_size", "TooltipLabel", 0)

	t.set_stylebox("panel", "PopupPanel", flat(CARD, R_CARD, CARD_EDGE, 2, Color(0.1, 0.14, 0.26, 0.30), 16, Vector2(0, 6), Vector4(14, 12, 14, 12)))


# ==== buttons ====================================================================================
static func _btn_set(t: Theme, type: StringName, face: Color, edge: Color, text: Color, text_dis: Color,
		radius: int = R_BTN, pad: Vector4 = Vector4(22, 8, 22, 13), lip: int = 5, light: float = 0.14) -> void:
	var f_hover := face.lerp(Color(1, 1, 1, face.a), light)
	var f_press := face.lerp(Color(0.1, 0.14, 0.26, face.a), 0.12)
	var e_press := edge.lerp(Color(0.1, 0.14, 0.26, edge.a), 0.1)
	var pad_press := Vector4(pad.x, pad.y + 3.0, pad.z, pad.w - 3.0)
	t.set_stylebox("normal", type, chunky(face, edge, lip, radius, 4, 3.0, pad))
	t.set_stylebox("hover", type, chunky(f_hover, edge, lip, radius, 9, 5.0, pad))
	t.set_stylebox("pressed", type, chunky(f_press, e_press, 2, radius, 1, 1.0, pad_press))
	t.set_stylebox("hover_pressed", type, chunky(f_press.lerp(Color.WHITE, 0.08), e_press, 2, radius, 1, 1.0, pad_press))
	t.set_stylebox("disabled", type, chunky(Color("D6CDBE"), Color("C2B8A5"), lip, radius, 0, 0.0, pad))
	t.set_stylebox("focus", type, flat(Color(0, 0, 0, 0), radius + 3, Color(1, 1, 1, 0.55), 2, Color(0, 0, 0, 0), 0, Vector2.ZERO))
	t.set_color("font_color", type, text)
	t.set_color("font_hover_color", type, text)
	t.set_color("font_pressed_color", type, text)
	t.set_color("font_hover_pressed_color", type, text)
	t.set_color("font_focus_color", type, text)
	t.set_color("font_disabled_color", type, text_dis)
	t.set_color("icon_normal_color", type, text)
	t.set_color("icon_hover_color", type, text)
	t.set_color("icon_pressed_color", type, text)
	t.set_color("icon_disabled_color", type, text_dis)
	t.set_font("font", type, font_bold())
	t.set_font_size("font_size", type, 22)
	t.set_constant("h_separation", type, 8)
	t.set_constant("outline_size", type, 0)


static func _variation(t: Theme, name: StringName, base: StringName = &"Button") -> void:
	t.set_type_variation(name, base)


static func _buttons(t: Theme) -> void:
	# Default = neutral cream
	_btn_set(t, &"Button", Color("FFFDF7"), Color("E3D3B3"), TEXT_INK, Color("9A9486"))
	_variation(t, &"PrimaryButton")
	_btn_set(t, &"PrimaryButton", Palette.CORAL, Palette.CORAL_DARK, Color.WHITE, Color("F5E9E6"), R_BTN, Vector4(26, 9, 26, 14))
	_variation(t, &"SecondaryButton")
	_btn_set(t, &"SecondaryButton", Palette.TEAL, Palette.TEAL_DARK, Color.WHITE, Color("EAF4F8"), R_BTN, Vector4(24, 8, 24, 13))
	_variation(t, &"SunButton")
	_btn_set(t, &"SunButton", Palette.SUN, Palette.SUN_DEEP, TEXT_INK, Color("A89F86"))
	_variation(t, &"DangerButton")
	_btn_set(t, &"DangerButton", Palette.CORAL_DARK, Color("8E2A39"), Color.WHITE, Color("D9B9BE"))

	# Ghost: transparent on navy
	_variation(t, &"GhostButton")
	var gpad := Vector4(18, 8, 18, 8)
	t.set_stylebox("normal", "GhostButton", flat(Color(1, 1, 1, 0.0), R_BTN, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, gpad))
	t.set_stylebox("hover", "GhostButton", flat(Color(1, 1, 1, 0.14), R_BTN, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, gpad))
	t.set_stylebox("pressed", "GhostButton", flat(Color(1, 1, 1, 0.24), R_BTN, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(18, 10, 18, 6)))
	t.set_stylebox("hover_pressed", "GhostButton", flat(Color(1, 1, 1, 0.28), R_BTN, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(18, 10, 18, 6)))
	t.set_stylebox("disabled", "GhostButton", flat(Color(1, 1, 1, 0.0), R_BTN, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, gpad))
	t.set_stylebox("focus", "GhostButton", flat(Color(0, 0, 0, 0), R_BTN + 3, Color(1, 1, 1, 0.55), 2))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "GhostButton", TEXT_ON_DARK)
	t.set_color("font_disabled_color", "GhostButton", Color(1, 1, 1, 0.35))
	t.set_font("font", "GhostButton", font_bold())
	t.set_font_size("font_size", "GhostButton", 22)

	# Icon buttons: round, no text padding. Cream on light UI, navy on bars.
	_variation(t, &"IconButton")
	_btn_set(t, &"IconButton", Color("FFFDF7"), Color("E3D3B3"), TEXT_INK, Color("9A9486"), 28, Vector4(4, 4, 4, 8), 4)
	_variation(t, &"IconButtonDark")
	_btn_set(t, &"IconButtonDark", Color("3D5073"), Color("26334C"), TEXT_ON_DARK, Color("7886A0"), 28, Vector4(4, 4, 4, 8), 4)
	# toggled-on state of the dark icon button = sun yellow
	t.set_stylebox("pressed", "IconButtonDark", chunky(Palette.SUN, Palette.SUN_DEEP, 2, 28, 1, 1.0, Vector4(4, 7, 4, 5)))
	t.set_stylebox("hover_pressed", "IconButtonDark", chunky(Palette.SUN.lerp(Color.WHITE, 0.2), Palette.SUN_DEEP, 2, 28, 1, 1.0, Vector4(4, 7, 4, 5)))

	# Tab pill buttons (toggle_mode): selected = coral.
	_variation(t, &"TabButton")
	_btn_set(t, &"TabButton", Color(1, 1, 1, 0.10), Color(0, 0, 0, 0), TEXT_ON_DARK, Color("7886A0"), 14, Vector4(20, 8, 20, 10), 0, 0.0)
	t.set_stylebox("normal", "TabButton", flat(Color(1, 1, 1, 0.10), 14, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(20, 9, 20, 9)))
	t.set_stylebox("hover", "TabButton", flat(Color(1, 1, 1, 0.22), 14, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(20, 9, 20, 9)))
	t.set_stylebox("pressed", "TabButton", chunky(Palette.CORAL, Palette.CORAL_DARK, 4, 14, 3, 2.0, Vector4(20, 8, 20, 11)))
	t.set_stylebox("hover_pressed", "TabButton", chunky(Palette.CORAL.lerp(Color.WHITE, 0.14), Palette.CORAL_DARK, 4, 14, 5, 3.0, Vector4(20, 8, 20, 11)))
	t.set_color("font_pressed_color", "TabButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "TabButton", Color.WHITE)

	# OptionButton (+ MenuButton) share the neutral look
	var arrow := _arrow_tex(Color("3D5073"))
	for type in [&"OptionButton", &"MenuButton"]:
		_btn_set(t, type, Color("FFFDF7"), Color("E3D3B3"), TEXT_INK, Color("9A9486"), R_BTN, Vector4(18, 8, 18, 13))
		t.set_icon("arrow", type, arrow)
		t.set_constant("arrow_margin", type, 10)
		t.set_color("icon_normal_color", type, Color.WHITE)
		t.set_color("icon_hover_color", type, Color.WHITE)
		t.set_color("icon_pressed_color", type, Color.WHITE)
		t.set_color("icon_hover_pressed_color", type, Color.WHITE)
		t.set_color("icon_focus_color", type, Color.WHITE)


# ==== check boxes / switches / radios ============================================================
static func _toggles(t: Theme) -> void:
	var chk_off := _check_tex(false, false)
	var chk_on := _check_tex(true, false)
	var chk_off_d := _check_tex(false, true)
	var chk_on_d := _check_tex(true, true)
	var rad_off := _radio_tex(false, false)
	var rad_on := _radio_tex(true, false)
	var rad_off_d := _radio_tex(false, true)
	var rad_on_d := _radio_tex(true, true)
	var empty_sb := empty()
	for type in [&"CheckBox", &"CheckButton"]:
		for s in ["normal", "pressed", "disabled", "hover", "hover_pressed"]:
			t.set_stylebox(s, type, empty_sb)
		t.set_stylebox("focus", type, flat(Color(0, 0, 0, 0), 10, Color(0.1, 0.14, 0.26, 0.25), 2))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(c, type, TEXT_INK)
		t.set_color("font_disabled_color", type, TEXT_MUTED)
		t.set_font("font", type, font())
		t.set_font_size("font_size", type, 22)
		t.set_constant("h_separation", type, 12)
		t.set_constant("check_v_offset", type, 0)
		t.set_constant("outline_size", type, 0)
	t.set_icon("unchecked", "CheckBox", chk_off)
	t.set_icon("checked", "CheckBox", chk_on)
	t.set_icon("unchecked_disabled", "CheckBox", chk_off_d)
	t.set_icon("checked_disabled", "CheckBox", chk_on_d)
	t.set_icon("radio_unchecked", "CheckBox", rad_off)
	t.set_icon("radio_checked", "CheckBox", rad_on)
	t.set_icon("radio_unchecked_disabled", "CheckBox", rad_off_d)
	t.set_icon("radio_checked_disabled", "CheckBox", rad_on_d)
	var sw_off := _switch_tex(false, false)
	var sw_on := _switch_tex(true, false)
	var sw_off_d := _switch_tex(false, true)
	var sw_on_d := _switch_tex(true, true)
	t.set_icon("unchecked", "CheckButton", sw_off)
	t.set_icon("checked", "CheckButton", sw_on)
	t.set_icon("unchecked_disabled", "CheckButton", sw_off_d)
	t.set_icon("checked_disabled", "CheckButton", sw_on_d)
	t.set_icon("unchecked_mirrored", "CheckButton", sw_off)
	t.set_icon("checked_mirrored", "CheckButton", sw_on)
	t.set_icon("unchecked_disabled_mirrored", "CheckButton", sw_off_d)
	t.set_icon("checked_disabled_mirrored", "CheckButton", sw_on_d)


# ==== sliders ====================================================================================
static func _sliders(t: Theme) -> void:
	var grab := _grabber_tex(false)
	var grab_h := _grabber_tex(true)
	var trough := flat(Color(0.1686, 0.2275, 0.3333, 0.16), 8, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(0, 7, 0, 7))
	var fill := flat(Palette.TEAL, 8, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(0, 7, 0, 7))
	var fill_h := flat(Palette.TEAL.lerp(Color.WHITE, 0.15), 8, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(0, 7, 0, 7))
	for type in [&"HSlider", &"VSlider"]:
		var tr := trough
		var fl := fill
		var flh := fill_h
		if type == &"VSlider":
			tr = flat(Color(0.1686, 0.2275, 0.3333, 0.16), 8, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(7, 0, 7, 0))
			fl = flat(Palette.TEAL, 8, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(7, 0, 7, 0))
			flh = flat(Palette.TEAL.lerp(Color.WHITE, 0.15), 8, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(7, 0, 7, 0))
		t.set_stylebox("slider", type, tr)
		t.set_stylebox("grabber_area", type, fl)
		t.set_stylebox("grabber_area_highlight", type, flh)
		t.set_icon("grabber", type, grab)
		t.set_icon("grabber_highlight", type, grab_h)
		t.set_icon("grabber_disabled", type, grab)
		t.set_constant("center_grabber", type, 0)
		t.set_constant("grabber_offset", type, 0)


# ==== progress bars ==============================================================================
static func _bar_fill(t: Theme, name: StringName, top: Color) -> void:
	t.set_type_variation(name, &"ProgressBar")
	t.set_stylebox("background", name, flat(Color(0.1686, 0.2275, 0.3333, 0.22), 11, Color(0, 0, 0, 0.05), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(0, 11, 0, 11)))
	t.set_stylebox("fill", name, chunky(top, top.lerp(Color(0.1, 0.14, 0.26), 0.22), 3, 11, 0, 0.0, Vector4(0, 11, 0, 11)))
	t.set_color("font_color", name, Color.WHITE)
	t.set_color("font_outline_color", name, Color(0.1, 0.14, 0.26, 0.6))
	t.set_constant("outline_size", name, 4)
	t.set_font_size("font_size", name, 16)
	t.set_font("font", name, font_bold())


static func _progress(t: Theme) -> void:
	_bar_fill(t, &"MintBar", Palette.MINT)
	_bar_fill(t, &"CoralBar", Palette.CORAL)
	_bar_fill(t, &"SunBar", Palette.SUN)
	_bar_fill(t, &"TealBar", Palette.TEAL)
	t.set_stylebox("background", "ProgressBar", flat(Color(0.1686, 0.2275, 0.3333, 0.22), 11, Color(0, 0, 0, 0.05), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(0, 11, 0, 11)))
	t.set_stylebox("fill", "ProgressBar", chunky(Palette.MINT, Palette.MINT_DARK, 3, 11, 0, 0.0, Vector4(0, 11, 0, 11)))
	t.set_color("font_color", "ProgressBar", Color.WHITE)
	t.set_color("font_outline_color", "ProgressBar", Color(0.1, 0.14, 0.26, 0.6))
	t.set_constant("outline_size", "ProgressBar", 4)
	t.set_font_size("font_size", "ProgressBar", 16)
	t.set_font("font", "ProgressBar", font_bold())


# ==== scrollbars =================================================================================
static func _scrollbars(t: Theme) -> void:
	for type in [&"VScrollBar", &"HScrollBar"]:
		var v: bool = type == &"VScrollBar"
		var m := Vector4(5, 0, 5, 0) if v else Vector4(0, 5, 0, 5)
		t.set_stylebox("scroll", type, flat(Color(0.1686, 0.2275, 0.3333, 0.10), 6, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, m))
		t.set_stylebox("scroll_focus", type, flat(Color(0.1686, 0.2275, 0.3333, 0.10), 6, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, m))
		t.set_stylebox("grabber", type, flat(Palette.TEAL.lerp(Palette.NAVY, 0.15), 6, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, m))
		t.set_stylebox("grabber_highlight", type, flat(Palette.TEAL, 6, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, m))
		t.set_stylebox("grabber_pressed", type, flat(Palette.TEAL_DARK, 6, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, m))
		var none := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
		for ic in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(ic, type, none)


# ==== line edit / text edit / item list ==========================================================
static func _inputs(t: Theme) -> void:
	for type in [&"LineEdit", &"TextEdit", &"CodeEdit"]:
		var pad := Vector4(16, 9, 16, 9)
		t.set_stylebox("normal", type, flat(Color("FFFDF7"), R_BTN, Color("E3D3B3"), 3, Color(0, 0, 0, 0), 0, Vector2.ZERO, pad))
		t.set_stylebox("focus", type, flat(Color("FFFDF7"), R_BTN, Palette.CORAL, 3, Color(0.91, 0.31, 0.36, 0.25), 6, Vector2.ZERO, pad))
		t.set_stylebox("read_only", type, flat(Color("EFE6D2"), R_BTN, Color("DCCFB2"), 3, Color(0, 0, 0, 0), 0, Vector2.ZERO, pad))
		t.set_color("font_color", type, TEXT_INK)
		t.set_color("font_selected_color", type, Color.WHITE)
		t.set_color("font_placeholder_color", type, Color("A39C8B"))
		t.set_color("font_uneditable_color", type, TEXT_MUTED)
		t.set_color("caret_color", type, Palette.CORAL)
		t.set_color("selection_color", type, Color(Palette.CORAL.r, Palette.CORAL.g, Palette.CORAL.b, 0.85))
		t.set_font("font", type, font())
		t.set_font_size("font_size", type, 22)
		t.set_constant("caret_width", type, 3)
	t.set_icon("clear", "LineEdit", _clear_tex())

	t.set_stylebox("panel", "ItemList", flat(Color("FFFDF7"), R_BTN, Color("E3D3B3"), 3, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(8, 8, 8, 8)))
	t.set_stylebox("focus", "ItemList", flat(Color(0, 0, 0, 0), R_BTN, Color(0.1, 0.14, 0.26, 0.2), 2))
	t.set_stylebox("selected", "ItemList", flat(Palette.CORAL_LIGHT.lerp(Color.WHITE, 0.45), R_SMALL))
	t.set_stylebox("selected_focus", "ItemList", flat(Palette.CORAL_LIGHT.lerp(Color.WHITE, 0.35), R_SMALL))
	t.set_stylebox("hovered", "ItemList", flat(Color(0.1686, 0.2275, 0.3333, 0.07), R_SMALL))
	t.set_stylebox("cursor", "ItemList", flat(Color(0, 0, 0, 0), R_SMALL, Color(0.1, 0.14, 0.26, 0.25), 2))
	t.set_stylebox("cursor_unfocused", "ItemList", flat(Color(0, 0, 0, 0), R_SMALL))
	t.set_color("font_color", "ItemList", TEXT_INK)
	t.set_color("font_selected_color", "ItemList", TEXT_INK)
	t.set_color("font_hovered_color", "ItemList", TEXT_INK)
	t.set_font("font", "ItemList", font())
	t.set_font_size("font_size", "ItemList", 22)
	t.set_constant("v_separation", "ItemList", 6)


# ==== tabs =======================================================================================
static func _tabs(t: Theme) -> void:
	# TabBar / TabContainer are styled for LIGHT (cream) backgrounds; use TabButton (toggle) on navy bars.
	var dark_tab := flat(Color(0.1686, 0.2275, 0.3333, 0.10), 14, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(20, 8, 20, 8))
	var dark_tab_h := flat(Color(0.1686, 0.2275, 0.3333, 0.20), 14, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(20, 8, 20, 8))
	var sel := chunky(Palette.CORAL, Palette.CORAL_DARK, 4, 14, 0, 0.0, Vector4(20, 7, 20, 9))
	for type in [&"TabBar", &"TabContainer"]:
		t.set_stylebox("tab_selected", type, sel)
		t.set_stylebox("tab_unselected", type, dark_tab)
		t.set_stylebox("tab_hovered", type, dark_tab_h)
		t.set_stylebox("tab_disabled", type, dark_tab)
		t.set_stylebox("tab_focus", type, flat(Color(0, 0, 0, 0), 14, Color(0.1, 0.14, 0.26, 0.25), 2))
		t.set_color("font_selected_color", type, Color.WHITE)
		t.set_color("font_unselected_color", type, TEXT_INK)
		t.set_color("font_hovered_color", type, TEXT_INK)
		t.set_color("font_disabled_color", type, Color("A39C8B"))
		t.set_font("font", type, font_bold())
		t.set_font_size("font_size", type, 22)
		t.set_constant("h_separation", type, 8)
		t.set_constant("outline_size", type, 0)
	t.set_stylebox("tabbar_background", "TabContainer", flat(Color(0, 0, 0, 0)))
	t.set_stylebox("panel", "TabContainer", flat(CARD, R_CARD, CARD_EDGE, 2, Color(0.1, 0.14, 0.26, 0.2), 12, Vector2(0, 4), Vector4(16, 14, 16, 14)))
	t.set_constant("side_margin", "TabContainer", 0)


# ==== popups =====================================================================================
static func _popups(t: Theme) -> void:
	t.set_stylebox("panel", "PopupMenu", flat(CARD, R_BTN, CARD_EDGE, 2, Color(0.1, 0.14, 0.26, 0.30), 14, Vector2(0, 6), Vector4(8, 8, 8, 8)))
	t.set_stylebox("hover", "PopupMenu", flat(Color(Palette.CORAL.r, Palette.CORAL.g, Palette.CORAL.b, 0.18), R_SMALL))
	t.set_stylebox("separator", "PopupMenu", flat(Color(0.1686, 0.2275, 0.3333, 0.15), 2, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(0, 1, 0, 1)))
	t.set_stylebox("labeled_separator_left", "PopupMenu", flat(Color(0.1686, 0.2275, 0.3333, 0.15), 2, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(0, 1, 0, 1)))
	t.set_stylebox("labeled_separator_right", "PopupMenu", flat(Color(0.1686, 0.2275, 0.3333, 0.15), 2, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(0, 1, 0, 1)))
	t.set_color("font_color", "PopupMenu", TEXT_INK)
	t.set_color("font_hover_color", "PopupMenu", TEXT_INK)
	t.set_color("font_disabled_color", "PopupMenu", Color("A39C8B"))
	t.set_color("font_separator_color", "PopupMenu", TEXT_MUTED)
	t.set_color("font_accelerator_color", "PopupMenu", TEXT_MUTED)
	t.set_font("font", "PopupMenu", font())
	t.set_font_size("font_size", "PopupMenu", 22)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_constant("h_separation", "PopupMenu", 10)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 10)
	t.set_icon("checked", "PopupMenu", _check_tex(true, false, 22))
	t.set_icon("unchecked", "PopupMenu", _check_tex(false, false, 22))
	t.set_icon("radio_checked", "PopupMenu", _radio_tex(true, false, 22))
	t.set_icon("radio_unchecked", "PopupMenu", _radio_tex(false, false, 22))


static func _misc(t: Theme) -> void:
	var sep_h := flat(Color(0.1686, 0.2275, 0.3333, 0.14), 2, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(0, 2, 0, 2))
	var sep_v := flat(Color(0.1686, 0.2275, 0.3333, 0.14), 2, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(2, 0, 2, 0))
	t.set_stylebox("separator", "HSeparator", sep_h)
	t.set_stylebox("separator", "VSeparator", sep_v)
	t.set_constant("separation", "HSeparator", 12)
	t.set_constant("separation", "VSeparator", 12)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("h_separation", "GridContainer", 12)
	t.set_constant("v_separation", "GridContainer", 12)
	t.set_constant("separation", "FlowContainer", 10)


# ==== procedural textures (SDF-painted for crisp anti-aliased edges) ==============================
static func _sd_rr(p: Vector2, c: Vector2, hs: Vector2, r: float) -> float:
	var q := (p - c).abs() - (hs - Vector2(r, r))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


static func _sd_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length()


static func _dist(L: Dictionary, p: Vector2) -> float:
	match L["k"]:
		"rr": return _sd_rr(p, L["c"], L["hs"], L["r"])
		"circle": return (p - L["c"]).length() - float(L["r"])
		"seg": return _sd_seg(p, L["a"], L["b"]) - float(L["w"]) * 0.5
	return 1000.0


static func _paint(w: int, h: int, layers: Array) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var p := Vector2(x + 0.5, y + 0.5)
			var out := Color(0, 0, 0, 0)
			for L: Dictionary in layers:
				var d := _dist(L, p)
				var soft: float = L.get("soft", 1.0)
				var cov := clampf(0.5 - d / soft, 0.0, 1.0)
				var c: Color = L["col"]
				var a := c.a * cov
				if a <= 0.0:
					continue
				var oa := out.a
				var na := a + oa * (1.0 - a)
				out = Color((c.r * a + out.r * oa * (1.0 - a)) / na, (c.g * a + out.g * oa * (1.0 - a)) / na,
						(c.b * a + out.b * oa * (1.0 - a)) / na, na)
			img.set_pixel(x, y, out)
	return ImageTexture.create_from_image(img)


static func _check_tex(on: bool, disabled: bool, s: int = 34) -> ImageTexture:
	var k := float(s) / 34.0
	var c := Vector2(s * 0.5, s * 0.5)
	var layers: Array = []
	if on:
		var base := Palette.CORAL if not disabled else Color("CFC6B6")
		var edge := Palette.CORAL_DARK if not disabled else Color("B8AE9B")
		layers.append({"k": "rr", "c": c + Vector2(0, 1.5 * k), "hs": Vector2(14, 14) * k, "r": 9.0 * k, "col": edge})
		layers.append({"k": "rr", "c": c, "hs": Vector2(14, 13.2) * k, "r": 9.0 * k, "col": base})
		layers.append({"k": "seg", "a": Vector2(10, 17.5) * k, "b": Vector2(15, 22.5) * k, "w": 4.6 * k, "col": Color.WHITE})
		layers.append({"k": "seg", "a": Vector2(15, 22.5) * k, "b": Vector2(24.5, 11.5) * k, "w": 4.6 * k, "col": Color.WHITE})
	else:
		var edge2 := Color("D9C7A6") if not disabled else Color("D6CDBE")
		layers.append({"k": "rr", "c": c, "hs": Vector2(14, 14) * k, "r": 9.0 * k, "col": edge2})
		layers.append({"k": "rr", "c": c, "hs": Vector2(11.4, 11.4) * k, "r": 7.0 * k, "col": Color("FFFDF7") if not disabled else Color("EFE9DC")})
	return _paint(s, s, layers)


static func _radio_tex(on: bool, disabled: bool, s: int = 34) -> ImageTexture:
	var k := float(s) / 34.0
	var c := Vector2(s * 0.5, s * 0.5)
	var layers: Array = []
	if on:
		var base := Palette.CORAL if not disabled else Color("CFC6B6")
		var edge := Palette.CORAL_DARK if not disabled else Color("B8AE9B")
		layers.append({"k": "circle", "c": c + Vector2(0, 1.5 * k), "r": 14.0 * k, "col": edge})
		layers.append({"k": "circle", "c": c, "r": 13.5 * k, "col": base})
		layers.append({"k": "circle", "c": c, "r": 5.2 * k, "col": Color.WHITE})
	else:
		layers.append({"k": "circle", "c": c, "r": 14.0 * k, "col": Color("D9C7A6") if not disabled else Color("D6CDBE")})
		layers.append({"k": "circle", "c": c, "r": 11.4 * k, "col": Color("FFFDF7") if not disabled else Color("EFE9DC")})
	return _paint(s, s, layers)


static func _switch_tex(on: bool, disabled: bool) -> ImageTexture:
	var w := 64
	var h := 36
	var c := Vector2(w * 0.5, h * 0.5)
	var layers: Array = []
	var track: Color = Palette.MINT if on else Color("D9C7A6")
	var track_edge: Color = Palette.MINT_DARK if on else Color("C4B08B")
	if disabled:
		track = Color("D6CDBE")
		track_edge = Color("C2B8A5")
	layers.append({"k": "rr", "c": c + Vector2(0, 1.5), "hs": Vector2(30, 15), "r": 15.0, "col": track_edge})
	layers.append({"k": "rr", "c": c, "hs": Vector2(30, 14.2), "r": 14.2, "col": track})
	var kx: float = 46.0 if on else 18.0
	layers.append({"k": "circle", "c": Vector2(kx, 20.0), "r": 12.0, "col": Color(0.1, 0.14, 0.26, 0.28), "soft": 3.0})
	layers.append({"k": "circle", "c": Vector2(kx, 17.5), "r": 11.5, "col": Color.WHITE if not disabled else Color("F5F1E8")})
	return _paint(w, h, layers)


static func _grabber_tex(hl: bool) -> ImageTexture:
	var s := 36
	var c := Vector2(18, 17)
	var layers: Array = []
	layers.append({"k": "circle", "c": c + Vector2(0, 2.5), "r": 14.0, "col": Color(0.1, 0.14, 0.26, 0.30), "soft": 4.0})
	layers.append({"k": "circle", "c": c + Vector2(0, 1.2), "r": 14.0, "col": Palette.SUN_DEEP})
	layers.append({"k": "circle", "c": c, "r": 12.6 if not hl else 13.4, "col": Palette.SUN if not hl else Palette.SUN.lerp(Color.WHITE, 0.25)})
	layers.append({"k": "circle", "c": c + Vector2(-4, -4.5), "r": 3.4, "col": Color(1, 1, 1, 0.55)})
	return _paint(s, s, layers)


static func _arrow_tex(color: Color) -> ImageTexture:
	var layers: Array = []
	layers.append({"k": "seg", "a": Vector2(4.5, 8), "b": Vector2(11, 14.5), "w": 3.6, "col": color})
	layers.append({"k": "seg", "a": Vector2(11, 14.5), "b": Vector2(17.5, 8), "w": 3.6, "col": color})
	return _paint(22, 22, layers)


static func _clear_tex() -> ImageTexture:
	var layers: Array = []
	layers.append({"k": "circle", "c": Vector2(11, 11), "r": 9.0, "col": Color("D9C7A6")})
	layers.append({"k": "seg", "a": Vector2(7.5, 7.5), "b": Vector2(14.5, 14.5), "w": 2.6, "col": Color.WHITE})
	layers.append({"k": "seg", "a": Vector2(14.5, 7.5), "b": Vector2(7.5, 14.5), "w": 2.6, "col": Color.WHITE})
	return _paint(22, 22, layers)
