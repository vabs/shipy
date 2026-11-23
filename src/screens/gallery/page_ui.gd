extends Control
## Gallery page "ui": theme sampler composed like a real port screen (top bar, build cards, widgets).

const U := preload("res://src/render/art/art_util.gd")

var _dest: StringName = &"med"


class Backdrop extends Control:
	var dest: StringName = &"med"
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if size.x < 100.0:
			return
		var pd := Palette.dest(dest)
		var h := size.y
		var horizon := h * 0.62
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, horizon), Vector2(0, horizon)]),
				PackedColorArray([pd["sky_top"], pd["sky_top"], pd["sky_bottom"], pd["sky_bottom"]]))
		draw_polygon(PackedVector2Array([Vector2(0, horizon), Vector2(size.x, horizon), Vector2(size.x, h), Vector2(0, h)]),
				PackedColorArray([pd["sea_top"], pd["sea_top"], pd["sea_bottom"], pd["sea_bottom"]]))
		# soft clouds
		for i in range(6):
			var cx := fposmod(float(i) * 380.0 + _t * 8.0, size.x + 300.0) - 150.0
			var cy := 150.0 + float(i % 3) * 70.0
			U.ellipse(self, Vector2(cx, cy), 90, 22, Color(1, 1, 1, 0.55))
			U.ellipse(self, Vector2(cx + 40, cy - 16), 50, 24, Color(1, 1, 1, 0.55))
		# waves
		for k in range(3):
			var wy := horizon + 40.0 + float(k) * 90.0
			var pts := PackedVector2Array()
			for x in range(0, int(size.x) + 40, 40):
				pts.append(Vector2(x, wy + sin(float(x) * 0.02 + _t * (1.0 + k * 0.3)) * 5.0))
			draw_polyline(pts, Color(1, 1, 1, 0.14), 3.0, true)


func setup(dest: StringName) -> void:
	_dest = dest


func _ready() -> void:
	# Fill the viewport regardless of the parent's layout state.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	theme = UITheme.build()
	var bd := Backdrop.new()
	bd.dest = _dest
	bd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bd)
	_build_top_bar()
	_build_middle()
	_build_bottom_bar()


# ---- top bar ---------------------------------------------------------------------------------
func _build_top_bar() -> void:
	var bar := UIKit.navy_bar()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 92.0
	add_child(bar)
	var hb := UIKit.hbox(22)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(hb)

	var money := UIKit.stat_pill(&"coin", "$12,450")
	money.custom_minimum_size = Vector2(190, 48)
	hb.add_child(money)

	var lv := UIKit.vbox(0)
	var l1 := Label.new()
	l1.text = "Sunny Shores 3"
	l1.theme_type_variation = &"OnDarkTitle"
	l1.add_theme_font_size_override("font_size", 26)
	var l2 := Label.new()
	l2.text = "Mediterranean  -  Port"
	l2.theme_type_variation = &"OnDarkSmall"
	lv.add_child(l1)
	lv.add_child(l2)
	hb.add_child(lv)

	var vp := UIKit.make_voyage_progress()
	vp.value = 0.58
	vp.custom_minimum_size = Vector2(430, 48)
	hb.add_child(vp)

	var meter := UIKit.make_meter()
	meter.value = 71.0
	meter.custom_minimum_size = Vector2(400, 48)
	hb.add_child(meter)

	var stars := UIKit.stat_pill(&"star", "14 / 54")
	stars.custom_minimum_size = Vector2(150, 48)
	hb.add_child(stars)

	var sp := UIKit.h_spacer(0.0, true)
	hb.add_child(sp)
	var group := ButtonGroup.new()
	for entry in [[&"pause", "Pause"], [&"play", "1x"], [&"fast", "2x"], [&"faster", "3x"]]:
		var b := UIKit.icon_button(entry[0], entry[1], 52.0, true)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = entry[0] == &"fast"
		hb.add_child(b)


