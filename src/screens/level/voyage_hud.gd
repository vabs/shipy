class_name VoyageHud
extends Control
## Voyage HUD: top bar (money, voyage progress, ship rating meter, live stars, speed), bottom bar (crew roster,
## hire buttons, alert feed), event chips, mutiny warning + vignette, hover / pinned tooltips.
##
##   setup(level, world, ctl, renderer) -> builds everything; `input` is assigned by LevelScreen afterwards.
##   refresh(delta)                      -> call every frame.
##   signal focus_requested(local_pos)   signal banner_requested(title, subtitle, icon, color, seconds)

signal focus_requested(local_pos: Vector2)
## Kept for API compatibility: event announcements now use the compact pill (CompactBanner) so they never
## cover the ship; the big full-width Banner is reserved for moments when play is not running.
@warning_ignore("unused_signal")
signal banner_requested(title: String, subtitle: String, icon: StringName, color: Color, seconds: float)

const U := preload("res://src/render/art/art_util.gd")
const TOP_H: float = 84.0
const BOTTOM_H: float = 190.0

var level: LevelDef = null
var world: SimWorld = null
var ctl: VoyageController = null
var renderer: VoyageRenderer = null
var input: VoyageInput = null

var top_bar: PanelContainer
var bottom_bar: PanelContainer
var money_pill: StatPill
var time_pill: StatPill
var guests_pill: StatPill
var progress: VoyageProgress
var meter: SatisfactionMeter
var pct_label: Label
var stars: StarRow
var speed_buttons: Array[Button] = []
var alerts: AlertFeed
var tooltip: VoyageTooltip

var _roster: HBoxContainer
var _cards: Dictionary = {}
var _hire_buttons: Dictionary = {}
var _crew_label: Label
var _chips: HBoxContainer
var _chip_nodes: Dictionary = {}
var _mutiny_panel: PanelContainer
var _mutiny_label: Label
var _vignette: _Vignette
var _money_disp: float = 0.0
var _rating_disp: float = 50.0
var _slow_t: float = 0.0
var _goals_hover: bool = false
var _prev_stars: int = -1
var _thresholds: Array[float] = [50.0, 70.0, 85.0]
var _t: float = 0.0
var _last_money: int = 0
var _goal_rows: Array[Dictionary] = []
var _pill_pending: Dictionary = {}   # event id -> true while its announcement pill is still on its way to the chip


class _Vignette extends Control:
	var tex: GradientTexture2D
	var intensity: float = 0.0
	var t: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		g.colors = PackedColorArray([Color(0.91, 0.31, 0.36, 0.0), Color(0.91, 0.31, 0.36, 0.0), Color(0.86, 0.16, 0.24, 0.8)])
		tex = GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 128
		tex.height = 128

	func _process(delta: float) -> void:
		t += delta
		visible = intensity > 0.01
		if visible:
			queue_redraw()

	func _draw() -> void:
		var pulse: float = 0.65 + 0.35 * sin(t * 4.2)
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, clampf(intensity * pulse, 0.0, 1.0)))


