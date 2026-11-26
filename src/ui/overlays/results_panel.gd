class_name ResultsPanel
extends Control
## End-of-voyage results overlay with a juicy reveal (backdrop dim, card slides up, goals tick, stars pop one by one
## with sparkle bursts, rating counts up, ledger fills in, "New!" unlock chips pop).
##
##   var rp := ResultsPanel.new()
##   rp.retry_pressed.connect(...); rp.next_pressed.connect(...); rp.map_pressed.connect(...)
##   host.add_child(rp)
##   rp.show_result(result, unlocks, level_def)
## result  = LevelDirector result {stars, goals:[{text, met}], rating, profit, ledger{tickets,spending,upkeep,wages,hires},
##           guests_total, guests_lost, served, mutiny, level_id}
## unlocks = SaveManager.record_result() return value (newly_unlocked_rooms / _destinations / _levels / _features)
## `result.vips` ([{kind, grade, pay, detail}], docs/SPEC.md §13.5) adds a "VIP verdicts" plate (kind, how the review went and
## the verdict chip with its money); VIP bonuses / penalties get their own lines in the voyage accounts. `result.groups`
## ({count, split, kids}) adds a "Couples & families" pill.
## Also shows the company funds earned (SPEC §13.1, from `unlocks.funds_earned / best_payout / funds_total` and
## `result.payout`) and, when `result.report` exists, buttons for the Voyage report view (ReportView) and the heatmap.
## Star pops follow AudioManager's results jingle (first at 0.55 s, then every 0.5 s); this panel plays no star sfx itself.
## "Next" is disabled while the following level is locked (SaveManager.is_level_unlocked) and hidden after the last level.
## Click the card (not a button) to skip the reveal.

signal retry_pressed
signal next_pressed
signal map_pressed
## "Show heatmap" was pressed (from the results or the voyage report): the host hides this panel, shows the heatmap
## overlay and makes the panel visible again when the player comes back.
signal heatmap_pressed

## Keys (Enter / ui_accept) do nothing for this long after the panel appears, so a Space / Enter pressed while the
## voyage ends cannot skip the results. Space never activates a button here (it is also the pause key).
const KEY_GRACE_MSEC: int = 1000
const STAR_START: float = 0.55
const STAR_GAP: float = 0.5
const GREEN: Color = Color("2E9E68")
const RED: Color = Color("C23B49")
const LEDGER_ROWS: Array[Array] = [
	["tickets", "Ticket sales", 1],
	["spending", "Guest spending", 1],
	["upkeep", "Room upkeep", -1],
	["hires", "Mid-voyage hires", -1],
]

var _result: Dictionary = {}
var _unlocks: Dictionary = {}
var _level: LevelDef = null
var _backdrop: ColorRect
var _confetti: _Confetti
var _slide: Control
var _card: PanelContainer
var _stars: _Stars = null
var _rating_label: Label
var _rating_bar: ProgressBar
var _goal_rows: Array[Dictionary] = []
var _ledger_rows: Array[Dictionary] = []
var _profit_row: Dictionary = {}
var _wages_row: Control = null   # informational only: wages are paid in port, so they are NOT part of the profit sum
var _chips: Array[Control] = []
var _chip_title: Control = null
var _stat_pills: Array[Control] = []
var _btn_row: Control
var _tw: Tween = null
var _skipped: bool = false
var _revealed_all: bool = false
var _next_btn: Button = null
var _retry_btn: Button = null
var _hint: Label
var _tip_panel: Control = null
var _next_star_panel: Control = null
var _shown_msec: int = 0
var _funds_plate: Control = null
var _funds_amount: Label = null
var _funds_target: int = 0
var _report_row: Control = null
var _report_center: CenterContainer = null
var _report_view: ReportView = null
var _main_center: CenterContainer = null
var _reserve: float = 0.0
var _fit_tw: Tween = null
var _funds_tw: Tween = null


func _init() -> void:
	theme = UITheme.build()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 130
	_backdrop = OvUtil.make_backdrop(0.72)
	add_child(_backdrop)
	_confetti = _Confetti.new()
	_confetti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_confetti)
	_slide = Control.new()
	_slide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slide)


# ================================================================================================
# public
# ================================================================================================
func show_result(result: Dictionary, unlocks: Dictionary, level: LevelDef) -> void:
	_result = result
	_unlocks = unlocks
	_level = level
	_skipped = false
	_revealed_all = false
	for c in _slide.get_children():
		c.queue_free()
	_goal_rows.clear()
	_ledger_rows.clear()
	_chips.clear()
	_stat_pills.clear()
	_funds_plate = null
	_report_row = null
	_report_view = null
	if _report_center != null:
		_report_center.queue_free()
		_report_center = null
	_build()
	_fit_card.call_deferred()
	if is_inside_tree():
		_start()
	else:
		ready.connect(_start, CONNECT_ONE_SHOT)


# ================================================================================================
# construction
# ================================================================================================
func _mutiny() -> bool:
	return bool(_result.get("mutiny", false))


func _stars_n() -> int:
	return 0 if _mutiny() else clampi(int(_result.get("stars", 0)), 0, 3)


func _lget(d: Dictionary, key: String) -> int:
	if d.has(key):
		return int(d[key])
	if d.has(StringName(key)):
		return int(d[StringName(key)])
	return 0