# ---- middle ----------------------------------------------------------------------------------
func _sample_state(variation: StringName, state: String, label_text: String) -> Control:
	var pc := PanelContainer.new()
	var sb: StyleBox = UITheme.build().get_stylebox(state, variation).duplicate()
	pc.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = label_text
	l.theme_type_variation = &"OnDarkSmall"
	l.add_theme_font_size_override("font_size", 19)
	var tc: Color = UITheme.build().get_color("font_disabled_color" if state == "disabled" else "font_color", variation)
	l.add_theme_color_override("font_color", tc)
	l.add_theme_font_override("font", UITheme.font_bold())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	return pc


func _heading(text: String) -> Label:
	var l := UIKit.header_label(text)
	return l


func _build_middle() -> void:
	var row := UIKit.hbox(26)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 44.0
	row.offset_right = -44.0
	row.offset_top = 124.0
	row.offset_bottom = -392.0
	add_child(row)
	row.add_child(_buttons_card())
	row.add_child(_controls_card())
	row.add_child(_crew_card())


func _buttons_card() -> Control:
	var card := UIKit.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(14)
	card.add_child(v)
	v.add_child(_heading("Buttons"))
	var r1 := UIKit.hbox(14)
	r1.add_child(UIKit.primary_button("Set Sail!"))
	r1.add_child(UIKit.secondary_button("Hire Staff"))
	r1.add_child(UIKit.sun_button("Upgrade"))
	v.add_child(r1)
	var r2 := UIKit.hbox(14)
	r2.add_child(UIKit.danger_button("Sell +$90"))
	var neutral := Button.new()
	neutral.text = "Cancel"
	neutral.focus_mode = Control.FOCUS_NONE
	r2.add_child(neutral)
	var dis := UIKit.primary_button("Locked")
	dis.disabled = true
	r2.add_child(dis)
	v.add_child(r2)
	# states
	var lab := UIKit.small_label("Primary states: normal / hover / pressed / disabled")
	v.add_child(lab)
	var st := UIKit.hbox(12)
	for s in [["normal", "Normal"], ["hover", "Hover"], ["pressed", "Pressed"], ["disabled", "Off"]]:
		var sample := _sample_state(&"PrimaryButton", s[0], s[1])
		sample.custom_minimum_size = Vector2(110, 0)
		st.add_child(sample)
	v.add_child(st)
	var st2 := UIKit.hbox(12)
	for s in [["normal", "Normal"], ["hover", "Hover"], ["pressed", "Pressed"], ["disabled", "Off"]]:
		var sample2 := _sample_state(&"SecondaryButton", s[0], s[1])
		sample2.custom_minimum_size = Vector2(110, 0)
		st2.add_child(sample2)
	v.add_child(st2)
	# icon buttons
	v.add_child(UIKit.small_label("Icon buttons"))
	var ib := UIKit.hbox(12)
	for ic in [&"wrench", &"mop", &"star", &"clock", &"warning", &"lock"]:
		ib.add_child(UIKit.icon_button(ic, String(ic).capitalize(), 56.0))
	v.add_child(ib)
	# ghost on navy
	var navy := UIKit.navy_bar()
	var nb := UIKit.hbox(8)
	navy.add_child(nb)
	nb.add_child(UIKit.ghost_button("Staff"))
	nb.add_child(UIKit.ghost_button("Manifest"))
	nb.add_child(UIKit.ghost_button("Utilities"))
	var tgl := UIKit.tab_button("Fun")
	tgl.button_pressed = true
	nb.add_child(tgl)
	nb.add_child(UIKit.tab_button("Food"))
	v.add_child(navy)
	return card