class _StaffCard extends PanelContainer:
	signal clicked(id: int)
	signal double_clicked(id: int)
	signal hovered(id: int, on: bool)
	var staff_id: int = -1
	var portrait: BeanPortrait
	var role_label: Label
	var state_label: Label
	var selected: bool = false
	var _sb_norm: StyleBoxFlat
	var _sb_sel: StyleBoxFlat

	func _init(id: int, role: StringName, role_name: String) -> void:
		staff_id = id
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(112, 0)
		_sb_norm = UITheme.flat(UITheme.CARD, 16, UITheme.CARD_EDGE, 2, Color(0.1, 0.14, 0.26, 0.25), 8, Vector2(0, 4), Vector4(8, 8, 8, 8))
		_sb_sel = UITheme.flat(Color("FFF2D6"), 16, Palette.CORAL, 4, Color(0.91, 0.31, 0.36, 0.45), 12, Vector2(0, 0), Vector4(8, 8, 8, 8))
		add_theme_stylebox_override("panel", _sb_norm)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait = BeanPortrait.new()
		portrait.staff_role = role
		portrait.portrait_size = 70.0
		portrait.plate_color = Color("CDEFFB") if role == &"janitor" else Color("FFE3A8")
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(portrait)
		role_label = Label.new()
		role_label.text = role_name
		role_label.add_theme_font_override("font", UITheme.font_bold())
		role_label.add_theme_font_size_override("font_size", 19)
		role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(role_label)
		state_label = Label.new()
		state_label.text = "Idle"
		state_label.add_theme_font_size_override("font_size", 16)
		state_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(state_label)
		add_child(v)
		mouse_entered.connect(func() -> void: hovered.emit(staff_id, true))
		mouse_exited.connect(func() -> void: hovered.emit(staff_id, false))

	## density 0 (up to 4 crew) / 1 (5-6) / 2 (7-8): shrinks the card so a full crew still fits the bottom bar
	## next to the hire buttons, star goals and alert feed.
	func set_density(d: int) -> void:
		portrait.portrait_size = [70.0, 58.0, 48.0][d]
		custom_minimum_size = Vector2([112, 96, 82][d], 0)
		role_label.add_theme_font_size_override("font_size", [19, 17, 15][d])
		state_label.add_theme_font_size_override("font_size", [16, 15, 13][d])

	func set_selected(s: bool) -> void:
		if s == selected:
			return
		selected = s
		portrait.selected = s
		add_theme_stylebox_override("panel", _sb_sel if s else _sb_norm)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				double_clicked.emit(staff_id)
			else:
				clicked.emit(staff_id)
			accept_event()


# =================================================================================================
# build
# =================================================================================================
func setup(p_level: LevelDef, p_world: SimWorld, p_ctl: VoyageController, p_renderer: VoyageRenderer) -> void:
	level = p_level
	world = p_world
	ctl = p_ctl
	renderer = p_renderer
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compute_thresholds()
	_vignette = _Vignette.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_vignette)
	_build_top()
	_build_bottom()
	_build_overlays()
	tooltip = VoyageTooltip.new()
	add_child(tooltip)
	_money_disp = float(world.money)
	_last_money = world.money
	_rating_disp = world.rating()
	world.event_started.connect(_on_event_started)
	world.money_changed.connect(_on_money_changed)
	alerts.setup(world, renderer)
	alerts.focus_requested.connect(func(p: Vector2) -> void: focus_requested.emit(p))
	_sync_roster()


func _compute_thresholds() -> void:
	var vals: Array[float] = []
	for goal in level.star_goals:
		if String(goal.get("type", "")) == "rating":
			vals.append(float(goal.get("value", 60)))
	vals.sort()
	# only the level's real rating goals get a marker (0..3), never invented ones
	_thresholds = vals


func _build_top() -> void:
	top_bar = UIKit.navy_bar()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.custom_minimum_size = Vector2(0, TOP_H)
	top_bar.offset_bottom = TOP_H
	var row := UIKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	money_pill = UIKit.stat_pill(&"coin", "$0")
	money_pill.custom_minimum_size = Vector2(176, 0)
	row.add_child(money_pill)
	progress = UIKit.make_voyage_progress()
	progress.custom_minimum_size = Vector2(430, 46)
	row.add_child(progress)
	time_pill = UIKit.stat_pill(&"clock", "0:00")
	time_pill.custom_minimum_size = Vector2(128, 0)
	row.add_child(time_pill)
	guests_pill = UIKit.stat_pill(&"guest", "0/0")
	guests_pill.custom_minimum_size = Vector2(128, 0)
	row.add_child(guests_pill)
	row.add_child(UIKit.h_spacer())
	meter = UIKit.make_meter()
	meter.star_thresholds = _thresholds
	meter.custom_minimum_size = Vector2(400, 40)
	row.add_child(meter)
	pct_label = Label.new()
	pct_label.theme_type_variation = &"PillLabel"
	pct_label.custom_minimum_size = Vector2(60, 0)
	pct_label.add_theme_font_size_override("font_size", 24)
	pct_label.text = "72%"
	row.add_child(pct_label)
	stars = UIKit.star_row(0, 32.0)
	stars.mouse_filter = Control.MOUSE_FILTER_STOP
	stars.mouse_entered.connect(func() -> void: _goals_hover = true)
	stars.mouse_exited.connect(func() -> void: _goals_hover = false)
	row.add_child(stars)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	var icons: Array[StringName] = [&"pause", &"play", &"fast", &"faster"]
	var tips: Array[String] = ["Pause (Space)", "Normal speed (1)", "Fast (2)", "Fastest (3)"]
	for i in 4:
		var b := UIKit.icon_button(icons[i], tips[i], 52.0, true)
		b.toggle_mode = true
		b.button_group = group
		var spd: int = i
		b.pressed.connect(func() -> void: ctl.set_speed(spd))
		row.add_child(b)
		speed_buttons.append(b)
	top_bar.add_child(row)
	add_child(top_bar)


