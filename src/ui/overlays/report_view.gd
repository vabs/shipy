class_name ReportView
extends PanelContainer
## "Voyage report" card shown from the results panel (docs/SPEC.md §13.2): one row per guest room with busy bar, queue,
## visits and a coloured verdict chip (Overloaded / Unreliable / Idle / OK), up to three captain's tips and a rating sparkline.
##
##   var rv := ReportView.new()
##   rv.back_pressed.connect(...); rv.heatmap_pressed.connect(...)
##   rv.setup(report: Dictionary, result: Dictionary, level: LevelDef)
## `report` is VoyageTelemetry.report() (result["report"]). Colours follow Settings.colorblind (Okabe-Ito set).

signal back_pressed
signal heatmap_pressed

const TAG_ORDER: Array[StringName] = [&"overloaded", &"unreliable", &"idle", &"ok"]
const ROW_H: float = 50.0
const LIST_MAX_H: float = 520.0

var _report: Dictionary = {}
var _result: Dictionary = {}
var _level: LevelDef = null
var _cb: bool = false
var _back_btn: Button
var _spark: _Sparkline = null


# ---------------------------------------------------------------------------------------------
class _Sparkline extends Control:
	var values: Array[float] = []
	var duration: float = 180.0
	var goals: Array[float] = []
	var line_color: Color = Palette.TEAL
	var reveal: float = 1.0:
		set(v):
			reveal = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(380, 170)

	func _draw() -> void:
		var pad_l: float = 38.0
		var pad_r: float = 14.0
		var pad_t: float = 12.0
		var pad_b: float = 28.0
		var area := Rect2(pad_l, pad_t, size.x - pad_l - pad_r, size.y - pad_t - pad_b)
		ArtUtil.rr(self, Rect2(0, 0, size.x, size.y), 12.0, Color("FBF4E4"))
		var font: Font = UITheme.font()
		# grid
		for v in [0, 25, 50, 75, 100]:
			var y: float = area.end.y - area.size.y * float(v) / 100.0
			ArtUtil.line(self, Vector2(area.position.x, y), Vector2(area.end.x, y), Color(0.42, 0.47, 0.58, 0.18), 1.5)
			self.draw_string(font, Vector2(4, y + 5), "%d" % v, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.42, 0.47, 0.58, 0.9))
		# star goals as dashed lines
		for g in goals:
			var gy: float = area.end.y - area.size.y * clampf(g, 0.0, 100.0) / 100.0
			var x: float = area.position.x
			while x < area.end.x:
				ArtUtil.line(self, Vector2(x, gy), Vector2(minf(x + 7.0, area.end.x), gy), Color(Palette.SUN_DEEP.r, Palette.SUN_DEEP.g, Palette.SUN_DEEP.b, 0.9), 2.0)
				x += 13.0
			IconArt.draw_icon(self, &"star", Vector2(area.end.x - 8.0, gy - 9.0), 15.0)
		# axis labels
		var total: float = maxf(duration, 1.0)
		for f in [0.0, 0.5, 1.0]:
			var tx: float = area.position.x + area.size.x * f
			var label: String = OvUtil.time_text(total * f)
			var al: int = HORIZONTAL_ALIGNMENT_CENTER
			self.draw_string(font, Vector2(tx - 30.0, size.y - 7.0), label, al, 60.0, 14, Color(0.42, 0.47, 0.58, 0.9))
		if values.size() < 2:
			return
		var pts := PackedVector2Array()
		var n: int = values.size()
		var shown: float = clampf(reveal, 0.0, 1.0) * float(n - 1)
		for i in range(n):
			if float(i) > shown + 0.0001:
				break
			var fx: float = float(i) / float(n - 1)
			pts.append(Vector2(area.position.x + area.size.x * fx, area.end.y - area.size.y * clampf(values[i], 0.0, 100.0) / 100.0))
		if float(n - 1) > shown and shown > 0.0:
			var i0: int = int(floor(shown))
			var i1: int = mini(i0 + 1, n - 1)
			var fr: float = shown - float(i0)
			var vv: float = lerpf(values[i0], values[i1], fr)
			var fxx: float = shown / float(n - 1)
			pts.append(Vector2(area.position.x + area.size.x * fxx, area.end.y - area.size.y * clampf(vv, 0.0, 100.0) / 100.0))
		if pts.size() < 2:
			return
		# soft fill under the line
		var top_c := Color(line_color.r, line_color.g, line_color.b, 0.32)
		var bot_c := Color(line_color.r, line_color.g, line_color.b, 0.02)
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			self.draw_primitive(PackedVector2Array([a, b, Vector2(b.x, area.end.y), Vector2(a.x, area.end.y)]),
					PackedColorArray([top_c, top_c, bot_c, bot_c]), PackedVector2Array())
		ArtUtil.pline(self, pts, Palette.shade(line_color, 0.3), 5.0)
		ArtUtil.pline(self, pts, line_color, 3.5)
		var last: Vector2 = pts[pts.size() - 1]
		ArtUtil.circ(self, last, 7.5, Color.WHITE)
		ArtUtil.circ(self, last, 5.0, line_color)
		if reveal >= 0.999:
			var txt: String = "%d%%" % int(round(values[n - 1]))
			var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			var lx: float = clampf(last.x - tw * 0.5, area.position.x, size.x - tw - 4.0)
			var ly: float = last.y - 14.0 if last.y > area.position.y + 24.0 else last.y + 26.0
			ArtUtil.text_outlined(self, txt, Vector2(lx, ly), 18, Palette.INK, Color(1, 1, 1, 0.9))


