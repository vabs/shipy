class_name AlertFeed
extends PanelContainer
## Voyage alert feed (newest first): icon + short text + age. Click a row to pan the camera there.
## Resolved problems turn green and fade out; one-off notices expire. Header shows open problem counts.

signal focus_requested(local_pos: Vector2)

const MAX_ROWS: int = 4
const NOTICE_LIFE: float = 9.0
const RESOLVED_LIFE: float = 1.1

var world: SimWorld = null
var renderer: VoyageRenderer = null

var _alerts: Array[Dictionary] = []
var _rows: Array[_Row] = []
var _counts: Dictionary = {}
var _count_labels: Dictionary = {}
var _empty: Label = null
var _more: Label = null
var _check_t: float = 0.0


class _Row extends PanelContainer:
	var icon: IconView
	var text: Label
	var age: Label
	var alert: Dictionary = {}
	var feed: AlertFeed
	var hover: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(0, 28)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon = IconView.new()
		icon.icon_size = 22.0
		hb.add_child(icon)
		text = Label.new()
		text.add_theme_font_size_override("font_size", 18)
		text.add_theme_font_override("font", UITheme.font_bold())
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.clip_text = true
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(text)
		age = Label.new()
		age.add_theme_font_size_override("font_size", 16)
		age.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		age.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(age)
		add_child(hb)
		_style(false)
		mouse_entered.connect(func() -> void:
			hover = true
			_style(true))
		mouse_exited.connect(func() -> void:
			hover = false
			_style(false))

	func _style(h: bool) -> void:
		var res: bool = alert.get("resolved", false)
		var bg: Color = Color("EAF8EF") if res else (Color("FBEFD6") if h else Color("F6EAD3"))
		add_theme_stylebox_override("panel", UITheme.flat(bg, 10, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(10, 2, 10, 2)))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not alert.is_empty():
			feed.row_clicked(alert)
			accept_event()