func _headline() -> Array[String]:
	if _mutiny():
		return ["Mutiny!", "The guests took over the ship"]
	match _stars_n():
		3: return ["Magnificent!", "Every goal smashed. Guests are raving."]
		2: return ["Smooth sailing!", "So close to a perfect voyage."]
		1: return ["Made it to port!", "A star is a star. Can you get more?"]
	return ["Rough seas...", "Meet the rating goal to earn your first star."]


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide.add_child(center)
	_main_center = center
	_card = UIKit.card()
	_card.custom_minimum_size = Vector2(1280, 0)
	_card.gui_input.connect(_on_card_input)
	_card.resized.connect(_fit_card)   # wrapping chips / late rows can make the card taller after the first layout pass
	center.add_child(_card)
	var outer := UIKit.vbox(12)
	_card.add_child(UIKit.with_margin(outer, 10))
	# ---- header
	var head := UIKit.vbox(0)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var lvl := ""
	if _level != null:
		lvl = "LEVEL %d   -   %s" % [_level.campaign_index, _level.display_name.to_upper()]
	var top_l := UIKit.small_label(lvl)
	top_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(top_l)
	var hl := _headline()
	var title := Label.new()
	title.text = hl[0]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UITheme.font_bold())
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Palette.CORAL if _mutiny() else UITheme.TEXT_INK)
	head.add_child(title)
	var sub := Label.new()
	sub.text = hl[1]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	head.add_child(sub)
	outer.add_child(head)
	title.pivot_offset = Vector2(300, 36)
	OvUtil.pop_in(title, 0.2, 0.45)
	# ---- body
	var body := UIKit.hbox(28)
	outer.add_child(body)
	var left := UIKit.vbox(12)
	left.custom_minimum_size = Vector2(540, 0)
	body.add_child(left)
	var right := UIKit.vbox(12)
	right.custom_minimum_size = Vector2(580, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_build_left(left)
	_build_right(right)
	# ---- buttons
	var row := UIKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_row = row
	var map_b := UIKit.secondary_button("Map")
	map_b.custom_minimum_size = Vector2(200, 64)
	OvUtil.focusable(map_b)
	map_b.pressed.connect(func() -> void: map_pressed.emit())
	row.add_child(map_b)
	_retry_btn = UIKit.sun_button("Retry")
	_retry_btn.custom_minimum_size = Vector2(220, 64)
	OvUtil.focusable(_retry_btn)
	_retry_btn.pressed.connect(func() -> void: retry_pressed.emit())
	row.add_child(_retry_btn)
	var next_id: StringName = &""
	if _level != null:
		next_id = SaveManager.next_level_id(_level.id)
	_next_btn = null
	_hint = UIKit.small_label("")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if next_id != &"":
		_next_btn = UIKit.primary_button("Next level")
		_next_btn.custom_minimum_size = Vector2(280, 64)
		OvUtil.focusable(_next_btn)
		var ok: bool = SaveManager.is_level_unlocked(next_id) and (_stars_n() >= 1 or SaveManager.stars_for(_level.id) >= 1)
		_next_btn.disabled = not ok
		if ok:
			var nd: LevelDef = ContentDB.level(next_id)
			if nd != null:
				_next_btn.tooltip_text = "Up next: %s" % nd.display_name
		else:
			_hint.text = SaveManager.level_lock_reason(next_id)
			if _hint.text == "" or _stars_n() < 1:
				_hint.text = "Earn at least one star on this level to unlock the next one."
		_next_btn.pressed.connect(func() -> void: next_pressed.emit())
		row.add_child(_next_btn)
	outer.add_child(UIKit.v_spacer(2))
	outer.add_child(row)
	outer.add_child(_hint)
	_hint.visible = _hint.text != ""


## Shrinks the card (around its centre) when a busy voyage (VIP verdicts, groups, a port stop, funds, unlocks...) makes it taller than
## the screen, so the buttons never fall off the bottom. `_reserve` px at the bottom stay free (a first-time hint card sits there).
## (A Container resets its children's scale, so the whole full-rect centre container is scaled. That container is never smaller than
## the card, so a card taller than the screen makes it taller than the screen too: its centre is moved back onto the screen centre.)
func _fit_card(animate: bool = false) -> void:
	if _card == null or not is_instance_valid(_card) or _main_center == null or not is_instance_valid(_main_center) or not is_inside_tree():
		return
	var need: Vector2 = _card.get_combined_minimum_size()
	var avail: float = maxf(size.y - 20.0 - _reserve, 200.0)
	var f: float = clampf(avail / maxf(need.y, 1.0), 0.55, 1.0)
	var box_h: float = maxf(size.y, need.y)
	_main_center.pivot_offset = Vector2(size.x * 0.5, box_h * 0.5)
	var shift: float = (size.y - box_h) * 0.5 - _reserve * 0.5
	if _fit_tw != null and _fit_tw.is_valid():
		_fit_tw.kill()
	if animate:
		_fit_tw = create_tween().set_parallel(true)
		_fit_tw.tween_property(_main_center, "scale", Vector2(f, f), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_fit_tw.tween_property(_main_center, "offset_top", shift, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_fit_tw.tween_property(_main_center, "offset_bottom", shift, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_main_center.scale = Vector2(f, f)
		_main_center.offset_top = shift
		_main_center.offset_bottom = shift


## Keeps `px` free at the bottom of the screen (the hint director shows its card there) / gives it back with 0.
func reserve_bottom(px: float) -> void:
	_reserve = maxf(px, 0.0)
	_fit_card(true)


func _plate() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"PlatePanel"
	return p


func _build_left(left: VBoxContainer) -> void:
	if _mutiny():
		var art := MutinyArt.new()
		art.custom_minimum_size = Vector2(540, 220)
		left.add_child(art)
		var none := UIKit.star_row(0, 40.0)
		none.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		left.add_child(none)
	else:
		_stars = _Stars.new()
		_stars.earned = _stars_n()
		_stars.custom_minimum_size = Vector2(540, 232)
		left.add_child(_stars)
	# rating
	var rate := _plate()
	var rv := UIKit.vbox(6)
	rate.add_child(rv)
	var rh := UIKit.hbox(10)
	var rl := UIKit.header_label("Ship rating")
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(rl)
	rh.add_child(UIKit.h_spacer())
	_rating_label = Label.new()
	_rating_label.text = "0%"
	_rating_label.add_theme_font_override("font", UITheme.font_bold())
	_rating_label.add_theme_font_size_override("font_size", 46)
	rh.add_child(_rating_label)
	rv.add_child(rh)
	_rating_bar = UIKit.make_progress_bar(&"CoralBar")
	_rating_bar.custom_minimum_size = Vector2(0, 22)
	rv.add_child(_rating_bar)
	left.add_child(rate)
	# goals
	var gp := _plate()
	var gv := UIKit.vbox(8)
	gp.add_child(gv)
	var gt := UIKit.small_label("STAR GOALS")
	gv.add_child(gt)
	var goals: Array = _result.get("goals", [])
	for g: Variant in goals:
		var gd: Dictionary = g
		var h := UIKit.hbox(12)
		var chk := _Check.new()
		chk.met = bool(gd.get("met", false))
		h.add_child(chk)
		var l := Label.new()
		l.text = String(gd.get("text", ""))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.add_theme_font_override("font", UITheme.font_bold())
		if not chk.met:
			l.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		h.add_child(l)
		gv.add_child(h)
		_goal_rows.append({"row": h, "check": chk})
	left.add_child(gp)
	_funds_plate = _build_funds_plate()
	if _funds_plate != null:
		left.add_child(_funds_plate)
	_report_row = _build_report_row()
	if _report_row != null:
		left.add_child(_report_row)
		_stat_pills.append(_report_row)


## "Company funds" row (SPEC §13.1): what this voyage added to the Shipyard funds, or what to beat.
func _build_funds_plate() -> Control:
	if not _unlocks.has("best_payout") or not _result.has("payout"):
		return null
	var payout: int = int(_result.get("payout", 0))
	var earned: int = int(_unlocks.get("funds_earned", 0))
	var best: int = int(_unlocks.get("best_payout", 0))
	var total: int = int(_unlocks.get("funds_total", 0))
	_funds_target = earned
	var p := _plate()
	p.name = "FundsPlate"
	var h := UIKit.hbox(12)
	p.add_child(h)
	var coin := GlyphView.new(&"coin", 46.0)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(coin)
	var v := UIKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	_funds_amount = Label.new()
	_funds_amount.add_theme_font_override("font", UITheme.font_bold())
	_funds_amount.add_theme_font_size_override("font_size", 25)
	if earned > 0:
		_funds_amount.text = "+%s company funds (new best!)" % OvUtil.money(earned)
		_funds_amount.add_theme_color_override("font_color", GREEN)
	elif best > 0:
		_funds_amount.text = "Beat %s to earn funds" % OvUtil.money(best)
		_funds_amount.add_theme_color_override("font_color", UITheme.TEXT_INK)
	else:
		_funds_amount.text = "Finish a voyage to earn funds"
		_funds_amount.add_theme_color_override("font_color", UITheme.TEXT_INK)
	_funds_amount.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_funds_amount)
	var sub: String
	if _mutiny():
		sub = "No payout after a mutiny"
	else:
		sub = "Voyage payout %s  -  %s in the bank" % [OvUtil.money(payout), OvUtil.money(total)]
	var sl := UIKit.small_label(sub)
	sl.add_theme_font_size_override("font_size", 16)
	v.add_child(sl)
	return p


## "Voyage report" / "Show heatmap" buttons (only when the result carries telemetry).
func _build_report_row() -> Control:
	var report: Variant = _result.get("report", null)
	if not (report is Dictionary) or (report as Dictionary).is_empty():
		return null
	var row := UIKit.hbox(10)
	row.name = "ReportRow"
	var rb := UIKit.secondary_button("Voyage report")
	rb.custom_minimum_size = Vector2(0, 52)
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OvUtil.focusable(rb)
	rb.pressed.connect(show_report)
	row.add_child(rb)
	var hb := UIKit.sun_button("Show heatmap")
	hb.custom_minimum_size = Vector2(0, 52)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OvUtil.focusable(hb)
	hb.pressed.connect(func() -> void: heatmap_pressed.emit())
	row.add_child(hb)
	return row


# ================================================================================================
# voyage report view
# ================================================================================================
## Swaps the results card for the Voyage report (ReportView). No-op without telemetry.
func show_report() -> void:
	var report: Variant = _result.get("report", null)
	if not (report is Dictionary) or _report_view != null:
		return
	if _tw != null:
		skip_reveal()
	_report_view = ReportView.new()
	_report_view.setup(report, _result, _level)
	_report_view.back_pressed.connect(show_main)
	_report_view.heatmap_pressed.connect(func() -> void: heatmap_pressed.emit())
	_report_center = CenterContainer.new()
	_report_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_report_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_report_center.add_child(_report_view)
	_slide.add_child(_report_center)
	_main_center.visible = false
	_report_view.pivot_offset = Vector2(640, 300)
	_report_view.scale = Vector2(0.96, 0.96)
	_report_view.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_report_view, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_report_view, "modulate:a", 1.0, 0.18)
	_report_view.play_reveal()
	_report_view.back_button().call_deferred("grab_focus")


## Back from the report to the results card.
func show_main() -> void:
	if _report_view == null:
		return
	_report_center.queue_free()
	_report_center = null
	_report_view = null
	_main_center.visible = true
	_focus_default.call_deferred()


func is_report_open() -> bool:
	return _report_view != null


func _build_right(right: VBoxContainer) -> void:
	var led := _plate()
	var lv := UIKit.vbox(5)
	led.add_child(lv)
	lv.add_child(UIKit.small_label("VOYAGE ACCOUNTS"))
	var ledger: Dictionary = _result.get("ledger", {})
	var rows: Array[Array] = LEDGER_ROWS.duplicate()
	if _lget(ledger, "vip_bonus") > 0:
		rows.insert(2, ["vip_bonus", "VIP bonuses", 1])
	if _lget(ledger, "vip_fines") > 0:
		rows.insert(rows.size() - 1, ["vip_fines", "VIP penalties", -1])
	if _lget(ledger, "refit") > 0:
		rows.append(["refit", "Port refit", -1])
	for r in rows:
		var key: String = r[0]
		var sign_v: int = r[2]
		var amount: int = _lget(ledger, key)
		var h := UIKit.hbox(8)
		var nl := Label.new()
		nl.text = String(r[1])
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if amount == 0:
			nl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		h.add_child(nl)
		var al := Label.new()
		al.add_theme_font_override("font", UITheme.font_bold())
		al.text = OvUtil.money_signed(0)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		al.custom_minimum_size = Vector2(150, 0)
		var col: Color = UITheme.TEXT_MUTED
		if amount != 0:
			col = GREEN if sign_v > 0 else RED
		al.add_theme_color_override("font_color", col)
		h.add_child(al)
		lv.add_child(h)
		_ledger_rows.append({"row": h, "label": al, "value": amount * sign_v})
	lv.add_child(HSeparator.new())
	var ph := UIKit.hbox(8)
	var pl := UIKit.header_label("Profit")
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pl)
	var pa := Label.new()
	pa.add_theme_font_override("font", UITheme.font_bold())
	pa.add_theme_font_size_override("font_size", 38)
	pa.text = "$0"
	pa.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pa.custom_minimum_size = Vector2(200, 0)
	ph.add_child(pa)
	lv.add_child(ph)
	_profit_row = {"row": ph, "label": pa, "value": int(_result.get("profit", 0))}
	var wages: int = _lget(ledger, "wages")
	if wages > 0:
		# paid in port, outside the voyage profit: a greyed note below the total, never a row of the sum
		_wages_row = UIKit.hbox(8)
		var wl := UIKit.small_label("Crew wages (paid in port)")
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_wages_row.add_child(wl)
		var wv := UIKit.small_label(OvUtil.money(wages))
		wv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_wages_row.add_child(wv)
		lv.add_child(_wages_row)
	right.add_child(led)
	# guests
	var gh := UIKit.hbox(10)
	var served := _light_pill(&"guest", "%d visits, %d guests" % [int(_result.get("served", 0)), int(_result.get("guests_total", 0))])
	var lost_n: int = int(_result.get("guests_lost", 0))
	var lost := _light_pill(&"angry" if lost_n > 0 else &"heart", "Lost %d" % lost_n if lost_n > 0 else "No guests lost")
	gh.add_child(served)
	gh.add_child(lost)
	_stat_pills.append(served)
	_stat_pills.append(lost)
	right.add_child(gh)
	var groups_info: Dictionary = _result.get("groups", {})
	if int(groups_info.get("count", 0)) > 0:
		var split_n: int = int(groups_info.get("split", 0))
		var gtxt: String = "%d couples & families" % int(groups_info["count"])
		if int(groups_info["count"]) == 1:
			gtxt = "1 couple / family"
		if split_n > 0:
			gtxt += ", %d split up" % split_n
		var gp := _light_pill(&"family", gtxt)
		gp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_stat_pills.append(gp)
		right.add_child(gp)
	# the mid-voyage port stop (SPEC §13.8): where, how many went ashore / boarded and what the refit added
	var stop_info: Dictionary = _result.get("port_stop", {})
	if not stop_info.is_empty():
		var built: int = int(stop_info.get("rooms", 0)) + int(stop_info.get("upgrades", 0))
		var stxt: String = "%s: %d ashore, %d boarded" % [String(stop_info.get("name", "Port")), int(stop_info.get("excursion", 0)), int(stop_info.get("boarded", 0))]
		if built > 0:
			stxt += ", refit +%d" % built
		var sp := _light_pill(&"event", stxt)
		sp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_stat_pills.append(sp)
		right.add_child(sp)
	var vip_plate: Control = _build_vip_plate()
	if vip_plate != null:
		right.add_child(vip_plate)
		_stat_pills.append(vip_plate)
	# next-star nudge
	if not _mutiny() and _stars_n() < 3:
		for g: Variant in _result.get("goals", []):
			var gd2: Dictionary = g
			if not bool(gd2.get("met", false)):
				var np := _plate()
				var nh := UIKit.hbox(14)
				np.add_child(nh)
				nh.add_child(GlyphView.new(&"star_empty", 40.0))
				var nv := UIKit.vbox(0)
				nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				nv.add_child(UIKit.small_label("TRY FOR THE NEXT STAR"))
				var nt := Label.new()
				nt.text = String(gd2.get("text", ""))
				nt.add_theme_font_override("font", UITheme.font_bold())
				nv.add_child(nt)
				nh.add_child(nv)
				right.add_child(np)
				_next_star_panel = np
				break
	# unlocks
	_build_unlocks(right)
	if _mutiny():
		var tip := _plate()
		var th := UIKit.hbox(14)
		tip.add_child(th)
		th.add_child(GlyphView.new(&"warning", 44.0))
		var tv := UIKit.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UIKit.header_label("Captain's tip"))
		var tl := UIKit.small_label("The ship mutinies if the rating stays under 20% for 30 seconds. Clean messes, fix breakdowns and feed the hungry first.")
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.custom_minimum_size = Vector2(440, 0)
		tv.add_child(tl)
		th.add_child(tv)
		right.add_child(tip)
		_tip_panel = tip