# ---------------------------------------------------------------------------------------------
func setup(report: Dictionary, result: Dictionary, level: LevelDef) -> void:
	_report = report
	_result = result
	_level = level
	_cb = Settings.colorblind
	theme = UITheme.build()
	custom_minimum_size = Vector2(1280, 0)
	var outer := UIKit.vbox(12)
	add_child(UIKit.with_margin(outer, 10))
	outer.add_child(_header())
	var body := UIKit.hbox(22)
	outer.add_child(body)
	body.add_child(_rooms_column())
	body.add_child(_side_column())


func back_button() -> Button:
	return _back_btn


func _header() -> Control:
	var h := UIKit.hbox(16)
	_back_btn = UIKit.secondary_button("Back to results")
	_back_btn.custom_minimum_size = Vector2(230, 56)
	OvUtil.focusable(_back_btn)
	_back_btn.pressed.connect(func() -> void: back_pressed.emit())
	h.add_child(_back_btn)
	var tv := UIKit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	var sub := UIKit.small_label("")
	if _level != null:
		sub.text = "LEVEL %d   -   %s" % [_level.campaign_index, _level.display_name.to_upper()]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(sub)
	var title := Label.new()
	title.text = "Voyage report"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UITheme.font_bold())
	title.add_theme_font_size_override("font_size", 46)
	tv.add_child(title)
	h.add_child(tv)
	var hm := UIKit.sun_button("Show heatmap")
	hm.custom_minimum_size = Vector2(230, 56)
	OvUtil.focusable(hm)
	hm.pressed.connect(func() -> void: heatmap_pressed.emit())
	h.add_child(hm)
	return h


func _plate() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"PlatePanel"
	return p


# ---- rooms --------------------------------------------------------------------------------------
func _rooms_column() -> Control:
	var plate := _plate()
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(6)
	plate.add_child(v)
	var rooms: Array = _report.get("rooms", [])
	var head := UIKit.hbox(10)
	head.add_child(_col_label("ROOMS  (%d)" % rooms.size(), 262, HORIZONTAL_ALIGNMENT_LEFT, 44))
	head.add_child(_col_label("BUSY", 118))
	head.add_child(_col_label("QUEUE", 64))
	head.add_child(_col_label("VISITS", 64))
	head.add_child(_col_label("VERDICT", 130, HORIZONTAL_ALIGNMENT_LEFT))
	v.add_child(head)
	v.add_child(HSeparator.new())
	var sorted: Array = rooms.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: int = TAG_ORDER.find(StringName(a["tag"]))
		var tb: int = TAG_ORDER.find(StringName(b["tag"]))
		if ta != tb:
			return ta < tb
		if int(a["deck"]) != int(b["deck"]):
			return int(a["deck"]) > int(b["deck"])
		return int(a["x"]) < int(b["x"]))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UIKit.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for row: Dictionary in sorted:
		list.add_child(_room_row(row))
	if sorted.is_empty():
		var none := UIKit.small_label("No guest rooms on this ship.")
		list.add_child(none)
	var rows_h: float = minf(float(maxi(sorted.size(), 1)) * (ROW_H + 4.0), LIST_MAX_H)
	scroll.custom_minimum_size = Vector2(0, rows_h)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	# colour legend
	var legend := UIKit.hbox(14)
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	for tag in TAG_ORDER:
		var lh := UIKit.hbox(6)
		var dot := _Dot.new()
		dot.color = tag_color(tag, _cb)
		lh.add_child(dot)
		var ll := UIKit.small_label(_tag_hint(tag))
		ll.add_theme_font_size_override("font_size", 15)
		lh.add_child(ll)
		legend.add_child(lh)
	v.add_child(legend)
	return plate


