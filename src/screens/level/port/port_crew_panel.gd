class_name PortCrewPanel
extends HBoxContainer
## "Crew" tab of the build bar: janitor + mechanic cards with portraits, wage, what they handle and
## hire / fire buttons. Preset (free) crew show as locked portraits; hired crew pop in.

signal hire_requested(role: StringName)
signal fire_requested(role: StringName)

const ROLES: Array[StringName] = [&"janitor", &"mechanic"]
const HANDLES_TEXT: Dictionary = {
	&"mess": "Cleans up messes",
	&"breakdown": "Repairs broken rooms",
}

var _port: PortState
var _cards: Dictionary = {}   # role -> {portraits: HBox, count: Label, hire: Button, fire: Button, hint: Label}
var _summary_dots: HBoxContainer
var _summary_label: Label
var _summary_note: Label
var _last_counts: Dictionary = {}


func setup(port: PortState) -> void:
	_port = port
	add_theme_constant_override("separation", 16)
	for role in ROLES:
		var def: StaffDef = ContentStore.staff_role(role)
		if def != null:
			add_child(_build_card(def))
	add_child(_build_summary())
	refresh()


func _build_card(def: StaffDef) -> Control:
	var card := UIKit.card()
	card.custom_minimum_size = Vector2(500, 0)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UITheme.flat(UITheme.CARD, 16, UITheme.CARD_EDGE, 2, Color(0.05, 0.08, 0.16, 0.3), 8, Vector2(0, 4), Vector4(14, 10, 14, 10)))
	var h := UIKit.hbox(14)
	card.add_child(h)
	var left := UIKit.vbox(4)
	left.custom_minimum_size = Vector2(100, 0)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	var big := BeanPortrait.new()
	big.staff_role = def.id
	big.portrait_size = 92.0
	big.plate_color = Color("FFE6A8")
	left.add_child(big)
	h.add_child(left)
	var right := UIKit.vbox(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var title := UIKit.hbox(8)
	var nm := UIKit.header_label(def.display_name)
	title.add_child(nm)
	title.add_child(UIKit.h_spacer())
	var wage := StatPill.new(&"coin", "$%d" % def.wage)
	wage.set_light(true)
	title.add_child(wage)
	right.add_child(title)
	var what := UIKit.hbox(6)
	var wi := IconView.new()
	wi.icon = &"mop" if def.handles == &"mess" else &"wrench"
	wi.icon_size = 22.0
	what.add_child(wi)
	var wl := UIKit.small_label(String(HANDLES_TEXT.get(def.handles, "Helps out")))
	what.add_child(wl)
	right.add_child(what)
	var portraits := UIKit.hbox(5)
	portraits.custom_minimum_size = Vector2(0, 46)
	right.add_child(portraits)
	var ctl := UIKit.hbox(10)
	var fire := UIKit.secondary_button("-")
	fire.custom_minimum_size = Vector2(56, 46)
	fire.tooltip_text = "Dismiss one (refunds the wage)"
	fire.pressed.connect(func() -> void: fire_requested.emit(def.id))
	ctl.add_child(fire)
	var count := UIKit.header_label("0")
	count.custom_minimum_size = Vector2(34, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctl.add_child(count)
	var hire := UIKit.primary_button("Hire  $%d" % def.wage)
	hire.custom_minimum_size = Vector2(170, 46)
	hire.pressed.connect(func() -> void: hire_requested.emit(def.id))
	ctl.add_child(hire)
	right.add_child(ctl)
	_cards[def.id] = {"portraits": portraits, "count": count, "hire": hire, "fire": fire, "card": card}
	return card


func _build_summary() -> Control:
	var v := UIKit.vbox(8)
	v.custom_minimum_size = Vector2(260, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := Label.new()
	t.text = "Crew"
	t.theme_type_variation = &"OnDarkTitle"
	t.add_theme_font_size_override("font_size", 28)
	v.add_child(t)
	_summary_label = Label.new()
	_summary_label.theme_type_variation = &"OnDark"
	v.add_child(_summary_label)
	_summary_dots = UIKit.hbox(5)
	_summary_dots.custom_minimum_size = Vector2(0, 26)
	v.add_child(_summary_dots)
	_summary_note = Label.new()
	_summary_note.theme_type_variation = &"OnDarkSmall"
	_summary_note.add_theme_font_size_override("font_size", 17)
	_summary_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_note.custom_minimum_size = Vector2(230, 0)
	v.add_child(_summary_note)
	return v


func portrait_global_rect(role: StringName) -> Rect2:
	var d: Dictionary = _cards.get(role, {})
	if d.is_empty():
		return Rect2()
	return (d["hire"] as Button).get_global_rect()


func hire_button(role: StringName) -> Button:
	var d: Dictionary = _cards.get(role, {})
	return d.get("hire") as Button if not d.is_empty() else null


func fire_button(role: StringName) -> Button:
	var d: Dictionary = _cards.get(role, {})
	return d.get("fire") as Button if not d.is_empty() else null


func refresh() -> void:
	if _port == null:
		return
	var total: int = _port.staff_total()
	var maxn: int = _port.max_staff()
	var problem: String = ""
	var free_crew: int = 0
	for role in ROLES:
		var d: Dictionary = _cards.get(role, {})
		if d.is_empty():
			continue
		var def: StaffDef = ContentStore.staff_role(role)
		var preset: int = int(_port.preset_staff.get(role, 0))
		free_crew += preset
		var hired: int = int(_port.hired.get(role, 0))
		var box: HBoxContainer = d["portraits"]
		var prev_total: int = int(_last_counts.get(role, -1))
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
		for i in preset:
			box.add_child(_mini(role, true, false))
		for i in hired:
			var is_new: bool = prev_total >= 0 and i == hired - 1 and (preset + hired) > prev_total
			box.add_child(_mini(role, false, is_new))
		if preset + hired == 0:
			var none := UIKit.small_label("Nobody yet")
			none.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(none)
		_last_counts[role] = preset + hired
		(d["count"] as Label).text = str(preset + hired)
		var hire: Button = d["hire"]
		var chk: Dictionary = _port.can_hire(role)
		hire.disabled = not bool(chk["ok"])
		var fire: Button = d["fire"]
		fire.disabled = hired <= 0
		if not bool(chk["ok"]):
			problem = String(chk["reason"])
		(d["card"] as Control).tooltip_text = "%s: %s. Wage $%d." % [def.display_name, String(HANDLES_TEXT.get(def.handles, "")), def.wage]
	_summary_label.text = "%d of %d crew berths filled" % [total, maxn]
	if problem != "":
		_summary_note.text = problem
		_summary_note.add_theme_color_override("font_color", Palette.CORAL_LIGHT)
	else:
		_summary_note.text = "Wages are paid now, and mid-voyage hires cost 1.5x." + (("\n%d free crew can't be dismissed." % free_crew) if free_crew > 0 else "")
		_summary_note.add_theme_color_override("font_color", Color("C9D3E8"))
	for c in _summary_dots.get_children():
		_summary_dots.remove_child(c)
		c.queue_free()
	for i in maxn:
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(24, 24)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var filled: bool = i < total
		dot.draw.connect(func() -> void:
			ArtUtil.circ(dot, Vector2(12, 12), 10.0, Palette.SUN if filled else Color(1, 1, 1, 0.16)))
		_summary_dots.add_child(dot)


func _mini(role: StringName, locked: bool, animate_in: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(46, 46)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bp := BeanPortrait.new()
	bp.staff_role = role
	bp.portrait_size = 44.0
	bp.plate_color = Color("E4DCCB") if locked else Color("FFE6A8")
	bp.animate = false
	bp.position = Vector2(1, 1)
	holder.add_child(bp)
	if locked:
		var lk := IconView.new()
		lk.icon = &"lock"
		lk.icon_size = 20.0
		lk.position = Vector2(26, 24)
		holder.add_child(lk)
		holder.tooltip_text = "Free crew from the level. Can't be dismissed."
		holder.mouse_filter = Control.MOUSE_FILTER_PASS
	if animate_in:
		holder.pivot_offset = Vector2(23, 23)
		holder.scale = Vector2.ZERO
		holder.ready.connect(func() -> void:
			var tw := holder.create_tween()
			tw.tween_property(holder, "scale", Vector2.ONE, 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT), CONNECT_ONE_SHOT)
	return holder
