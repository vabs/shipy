class_name PortCrewPanel
extends HBoxContainer
## "Crew" tab of the build bar: one card per role the level offers (janitor, mechanic, medic, entertainer, chef,
## warden) with portrait, wage, what they do and hire / fire buttons. With one or two roles the cards are large and
## show the hired crew as portraits (preset free crew as locked ones); from three roles on they are compact (one
## row of narrow cards) so six roles fit the bar. Level-3 players see a medic, level 13 in the Underworld all six.

signal hire_requested(role: StringName)
signal fire_requested(role: StringName)

const HANDLES_TEXT: Dictionary = {
	&"mess": "Cleans up messes",
	&"breakdown": "Repairs broken rooms",
	&"sick": "Treats sick guests",
	&"ghost": "Banishes ghosts",
	&"aura": "Works a room",
}
## From this many roles on the cards turn compact.
const COMPACT_FROM: int = 3

var _port: PortState
static var _theme_cache: Theme = null
var _roles: Array[StaffDef] = []
var _compact: bool = false
var _cards: Dictionary = {}   # role -> {portraits: HBox, count: Label, hire: Button, fire: Button, hint: Label}
var _summary_dots: HBoxContainer
var _summary_label: Label
var _summary_note: Label
var _last_counts: Dictionary = {}


func setup(port: PortState) -> void:
	_port = port
	_roles = port.available_roles()
	_compact = _roles.size() >= COMPACT_FROM
	add_theme_constant_override("separation", 16)
	if _compact:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for def in _roles:
			row.add_child(_build_compact_card(def))
		add_child(row)
	else:
		for def in _roles:
			add_child(_build_card(def))
	add_child(_build_summary())
	refresh()


## Trims a themed button's side padding (so a card of six fits the bar): copies its styleboxes with narrow margins.
func _slim(b: Button, margin: float) -> void:
	if _theme_cache == null:
		_theme_cache = UITheme.build()
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBox = _theme_cache.get_stylebox(state, b.theme_type_variation)
		if sb is StyleBoxFlat:
			var d: StyleBoxFlat = (sb as StyleBoxFlat).duplicate()
			d.content_margin_left = margin
			d.content_margin_right = margin
			b.add_theme_stylebox_override(state, d)


func _what_text(def: StaffDef) -> String:
	if def.description != "":
		return def.description
	return String(HANDLES_TEXT.get(def.handles, "Helps out"))


## Compact card (3+ roles, one row of up to six): portrait + name, two lines of what they do, [-] count [Hire $].
func _build_compact_card(def: StaffDef) -> Control:
	var card := UIKit.card()
	card.custom_minimum_size = Vector2(170, 0)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UITheme.flat(UITheme.CARD, 16, UITheme.CARD_EDGE, 2, Color(0.05, 0.08, 0.16, 0.3), 8, Vector2(0, 4), Vector4(10, 8, 10, 8)))
	var v := UIKit.vbox(5)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	var top := UIKit.hbox(8)
	v.add_child(top)
	var big := BeanPortrait.new()
	big.staff_role = def.id
	big.portrait_size = 54.0
	big.plate_color = Palette.role_plate(def.id)
	big.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(big)
	var nm := UIKit.header_label(def.display_name)
	nm.add_theme_font_size_override("font_size", 19)
	nm.clip_text = true   # a clipped label has no minimum width, so six cards always fit the bar
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(nm)
	var wl := UIKit.small_label(_what_text(def))
	wl.add_theme_font_size_override("font_size", 15)
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wl.custom_minimum_size = Vector2(0, 40)
	v.add_child(wl)
	var ctl := UIKit.hbox(6)
	var fire := UIKit.secondary_button("-")
	fire.custom_minimum_size = Vector2(34, 40)
	_slim(fire, 6.0)
	fire.tooltip_text = "Dismiss one (refunds the wage)"
	fire.pressed.connect(func() -> void: fire_requested.emit(def.id))
	ctl.add_child(fire)
	var count := UIKit.header_label("0")
	count.custom_minimum_size = Vector2(18, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctl.add_child(count)
	var hire := UIKit.primary_button("Hire $%d" % def.wage)
	hire.custom_minimum_size = Vector2(0, 40)
	hire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hire.add_theme_font_size_override("font_size", 17)
	_slim(hire, 8.0)
	hire.pressed.connect(func() -> void: hire_requested.emit(def.id))
	ctl.add_child(hire)
	v.add_child(ctl)
	var portraits := UIKit.hbox(0)
	portraits.visible = false
	v.add_child(portraits)
	_cards[def.id] = {"portraits": portraits, "count": count, "hire": hire, "fire": fire, "card": card}
	return card


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
	big.plate_color = Palette.role_plate(def.id)
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
	wi.icon = IconArt.role_icon(def.id)
	wi.icon_size = 22.0
	what.add_child(wi)
	var wl := UIKit.small_label(_what_text(def))
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
	v.custom_minimum_size = Vector2(210 if _compact else 260, 0)
	v.size_flags_horizontal = Control.SIZE_SHRINK_END if _compact else Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := Label.new()
	t.text = "Crew"
	t.theme_type_variation = &"OnDarkTitle"
	t.add_theme_font_size_override("font_size", 28)
	v.add_child(t)
	_summary_label = Label.new()
	_summary_label.theme_type_variation = &"OnDark"
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.custom_minimum_size = Vector2(190, 0)
	v.add_child(_summary_label)
	_summary_dots = UIKit.hbox(5)
	_summary_dots.custom_minimum_size = Vector2(0, 26)
	v.add_child(_summary_dots)
	_summary_note = Label.new()
	_summary_note.theme_type_variation = &"OnDarkSmall"
	_summary_note.add_theme_font_size_override("font_size", 17)
	_summary_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_note.custom_minimum_size = Vector2(190, 0)
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
	for def in _roles:
		var role: StringName = def.id
		var d: Dictionary = _cards.get(role, {})
		if d.is_empty():
			continue
		var preset: int = int(_port.preset_staff.get(role, 0))
		free_crew += preset
		var hired: int = int(_port.hired.get(role, 0))
		var box: HBoxContainer = d["portraits"]
		var prev_total: int = int(_last_counts.get(role, -1))
		if not _compact:
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
		fire.visible = not _port.is_refit()   # nobody is dismissed at a port stop
		if not bool(chk["ok"]):
			problem = String(chk["reason"])
		(d["card"] as Control).tooltip_text = "%s: %s. Wage $%d." % [def.display_name, _what_text(def), def.wage]
	_summary_label.text = ("%d of %d berths filled" if _compact else "%d of %d crew berths filled") % [total, maxn]
	if problem != "":
		_summary_note.text = problem
		_summary_note.add_theme_color_override("font_color", Palette.CORAL_LIGHT)
	else:
		if _port.is_refit():
			_summary_note.text = "Hire at the normal wage while docked. At sea it costs 1.5x."
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
	bp.plate_color = Color("E4DCCB") if locked else Palette.role_plate(role)
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
