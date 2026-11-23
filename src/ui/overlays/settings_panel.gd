class_name SettingsPanel
extends PanelContainer
## Reusable settings card (used by the settings screen and embedded in the pause menu).
## Tabs: Audio | Display | Accessibility | Controls | Progress.
##
##   var p := SettingsPanel.new(); p.back_text = "Back"; p.closed.connect(...)
##   p.focus_first()            # give keyboard focus to the tab row
##   p.show_tab(3)              # 0 audio, 1 display, 2 accessibility, 3 controls, 4 progress
## `closed` fires on the footer button and on Esc / cancel (unless a key capture is running).

signal closed

const TAB_NAMES: Array[String] = ["Audio", "Display", "Accessibility", "Controls", "Progress"]
const PREVIEW_ICONS: Array[StringName] = [&"mess", &"breakdown", &"sick", &"angry", &"ghost"]
const PREVIEW_NAMES: Array[String] = ["Mess", "Broken", "Sick", "Angry", "Ghost"]

var back_text: String = "Back":
	set(v):
		back_text = v
		if _back_btn != null:
			_back_btn.text = v

var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _scroll: ScrollContainer
var _back_btn: Button
var _slider_value_labels: Dictionary = {}
var _sliders: Dictionary = {}
var _toggles: Dictionary = {}
var _last_preview_ms: int = 0
var _prev_row_normal: PanelContainer
var _prev_row_cb: PanelContainer
# controls page
var _slot_buttons: Dictionary = {}
var _clear_buttons: Dictionary = {}
var _warn_icons: Dictionary = {}
var _conflict_label: Label
var _cap_action: StringName = &""
var _cap_slot: int = -1
var _cap_tween: Tween
# progress page
var _stars_label: Label
var _stars_bar: ProgressBar
var _dest_labels: Dictionary = {}
var _cleared_label: Label


func _init() -> void:
	theme = UITheme.build()
	theme_type_variation = &"CardPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(1100, 780)
	_build()


func _ready() -> void:
	Settings.changed.connect(_on_settings_changed)
	SaveManager.progress_changed.connect(_refresh_progress)
	_refresh_all()
	show_tab(0)


func focus_first() -> void:
	for t in _tabs:
		if t.button_pressed:
			t.grab_focus()
			return
	if not _tabs.is_empty():
		_tabs[0].grab_focus()


func show_tab(i: int) -> void:
	i = clampi(i, 0, _pages.size() - 1)
	_cancel_capture()
	for k in range(_pages.size()):
		_pages[k].visible = k == i
		_tabs[k].set_pressed_no_signal(k == i)
	_scroll.scroll_vertical = 0
	if is_inside_tree():
		_pages[i].modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_pages[i], "modulate:a", 1.0, 0.18)
	if i == 3:
		_refresh_controls()
	if i == 4:
		_refresh_progress()


# ================================================================================================
# construction
# ================================================================================================
func _build() -> void:
	var outer := UIKit.vbox(16)
	add_child(UIKit.with_margin(outer, 12))
	# header
	var head := UIKit.hbox(14)
	head.add_child(_Gear.new())
	head.add_child(UIKit.title_label("Settings"))
	outer.add_child(head)
	# tab strip (dark pill so the white tab buttons read on the cream card)
	var strip := PanelContainer.new()
	strip.theme_type_variation = &"PillPanel"
	var strip_sb: StyleBoxFlat = (UITheme.build().get_stylebox("panel", "PillPanel") as StyleBoxFlat).duplicate()
	strip_sb.bg_color = Color(0.1686, 0.2275, 0.3333, 0.94)
	strip_sb.set_corner_radius_all(24)
	strip_sb.content_margin_left = 8
	strip_sb.content_margin_right = 8
	strip_sb.content_margin_top = 6
	strip_sb.content_margin_bottom = 6
	strip.add_theme_stylebox_override("panel", strip_sb)
	var tab_row := UIKit.hbox(6)
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_child(tab_row)
	var group := ButtonGroup.new()
	for i in range(TAB_NAMES.size()):
		var tb := UIKit.tab_button(TAB_NAMES[i])
		tb.button_group = group
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.custom_minimum_size = Vector2(0, 50)
		OvUtil.focusable(tb, Palette.SUN, 14)
		tb.pressed.connect(show_tab.bind(i))
		tab_row.add_child(tb)
		_tabs.append(tb)
	outer.add_child(strip)
	# pages
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 520)
	outer.add_child(_scroll)
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(holder)
	_pages.append(_build_audio())
	_pages.append(_build_display())
	_pages.append(_build_access())
	_pages.append(_build_controls())
	_pages.append(_build_progress())
	for p in _pages:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_child(p)
	# footer
	var foot := UIKit.hbox(12)
	outer.add_child(foot)
	_conflict_label = Label.new()
	_conflict_label.theme_type_variation = &"WarningLabel"
	_conflict_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_conflict_label.visible = false
	foot.add_child(_conflict_label)
	foot.add_child(UIKit.h_spacer())
	_back_btn = UIKit.primary_button(back_text)
	_back_btn.custom_minimum_size = Vector2(220, 58)
	OvUtil.focusable(_back_btn)
	_back_btn.pressed.connect(func() -> void: closed.emit())
	foot.add_child(_back_btn)