func _build_bottom() -> void:
	bottom_bar = UIKit.navy_bar_bottom()
	bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.custom_minimum_size = Vector2(0, BOTTOM_H)
	bottom_bar.offset_top = -BOTTOM_H
	var row := UIKit.hbox(16)
	_roster = UIKit.hbox(10)
	_roster.alignment = BoxContainer.ALIGNMENT_BEGIN
	_roster.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(_roster)
	# hire column
	var hire := UIKit.vbox(8)
	hire.alignment = BoxContainer.ALIGNMENT_CENTER
	_crew_label = Label.new()
	_crew_label.theme_type_variation = &"OnDarkSmall"
	_crew_label.text = "Crew"
	hire.add_child(_crew_label)
	for role in [&"janitor", &"mechanic"]:
		var b: Button = UIKit.secondary_button("") if role == &"janitor" else UIKit.sun_button("")
		b.custom_minimum_size = Vector2(222, 52)
		b.add_theme_font_size_override("font_size", 20)
		var iv := IconView.new()
		iv.icon = &"mop" if role == &"janitor" else &"wrench"
		iv.icon_size = 28.0
		iv.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
		iv.offset_left = 14
		iv.offset_top = -17
		iv.offset_right = 42
		iv.offset_bottom = 11
		b.add_child(iv)
		var rr: StringName = role
		b.pressed.connect(func() -> void: _on_hire(rr))
		hire.add_child(b)
		_hire_buttons[role] = b
	row.add_child(hire)
	row.add_child(UIKit.h_spacer())
	row.add_child(_build_goals_card())
	alerts = AlertFeed.new()
	alerts.custom_minimum_size = Vector2(450, 0)
	row.add_child(alerts)
	bottom_bar.add_child(row)
	add_child(bottom_bar)


func _build_goals_card() -> Control:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = UITheme.flat(Color(1, 1, 1, 0.1), 16, Color(1, 1, 1, 0.14), 2, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(14, 8, 14, 8))
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(296, 0)
	var v := UIKit.vbox(3)
	var h := Label.new()
	h.theme_type_variation = &"OnDark"
	h.add_theme_font_override("font", UITheme.font_bold())
	h.add_theme_font_size_override("font_size", 20)
	h.text = "Star goals"
	v.add_child(h)
	for i in level.star_goals.size():
		var hb := UIKit.hbox(8)
		var iv := IconView.new()
		iv.icon = &"star_empty"
		iv.icon_size = 24.0
		hb.add_child(iv)
		var l := Label.new()
		l.theme_type_variation = &"OnDark"
		l.add_theme_font_size_override("font_size", 18)
		hb.add_child(l)
		v.add_child(hb)
		_goal_rows.append({"icon": iv, "label": l})
	card.add_child(v)
	return card