## "VIP verdicts": one row per VIP with the kind, how the review went and the verdict chip (grade + money).
func _build_vip_plate() -> Control:
	var vips: Array = _result.get("vips", [])
	if vips.is_empty():
		return null
	var p := _plate()
	p.name = "VipPlate"
	var v := UIKit.vbox(6)
	p.add_child(v)
	v.add_child(UIKit.small_label("VIP VERDICTS"))
	for e: Variant in vips:
		var d: Dictionary = e
		var kind: StringName = StringName(d.get("kind", &""))
		var grade: StringName = StringName(d.get("grade", &""))
		var row := UIKit.hbox(10)
		row.add_child(GlyphView.new(kind, 42.0))
		var col := UIKit.vbox(0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var nl := Label.new()
		nl.text = VipSim.kind_label(kind)
		nl.add_theme_font_override("font", UITheme.font_bold())
		nl.add_theme_font_size_override("font_size", 22)
		col.add_child(nl)
		var dl := UIKit.small_label(String(d.get("detail", "")))
		dl.add_theme_font_size_override("font_size", 16)
		col.add_child(dl)
		row.add_child(col)
		row.add_child(_vip_chip(grade, int(d.get("pay", 0))))
		v.add_child(row)
	return p


## Verdict chip: grade word + money, tinted by the grade.
func _vip_chip(grade: StringName, pay: int) -> Control:
	var tint: Color = GREEN if grade == VipSim.GREAT else (RED if grade == VipSim.BAD else Palette.TEAL_DARK)
	var c := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tint.r, tint.g, tint.b, 0.14)
	sb.border_color = tint
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.anti_aliasing = true
	c.add_theme_stylebox_override("panel", sb)
	c.custom_minimum_size = Vector2(124, 0)
	var vb := UIKit.vbox(-2)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var gl := Label.new()
	gl.text = VipSim.grade_label(grade).to_upper()
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.add_theme_font_override("font", UITheme.font_bold())
	gl.add_theme_font_size_override("font_size", 22)
	gl.add_theme_color_override("font_color", tint)
	vb.add_child(gl)
	var ml := Label.new()
	ml.text = OvUtil.money_signed(pay) if pay != 0 else "no change"
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.add_theme_font_override("font", UITheme.font_bold())
	ml.add_theme_font_size_override("font_size", 16)
	ml.add_theme_color_override("font_color", tint if pay != 0 else UITheme.TEXT_MUTED)
	vb.add_child(ml)
	c.add_child(vb)
	return c


