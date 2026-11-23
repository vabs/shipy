class_name PortManifestPanel
extends HBoxContainer
## "Manifest" tab: guest total, wave timeline, archetype breakdown (portraits + favourite rooms),
## cabins needed vs beds built (red when short), scheduled events and star goals.

const U := preload("res://src/render/art/art_util.gd")
## EventDef.icon ids -> IconArt ids.
const EVENT_ICONS: Dictionary = {
	&"ghost": &"ghost", &"sun": &"smile", &"star": &"star", &"skull_drop": &"sick", &"film": &"need_fun",
	&"thermo": &"need_hygiene", &"bolt": &"power", &"fork": &"need_hunger", &"aurora": &"event",
}

var _port: PortState
var _beds_box: VBoxContainer
var _wave_chart: _WaveChart


## Wave timeline: a little bar per wave at its spawn time with the guest count above it.
class _WaveChart extends Control:
	var waves: Array = []
	var duration: float = 200.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 88)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ctext(text: String, pos: Vector2, size_px: int, color: Color, regular: bool) -> void:
		var f: Font = ArtUtil.font() if regular else ArtUtil.font_bold()
		var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		ArtUtil.text(self, text, Vector2(pos.x - tw * 0.5, pos.y), size_px, color, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var base_y: float = h - 20.0
		var left: float = 12.0
		var span: float = maxf(w - 24.0, 10.0)
		ArtUtil.rr(self, Rect2(left - 4.0, base_y, span + 8.0, 4.0), 2.0, Color("D9C9A6"))
		var mx: int = 1
		for wv in waves:
			mx = maxi(mx, int((wv as Dictionary).get("count", 0)))
		var last_label_x: float = -999.0
		for i in waves.size():
			var wd: Dictionary = waves[i]
			var t: float = float(wd.get("t", 0.0))
			var n: int = int(wd.get("count", 0))
			var cx: float = left + clampf(t / maxf(duration, 1.0), 0.0, 1.0) * (span - 10.0) + 6.0
			var bh: float = maxf(10.0, float(n) / float(mx) * (h - 46.0))
			var r := Rect2(cx - 8.0, base_y - bh, 16.0, bh)
			ArtUtil.rr(self, r, 6.0, Palette.TEAL_DARK)
			ArtUtil.rr(self, Rect2(r.position.x, r.position.y, r.size.x, maxf(bh - 3.0, 4.0)), 6.0, Palette.TEAL)
			ArtUtil.rr(self, Rect2(r.position.x + 3.0, r.position.y + 3.0, 4.0, maxf(bh - 10.0, 2.0)), 2.0, Color(1, 1, 1, 0.35))
			_ctext(str(n), Vector2(cx, r.position.y - 4.0), 17, Palette.INK, false)
			if cx - last_label_x >= 38.0:
				var mm: int = int(t) / 60
				var ss: int = int(t) % 60
				_ctext("%d:%02d" % [mm, ss], Vector2(cx, h - 3.0), 14, UITheme.TEXT_MUTED, true)
				last_label_x = cx


func setup(port: PortState) -> void:
	_port = port
	add_theme_constant_override("separation", 12)
	_build()
	refresh()


func _card(title: String, width: float) -> VBoxContainer:
	var c := UIKit.card()
	c.custom_minimum_size = Vector2(width, 0)
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.add_theme_stylebox_override("panel", UITheme.flat(UITheme.CARD, 16, UITheme.CARD_EDGE, 2, Color(0.05, 0.08, 0.16, 0.3), 8, Vector2(0, 4), Vector4(14, 8, 14, 8)))
	var v := UIKit.vbox(4)
	c.add_child(v)
	var t := Label.new()
	t.text = title
	t.theme_type_variation = &"HeaderLabel"
	t.add_theme_font_size_override("font_size", 22)
	v.add_child(t)
	add_child(c)
	return v


static func fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func _build() -> void:
	var lvl: LevelDef = _port.level
	# --- guests + waves ----
	var g := _card("Guests", 280.0)
	var hdr := UIKit.hbox(8)
	var gi := IconView.new()
	gi.icon = &"guest"
	gi.icon_size = 30.0
	hdr.add_child(gi)
	var gl := Label.new()
	gl.text = "%d aboard" % lvl.total_guests()
	gl.theme_type_variation = &"TitleLabel"
	gl.add_theme_font_size_override("font_size", 30)
	hdr.add_child(gl)
	hdr.add_child(UIKit.h_spacer())
	var ci := IconView.new()
	ci.icon = &"clock"
	ci.icon_size = 22.0
	hdr.add_child(ci)
	var dl := UIKit.small_label(fmt_time(lvl.duration))
	hdr.add_child(dl)
	g.add_child(hdr)
	_wave_chart = _WaveChart.new()
	_wave_chart.waves = lvl.waves
	_wave_chart.duration = lvl.duration
	_wave_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	g.add_child(_wave_chart)
	# --- archetypes ----
	var a := _card("Who's coming", 404.0)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	a.add_child(grid)
	var man: Dictionary = _port.manifest()
	var by: Dictionary = man.get("by_archetype", {})
	var ids: Array = by.keys()
	ids.sort_custom(func(x: Variant, y: Variant) -> bool: return int(by[x]) > int(by[y]))
	for k in ids:
		var arch: ArchetypeDef = ContentStore.archetype(StringName(k))
		if arch == null:
			continue
		grid.add_child(_archetype_cell(arch, int(by[k])))
	# --- beds ----
	var b := _card("Beds", 236.0)
	_beds_box = b
	# --- events ----
	var e := _card("Events", 240.0)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	e.add_child(sc)
	var ev := UIKit.vbox(5)
	ev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(ev)
	var evs: Array = lvl.scheduled_events.duplicate()
	evs.sort_custom(func(x: Variant, y: Variant) -> bool: return float((x as Dictionary).get("t", 0.0)) < float((y as Dictionary).get("t", 0.0)))
	for item in evs:
		var d: Dictionary = item
		var def: EventDef = ContentStore.event(StringName(d.get("event", &"")))
		var row := UIKit.hbox(8)
		var ic := IconView.new()
		ic.icon = EVENT_ICONS.get(def.icon, &"event") if def != null else &"event"
		ic.icon_size = 26.0
		row.add_child(ic)
		var nl := Label.new()
		nl.text = def.display_name if def != null else String(d.get("event", ""))
		nl.add_theme_font_size_override("font_size", 19)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		row.add_child(nl)
		row.add_child(UIKit.small_label(fmt_time(float(d.get("t", 0.0)))))
		if def != null:
			row.tooltip_text = def.description
			row.mouse_filter = Control.MOUSE_FILTER_PASS
		ev.add_child(row)
	if evs.is_empty():
		ev.add_child(UIKit.small_label("Smooth sailing expected."))
	if lvl.random_event_interval > 0.0:
		var more := UIKit.small_label("+ surprises along the way")
		more.add_theme_font_size_override("font_size", 16)
		ev.add_child(more)
	# --- goals ----
	var s := _card("Star goals", 276.0)
	var idx: int = 0
	for item in lvl.star_goals:
		idx += 1
		var row := UIKit.hbox(8)
		var si := IconView.new()
		si.icon = &"star"
		si.icon_size = 28.0
		row.add_child(si)
		var gl2 := Label.new()
		gl2.text = goal_text(item)
		gl2.add_theme_font_size_override("font_size", 20)
		gl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(gl2)
		s.add_child(row)


static func goal_text(goal: Dictionary) -> String:
	match String(goal.get("type", "")):
		"rating": return "Rating %d%% or more" % int(goal.get("value", 0))
		"profit": return "Earn $%d profit" % int(goal.get("value", 0))
		"no_lost_guests": return "Don't lose any guests"
		"served": return "Serve %d visits" % int(goal.get("value", 0))
	return String(goal.get("type", "?"))


func _archetype_cell(arch: ArchetypeDef, count: int) -> Control:
	var pc := PanelContainer.new()
	pc.theme_type_variation = &"PlatePanel"
	pc.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PLATE, 12, Color("E8D8BA"), 2, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(8, 5, 8, 5)))
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var loves: PackedStringArray = []
	for rid2 in arch.favorite_rooms:
		var rd2: RoomDef = ContentStore.room(rid2)
		if rd2 != null:
			loves.append(rd2.display_name)
	pc.tooltip_text = "%s\nLoves: %s\n%s" % [arch.display_name, ", ".join(loves), arch.quirk_text]
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := UIKit.hbox(8)
	pc.add_child(h)
	var bp := BeanPortrait.new()
	bp.prop = arch.prop
	bp.body_color = Palette.archetype_color(arch.id)
	bp.portrait_size = 46.0
	bp.animate = false
	h.add_child(bp)
	var v := UIKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := Label.new()
	nm.text = arch.display_name
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_font_override("font", UITheme.font_bold())
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(112, 0)
	v.add_child(nm)
	var favs := UIKit.hbox(3)
	var cnt := Label.new()
	cnt.text = "x%d" % count
	cnt.add_theme_font_size_override("font_size", 21)
	cnt.add_theme_font_override("font", UITheme.font_bold())
	cnt.add_theme_color_override("font_color", Palette.TEAL_DARK)
	cnt.custom_minimum_size = Vector2(38, 0)
	favs.add_child(cnt)
	var shown: Dictionary = {}
	for rid in arch.favorite_rooms:
		if shown.size() >= 3:
			break
		shown[rid] = true
		var badge := Control.new()
		badge.custom_minimum_size = Vector2(26, 26)
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		var rdef: RoomDef = ContentStore.room(rid)
		badge.draw.connect(func() -> void: IconArt.draw_room_icon(badge, rid, Vector2(13, 13), 24.0))
		if rdef != null:
			badge.tooltip_text = rdef.display_name
		favs.add_child(badge)
	v.add_child(favs)
	h.add_child(v)
	return pc