func _tag_hint(tag: StringName) -> String:
	match tag:
		&"overloaded": return "queue 2+ or 3 gave up"
		&"unreliable": return "broken 20%+"
		&"idle": return "barely used"
	return "fine"


func _col_label(text: String, w: float, align: int = HORIZONTAL_ALIGNMENT_CENTER, indent: float = 0.0) -> Control:
	var l := UIKit.small_label(text)
	l.add_theme_font_size_override("font_size", 15)
	l.horizontal_alignment = align
	l.custom_minimum_size = Vector2(w, 0)
	if indent > 0.0:
		var box := UIKit.hbox(0)
		box.add_child(UIKit.h_spacer(indent, false))
		l.custom_minimum_size = Vector2(w - indent, 0)
		box.add_child(l)
		return box
	return l


class _Dot extends Control:
	var color: Color = Palette.MINT

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(16, 22)

	func _draw() -> void:
		ArtUtil.circ(self, size * 0.5, 6.5, color)


## Chip colour per verdict (Okabe-Ito based when colour-blind mode is on).
static func tag_color(tag: StringName, cb: bool) -> Color:
	if cb:
		match tag:
			&"overloaded": return Color("D55E00")
			&"unreliable": return Color("E69F00")
			&"idle": return Color("56B4E9")
		return Color("009E73")
	match tag:
		&"overloaded": return Palette.CORAL
		&"unreliable": return Palette.SUN_DEEP
		&"idle": return Palette.LILAC_DARK
	return Palette.MINT_DARK


func _room_row(row: Dictionary) -> Control:
	var tag: StringName = StringName(row["tag"])
	var pc := PanelContainer.new()
	var sb := UITheme.flat(Color(1, 1, 1, 0.55) if tag == &"ok" else Color(1, 1, 1, 0.9), 12, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(10, 4, 10, 4))
	if tag != &"ok":
		sb.border_color = tag_color(tag, _cb)
		sb.border_width_left = 6
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(0, ROW_H)
	var h := UIKit.hbox(10)
	pc.add_child(h)
	var icon := GlyphView.new(StringName(row["id"]), 36.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var nv := UIKit.vbox(-2)
	nv.custom_minimum_size = Vector2(212, 0)
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	var nl := Label.new()
	nl.text = String(row["name"])
	nl.add_theme_font_override("font", UITheme.font_bold())
	nl.add_theme_font_size_override("font_size", 21)
	nv.add_child(nl)
	var dl := UIKit.small_label(_deck_text(int(row["deck"])))
	dl.add_theme_font_size_override("font_size", 14)
	nv.add_child(dl)
	h.add_child(nv)
	var bar := UIKit.make_progress_bar(&"TealBar")
	bar.custom_minimum_size = Vector2(118, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var util: float = clampf(float(row["util"]), 0.0, 1.0)
	bar.value = util
	bar.tooltip_text = "%d%% of the places were in use on average" % int(round(util * 100.0))
	h.add_child(bar)
	var q: float = float(row["avg_queue"])
	var ql := Label.new()
	ql.text = "%.1f" % q
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ql.custom_minimum_size = Vector2(64, 0)
	ql.add_theme_font_override("font", UITheme.font_bold())
	ql.add_theme_color_override("font_color", tag_color(&"overloaded", _cb) if q >= VoyageTelemetry.OVERLOADED_QUEUE else UITheme.TEXT_INK)
	ql.tooltip_text = "Average number of guests waiting in line"
	h.add_child(ql)
	var ul := Label.new()
	ul.text = "%d" % int(row["uses"])
	ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ul.custom_minimum_size = Vector2(64, 0)
	h.add_child(ul)
	h.add_child(_chip(row, tag))
	return pc


func _deck_text(deck: int) -> String:
	var decks: int = int(_report.get("decks", 0))
	if decks > 1 and deck >= decks - 1:
		return "Top deck"
	return "Deck %d" % (deck + 1)


func _chip(row: Dictionary, tag: StringName) -> Control:
	var c := PanelContainer.new()
	var col: Color = tag_color(tag, _cb)
	var sb := UITheme.flat(col, 14, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(12, 2, 12, 5))
	sb.border_width_bottom = 3
	sb.border_color = Palette.shade(col, 0.25)
	c.add_theme_stylebox_override("panel", sb)
	c.custom_minimum_size = Vector2(130, 0)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = VoyageTelemetry.tag_text(tag)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UITheme.font_bold())
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Palette.INK if tag == &"unreliable" else Color.WHITE)
	c.add_child(l)
	var tip: String = ""
	match tag:
		&"overloaded": tip = "Queue averaged %.1f guests, %d gave up waiting" % [float(row["avg_queue"]), int(row["patience_outs"])]
		&"unreliable": tip = "Broken %d%% of the voyage" % int(round(float(row["broken_frac"]) * 100.0))
		&"idle": tip = "Hardly used: %d visits" % int(row["uses"])
		_: tip = "Working well"
	c.tooltip_text = tip
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	return c