func _light_pill(icon: StringName, text: String) -> StatPill:
	var p := UIKit.stat_pill(icon, text)
	p.set_light(true)
	return p


func _chip(icon: StringName, name_text: String, tag: String, tint: Color) -> PanelContainer:
	var c := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(16)
	sb.border_color = tint
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0.1, 0.14, 0.26, 0.16)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 10
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = true
	c.add_theme_stylebox_override("panel", sb)
	var h := UIKit.hbox(10)
	c.add_child(h)
	h.add_child(GlyphView.new(icon, 46.0))
	var v := UIKit.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var nl := Label.new()
	nl.text = name_text
	nl.add_theme_font_override("font", UITheme.font_bold())
	nl.add_theme_font_size_override("font_size", 21)
	v.add_child(nl)
	var tl := Label.new()
	tl.text = tag
	tl.add_theme_font_override("font", UITheme.font_bold())
	tl.add_theme_font_size_override("font_size", 15)
	tl.add_theme_color_override("font_color", tint)
	v.add_child(tl)
	h.add_child(v)
	return c


func _build_unlocks(right: VBoxContainer) -> void:
	var items: Array[Control] = []
	for rid: StringName in _unlocks.get("newly_unlocked_rooms", []):
		var rd: RoomDef = ContentDB.room(rid)
		items.append(_chip(rid, rd.display_name if rd != null else String(rid), "NEW ROOM", Palette.CORAL))
	for did: StringName in _unlocks.get("newly_unlocked_destinations", []):
		var dd: DestinationDef = ContentDB.destination(did)
		items.append(_chip(&"star", (dd.display_name if dd != null else String(did)) + " unlocked", "NEW DESTINATION", Palette.TEAL))
	for fid: StringName in _unlocks.get("newly_unlocked_features", []):
		var role_id: StringName = SaveManager.staff_role_of_feature(fid)
		if role_id != &"":
			items.append(_chip(IconArt.role_icon(role_id), SaveManager.feature_display_name(fid), "NEW CREW", Palette.role_color(role_id)))
		elif fid == &"guests_vips":
			items.append(_chip(&"vip", SaveManager.feature_display_name(fid), "NEW GUESTS", Palette.SUN_DEEP))
		elif fid == &"guests_kids":
			items.append(_chip(&"kid", SaveManager.feature_display_name(fid), "NEW GUESTS", Palette.PINK))
		else:
			items.append(_chip(&"wrench", SaveManager.feature_display_name(fid), "NEW UPGRADE", Palette.LILAC_DARK))
	var lvl_ids: Array = _unlocks.get("newly_unlocked_levels", [])
	if not lvl_ids.is_empty():
		var ld: LevelDef = ContentDB.level(lvl_ids[0])
		if ld != null:
			items.append(_chip(&"event", "Level %d: %s" % [ld.campaign_index, ld.display_name], "NEW LEVEL", Palette.MINT_DARK))
	if items.is_empty():
		return
	var box := UIKit.vbox(6)
	var hdr := UIKit.header_label("Unlocked!")
	hdr.add_theme_color_override("font_color", Palette.CORAL)
	box.add_child(hdr)
	_chip_title = hdr
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	for c in items:
		flow.add_child(c)
		_chips.append(c)
	box.add_child(flow)
	right.add_child(box)