func _row(title: String, desc: String, ctrl: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"PlatePanel"
	var h := UIKit.hbox(18)
	p.add_child(h)
	var v := UIKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var tl := UIKit.header_label(title)
	OvUtil.set_font_px(tl, 23)
	v.add_child(tl)
	if desc != "":
		var dl := UIKit.small_label(desc)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(dl)
	h.add_child(v)
	if ctrl != null:
		ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ctrl)
	p.custom_minimum_size = Vector2(0, 76)
	return p


func _page() -> VBoxContainer:
	var v := UIKit.vbox(12)
	v.visible = false
	return v


func _slider_row(title: String, desc: String, key: StringName) -> PanelContainer:
	var box := UIKit.hbox(14)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.custom_minimum_size = Vector2(380, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	s.add_theme_stylebox_override("focus", OvUtil.focus_box(Palette.SUN, 10))
	s.value = float(Settings.get_value(key))
	s.value_changed.connect(_on_slider.bind(key))
	box.add_child(s)
	var pct := Label.new()
	pct.custom_minimum_size = Vector2(70, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.add_theme_font_override("font", UITheme.font_bold())
	box.add_child(pct)
	_sliders[key] = s
	_slider_value_labels[key] = pct
	return _row(title, desc, box)


func _toggle_row(title: String, desc: String, key: StringName) -> PanelContainer:
	var cb := CheckButton.new()
	cb.focus_mode = Control.FOCUS_ALL
	cb.add_theme_stylebox_override("focus", OvUtil.focus_box(Palette.SUN, 16))
	cb.button_pressed = bool(Settings.get_value(key))
	cb.toggled.connect(func(on: bool) -> void:
		Settings.set_value(key, on)
		AudioManager.play_sfx(&"ui_click"))
	cb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_toggles[key] = cb
	return _row(title, desc, cb)


func _build_audio() -> Control:
	var p := _page()
	p.add_child(_slider_row("Master volume", "Everything at once.", &"master_volume"))
	p.add_child(_slider_row("Music", "The jaunty harbour tunes.", &"music_volume"))
	p.add_child(_slider_row("Sound effects", "Splats, dings and ship horns.", &"sfx_volume"))
	var test := UIKit.hbox(10)
	for entry in [["Ding", &"coin"], ["Splat", &"mess_splat"], ["Horn", &"event_horn"], ["Cheer", &"star_3"]]:
		var b := UIKit.secondary_button(String(entry[0]))
		b.custom_minimum_size = Vector2(130, 48)
		OvUtil.focusable(b)
		var sfx: StringName = entry[1]
		b.pressed.connect(func() -> void: AudioManager.play_sfx(sfx, 0.0, 0.0))
		test.add_child(b)
	p.add_child(_row("Sound check", "Try each sound at the current volume.", test))
	var tip := UIKit.small_label("Drag a slider to hear it. Left / right arrows nudge it when focused.")
	p.add_child(tip)
	return p


func _build_display() -> Control:
	var p := _page()
	p.add_child(_toggle_row("Fullscreen", "Fill the whole screen (F11 toggles it any time).", &"fullscreen"))
	p.add_child(_toggle_row("Screen shake", "A tiny camera wobble when something breaks.", &"screen_shake"))
	return p


func _preview_row(title: String, colorblind: bool) -> PanelContainer:
	var holder := PanelContainer.new()
	var h := UIKit.hbox(10)
	holder.add_child(h)
	var tl := UIKit.header_label(title)
	OvUtil.set_font_px(tl, 22)
	tl.custom_minimum_size = Vector2(210, 0)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tl)
	for i in range(PREVIEW_ICONS.size()):
		var v := UIKit.vbox(2)
		v.custom_minimum_size = Vector2(96, 0)
		var g := GlyphView.new(PREVIEW_ICONS[i], 58.0)
		g.colorblind = colorblind
		g.custom_minimum_size = Vector2(0, 64)
		v.add_child(g)
		var nl := UIKit.small_label(PREVIEW_NAMES[i])
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nl)
		h.add_child(v)
	return holder


