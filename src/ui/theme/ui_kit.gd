class_name UIKit
extends RefCounted
## Static helpers that build pre-styled Controls (requires `UITheme.build()` assigned on an ancestor).
##
##   primary_button(text) / secondary_button(text) / ghost_button(text) / sun_button(text) / danger_button(text) -> Button
##   tab_button(text) -> Button (toggle_mode pill; pressed = selected)
##   icon_button(icon: StringName, tooltip := "", size := 56.0, dark := false) -> Button   (dark = navy-bar style; toggle_mode via .toggle_mode)
##   card() -> PanelContainer   navy_bar() -> PanelContainer   navy_bar_bottom() -> PanelContainer
##   title_label / header_label / small_label (text) -> Label
##   stat_pill(icon, text) -> StatPill   (has set_text(s), set_icon(i), set_light(b))
##   make_meter() -> SatisfactionMeter   make_progress_bar(variation := &"MintBar") -> ProgressBar (max 1.0)
##   make_voyage_progress() -> VoyageProgress   star_row(n, size := 28.0) -> StarRow
##   h_spacer(width := 0.0, expand := true) / v_spacer(height := 0.0, expand := false) -> Control
##   hbox(sep := 10) / vbox(sep := 10) -> BoxContainer     with_margin(child, px) -> MarginContainer
##   tween_pop(node: Control) -> void   (scale pop-in with back easing)
##   juice(btn: Button) -> void         (hover lift scale + press squash; applied to all UIKit buttons)


static func _btn(text: String, variation: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	juice(b)
	return b


static func primary_button(text: String) -> Button:
	return _btn(text, &"PrimaryButton")


static func secondary_button(text: String) -> Button:
	return _btn(text, &"SecondaryButton")


static func ghost_button(text: String) -> Button:
	return _btn(text, &"GhostButton")


static func sun_button(text: String) -> Button:
	return _btn(text, &"SunButton")


static func danger_button(text: String) -> Button:
	return _btn(text, &"DangerButton")


static func tab_button(text: String) -> Button:
	var b := _btn(text, &"TabButton")
	b.toggle_mode = true
	return b


static func icon_button(icon: StringName, tooltip: String = "", icon_px: float = 56.0, dark: bool = false) -> Button:
	var b := _btn("", &"IconButtonDark" if dark else &"IconButton")
	b.custom_minimum_size = Vector2(icon_px, icon_px)
	b.tooltip_text = tooltip
	var iv := IconView.new()
	iv.icon = icon
	iv.icon_size = icon_px * 0.56
	iv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	iv.offset_bottom = -3.0  # sit centred on the button face (above the lip)
	b.add_child(iv)
	return b


## Hover lift (scale up) + press squash (scale down) tweens. Safe to call once per button.
static func juice(b: Button) -> void:
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void: _scale_to(b, 1.04 if not b.disabled else 1.0, 0.12))
	b.mouse_exited.connect(func() -> void: _scale_to(b, 1.0, 0.14))
	b.button_down.connect(func() -> void: _scale_to(b, 0.96, 0.06))
	b.button_up.connect(func() -> void: _scale_to(b, 1.04 if b.is_hovered() else 1.0, 0.12))


static func _scale_to(n: Control, s: float, dur: float) -> void:
	if not n.is_inside_tree():
		return
	if n.has_meta(&"_juice_tween"):
		var old: Tween = n.get_meta(&"_juice_tween")
		if old != null and old.is_valid():
			old.kill()
	var tw := n.create_tween()
	n.set_meta(&"_juice_tween", tw)
	tw.tween_property(n, "scale", Vector2(s, s), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func card() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"CardPanel"
	return p


static func navy_bar() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"NavyBar"
	return p


static func navy_bar_bottom() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"NavyBarBottom"
	return p


static func _label(text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


static func title_label(text: String) -> Label:
	return _label(text, &"TitleLabel")


static func header_label(text: String) -> Label:
	return _label(text, &"HeaderLabel")


static func small_label(text: String) -> Label:
	return _label(text, &"SmallLabel")


static func stat_pill(icon: StringName, text: String) -> StatPill:
	return StatPill.new(icon, text)


static func make_meter() -> SatisfactionMeter:
	return SatisfactionMeter.new()


static func make_voyage_progress() -> VoyageProgress:
	return VoyageProgress.new()


static func star_row(n: int, star_px: float = 28.0) -> StarRow:
	var s := StarRow.new()
	s.star_size = star_px
	s.value = n
	return s


static func make_progress_bar(variation: StringName = &"MintBar") -> ProgressBar:
	var p := ProgressBar.new()
	p.theme_type_variation = variation
	p.min_value = 0.0
	p.max_value = 1.0
	p.step = 0.001
	p.show_percentage = false
	p.custom_minimum_size = Vector2(120, 22)
	return p


static func h_spacer(width: float = 0.0, expand: bool = true) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func v_spacer(height: float = 0.0, expand: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func hbox(sep: int = 10) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func vbox(sep: int = 10) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func with_margin(child: Control, px: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", px)
	m.add_theme_constant_override("margin_right", px)
	m.add_theme_constant_override("margin_top", px)
	m.add_theme_constant_override("margin_bottom", px)
	m.add_child(child)
	return m


static func tween_pop(node: Control) -> void:
	if not node.is_inside_tree():
		node.ready.connect(func() -> void: tween_pop(node), CONNECT_ONE_SHOT)
		return
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(0.6, 0.6)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