# ---- tips + sparkline ---------------------------------------------------------------------------
func _side_column() -> Control:
	var v := UIKit.vbox(12)
	v.custom_minimum_size = Vector2(418, 0)
	# tips
	var tp := _plate()
	var tv := UIKit.vbox(10)
	tp.add_child(tv)
	tv.add_child(UIKit.small_label("CAPTAIN'S TIPS"))
	var tips: Array = _report.get("tips", [])
	if tips.is_empty():
		tips = ["Nothing stood out. Aim for the next star goal."]
	for i in range(tips.size()):
		var th := UIKit.hbox(10)
		var num := _TipNum.new()
		num.number = i + 1
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		th.add_child(num)
		var tl := Label.new()
		tl.text = String(tips[i])
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.custom_minimum_size = Vector2(340, 0)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.add_theme_font_size_override("font_size", 20)
		th.add_child(tl)
		tv.add_child(th)
	v.add_child(tp)
	# rating sparkline
	var rp := _plate()
	var rv := UIKit.vbox(8)
	rp.add_child(rv)
	var rh := UIKit.hbox(8)
	rh.add_child(UIKit.small_label("RATING OVER THE VOYAGE"))
	rv.add_child(rh)
	var sp := _Sparkline.new()
	var curve: Array = _report.get("rating_curve", [])
	for f in curve:
		sp.values.append(float(f))
	sp.duration = float(_report.get("duration", 0.0))
	if _level != null:
		for g: Dictionary in _level.star_goals:
			if String(g.get("type", "")) == "rating":
				sp.goals.append(float(g.get("value", 0)))
	sp.line_color = Palette.TEAL if not _cb else Color("0072B2")
	rv.add_child(sp)
	var cap := UIKit.small_label("Dashed lines mark your rating goals.")
	cap.add_theme_font_size_override("font_size", 15)
	rv.add_child(cap)
	v.add_child(rp)
	_spark = sp
	v.add_child(_glance())
	return v


## Four headline numbers from the result next to the verdicts.
func _glance() -> Control:
	var p := _plate()
	var v := UIKit.vbox(6)
	p.add_child(v)
	v.add_child(UIKit.small_label("AT A GLANCE"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	var spawned: int = int(_result.get("problems_spawned", 0))
	var handled: int = int(_result.get("problems_handled", 0))
	var items: Array = [
		["Guests", "%d" % int(_result.get("guests_total", 0))],
		["Room visits", "%d" % int(_result.get("served", 0))],
		["Guests lost", "%d" % int(_result.get("guests_lost", 0))],
		["Problems handled", "%d / %d" % [handled, spawned] if spawned > 0 else "none"],
	]
	for it in items:
		var kl := UIKit.small_label(String(it[0]))
		kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(kl)
		var vl := Label.new()
		vl.text = String(it[1])
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.add_theme_font_override("font", UITheme.font_bold())
		grid.add_child(vl)
	v.add_child(grid)
	return p


class _TipNum extends Control:
	var number: int = 1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(34, 34)

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		ArtUtil.circ(self, c + Vector2(0, 2), 15.0, Color(0.1, 0.14, 0.26, 0.2))
		ArtUtil.circ(self, c, 15.0, Palette.shade(Palette.TEAL, 0.3))
		ArtUtil.circ(self, c + Vector2(0, -1.0), 14.0, Palette.TEAL)
		ArtUtil.text(self, str(number), Vector2(0, c.y + 8.0), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)


## Plays the sparkline draw-on animation (call when the view becomes visible).
func play_reveal() -> void:
	if _spark == null:
		return
	_spark.reveal = 0.0
	var tw := create_tween()
	tw.tween_property(_spark, "reveal", 1.0, 1.1).set_delay(0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