func _controls_card() -> Control:
	var card := UIKit.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(12)
	card.add_child(v)
	v.add_child(_heading("Controls"))
	for entry in [["Music", 0.7], ["Effects", 0.45]]:
		var r := UIKit.hbox(14)
		var l := Label.new()
		l.text = entry[0]
		l.custom_minimum_size = Vector2(110, 0)
		r.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.01
		s.value = entry[1]
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(s)
		v.add_child(r)
	var cb1 := CheckBox.new()
	cb1.text = "Colourblind mode"
	cb1.button_pressed = true
	var cb2 := CheckBox.new()
	cb2.text = "Screen shake"
	var cb3 := CheckButton.new()
	cb3.text = "Fullscreen"
	cb3.button_pressed = true
	var cbd := CheckBox.new()
	cbd.text = "Disabled option"
	cbd.disabled = true
	var gr := GridContainer.new()
	gr.columns = 2
	gr.add_theme_constant_override("h_separation", 24)
	gr.add_child(cb1)
	gr.add_child(cb3)
	gr.add_child(cb2)
	gr.add_child(cbd)
	v.add_child(gr)
	var tb := TabBar.new()
	for n in ["Rooms", "Crew", "Stats"]:
		tb.add_tab(n)
	tb.tab_alignment = TabBar.ALIGNMENT_LEFT
	v.add_child(UIKit.with_margin(tb, 0))
	var r3 := UIKit.hbox(12)
	var ob := OptionButton.new()
	for d in ["Mediterranean", "Arctic", "Underworld"]:
		ob.add_item(d)
	ob.custom_minimum_size = Vector2(240, 0)
	r3.add_child(ob)
	var le := LineEdit.new()
	le.text = "Captain Biscuit"
	le.placeholder_text = "Captain name"
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r3.add_child(le)
	v.add_child(r3)
	v.add_child(UIKit.small_label("Utilities / meters"))
	for entry in [["Power", &"power", &"MintBar", 0.72], ["Water", &"water", &"TealBar", 0.45], ["Budget", &"coin", &"SunBar", 0.6], ["Mess", &"mess", &"CoralBar", 0.85]]:
		var r := UIKit.hbox(12)
		var iv := IconView.new()
		iv.icon = entry[1]
		iv.icon_size = 30.0
		r.add_child(iv)
		var pl := Label.new()
		pl.text = entry[0]
		pl.theme_type_variation = &"SmallLabel"
		pl.custom_minimum_size = Vector2(60, 0)
		r.add_child(pl)
		var pb := UIKit.make_progress_bar(entry[2])
		pb.value = entry[3]
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(pb)
		v.add_child(r)
	return card


func _crew_card() -> Control:
	var card := UIKit.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(12)
	card.add_child(v)
	v.add_child(_heading("Crew & Alerts"))
	var r := UIKit.hbox(14)
	var roster := [
		["Mopsy", &"janitor", &"sun_hat", Color("FFB347"), &"", false],
		["Bolt", &"mechanic", &"sun_hat", Color("FFB347"), &"", true],
		["Sunny", &"", &"sun_hat", Color("FFB347"), &"happy", false],
		["Rex", &"", &"headband", Color("6EC6A5"), &"angry", false],
		["Mia", &"", &"headphones", Color("FF7FA8"), &"need_hunger", false],
	]
	for e in roster:
		var col := UIKit.vbox(4)
		var bp := BeanPortrait.new()
		bp.portrait_size = 76.0
		bp.staff_role = e[1]
		bp.prop = e[2]
		bp.body_color = e[3]
		bp.mood = e[4]
		bp.selected = e[5]
		bp.plate_color = Color("CDEFFB") if e[1] == &"" else Color("FFE6A8")
		col.add_child(bp)
		var nl := Label.new()
		nl.text = e[0]
		nl.theme_type_variation = &"SmallLabel"
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(nl)
		r.add_child(col)
	v.add_child(r)
	# scrolling alert feed
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 170)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var lv := UIKit.vbox(8)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var alerts := [
		[&"breakdown", "Cinema broke down", "0:42"], [&"mess", "Mess near the buffet", "0:51"],
		[&"sick", "A guest feels queasy", "1:03"], [&"angry", "Rex is storming off!", "1:10"],
		[&"ghost", "A ghost wanders on deck 2", "1:21"], [&"event", "Film night begins", "1:30"],
	]
	for a in alerts:
		var pc := PanelContainer.new()
		pc.theme_type_variation = &"PlatePanel"
		var h := UIKit.hbox(12)
		var iv := IconView.new()
		iv.icon = a[0]
		iv.icon_size = 30.0
		iv.animate = true
		h.add_child(iv)
		var tl := Label.new()
		tl.text = a[1]
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tl)
		var tm := UIKit.small_label(a[2])
		h.add_child(tm)
		pc.add_child(h)
		lv.add_child(pc)
	sc.add_child(lv)
	v.add_child(sc)
	# results row
	var rr := UIKit.hbox(16)
	rr.add_child(UIKit.star_row(2, 40.0))
	var tip := PanelContainer.new()
	tip.theme_type_variation = &"TooltipPanel"
	var tl2 := Label.new()
	tl2.text = "Buffet: 3 users, 2 queued"
	tl2.theme_type_variation = &"TooltipLabel"
	tip.add_child(tl2)
	rr.add_child(tip)
	v.add_child(rr)
	return card