func setup(w: SimWorld, r: VoyageRenderer) -> void:
	world = w
	renderer = r
	var v := UIKit.vbox(3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := UIKit.hbox(8)
	var title := UIKit.header_label("Alerts")
	title.add_theme_font_size_override("font_size", 20)
	head.add_child(title)
	_more = UIKit.small_label("")
	_more.add_theme_font_size_override("font_size", 15)
	head.add_child(_more)
	head.add_child(UIKit.h_spacer())
	for k in [&"mess", &"breakdown", &"sick", &"ghost"]:
		var c := UIKit.hbox(2)
		var iv := IconView.new()
		iv.icon = k
		iv.icon_size = 22.0
		c.add_child(iv)
		var l := Label.new()
		l.text = "0"
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_font_override("font", UITheme.font_bold())
		c.add_child(l)
		head.add_child(c)
		_count_labels[k] = l
		_counts[k] = c
	v.add_child(head)
	for i in MAX_ROWS:
		var row := _Row.new()
		row.feed = self
		row.visible = false
		v.add_child(row)
		_rows.append(row)
	_empty = UIKit.small_label("All quiet. Smooth sailing!")
	v.add_child(_empty)
	add_child(v)
	var sb: StyleBoxFlat = UITheme.build().get_stylebox("panel", "CardPanel").duplicate()
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	add_theme_stylebox_override("panel", sb)
	# signals
	w.mess_spawned.connect(_on_mess)
	w.room_broken.connect(_on_broken)
	w.guest_got_sick.connect(_on_sick)
	w.ghost_spawned.connect(_on_ghost)
	w.guest_stormed_off.connect(_on_storm)
	# problems that already exist (fast-forward / late bind)
	for m in w.messes:
		_on_mess(m.id)
	for r2 in w.rooms:
		if r2.broken:
			_on_broken(r2.uid)
	for g in w.guests:
		if g.sick and g.state != Guest.GONE:
			_on_sick(g.id)
	for gh in w.ghosts:
		_on_ghost(gh.id)


func _deck_name(deck: int) -> String:
	if deck >= world.grid.hull.decks - 1:
		return "the top deck"
	return "deck %d" % (deck + 1)


func _add(kind: StringName, icon: StringName, text: String, ref_kind: StringName, ref_id: int, expires: bool) -> void:
	for a in _alerts:
		if a["ref_kind"] == ref_kind and a["ref_id"] == ref_id and a["kind"] == kind and not a["resolved"]:
			return
	_alerts.push_front({"kind": kind, "icon": icon, "text": text, "ref_kind": ref_kind, "ref_id": ref_id,
			"born": world.time, "resolved": false, "resolved_at": 0.0, "expires": expires, "pos": Vector2.INF})
	if _alerts.size() > 24:
		_alerts.pop_back()


func _on_mess(id: int) -> void:
	var m: Mess = world.mess_by_id(id)
	if m == null:
		return
	var r: RoomRuntime = world.room_by_uid(m.room_uid)
	var txt: String = "Spill by the %s" % r.def.display_name if r != null else "Spill on %s" % _deck_name(m.deck)
	_add(&"mess", &"mess", txt, &"mess", id, false)
	var a: Dictionary = _alerts[0]
	a["pos"] = SimConst.to_px(m.x, float(m.deck)) + Vector2(0, -22)


func _on_broken(uid: int) -> void:
	var r: RoomRuntime = world.room_by_uid(uid)
	if r == null:
		return
	_add(&"breakdown", &"breakdown", "%s broke down!" % r.def.display_name, &"room", uid, false)


func _on_sick(gid: int) -> void:
	var g: Guest = world.guest_by_id(gid)
	if g == null:
		return
	# sick guests are grouped into one row ("3 guests feel sick") that points at the newest one
	for a in _alerts:
		if a["kind"] == &"sick" and not a["resolved"]:
			a["ids"].append(gid)
			a["ref_id"] = gid
			_alerts.erase(a)
			_alerts.push_front(a)
			return
	_add(&"sick", &"sick", "A guest feels sick", &"guest", gid, false)
	_alerts[0]["ids"] = [gid]


func _on_ghost(id: int) -> void:
	var gh: Ghost = world.ghost_by_id(id)
	if gh == null:
		return
	_add(&"ghost", &"ghost", "Ghost on %s!" % _deck_name(gh.deck), &"ghost", id, false)


func _on_storm(gid: int) -> void:
	_add(&"storm", &"angry", "A guest stormed off!", &"guest", gid, true)


func row_clicked(a: Dictionary) -> void:
	var p: Vector2 = renderer.local_pos_of(a["ref_kind"], a["ref_id"])
	if p == Vector2.INF:
		p = a["pos"]
	if p != Vector2.INF:
		focus_requested.emit(p)
		AudioManager.play_sfx(&"ui_click", 0.04, -3.0)


func _is_open(a: Dictionary) -> bool:
	match a["kind"]:
		&"mess":
			return world.mess_by_id(a["ref_id"]) != null
		&"breakdown":
			var r: RoomRuntime = world.room_by_uid(a["ref_id"])
			return r != null and r.broken
		&"ghost":
			return world.ghost_by_id(a["ref_id"]) != null
		&"sick":
			var n: int = 0
			var last: int = -1
			for gid in a["ids"]:
				var g: Guest = world.guest_by_id(gid)
				if g != null and g.sick and g.state != Guest.GONE and g.state != Guest.STORM_OFF:
					n += 1
					last = gid
			if n > 0:
				a["ref_id"] = last
				a["text"] = "A guest feels sick" if n == 1 else "%d guests feel sick" % n
			return n > 0
	return true


func refresh(delta: float) -> void:
	_check_t -= delta
	var now: float = world.time
	if _check_t <= 0.0:
		_check_t = 0.15
		var i: int = 0
		while i < _alerts.size():
			var a: Dictionary = _alerts[i]
			if not a["resolved"]:
				if a["expires"]:
					if now - float(a["born"]) > NOTICE_LIFE:
						_alerts.remove_at(i)
						continue
				elif not _is_open(a):
					a["resolved"] = true
					a["resolved_at"] = now
			elif now - float(a["resolved_at"]) > RESOLVED_LIFE:
				_alerts.remove_at(i)
				continue
			i += 1
		# counts
		var open: Dictionary = {&"mess": 0, &"breakdown": 0, &"sick": 0, &"ghost": 0}
		for a in _alerts:
			if not a["resolved"] and open.has(a["kind"]):
				open[a["kind"]] = int(open[a["kind"]]) + 1
		for k in _count_labels:
			var n: int = int(open[k])
			(_count_labels[k] as Label).text = str(n)
			(_counts[k] as Control).modulate = Color(1, 1, 1, 1) if n > 0 else Color(1, 1, 1, 0.35)
	# rows (cheap: only text/age)
	var shown: int = mini(_alerts.size(), MAX_ROWS)
	for i in MAX_ROWS:
		var row: _Row = _rows[i]
		if i >= shown:
			row.visible = false
			row.alert = {}
			continue
		var a: Dictionary = _alerts[i]
		var changed: bool = not is_same(row.alert, a) or row.text.text != a["text"] and not a["resolved"]
		row.alert = a
		row.visible = true
		var res: bool = a["resolved"]
		if changed:
			row.icon.icon = &"star" if res else a["icon"]
			row.text.text = a["text"]
			row._style(row.hover)
			if not res:
				UIKit.tween_pop(row)
		if res and row.icon.icon != &"star":
			row.icon.icon = &"star"
			row.text.text = "Sorted out!"
			row.text.add_theme_color_override("font_color", Palette.MINT_DARK)
			row._style(row.hover)
		elif not res:
			row.text.remove_theme_color_override("font_color")
		var age: int = int(now - float(a["born"]))
		row.age.text = "%ds" % age if age < 60 else "%dm" % (age / 60)
		row.modulate.a = 1.0 if not res else clampf(1.0 - (now - float(a["resolved_at"]) - 0.5) / 0.6, 0.0, 1.0)
	_empty.visible = shown == 0
	var extra: int = _alerts.size() - shown
	_more.visible = extra > 0
	if extra > 0:
		_more.text = "+%d more" % extra