func refresh() -> void:
	if _port == null or _beds_box == null:
		return
	var man: Dictionary = _port.manifest()
	var beds: int = int(man.get("beds", 0))
	var guests: int = int(man.get("guests", 0))
	var built: int = int(man.get("cabins_built", 0))
	var needed: int = int(man.get("cabins_needed", 0))
	var short: bool = beds < guests
	for i in range(_beds_box.get_child_count() - 1, 0, -1):
		var c: Node = _beds_box.get_child(i)
		_beds_box.remove_child(c)
		c.queue_free()
	var top := UIKit.hbox(8)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(34, 34)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.draw.connect(func() -> void: IconArt.draw_room_icon(badge, &"cabin", Vector2(17, 17), 32.0))
	top.add_child(badge)
	var bl := Label.new()
	bl.text = "%d / %d" % [beds, guests]
	bl.theme_type_variation = &"TitleLabel"
	bl.add_theme_font_size_override("font_size", 30)
	bl.add_theme_color_override("font_color", Palette.CORAL_DARK if short else Palette.MINT_DARK)
	top.add_child(bl)
	_beds_box.add_child(top)
	var bar := UIKit.make_progress_bar(&"CoralBar" if short else &"MintBar")
	bar.value = clampf(float(beds) / maxf(float(guests), 1.0), 0.0, 1.0)
	bar.custom_minimum_size = Vector2(0, 22)
	_beds_box.add_child(bar)
	var info := Label.new()
	info.text = "%d cabin%s built, %d needed" % [built, "" if built == 1 else "s", needed]
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_color", Palette.CORAL_DARK if short else UITheme.TEXT_MUTED)
	_beds_box.add_child(info)
	if short:
		var w := Label.new()
		w.text = "Guests without a bed grow cranky."
		w.add_theme_font_size_override("font_size", 16)
		w.add_theme_color_override("font_color", Palette.CORAL_DARK)
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_beds_box.add_child(w)