func _short_goal(goal: Dictionary) -> String:
	match String(goal.get("type", "")):
		"rating":
			return "Rating %d%%" % int(goal.get("value", 0))
		"profit":
			return "Profit %s  (%s)" % [fmt_money(int(goal.get("value", 0))), fmt_money(world.economy.profit())]
		"served":
			return "Serve %d visits  (%d)" % [int(goal.get("value", 0)), world.director.served]
		"no_lost_guests":
			return "No guests lost  (%d lost)" % world.director.lost_count(world)
	return "?"


func _build_overlays() -> void:
	_chips = UIKit.hbox(10)
	_chips.position = Vector2(24, TOP_H + 14.0)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chips)
	_mutiny_panel = PanelContainer.new()
	_mutiny_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mutiny_panel.add_theme_stylebox_override("panel", UITheme.flat(Palette.CORAL_DARK, 22, Color(1, 1, 1, 0.7), 3, Color(0.5, 0, 0.1, 0.5), 16, Vector2(0, 5), Vector4(24, 10, 28, 12)))
	var hb := UIKit.hbox(12)
	var iv := IconView.new()
	iv.icon = &"warning"
	iv.icon_size = 38.0
	iv.animate = true
	hb.add_child(iv)
	var vb := UIKit.vbox(0)
	_mutiny_label = Label.new()
	_mutiny_label.theme_type_variation = &"OnDarkTitle"
	_mutiny_label.add_theme_font_size_override("font_size", 32)
	_mutiny_label.text = "Mutiny in 30s!"
	vb.add_child(_mutiny_label)
	var sub := Label.new()
	sub.theme_type_variation = &"OnDarkSmall"
	sub.text = "Guests are furious. Clean up, repair and get the rating above 20%!"
	vb.add_child(sub)
	hb.add_child(vb)
	_mutiny_panel.add_child(hb)
	_mutiny_panel.visible = false
	add_child(_mutiny_panel)
	_mutiny_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)


# =================================================================================================
# helpers
# =================================================================================================
static func fmt_money(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	var c: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if n < 0 else "$") + out


static func fmt_time(secs: float) -> String:
	var s: int = maxi(int(ceil(secs)), 0)
	return "%d:%02d" % [s / 60, s % 60]


