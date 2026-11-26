class_name HeatmapHud
extends Control
## Controls that go with HeatmapOverlay: mode tabs (Traffic / Unhappy / Queues) top centre, a legend top left and,
## optionally, a "Back to results" button top right (docs/SPEC.md §13.2).
##
##   var hud := HeatmapHud.new()
##   host.add_child(hud)                     # full rect, only its own widgets take the mouse
##   hud.setup(overlay: HeatmapOverlay, back_text := "Back to results")   # back_text "" = no button
##   hud.closed.connect(...)                 # the back button / Esc
## The tabs drive `overlay.set_mode`. Esc counts as "closed" when a back button is shown.

signal closed
signal mode_changed(mode: StringName)

var _overlay: HeatmapOverlay
var _tabs: Dictionary = {}
var _legend_title: Label
var _legend_caption: Label
var _legend_bar: _LegendBar
var _legend_peak: Label
var _back: Button
var _group: ButtonGroup
var _has_back: bool = false


class _LegendBar extends Control:
	var colorblind: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(260, 22)

	func _draw() -> void:
		var n: int = 26
		var w: float = size.x / float(n)
		ArtUtil.rr(self, Rect2(0, 0, size.x, size.y), 8.0, Color(1, 1, 1, 0.16))
		for i in range(n):
			var t: float = float(i) / float(n - 1)
			var c: Color = HeatmapOverlay.ramp(t, colorblind)
			c.a = maxf(c.a, 0.0)
			# opaque version over a light plate so the low end still reads as "a little"
			var base: Color = Color(0.96, 0.93, 0.85, 1.0)
			var mix: Color = base.lerp(Color(c.r, c.g, c.b, 1.0), clampf(c.a / 0.82, 0.0, 1.0))
			ArtUtil.rect(self, Rect2(float(i) * w, 2.0, w + 0.6, size.y - 4.0), mix)
		ArtUtil.rr_outline(self, Rect2(0, 0, size.x, size.y), 8.0, Color(1, 1, 1, 0.5), 2.0)


func _init() -> void:
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(overlay: HeatmapOverlay, back_text: String = "Back to results") -> void:
	_overlay = overlay
	_has_back = back_text != ""
	_build_tabs()
	_build_legend()
	if _has_back:
		_back = UIKit.sun_button(back_text)
		_back.custom_minimum_size = Vector2(250, 56)
		OvUtil.focusable(_back)
		_back.pressed.connect(func() -> void: closed.emit())
		_back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_back.offset_left = -274.0
		_back.offset_right = -24.0
		_back.offset_top = 20.0
		_back.offset_bottom = 76.0
		add_child(_back)
		_back.call_deferred("grab_focus")
	select(_overlay.mode)


func select(m: StringName) -> void:
	_overlay.set_mode(m)
	for k in _tabs:
		(_tabs[k] as Button).set_pressed_no_signal(k == m)
	_legend_title.text = String(HeatmapOverlay.MODE_NAMES.get(m, ""))
	_legend_caption.text = String(HeatmapOverlay.MODE_CAPTIONS.get(m, ""))
	var pk: float = _overlay.peak()
	_legend_peak.text = "Hottest spot: %d s of guests" % int(round(pk)) if pk >= 1.0 else "Nothing recorded here"
	mode_changed.emit(m)


func _build_tabs() -> void:
	var pill := PanelContainer.new()
	pill.theme_type_variation = &"PillPanel"
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.offset_top = 20.0
	var h := UIKit.hbox(8)
	pill.add_child(h)
	_group = ButtonGroup.new()
	for m in HeatmapOverlay.MODES:
		var b := UIKit.tab_button(String(HeatmapOverlay.MODE_NAMES[m]))
		b.button_group = _group
		b.custom_minimum_size = Vector2(150, 46)
		OvUtil.focusable(b)
		b.pressed.connect(select.bind(m))
		h.add_child(b)
		_tabs[m] = b
	add_child(pill)


func _build_legend() -> void:
	var pill := PanelContainer.new()
	pill.theme_type_variation = &"PillPanel"
	pill.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pill.offset_left = 24.0
	pill.offset_top = 20.0
	var sb: StyleBoxFlat = (UITheme.build().get_stylebox("panel", "PillPanel") as StyleBoxFlat).duplicate()
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.bg_color = Color(0.12, 0.17, 0.27, 0.9)
	pill.add_theme_stylebox_override("panel", sb)
	var v := UIKit.vbox(4)
	pill.add_child(v)
	_legend_title = Label.new()
	_legend_title.theme_type_variation = &"OnDarkTitle"
	_legend_title.add_theme_font_size_override("font_size", 26)
	v.add_child(_legend_title)
	_legend_caption = Label.new()
	_legend_caption.theme_type_variation = &"OnDarkSmall"
	_legend_caption.add_theme_font_size_override("font_size", 16)
	v.add_child(_legend_caption)
	_legend_bar = _LegendBar.new()
	_legend_bar.colorblind = _overlay.colorblind
	v.add_child(_legend_bar)
	var lh := UIKit.hbox(0)
	var lo := Label.new()
	lo.theme_type_variation = &"OnDarkSmall"
	lo.add_theme_font_size_override("font_size", 15)
	lo.text = "Less"
	lh.add_child(lo)
	lh.add_child(UIKit.h_spacer())
	var hi := Label.new()
	hi.theme_type_variation = &"OnDarkSmall"
	hi.add_theme_font_size_override("font_size", 15)
	hi.text = "More"
	lh.add_child(hi)
	v.add_child(lh)
	_legend_peak = Label.new()
	_legend_peak.theme_type_variation = &"OnDarkSmall"
	_legend_peak.add_theme_font_size_override("font_size", 16)
	_legend_peak.add_theme_color_override("font_color", Palette.SUN)
	v.add_child(_legend_peak)
	add_child(pill)


func _unhandled_input(event: InputEvent) -> void:
	if not _has_back or not is_visible_in_tree() or event is InputEventMouseButton:
		return
	if event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