# ================================================================================================
# reveal timeline
# ================================================================================================
func _start() -> void:
	_shown_msec = Time.get_ticks_msec()
	# initial hidden states
	for g in _goal_rows:
		(g["row"] as Control).modulate.a = 0.0
	for l in _ledger_rows:
		(l["row"] as Control).modulate.a = 0.0
	(_profit_row["row"] as Control).modulate.a = 0.0
	if _wages_row != null:
		_wages_row.modulate.a = 0.0
	for c in _chips:
		c.modulate.a = 0.0
	if _chip_title != null:
		_chip_title.modulate.a = 0.0
	for p in _stat_pills:
		p.modulate.a = 0.0
	if _tip_panel != null:
		_tip_panel.modulate.a = 0.0
	if _next_star_panel != null:
		_next_star_panel.modulate.a = 0.0
	_btn_row.modulate.a = 0.0
	_hint.modulate.a = 0.0
	if _funds_plate != null:
		_funds_plate.modulate.a = 0.0
	# card entrance
	_backdrop.modulate.a = 0.0
	_slide.position = Vector2(0, 170)
	_slide.modulate.a = 0.0
	if _tw != null:
		_tw.kill()
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(_backdrop, "modulate:a", 1.0, 0.25)
	_tw.tween_property(_slide, "position:y", 0.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_slide, "modulate:a", 1.0, 0.25)
	# stars follow the AudioManager jingle timing
	var n: int = _stars_n()
	if _stars != null:
		for i in range(3):
			if i < n:
				_tw.tween_callback(_stars.pop.bind(i)).set_delay(STAR_START + STAR_GAP * float(i))
	if n == 3:
		_tw.tween_callback(_confetti.burst).set_delay(STAR_START + STAR_GAP * 2.0)
	# rating
	_tw.tween_method(_set_rating, 0.0, float(_result.get("rating", 0.0)), 1.1).set_delay(0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	# goals
	for i in range(_goal_rows.size()):
		_tw.tween_callback(_reveal_goal.bind(i)).set_delay(0.65 + 0.32 * float(i))
	# ledger
	for i in range(_ledger_rows.size()):
		_tw.tween_callback(_reveal_ledger.bind(i)).set_delay(0.6 + 0.12 * float(i))
	_tw.tween_callback(_reveal_profit).set_delay(0.6 + 0.12 * float(_ledger_rows.size()) + 0.1)
	for i in range(_stat_pills.size()):
		_tw.tween_callback(_reveal_pill.bind(i)).set_delay(1.35 + 0.12 * float(i))
	if _funds_plate != null:
		_tw.tween_callback(_reveal_funds).set_delay(1.6)
	# unlock chips after the last star lands
	var chip_t: float = STAR_START + STAR_GAP * float(maxi(n, 1)) + 0.15
	if _chip_title != null:
		_tw.tween_callback(_reveal_chip_title).set_delay(chip_t)
	for i in range(_chips.size()):
		_tw.tween_callback(_reveal_chip.bind(i)).set_delay(chip_t + 0.12 + 0.18 * float(i))
	if _next_star_panel != null:
		_tw.tween_callback(func() -> void:
			_next_star_panel.modulate.a = 1.0
			OvUtil.pop_in(_next_star_panel, 0.0, 0.35)).set_delay(1.6)
	if _tip_panel != null:
		_tw.tween_callback(func() -> void:
			_tip_panel.modulate.a = 1.0
			OvUtil.pop_in(_tip_panel, 0.0, 0.35)).set_delay(1.7)
	# buttons
	_tw.tween_callback(_reveal_buttons).set_delay(1.0)
	_tw.chain().tween_callback(func() -> void: _revealed_all = true)
	_focus_default.call_deferred()


func _focus_default() -> void:
	if _next_btn != null and not _next_btn.disabled and _stars_n() >= 1:
		_next_btn.grab_focus()
	elif _retry_btn != null:
		_retry_btn.grab_focus()


func _set_rating(v: float) -> void:
	_rating_label.text = "%d%%" % int(round(v))
	_rating_bar.value = v / 100.0
	var f: float = v / 100.0
	_rating_bar.theme_type_variation = &"MintBar" if v >= 65.0 else (&"SunBar" if v >= 40.0 else &"CoralBar")
	var amber: Color = Color("D9901A")
	var col: Color = RED.lerp(amber, clampf(f / 0.4, 0.0, 1.0)) if f < 0.4 else amber.lerp(GREEN, clampf((f - 0.4) / 0.3, 0.0, 1.0))
	_rating_label.add_theme_color_override("font_color", col)


func _reveal_goal(i: int) -> void:
	var g: Dictionary = _goal_rows[i]
	var row: Control = g["row"]
	var chk: _Check = g["check"]
	row.modulate.a = 1.0
	chk.reveal(not _skipped)


func _reveal_ledger(i: int) -> void:
	var l: Dictionary = _ledger_rows[i]
	var row: Control = l["row"]
	row.modulate.a = 1.0
	var target: int = int(l["value"])
	var lab: Label = l["label"]
	if _skipped or target == 0:
		lab.text = OvUtil.money_signed(target)
		return
	row.create_tween().tween_method(func(v: float) -> void: lab.text = OvUtil.money_signed(int(round(v))), 0.0, float(target), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _reveal_profit() -> void:
	var row: Control = _profit_row["row"]
	row.modulate.a = 1.0
	var lab: Label = _profit_row["label"]
	var target: int = int(_profit_row["value"])
	lab.add_theme_color_override("font_color", GREEN if target >= 0 else RED)
	if _wages_row != null:
		if _skipped:
			_wages_row.modulate.a = 1.0
		else:
			OvUtil.fade_in(_wages_row, 0.5, 0.4)
	if _skipped:
		lab.text = OvUtil.money_signed(target)
		return
	lab.pivot_offset = Vector2(lab.size.x, lab.size.y * 0.5)
	var tw := lab.create_tween()
	tw.tween_method(func(v: float) -> void: lab.text = OvUtil.money_signed(int(round(v))), 0.0, float(target), 0.8).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	lab.scale = Vector2(1.18, 1.18)
	tw.parallel().tween_property(lab, "scale", Vector2.ONE, 0.5).set_delay(0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _reveal_funds() -> void:
	if _funds_plate == null:
		return
	_funds_plate.modulate.a = 1.0
	if _skipped or _funds_target <= 0:
		return
	OvUtil.pop_in(_funds_plate, 0.0, 0.35)
	var label_text: String = _funds_amount.text
	var suffix: String = label_text.substr(label_text.find(" company"))
	if _funds_tw != null:
		_funds_tw.kill()
	_funds_tw = create_tween()
	_funds_tw.tween_method(func(v: float) -> void: _funds_amount.text = "+%s%s" % [OvUtil.money(int(round(v))), suffix], 0.0, float(_funds_target), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _reveal_pill(i: int) -> void:
	var p: Control = _stat_pills[i]
	p.modulate.a = 1.0
	if not _skipped:
		OvUtil.pop_in(p, 0.0, 0.3)


func _reveal_chip_title() -> void:
	_chip_title.modulate.a = 1.0
	if not _skipped:
		OvUtil.pop_in(_chip_title, 0.0, 0.3)


func _reveal_chip(i: int) -> void:
	var c: Control = _chips[i]
	c.modulate.a = 1.0
	if _skipped:
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.3, 0.3)
	c.rotation = -0.16
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", 0.0, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _reveal_buttons() -> void:
	_btn_row.modulate.a = 1.0
	_hint.modulate.a = 1.0
	if not _skipped:
		OvUtil.fade_in(_btn_row, 0.0, 0.3)
		OvUtil.fade_in(_hint, 0.0, 0.3)


## Keyboard guard (runs before the focused button sees the key): Space never activates a button on this screen,
## and Enter / ui_accept only counts after KEY_GRACE_MSEC.
func _input(event: InputEvent) -> void:
	if not visible or _shown_msec == 0:
		return
	if _report_view != null and (event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel")):
		get_viewport().set_input_as_handled()
		show_main()
		return
	var ke := event as InputEventKey
	var is_space: bool = ke != null and (ke.keycode == KEY_SPACE or ke.physical_keycode == KEY_SPACE)
	var in_grace: bool = Time.get_ticks_msec() - _shown_msec < KEY_GRACE_MSEC
	if is_space or (in_grace and event.is_action(&"ui_accept")):
		get_viewport().set_input_as_handled()


func _on_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		skip_reveal()


## Jumps to the final state of the reveal.
func skip_reveal() -> void:
	if _revealed_all or _skipped:
		return
	_skipped = true
	if _tw != null:
		_tw.kill()
	_backdrop.modulate.a = 1.0
	_slide.position = Vector2.ZERO
	_slide.modulate.a = 1.0
	_set_rating(float(_result.get("rating", 0.0)))
	if _stars != null:
		_stars.show_all()
	for i in range(_goal_rows.size()):
		_reveal_goal(i)
	for i in range(_ledger_rows.size()):
		_reveal_ledger(i)
	_reveal_profit()
	for i in range(_stat_pills.size()):
		_reveal_pill(i)
	if _funds_plate != null:
		_funds_plate.modulate.a = 1.0
		if _funds_tw != null:
			_funds_tw.kill()
		if _funds_target > 0:
			_funds_amount.text = "+%s company funds (new best!)" % OvUtil.money(_funds_target)
	if _chip_title != null:
		_reveal_chip_title()
	for i in range(_chips.size()):
		_reveal_chip(i)
	if _tip_panel != null:
		_tip_panel.modulate.a = 1.0
	if _next_star_panel != null:
		_next_star_panel.modulate.a = 1.0
	_reveal_buttons()
	_revealed_all = true


# ================================================================================================
# inner widgets
# ================================================================================================
class _Check extends Control:
	var met: bool = false
	var _state: float = 0.0   # 0 = hidden/empty, 0..1 = popping, 1 = done
	var _revealed: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(36, 36)
		set_process(false)

	func reveal(animated: bool) -> void:
		_revealed = true
		if not animated:
			_state = 1.0
			queue_redraw()
			return
		_state = 0.0
		set_process(true)

	func _process(delta: float) -> void:
		_state = minf(_state + delta * 3.2, 1.0)
		queue_redraw()
		if _state >= 1.0:
			set_process(false)

	func _draw() -> void:
		var c := size * 0.5
		var r: float = 15.0
		if not _revealed:
			ArtUtil.ring(self, c, r - 1.0, Color(0.4, 0.45, 0.58, 0.45), 3.0)
			return
		var k: float = ArtUtil.ease_out_back(clampf(_state, 0.0, 1.0)) if _state < 1.0 else 1.0
		var col: Color = Palette.MINT_DARK if met else Palette.CORAL
		ArtUtil.circ(self, c + Vector2(0, 2), r * k, Color(0.1, 0.14, 0.26, 0.2))
		ArtUtil.circ(self, c, r * k, col)
		var w: float = 4.0
		if met:
			var pts := PackedVector2Array([c + Vector2(-6.5, 0.5) * k, c + Vector2(-2.0, 5.5) * k, c + Vector2(7.0, -5.0) * k])
			ArtUtil.pline(self, pts, Color.WHITE, w)
		else:
			ArtUtil.line(self, c + Vector2(-5, -5) * k, c + Vector2(5, 5) * k, Color.WHITE, w)
			ArtUtil.line(self, c + Vector2(5, -5) * k, c + Vector2(-5, 5) * k, Color.WHITE, w)


class _Stars extends Control:
	var earned: int = 0
	var star_px: float = 150.0
	var _pop: Array[float] = [-1.0, -1.0, -1.0]
	var _parts: Array[Dictionary] = []
	var _rings: Array[Dictionary] = []
	var _t: float = 0.0
	var _rng := RandomNumberGenerator.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(540, 232)
		_rng.seed = 90210

	func _slot(i: int) -> Vector2:
		var gap: float = star_px * 1.04
		var x: float = size.x * 0.5 + float(i - 1) * gap
		var y: float = size.y * 0.5 + (-14.0 if i == 1 else 18.0)
		return Vector2(x, y)

	func pop(i: int) -> void:
		_pop[i] = 0.0
		var c := _slot(i)
		_rings.append({"c": c, "age": 0.0})
		var cols: Array[Color] = [Palette.SUN, Color.WHITE, Palette.MINT, Palette.CORAL_LIGHT, Palette.GOLD]
		for k in range(16):
			var a: float = _rng.randf() * TAU
			var sp: float = _rng.randf_range(120.0, 300.0)
			_parts.append({"p": c, "v": Vector2(cos(a), sin(a)) * sp, "age": 0.0, "life": _rng.randf_range(0.55, 0.95),
					"col": cols[k % cols.size()], "r": _rng.randf_range(0.7, 1.3)})
		set_process(true)

	func show_all() -> void:
		for i in range(earned):
			_pop[i] = 1.0
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		for i in range(3):
			if _pop[i] >= 0.0 and _pop[i] < 1.0:
				_pop[i] = minf(_pop[i] + delta / 0.6, 1.0)
		for p in _parts:
			p["age"] = float(p["age"]) + delta
			p["v"] = (p["v"] as Vector2) * (1.0 - 2.2 * delta) + Vector2(0, 160.0) * delta
			p["p"] = (p["p"] as Vector2) + (p["v"] as Vector2) * delta
		_parts = _parts.filter(func(p: Dictionary) -> bool: return float(p["age"]) < float(p["life"]))
		for r in _rings:
			r["age"] = float(r["age"]) + delta
		_rings = _rings.filter(func(r: Dictionary) -> bool: return float(r["age"]) < 0.6)
		queue_redraw()

	func _draw() -> void:
		for i in range(3):
			var c := _slot(i)
			var rot: float = (float(i) - 1.0) * 0.2
			# slot placeholder
			ArtUtil.begin_scaled(self, c, 1.0)
			ArtUtil.base_xf = Transform2D(rot, Vector2.ONE, 0.0, c)
			ArtUtil.cur_xf = ArtUtil.base_xf
			draw_set_transform_matrix(ArtUtil.base_xf)
			IconArt.draw_icon(self, &"star_empty", Vector2.ZERO, star_px * 0.94, 0.0, false)
			ArtUtil.end_scaled(self)
			if _pop[i] >= 0.0:
				var p: float = _pop[i]
				var k: float = ArtUtil.ease_out_back(clampf(p, 0.0, 1.0)) if p < 1.0 else 1.0
				var hop: float = -sin(clampf(p, 0.0, 1.0) * PI) * 18.0
				var wob: float = sin(p * 11.0) * 0.14 * (1.0 - p)
				# warm glow
				ArtUtil.circ(self, c + Vector2(0, hop), star_px * 0.5 * k, Color(1.0, 0.85, 0.4, 0.16 * (0.5 + 0.5 * sin(_t * 3.0 + float(i)))))
				ArtUtil.begin_scaled(self, c, 1.0)
				ArtUtil.base_xf = Transform2D(rot + wob, Vector2.ONE, 0.0, c + Vector2(0, hop))
				ArtUtil.cur_xf = ArtUtil.base_xf
				draw_set_transform_matrix(ArtUtil.base_xf)
				IconArt.draw_icon(self, &"star", Vector2.ZERO, star_px * k, _t, false)
				ArtUtil.end_scaled(self)
		for r in _rings:
			var a: float = float(r["age"]) / 0.6
			ArtUtil.ring(self, r["c"], star_px * 0.45 + 120.0 * ArtUtil.smooth(a), Color(1.0, 0.9, 0.5, 0.7 * (1.0 - a)), 5.0 * (1.0 - a) + 1.0)
		for p in _parts:
			var t01: float = float(p["age"]) / float(p["life"])
			FxArt.draw_sparkle(self, p["p"], t01, p["col"])


class _Confetti extends Control:
	var _bits: Array[Dictionary] = []
	var _emit_left: float = 0.0
	var _rng := RandomNumberGenerator.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)
		_rng.seed = 4242

	func burst() -> void:
		_emit_left = 2.4
		set_process(true)

	func _process(delta: float) -> void:
		if _emit_left > 0.0:
			_emit_left -= delta
			for k in range(3):
				var cols: Array[Color] = [Palette.CORAL, Palette.SUN, Palette.TEAL, Palette.MINT, Palette.LILAC, Palette.PINK]
				_bits.append({"p": Vector2(_rng.randf() * size.x, -20.0), "v": _rng.randf_range(170.0, 340.0), "sw": _rng.randf() * 6.0,
						"swf": _rng.randf_range(1.5, 3.5), "rot": _rng.randf() * TAU, "spin": _rng.randf_range(-6.0, 6.0),
						"col": cols[_rng.randi() % cols.size()], "w": _rng.randf_range(8.0, 15.0)})
		for b in _bits:
			b["p"] = (b["p"] as Vector2) + Vector2(sin(float(b["sw"])) * 70.0 * delta, float(b["v"]) * delta)
			b["sw"] = float(b["sw"]) + float(b["swf"]) * delta
			b["rot"] = float(b["rot"]) + float(b["spin"]) * delta
		_bits = _bits.filter(func(b: Dictionary) -> bool: return (b["p"] as Vector2).y < size.y + 30.0)
		queue_redraw()
		if _bits.is_empty() and _emit_left <= 0.0:
			set_process(false)

	func _draw() -> void:
		for b in _bits:
			var w: float = float(b["w"])
			var rot: float = float(b["rot"])
			var squash: float = absf(cos(float(b["sw"]) * 1.7))
			var ax := Vector2(cos(rot), sin(rot)) * w * 0.5
			var ay := Vector2(-sin(rot), cos(rot)) * w * 0.3 * squash
			var c: Vector2 = b["p"]
			var pts := PackedVector2Array([c - ax - ay, c + ax - ay, c + ax + ay, c - ax + ay])
			ArtUtil.poly(self, pts, b["col"])