func _build_access() -> Control:
	var p := _page()
	p.add_child(_toggle_row("Colourblind-safe icons",
			"Swaps problem icons to a blue / orange / white / black palette. Shapes stay the same.", &"colorblind"))
	var prev := PanelContainer.new()
	prev.theme_type_variation = &"PlatePanel"
	var pv := UIKit.vbox(8)
	prev.add_child(pv)
	pv.add_child(UIKit.small_label("Live preview of problem icons"))
	_prev_row_normal = _preview_row("Standard", false)
	_prev_row_cb = _preview_row("Colourblind-safe", true)
	pv.add_child(_prev_row_normal)
	pv.add_child(_prev_row_cb)
	p.add_child(prev)
	p.add_child(_toggle_row("Tutorial hints", "Show helper tips and arrows on the first voyage.", &"show_tutorial_hints"))
	return p


func _build_controls() -> Control:
	var p := _page()
	p.add_theme_constant_override("separation", 8)
	var hint := UIKit.small_label("Click a key slot, then press the key you want. Esc cancels. Each action has two slots.")
	p.add_child(hint)
	for action in Settings.ACTIONS:
		var row := PanelContainer.new()
		row.theme_type_variation = &"PlatePanel"
		row.custom_minimum_size = Vector2(0, 58)
		var h := UIKit.hbox(8)
		row.add_child(h)
		var warn := GlyphView.new(&"warning", 28.0)
		warn.modulate.a = 0.0
		warn.tooltip_text = "Also used by another action"
		_warn_icons[action] = warn
		h.add_child(warn)
		var nl := Label.new()
		nl.text = Settings.action_display_name(action)
		nl.add_theme_font_override("font", UITheme.font_bold())
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(nl)
		for slot in range(Settings.MAX_SLOTS):
			var kb := Button.new()
			kb.focus_mode = Control.FOCUS_ALL
			kb.custom_minimum_size = Vector2(190, 44)
			kb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			kb.tooltip_text = "Click, then press a key"
			OvUtil.focusable(kb, Palette.SUN, 12)
			kb.pressed.connect(_begin_capture.bind(action, slot))
			h.add_child(kb)
			_slot_buttons["%s:%d" % [action, slot]] = kb
			var xb := Button.new()
			xb.text = "×"
			xb.custom_minimum_size = Vector2(40, 44)
			xb.tooltip_text = "Clear this key"
			xb.focus_mode = Control.FOCUS_ALL
			xb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			OvUtil.focusable(xb, Palette.SUN, 12)
			xb.pressed.connect(func() -> void:
				_cancel_capture()
				Settings.clear_binding(action, slot))
			h.add_child(xb)
			_clear_buttons["%s:%d" % [action, slot]] = xb
		p.add_child(row)
	var reset := UIKit.secondary_button("Reset controls to defaults")
	reset.custom_minimum_size = Vector2(0, 54)
	OvUtil.focusable(reset)
	reset.pressed.connect(func() -> void:
		_cancel_capture()
		Settings.reset_bindings()
		Toast.show_toast(self, "Controls reset to defaults", &"wrench"))
	p.add_child(UIKit.v_spacer(4))
	p.add_child(reset)
	return p