# ---- bottom (port build bar) ------------------------------------------------------------------
func _build_bottom_bar() -> void:
	var bar := UIKit.navy_bar_bottom()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -330.0
	add_child(bar)
	var v := UIKit.vbox(12)
	bar.add_child(v)
	var tabs := UIKit.hbox(10)
	var grp := ButtonGroup.new()
	var first := true
	for n in ["Cabins & Rest", "Food", "Fun", "Hygiene & Health", "Transport", "Utility", "Staff", "Manifest"]:
		var tb := UIKit.tab_button(n)
		tb.button_group = grp
		tb.button_pressed = n == "Fun"
		tabs.add_child(tb)
		first = false
	tabs.add_child(UIKit.h_spacer())
	var pw := UIKit.stat_pill(&"power", "14 / 26")
	var wt := UIKit.stat_pill(&"water", "11 / 24")
	tabs.add_child(pw)
	tabs.add_child(wt)
	v.add_child(tabs)

	var row := UIKit.hbox(14)
	var cards := [
		[&"bar", "Bar", 250, 3, 2, 1, false, 0],
		[&"pool", "Pool", 500, 6, 2, 5, false, 0],
		[&"cinema", "Cinema", 400, 4, 4, 0, false, 0],
		[&"gym", "Gym", 300, 3, 2, 1, false, 0],
		[&"arcade", "Arcade", 350, 3, 4, 0, false, 4],
		[&"casino", "Casino", 650, 4, 4, 1, true, 13],
		[&"stairs", "Stairs", 60, 1, 0, 0, false, 0],
	]
	for c in cards:
		row.add_child(_room_card(c))
	row.add_child(UIKit.h_spacer())
	var sail := UIKit.vbox(8)
	var warn := UIKit.small_label("Only 4 cabins for 28 guests")
	warn.theme_type_variation = &"OnDarkSmall"
	warn.add_theme_color_override("font_color", Palette.SUN)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sail.add_child(warn)
	var go := UIKit.primary_button("Set Sail!")
	go.add_theme_font_size_override("font_size", 34)
	go.custom_minimum_size = Vector2(250, 96)
	sail.add_child(go)
	UIKit.tween_pop(go)
	sail.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(sail)
	v.add_child(row)


func _room_card(c: Array) -> Control:
	var card := UIKit.card()
	card.custom_minimum_size = Vector2(196, 0)
	var v := UIKit.vbox(6)
	card.add_child(v)
	var art := RoomCardArt.new()
	art.room_id = c[0]
	art.custom_minimum_size = Vector2(172, 112)
	art.locked = c[6]
	v.add_child(art)
	var top := UIKit.hbox(6)
	var nm := Label.new()
	nm.text = c[1]
	nm.theme_type_variation = &"HeaderLabel"
	nm.add_theme_font_size_override("font_size", 24)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	if not c[6]:
		var w := UIKit.small_label("%dw" % c[3])
		top.add_child(w)
	v.add_child(top)
	if c[6]:
		var lk := UIKit.small_label("Unlocks at level %d" % c[7])
		lk.custom_minimum_size = Vector2(0, 32)
		lk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.add_child(lk)
	else:
		var r := UIKit.hbox(8)
		for entry in [[&"coin", "%d" % c[2]], [&"power", "%d" % c[4]], [&"water", "%d" % c[5]]]:
			var p := HBoxContainer.new()
			p.add_theme_constant_override("separation", 2)
			var iv := IconView.new()
			iv.icon = entry[0]
			iv.icon_size = 24.0
			p.add_child(iv)
			var l := Label.new()
			l.text = entry[1]
			l.add_theme_font_size_override("font_size", 20)
			p.add_child(l)
			r.add_child(p)
		v.add_child(r)
	return card
