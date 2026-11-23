class_name PortTooltip
extends PanelContainer
## Rich tooltip for build-bar room cards: description, needs satisfied, capacity, service time,
## spend, upkeep, utilities, placement rule and tier bonuses. Positioned by the owner.

const NEED_NAMES: Dictionary = {&"rest": "Rest", &"hunger": "Hunger", &"fun": "Fun", &"hygiene": "Hygiene"}

var _body: VBoxContainer
var _shown_for: StringName = &""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"PanelContainer"
	var sb := UITheme.flat(Color(0.1176, 0.1412, 0.2, 0.97), 14, Color(1, 1, 1, 0.16), 2, Color(0, 0, 0, 0.32), 14, Vector2(0, 4), Vector4(18, 14, 18, 16))
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(400, 0)
	visible = false
	z_index = 50
	_body = UIKit.vbox(7)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)


func shown_for() -> StringName:
	return _shown_for


func hide_tip() -> void:
	visible = false
	_shown_for = &""


## Fills the tooltip for a room definition. `lock_text` non-empty = locked reason.
func fill(def: RoomDef, lock_text: String, hull_decks: int) -> void:
	_shown_for = def.id
	for c in _body.get_children():
		c.queue_free()
		_body.remove_child(c)
	var head := UIKit.hbox(10)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(38, 38)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.draw.connect(func() -> void: IconArt.draw_room_icon(badge, def.id, Vector2(19, 19), 36.0))
	head.add_child(badge)
	var nm := Label.new()
	nm.text = def.display_name
	nm.theme_type_variation = &"OnDarkTitle"
	nm.add_theme_font_size_override("font_size", 28)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(nm)
	_body.add_child(head)
	if def.description != "":
		var d := Label.new()
		d.text = def.description
		d.theme_type_variation = &"OnDarkSmall"
		d.add_theme_font_size_override("font_size", 19)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(360, 0)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(d)
	if lock_text != "":
		_row(&"lock", lock_text, Palette.SUN)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.12)
	sep.custom_minimum_size = Vector2(0, 2)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(sep)
	# needs satisfied
	if def.id == &"medbay":
		_row(&"sick", "Cures sick guests", Palette.MINT)
	for need in def.satisfies:
		var key: StringName = StringName(need)
		var amount: int = int(round(float(def.satisfies[need])))
		_row(StringName("need_%s" % key), "%s +%d" % [NEED_NAMES.get(key, String(key).capitalize()), amount], Palette.MINT)
	if def.power < 0:
		_row(&"power", "Supplies +%d power" % -def.power, Palette.MINT)
	if def.water < 0:
		_row(&"water", "Supplies +%d water" % -def.water, Palette.MINT)
	if def.capacity > 0 and not def.is_transport():
		_row(&"guest", ("Sleeps %d guests" % def.capacity) if def.id == &"cabin" else ("%d guests at a time" % def.capacity), Palette.CREAM)
	elif def.is_elevator():
		_row(&"guest", "Carries %d guests at a time" % SimConst.ELEVATOR_CAPACITY, Palette.CREAM)
	if def.service_time > 1.0 and not def.satisfies.is_empty():
		_row(&"clock", "%d s per visit" % int(round(def.service_time)), Palette.CREAM)
	if def.spend > 0 or def.upkeep > 0.0:
		var bits2: PackedStringArray = []
		if def.spend > 0:
			bits2.append("earns $%d a visit" % def.spend)
		if def.upkeep > 0.0:
			bits2.append("upkeep $%d / min" % int(round(def.upkeep)))
		var joined: String = ", ".join(bits2)
		_row(&"coin", joined.substr(0, 1).to_upper() + joined.substr(1), Palette.SUN)
	if def.power > 0:
		_row(&"power", "Uses %d power" % def.power, Palette.CREAM)
	if def.water > 0:
		_row(&"water", "Uses %d water" % def.water, Palette.CREAM)
	if def.breakdown_time > 0.0:
		_row(&"breakdown", "Wears out, needs a mechanic", Palette.CORAL_LIGHT)
	# footprint + placement rule
	if not def.is_elevator() and not def.is_stairs():
		_row_pips(def.width)
	var rule: String = ""
	if def.is_elevator():
		rule = "Runs through every deck"
	elif def.is_stairs():
		rule = "Joins two decks"
	elif def.placement == &"top_deck":
		rule = "Top deck only"
	elif def.placement == &"interior":
		rule = "Interior decks only"
	if rule != "":
		_row(&"warning", rule, Color("C9D3E8"))
	# tiers
	if def.tier_bonus.size() > 0:
		var sep2 := ColorRect.new()
		sep2.color = Color(1, 1, 1, 0.12)
		sep2.custom_minimum_size = Vector2(0, 2)
		sep2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(sep2)
		for i in def.tier_bonus.size():
			var tb: Dictionary = def.tier_bonus[i]
			var bits: PackedStringArray = []
			var ca: int = int(tb.get("capacity_add", 0))
			if ca > 0:
				bits.append("+%d %s" % [ca, "sleepers" if def.id == &"cabin" else "capacity"])
			var sm: float = float(tb.get("speed_mult", 1.0))
			if sm > 1.001:
				bits.append("%s faster" % ("x%.2f" % sm).trim_suffix("0"))
			_row(&"star", "Tier %s  $%d  %s" % ["II" if i == 0 else "III", int(tb.get("cost", 0)), ", ".join(bits)], Color("E9D9A6"))
	reset_size()
	visible = true


func _row_pips(cells: int) -> void:
	var r := UIKit.hbox(10)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pips := PortRoomCard._Pips.new(cells)
	pips.custom_minimum_size = Vector2(maxf(float(cells) * 11.0 + 2.0, 22.0), 22.0)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(pips)
	var l := Label.new()
	l.text = "%d cells wide" % cells
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Palette.CREAM)
	l.add_theme_font_override("font", UITheme.font())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(l)
	_body.add_child(r)


func _row(icon: StringName, text: String, color: Color) -> void:
	var r := UIKit.hbox(10)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := IconView.new()
	ic.icon = icon
	ic.icon_size = 22.0
	r.add_child(ic)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", UITheme.font())
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(330, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(l)
	_body.add_child(r)