func _build_progress() -> Control:
	var p := _page()
	var card := PanelContainer.new()
	card.theme_type_variation = &"PlatePanel"
	var v := UIKit.vbox(10)
	card.add_child(v)
	var top := UIKit.hbox(12)
	top.add_child(GlyphView.new(&"star", 44.0))
	_stars_label = UIKit.title_label("0 / 54 stars")
	top.add_child(_stars_label)
	v.add_child(top)
	_stars_bar = UIKit.make_progress_bar(&"SunBar")
	_stars_bar.custom_minimum_size = Vector2(0, 22)
	v.add_child(_stars_bar)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	for d in SaveManager.DEST_ORDER:
		var nl := Label.new()
		nl.add_theme_font_override("font", UITheme.font_bold())
		nl.custom_minimum_size = Vector2(210, 0)
		grid.add_child(nl)
		var bar := UIKit.make_progress_bar(&"TealBar")
		bar.custom_minimum_size = Vector2(0, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
		var cl := Label.new()
		cl.add_theme_font_override("font", UITheme.font_bold())
		cl.custom_minimum_size = Vector2(190, 0)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(cl)
		_dest_labels[d] = {"name": nl, "bar": bar, "count": cl}
	v.add_child(grid)
	_cleared_label = UIKit.small_label("")
	v.add_child(_cleared_label)
	p.add_child(card)
	var reset := UIKit.danger_button("Reset progress...")
	reset.custom_minimum_size = Vector2(260, 56)
	OvUtil.focusable(reset)
	reset.pressed.connect(_ask_reset)
	p.add_child(_row("Reset progress", "Erase every star and unlock and start the campaign again. Your settings and controls are kept.", reset))
	return p


# ================================================================================================
# refresh
# ================================================================================================
func _on_settings_changed(key: StringName) -> void:
	if key == &"bindings":
		_refresh_controls()
	else:
		_refresh_all()


func _refresh_all() -> void:
	for key: StringName in _sliders.keys():
		var s: HSlider = _sliders[key]
		var v: float = float(Settings.get_value(key))
		if not is_equal_approx(s.value, v):
			s.set_value_no_signal(v)
		(_slider_value_labels[key] as Label).text = "%d%%" % int(round(v * 100.0))
	for key: StringName in _toggles.keys():
		var cb: CheckButton = _toggles[key]
		cb.set_pressed_no_signal(bool(Settings.get_value(key)))
	if _prev_row_normal != null:
		var on: bool = Settings.colorblind
		_style_preview(_prev_row_normal, not on)
		_style_preview(_prev_row_cb, on)


func _style_preview(row: PanelContainer, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(14)
	sb.anti_aliasing = true
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if active:
		sb.bg_color = Color(1, 1, 1, 0.85)
		sb.border_color = Palette.CORAL
		sb.set_border_width_all(3)
	else:
		sb.bg_color = Color(1, 1, 1, 0.0)
		sb.border_color = Color(0, 0, 0, 0.0)
		sb.set_border_width_all(3)
	row.add_theme_stylebox_override("panel", sb)
	row.modulate = Color.WHITE if active else Color(1, 1, 1, 0.7)


func _on_slider(v: float, key: StringName) -> void:
	Settings.set_value(key, v)
	(_slider_value_labels[key] as Label).text = "%d%%" % int(round(v * 100.0))
	var now: int = Time.get_ticks_msec()
	if key != &"music_volume" and now - _last_preview_ms > 140:
		_last_preview_ms = now
		AudioManager.play_sfx(&"coin", 0.0, 0.0)


func _refresh_controls() -> void:
	var conflict_msg: String = ""
	for action in Settings.ACTIONS:
		var binds: Array[InputEvent] = Settings.get_bindings(action)
		var warn_row: bool = false
		for slot in range(Settings.MAX_SLOTS):
			var key: String = "%s:%d" % [action, slot]
			var kb: Button = _slot_buttons[key]
			var xb: Button = _clear_buttons[key]
			if _cap_action == action and _cap_slot == slot:
				continue
			if slot < binds.size():
				kb.text = Settings.event_display_text(binds[slot])
				xb.disabled = false
				xb.modulate.a = 1.0
				var cf: Array[StringName] = Settings.find_conflicts(binds[slot], action)
				if not cf.is_empty():
					warn_row = true
					if conflict_msg == "":
						conflict_msg = "'%s' is used by both %s and %s." % [kb.text,
								Settings.action_display_name(action), Settings.action_display_name(cf[0])]
			else:
				kb.text = "-"
				xb.disabled = true
				xb.modulate.a = 0.35
			kb.theme_type_variation = &""
		(_warn_icons[action] as GlyphView).modulate.a = 1.0 if warn_row else 0.0
	_conflict_label.visible = conflict_msg != ""
	_conflict_label.text = conflict_msg


func _refresh_progress() -> void:
	if _stars_label == null:
		return
	var total: int = SaveManager.total_stars()
	var max_total: int = maxi(ContentDB.campaign().size() * 3, 1)
	_stars_label.text = "%d / %d stars" % [total, max_total]
	_stars_bar.value = float(total) / float(max_total)
	var cleared: int = 0
	for lv in ContentDB.campaign():
		if SaveManager.stars_for(lv.id) >= 1:
			cleared += 1
	_cleared_label.text = "%d of %d levels cleared" % [cleared, ContentDB.campaign().size()]
	for d: StringName in SaveManager.DEST_ORDER:
		var def: DestinationDef = ContentDB.destination(d)
		var nm: String = def.display_name if def != null else String(d)
		var n_levels: int = maxi(ContentDB.levels_for(d).size(), 1)
		var row: Dictionary = _dest_labels[d]
		(row["name"] as Label).text = nm
		(row["bar"] as ProgressBar).value = float(SaveManager.stars_in_destination(d)) / float(n_levels * 3)
		var cnt: String = "%d / %d" % [SaveManager.stars_in_destination(d), n_levels * 3]
		if not SaveManager.is_destination_unlocked(d):
			cnt = "locked (needs %d)" % SaveManager.stars_required(d)
		(row["count"] as Label).text = cnt


func _ask_reset() -> void:
	var dlg := ConfirmDialog.present(self, "Reset all progress?",
			"Every star, best score and unlock will be erased. Your settings and key bindings stay. This cannot be undone.",
			"Reset everything", "Keep my stars", true)
	dlg.confirmed.connect(func(ok: bool) -> void:
		if ok:
			SaveManager.reset_progress()
			Toast.show_toast(self, "Progress reset", &"star")
		else:
			_tabs[4].grab_focus())


# ================================================================================================
# key capture
# ================================================================================================
func _begin_capture(action: StringName, slot: int) -> void:
	_cancel_capture()
	_cap_action = action
	_cap_slot = slot
	var kb: Button = _slot_buttons["%s:%d" % [action, slot]]
	kb.text = "Press a key..."
	kb.theme_type_variation = &"PrimaryButton"
	if _cap_tween != null:
		_cap_tween.kill()
	_cap_tween = kb.create_tween().set_loops()
	_cap_tween.tween_property(kb, "modulate:a", 0.65, 0.45)
	_cap_tween.tween_property(kb, "modulate:a", 1.0, 0.45)


func _cancel_capture() -> void:
	if _cap_action == &"":
		return
	var kb: Button = _slot_buttons["%s:%d" % [_cap_action, _cap_slot]]
	if _cap_tween != null:
		_cap_tween.kill()
	kb.modulate.a = 1.0
	kb.theme_type_variation = &""
	_cap_action = &""
	_cap_slot = -1
	_refresh_controls()


func is_capturing() -> bool:
	return _cap_action != &""


func _input(event: InputEvent) -> void:
	if _cap_action == &"" or not is_visible_in_tree():
		return
	if event is InputEventKey:
		var k: InputEventKey = event
		if not k.pressed or k.echo:
			get_viewport().set_input_as_handled()
			return
		var code: Key = k.keycode
		if code == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_cancel_capture()
			return
		if code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]:
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		_commit_capture(event)
	elif event is InputEventMouseButton:
		var m: InputEventMouseButton = event
		if not m.pressed:
			return
		if m.button_index == MOUSE_BUTTON_LEFT:
			_cancel_capture()  # let the click carry on (it may start another capture)
			return
		if m.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return
		get_viewport().set_input_as_handled()
		_commit_capture(event)


func _commit_capture(event: InputEvent) -> void:
	var action: StringName = _cap_action
	var slot: int = _cap_slot
	var conflicts: Array[StringName] = Settings.find_conflicts(event, action)
	if _cap_tween != null:
		_cap_tween.kill()
	var kb: Button = _slot_buttons["%s:%d" % [action, slot]]
	kb.modulate.a = 1.0
	kb.theme_type_variation = &""
	_cap_action = &""
	_cap_slot = -1
	Settings.rebind(action, event, slot)  # emits changed(&"bindings") -> refresh
	_refresh_controls()
	if not conflicts.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for c in conflicts:
			names.append(Settings.action_display_name(c))
		_conflict_label.text = "'%s' is also used by %s." % [Settings.event_display_text(event), " and ".join(names)]
		_conflict_label.visible = true
	# a little pop on the freshly bound slot
	kb.pivot_offset = kb.size * 0.5
	kb.scale = Vector2(1.12, 1.12)
	kb.create_tween().tween_property(kb, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or is_capturing() or event is InputEventMouseButton:
		return
	if event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


class _Gear extends Control:
	var _t: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(44, 44)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r_out: float = 20.0
		var r_in: float = 15.0
		var teeth: int = 8
		var pts := PackedVector2Array()
		var rot: float = _t * 0.35
		for i in range(teeth):
			var a: float = rot + float(i) * TAU / float(teeth)
			var step: float = TAU / float(teeth)
			pts.append(c + Vector2(cos(a - step * 0.22), sin(a - step * 0.22)) * r_in)
			pts.append(c + Vector2(cos(a - step * 0.13), sin(a - step * 0.13)) * r_out)
			pts.append(c + Vector2(cos(a + step * 0.13), sin(a + step * 0.13)) * r_out)
			pts.append(c + Vector2(cos(a + step * 0.22), sin(a + step * 0.22)) * r_in)
		draw_colored_polygon(pts, Palette.NAVY_LIGHT)
		ArtUtil.circ(self, c, 12.5, Palette.NAVY_LIGHT)
		ArtUtil.circ(self, c, 6.0, Color("FFF8EC"))