func _pop(n: Control, k: float = 1.12) -> void:
	if not n.is_inside_tree():
		return
	n.pivot_offset = n.size * 0.5
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector2(k, k), 0.08)
	tw.tween_property(n, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_money_changed(_m: int, delta: int, reason: StringName) -> void:
	if delta >= 15 and reason != &"tickets":
		_pop(money_pill, 1.06)
	elif reason == &"hire" or reason == &"hires":
		_pop(money_pill, 0.94)


func _on_hire(role: StringName) -> void:
	if world.hire_staff_mid_voyage(role):
		_sync_roster()


const _GOOD_EVENTS: Array[StringName] = [&"film_night", &"pool_party", &"captains_dinner", &"northern_lights"]


func _on_event_started(id: StringName) -> void:
	var def: EventDef = ContentStore.event(id)
	if def == null:
		return
	var col: Color = Palette.TEAL_DARK if id in _GOOD_EVENTS else (Palette.LILAC_DARK if id == &"haunting" else Palette.CORAL_DARK)
	var icon: StringName = &"ghost" if id == &"haunting" else (&"sick" if id == &"food_poisoning" else (&"breakdown" if id == &"power_surge" else &"event"))
	# compact pill under the top bar (top-left sky area), then it shrinks into the event chip
	_pill_pending[id] = true
	var pill: Control = Banner.show_compact(self, def.display_name, def.description, icon, col, 2.5,
			Vector2(24.0, TOP_H + 14.0 + 50.0), func() -> Vector2: return _chip_center(id))
	pill.connect(&"docked", func() -> void: _on_pill_docked(id))


func _chip_center(id: StringName) -> Vector2:
	var chip: Dictionary = _chip_nodes.get(id, {})
	if chip.is_empty():
		# instant events (no timer chip): shrink into the end of the chip row instead
		return _chips.global_position - global_position + Vector2(_chips.size.x + 56.0, 18.0)
	var n: Control = chip["node"]
	if not is_instance_valid(n) or not n.is_inside_tree():
		return Vector2.INF
	return n.global_position - global_position + n.size * 0.5


func _on_pill_docked(id: StringName) -> void:
	_pill_pending.erase(id)
	var chip: Dictionary = _chip_nodes.get(id, {})
	if chip.is_empty():
		return
	var n: Control = chip["node"]
	if is_instance_valid(n):
		n.modulate.a = 1.0
		UIKit.tween_pop(n)


# =================================================================================================
# roster
# =================================================================================================
func _role_name(role: StringName) -> String:
	var d: StaffDef = ContentStore.staff_role(role)
	return d.display_name if d != null else String(role).capitalize()


func _sync_roster() -> void:
	var ids: Dictionary = {}
	for s in world.staff:
		ids[s.id] = true
		if not _cards.has(s.id):
			var c := _StaffCard.new(s.id, s.role, _role_name(s.role))
			c.clicked.connect(_on_card_clicked)
			c.double_clicked.connect(_on_card_double_clicked)
			c.hovered.connect(func(id: int, on: bool) -> void:
				if input != null:
					input.set_roster_hover(id if on else -1))
			_roster.add_child(c)
			_cards[s.id] = c
			UIKit.tween_pop(c)
	for id in _cards.keys():
		if not ids.has(id):
			(_cards[id] as Node).queue_free()
			_cards.erase(id)
	var dens: int = 0 if world.staff.size() <= 4 else (1 if world.staff.size() <= 6 else 2)
	for id in _cards:
		(_cards[id] as _StaffCard).set_density(dens)


func _on_card_clicked(id: int) -> void:
	if input == null:
		return
	if input.selected_staff_id == id:
		input.cancel()
	else:
		input.select_staff(id)


func _on_card_double_clicked(id: int) -> void:
	if input == null:
		return
	if input.selected_staff_id != id:
		input.select_staff(id)
	var p: Vector2 = renderer.local_pos_of(&"staff", id)
	if p != Vector2.INF:
		focus_requested.emit(p)


func _state_text(s: StaffMember) -> String:
	match s.state:
		&"work":
			return "Cleaning" if s.work_kind == &"mess" else "Repairing"
		&"walk":
			return "On the way"
	return "Idle"


# =================================================================================================
# per frame
# =================================================================================================
func refresh(delta: float) -> void:
	_t += delta
	# money (animated count)
	var money: int = world.money
	_money_disp = lerpf(_money_disp, float(money), clampf(delta * 9.0, 0.0, 1.0))
	if absf(_money_disp - float(money)) < 1.0:
		_money_disp = float(money)
	money_pill.set_text(fmt_money(int(round(_money_disp))), false)
	money_pill.modulate = Color(1, 0.72, 0.72) if money < 0 else Color.WHITE
	# time + progress
	var left: float = maxf(world.duration - world.time, 0.0)
	progress.value = clampf(world.time / maxf(world.duration, 1.0), 0.0, 1.0)
	time_pill.set_text(fmt_time(left), false)
	# rating
	var rating: float = world.rating()
	var prev_disp: float = _rating_disp
	_rating_disp = lerpf(_rating_disp, rating, clampf(delta * 6.0, 0.0, 1.0))
	meter.value = _rating_disp
	for th in _thresholds:
		if (prev_disp < th) != (_rating_disp < th):
			_pop(meter, 1.06)
	pct_label.text = "%d%%" % int(round(rating))
	# speed buttons
	for i in speed_buttons.size():
		speed_buttons[i].set_pressed_no_signal(i == ctl.speed)
	# slow updates
	_slow_t -= delta
	if _slow_t <= 0.0:
		_slow_t = 0.2
		_slow_update()
	alerts.refresh(delta)
	_update_mutiny(delta)
	_update_tooltip()


func _live_goals() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d: LevelDirector = world.director
	for goal in level.star_goals:
		out.append({"text": d.goal_text(goal), "met": d.goal_met(world, goal, world.rating())})
	return out


func _slow_update() -> void:
	# stars
	var n: int = 0
	var gi: int = 0
	for g in _live_goals():
		if g["met"]:
			n += 1
		if gi < _goal_rows.size():
			var row: Dictionary = _goal_rows[gi]
			(row["icon"] as IconView).icon = &"star" if g["met"] else &"star_empty"
			(row["icon"] as IconView).modulate = Color.WHITE if g["met"] else Color(1, 1, 1, 0.5)
			var lab: Label = row["label"]
			lab.text = _short_goal(level.star_goals[gi])
			lab.add_theme_color_override("font_color", Palette.SUN if g["met"] else Color("C9D3E8"))
		gi += 1
	if n != _prev_stars:
		if _prev_stars >= 0 and n > _prev_stars:
			_pop(stars, 1.15)
			AudioManager.play_sfx(&"star_1", 0.0, -6.0)
		_prev_stars = n
		stars.value = n
	var st: Dictionary = world.stats()
	guests_pill.set_text("%d/%d" % [int(st["guests_on_board"]), world.director.guests_planned], false)
	# crew
	_sync_roster()
	for s in world.staff:
		var c: _StaffCard = _cards.get(s.id)
		if c != null:
			c.state_label.text = _state_text(s)
			c.state_label.add_theme_color_override("font_color", Palette.MINT_DARK if s.state == &"work" else (Palette.TEAL_DARK if s.state == &"walk" else UITheme.TEXT_MUTED))
			c.set_selected(input != null and input.selected_staff_id == s.id)
	var maxs: int = world.grid.hull.max_staff
	_crew_label.text = "Crew %d / %d" % [world.staff.size(), maxs]
	for role in _hire_buttons:
		var b: Button = _hire_buttons[role]
		var cost: int = world.mid_voyage_hire_cost(role)
		var nm: String = _role_name(role)
		b.visible = not (world.staff.size() >= maxs and role != &"janitor")   # one "Crew full" button is plenty
		if world.staff.size() >= maxs:
			b.text = "      Crew full"
			b.disabled = true
			b.tooltip_text = "Your ship can only carry %d crew." % maxs
		elif world.money < cost:
			b.text = "      %s  (need %s)" % [nm, fmt_money(cost)]
			b.disabled = true
			b.tooltip_text = "Not enough money."
		else:
			b.text = "      Hire %s  %s" % [nm, fmt_money(cost)]
			b.disabled = false
			b.tooltip_text = "Hire a %s now for %s (1.5x wage)." % [nm.to_lower(), fmt_money(cost)]
	_update_chips()


func _update_chips() -> void:
	var active: Array[Dictionary] = world.active_events()
	var seen: Dictionary = {}
	for a in active:
		var id: StringName = a["id"]
		seen[id] = true
		var def: EventDef = a["def"]
		var chip: Dictionary = _chip_nodes.get(id, {})
		if chip.is_empty():
			var p := PanelContainer.new()
			p.theme_type_variation = &"PillPanel"
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var hb := UIKit.hbox(8)
			var iv := IconView.new()
			iv.icon = &"event"
			iv.icon_size = 26.0
			iv.animate = true
			hb.add_child(iv)
			var nl := Label.new()
			nl.theme_type_variation = &"PillLabel"
			nl.text = def.display_name
			hb.add_child(nl)
			var tl := Label.new()
			tl.theme_type_variation = &"PillLabel"
			tl.add_theme_color_override("font_color", Palette.SUN)
			hb.add_child(tl)
			p.add_child(hb)
			_chips.add_child(p)
			if _pill_pending.has(id):
				p.modulate.a = 0.0   # revealed when its announcement pill lands
			else:
				UIKit.tween_pop(p)
			chip = {"node": p, "time": tl}
			_chip_nodes[id] = chip
		(chip["time"] as Label).text = fmt_time(float(a["time_left"]))
	for id in _chip_nodes.keys():
		if not seen.has(id):
			(_chip_nodes[id]["node"] as Node).queue_free()
			_chip_nodes.erase(id)


func _update_mutiny(delta: float) -> void:
	var active: bool = world.mutiny_active
	var rating: float = world.rating()
	var target: float = 1.0 if active else clampf((32.0 - rating) / 12.0, 0.0, 0.3)
	if world.guests.is_empty() or not level.mutiny_enabled:
		target = 0.0
	_vignette.intensity = lerpf(_vignette.intensity, target, clampf(delta * 3.0, 0.0, 1.0))
	if active != _mutiny_panel.visible:
		_mutiny_panel.visible = active
		if active:
			_mutiny_panel.position = Vector2(0, TOP_H + 14.0)
			_mutiny_panel.reset_size()
	if active:
		_mutiny_label.text = "Mutiny in %ds!" % int(ceil(maxf(world.mutiny_time_left, 0.0)))
		_mutiny_panel.reset_size()
		_mutiny_panel.position = Vector2((size.x - _mutiny_panel.size.x) * 0.5, TOP_H + 14.0)
		_mutiny_panel.pivot_offset = _mutiny_panel.size * 0.5
		var k: float = 1.0 + 0.035 * sin(_t * 7.0)
		_mutiny_panel.scale = Vector2(k, k)


# =================================================================================================
# tooltips
# =================================================================================================
func _update_tooltip() -> void:
	if input == null:
		return
	var mouse: Vector2 = input.mouse_screen
	if input.pinned_guest_id >= 0:
		var g: Guest = world.guest_by_id(input.pinned_guest_id)
		if g != null:
			var lp: Vector2 = renderer.local_pos_of(&"guest", g.id)
			if lp != Vector2.INF:
				var m: Dictionary = _guest_model(g)
				m["pinned"] = true
				m["hint"] = "Pinned. Click elsewhere to close"
				tooltip.show_model(m, input.local_to_screen(lp), Vector2(26, -40))
				return
	if _goals_hover:
		var lines: Array = []
		for gl in _live_goals():
			lines.append({"icon": &"star" if gl["met"] else &"star_empty", "text": gl["text"], "on": gl["met"]})
		tooltip.show_model({"title": "Star goals", "icon": &"star", "lines": lines, "accent": Palette.SUN,
				"hint": "Hit all three for a perfect voyage!"}, get_viewport().get_mouse_position(), Vector2(-250, 26))
		return
	if not input.over_world:
		tooltip.hide_tip()
		return
	var model: Dictionary = {}
	match input.hover_kind:
		&"guest":
			var g2: Guest = world.guest_by_id(input.hover_id)
			if g2 != null:
				model = _guest_model(g2)
				model["hint"] = "Click to pin"
		&"room":
			model = _room_model(world.room_by_uid(input.hover_id))
		&"staff":
			model = _staff_model(world.staff_by_id(input.hover_id))
		&"mess":
			model = _mess_model(world.mess_by_id(input.hover_id))
		&"ghost":
			model = {"title": "Ghost!", "icon": &"ghost", "accent": Palette.LILAC, "lines": ["Scares guests and ruins queues"], "hint": "Click to banish it"}
	if model.is_empty():
		tooltip.hide_tip()
	else:
		tooltip.show_model(model, mouse)


func _room_name(uid: int) -> String:
	var r: RoomRuntime = world.room_by_uid(uid)
	return r.def.display_name if r != null else "somewhere"


func _guest_intent(g: Guest) -> String:
	var prefix: String = ""
	if g.slip_timer > 0.0:
		return "Slipped on a spill!"
	if g.sick:
		prefix = "Sick. "
	match g.state:
		&"boarding":
			return prefix + "Just came aboard"
		&"wander":
			return prefix + "Strolling around"
		&"walk":
			return prefix + "Heading to the %s" % _room_name(g.target_uid)
		&"queue":
			return prefix + "In line for the %s (#%d)" % [_room_name(g.target_uid), g.queue_index + 1]
		&"use":
			var r: RoomRuntime = world.room_by_uid(g.target_uid)
			if r != null and r.def.id == &"cabin":
				return prefix + "Sleeping in the cabin"
			return prefix + "Enjoying the %s" % _room_name(g.target_uid)
		&"climb":
			return prefix + "Taking the stairs"
		&"elevator_wait":
			return prefix + "Waiting for the lift"
		&"elevator_ride":
			return prefix + "Riding the lift"
		&"storm_off":
			return "Storming off the ship!"
	return prefix + "Aboard"


func _need_color(v: float) -> Color:
	return SatisfactionMeter.color_at(v / 100.0)


func _guest_model(g: Guest) -> Dictionary:
	var sat: float = g.satisfaction
	var mood_icon: StringName = &"smile" if sat >= 65.0 else (&"meh" if sat >= 35.0 else &"frown")
	if g.sick:
		mood_icon = &"sick"
	var bars: Array = [{"icon": mood_icon, "label": "%d" % int(sat), "value": sat / 100.0, "color": _need_color(sat)}]
	var names: Array[StringName] = [&"need_rest", &"need_hunger", &"need_fun", &"need_hygiene"]
	for i in 4:
		var v: float = g.nv[i]
		bars.append({"icon": names[i], "label": "%d" % int(v), "value": v / 100.0, "color": _need_color(v)})
	var arch: ArchetypeDef = g.archetype
	return {"title": arch.display_name, "icon": &"guest", "tag": "mood %d%%" % int(sat), "accent": Palette.archetype_color(arch.id),
			"lines": [_guest_intent(g)], "bars": bars}


func _room_model(r: RoomRuntime) -> Dictionary:
	if r == null:
		return {}
	var d: RoomDef = r.def
	var tier: String = ["", " II", " III"][clampi(r.tier, 0, 2)]
	var lines: Array = []
	var bars: Array = []
	var hint: String = ""
	if d.id == &"cabin":
		lines.append("Sleepers %d / %d  (%d napping)" % [r.sleepers.size(), r.capacity(), r.users.size()])
	else:
		lines.append("Using %d / %d" % [r.users.size(), r.capacity()])
		lines.append("Queue: %d waiting" % r.queue.size())
	if r.broken:
		lines.append("BROKEN  (%d%% repaired)" % int(r.repair_progress * 100.0))
		hint = "Press and hold to repair!"
		bars.append({"icon": &"wrench", "label": "%d%%" % int(r.repair_progress * 100.0), "value": r.repair_progress, "color": Palette.MINT})
	elif r.is_breakable() and r.max_health > 0.0:
		var hv: float = clampf(r.health / r.max_health, 0.0, 1.0)
		bars.append({"icon": &"breakdown", "label": "%d%%" % int(hv * 100.0), "value": hv, "color": _need_color(hv * 100.0)})
	return {"title": d.display_name + tier, "room": d.id, "accent": IconArt.room_badge_color(d.id) if not r.broken else Palette.CORAL,
			"lines": lines, "bars": bars, "hint": hint}


func _staff_model(s: StaffMember) -> Dictionary:
	if s == null:
		return {}
	var job: String = "Idle. Waiting for a job"
	if s.state == &"work":
		job = "Cleaning a spill" if s.work_kind == &"mess" else "Repairing the %s" % _room_name(s.work_target_id)
	elif s.state == &"walk" and s.job != null:
		job = "Heading to a spill" if s.job.kind == &"mess" else "Heading to the %s" % _room_name(s.job.target_id)
	var role: String = _role_name(s.role)
	return {"title": role, "icon": &"mop" if s.role == &"janitor" else &"wrench", "accent": Palette.TEAL,
			"lines": [job], "hint": "Click, then click a %s" % ("spill" if s.role == &"janitor" else "broken room")}


func _mess_model(m: Mess) -> Dictionary:
	if m == null:
		return {}
	var bars: Array = []
	if m.clean_progress > 0.01:
		bars.append({"icon": &"mop", "label": "%d%%" % int(m.clean_progress * 100.0), "value": m.clean_progress, "color": Palette.MINT})
	return {"title": "Spill", "icon": &"mess", "accent": Palette.WOOD, "lines": ["Guests slip and get grumpy"], "bars": bars, "hint": "Click to scrub (3 clicks)"}
