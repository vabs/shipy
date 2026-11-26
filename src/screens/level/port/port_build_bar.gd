class_name PortBuildBar
extends PanelContainer
## The bottom bar of the port phase: category tabs + room cards, Crew and Manifest panels, power /
## water meters, budget chip, undo, collapse handle, back-to-map and the big Set Sail button.
## Pure presentation: it emits signals, PortPhase decides what they mean.

signal tab_changed(tab: StringName)
signal card_pressed(room_id: StringName)
signal card_blocked(room_id: StringName, reason: String)
signal card_hovered(card: PortRoomCard)
signal card_unhovered(card: PortRoomCard)
signal sail_pressed
signal back_pressed
signal undo_pressed
signal hire_requested(role: StringName)
signal fire_requested(role: StringName)
signal collapse_changed(collapsed: bool)

const U := preload("res://src/render/art/art_util.gd")
const TABS: Array[Dictionary] = [
	{"id": &"rest", "label": "Cabins & Rest", "cats": [&"rest"]},
	{"id": &"food", "label": "Food", "cats": [&"food"]},
	{"id": &"fun", "label": "Fun", "cats": [&"fun"]},
	{"id": &"health", "label": "Hygiene & Health", "cats": [&"hygiene", &"service"]},
	{"id": &"transport", "label": "Transport", "cats": [&"transport"]},
	{"id": &"utility", "label": "Utility", "cats": [&"utility"]},
	{"id": &"crew", "label": "Crew", "cats": []},
	{"id": &"manifest", "label": "Manifest", "cats": []},
]
const CONTENT_H: float = 206.0
const TIPS: Dictionary = {
	&"rest": "Every guest needs a bed. Cabins sleep 4, and each upgrade adds 2 more.",
	&"food": "Hungry guests queue for food. Buffets are cheap, restaurants earn more.",
	&"fun": "Guests chase what they love. Check the Manifest to see their favourites.",
	&"health": "Toilets keep guests fresh. A medbay cures anyone who falls sick.",
	&"transport": "Every deck with rooms needs stairs or an elevator to the gangway deck (the yellow badge).",
	&"utility": "Rooms draw power and water. Generators and tanks supply more.",
}

var current_tab: StringName = &"rest"
var collapsed: bool = false
var sail_button: Button
var undo_button: Button
var back_button: Button
var power_meter: PortUtilMeter
var water_meter: PortUtilMeter
var crew_panel: PortCrewPanel
var manifest_panel: PortManifestPanel

var _port: PortState
var _tab_row: HBoxContainer
var _refit: bool = false
var _tab_buttons: Dictionary = {}
var _tab_pages: Dictionary = {}
var _cards: Dictionary = {}          # room id -> PortRoomCard
var _holder: Control
var _content: HBoxContainer
var _stack: Control
var _scroll: ScrollContainer
var _status: Label
var _budget: StatPill
var _chevron: Button
var _chevron_glyph: _Glyph
var _hint_tween: Tween
var _collapse_tween: Tween
var _budget_tween: Tween
var _last_budget: int = -1
var _armed_id: StringName = &""
var _tips: Dictionary = {}


## Tiny vector glyph used on round buttons (the IconArt set has no arrows).
class _Glyph extends Control:
	var kind: StringName = &"undo"
	var color: Color = Palette.CREAM

	func _init(k: StringName = &"undo") -> void:
		kind = k
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c: Vector2 = size * 0.5 + Vector2(0, -2)
		match kind:
			&"undo":
				ArtUtil.arc(self, c + Vector2(1, 2), 9.0, deg_to_rad(200.0), deg_to_rad(450.0), color, 3.4, 16)
				ArtUtil.poly(self, PackedVector2Array([c + Vector2(-13, -1), c + Vector2(-3, -9), c + Vector2(-3, 7)]), color)
			&"chev_down":
				ArtUtil.pline(self, PackedVector2Array([c + Vector2(-9, -4), c + Vector2(0, 5), c + Vector2(9, -4)]), color, 4.0)
			&"chev_up":
				ArtUtil.pline(self, PackedVector2Array([c + Vector2(-9, 5), c + Vector2(0, -4), c + Vector2(9, 5)]), color, 4.0)


func _init() -> void:
	theme_type_variation = &"NavyBarBottom"
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(port: PortState) -> void:
	_port = port
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_theme_stylebox_override("panel", _bar_style())
	var v := UIKit.vbox(8)
	add_child(v)
	v.add_child(_build_tab_row())
	_holder = Control.new()
	_holder.custom_minimum_size = Vector2(0, CONTENT_H)
	_holder.clip_contents = true
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_holder)
	_content = UIKit.hbox(16)
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_content)
	_stack = Control.new()
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_stack)
	_build_pages()
	_content.add_child(_build_sail_column())
	select_tab(&"rest", false)
	refresh()


func _bar_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = (UITheme.build().get_stylebox("panel", "NavyBarBottom") as StyleBoxFlat).duplicate()
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 10.0
	sb.content_margin_left = 20.0
	sb.content_margin_right = 20.0
	return sb


# ------------------------------------------------------------------------------------------------
# construction
# ------------------------------------------------------------------------------------------------
func _glyph_button(kind: StringName, tip: String, px: float) -> Button:
	var b := UIKit.icon_button(&"star", tip, px, true)
	for c in b.get_children():
		c.queue_free()
		b.remove_child(c)
	var g := _Glyph.new(kind)
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.offset_bottom = -3.0
	b.add_child(g)
	b.set_meta(&"glyph", g)
	return b


func _build_tab_row() -> Control:
	var row := UIKit.hbox(6)
	_tab_row = row
	back_button = UIKit.ghost_button("< Map")
	back_button.tooltip_text = "Back to the map"
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	row.add_child(back_button)
	undo_button = _glyph_button(&"undo", "Undo  (Ctrl/Cmd + Z)", 48.0)
	undo_button.pressed.connect(func() -> void: undo_pressed.emit())
	row.add_child(undo_button)
	row.add_child(_sep())
	var grp := ButtonGroup.new()
	for t in TABS:
		var id: StringName = t["id"]
		if id == &"crew":
			row.add_child(_sep())
		var b := UIKit.tab_button(String(t["label"]))
		b.button_group = grp
		b.add_theme_font_size_override("font_size", 20)
		_tighten(b)
		b.pressed.connect(func() -> void: _on_tab_pressed(id))
		row.add_child(b)
		_tab_buttons[id] = b
	row.add_child(UIKit.h_spacer())
	power_meter = PortUtilMeter.new(&"power", Palette.MINT)
	power_meter.custom_minimum_size = Vector2(186, 46)
	power_meter.tooltip_text = "Power. Rooms draw it, generators supply it."
	row.add_child(power_meter)
	water_meter = PortUtilMeter.new(&"water", Palette.TEAL)
	water_meter.custom_minimum_size = Vector2(186, 46)
	water_meter.tooltip_text = "Water. Cabins, toilets and pools draw it, tanks supply it."
	row.add_child(water_meter)
	_budget = UIKit.stat_pill(&"coin", "$0")
	_budget.custom_minimum_size = Vector2(140, 46)
	_budget.tooltip_text = "Budget left"
	row.add_child(_budget)
	_chevron = _glyph_button(&"chev_down", "Hide the build bar", 46.0)
	_chevron_glyph = _chevron.get_meta(&"glyph") as _Glyph
	_chevron.pressed.connect(func() -> void: set_collapsed(not collapsed))
	row.add_child(_chevron)
	return row


## Quick refit at a port stop (docs/SPEC.md §13.8): no map / undo / manifest, a "Quick refit - <port>" title in their place, "Cast off!"
## instead of "Set Sail!", the budget chip says it is the voyage money.
func configure_refit(stop_name: String) -> void:
	_refit = true
	back_button.visible = false
	undo_button.visible = false
	var mb: Button = _tab_buttons.get(&"manifest")
	if mb != null:
		mb.visible = false
	var title := PanelContainer.new()
	title.theme_type_variation = &"PillPanel"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := UIKit.hbox(8)
	var iv := IconView.new()
	iv.icon = &"event"
	iv.icon_size = 28.0
	hb.add_child(iv)
	var l1 := Label.new()
	l1.theme_type_variation = &"PillLabel"
	l1.text = "Quick refit"
	hb.add_child(l1)
	var l2 := Label.new()
	l2.theme_type_variation = &"PillLabel"
	l2.add_theme_color_override("font_color", Palette.SUN)
	l2.text = stop_name
	hb.add_child(l2)
	title.add_child(hb)
	_tab_row.add_child(title)
	_tab_row.move_child(title, 0)
	sail_button.text = "Cast off!"
	sail_button.tooltip_text = "Leave %s and sail on: new guests come aboard" % stop_name
	_budget.tooltip_text = "Voyage money"
	select_tab(&"rest", false)


## Narrower side padding than the theme's tab pill so eight tabs + meters fit a 1920 bar.
func _tighten(b: Button) -> void:
	var th: Theme = UITheme.build()
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb: StyleBoxFlat = (th.get_stylebox(st, "TabButton") as StyleBoxFlat).duplicate()
		sb.content_margin_left = 14.0
		sb.content_margin_right = 14.0
		b.add_theme_stylebox_override(st, sb)


func _sep() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(14, 30)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void: ArtUtil.rr(c, Rect2(6, 2, 2, 26), 1.0, Color(1, 1, 1, 0.16)))
	return c


func _build_pages() -> void:
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.resized.connect(_fit_tips)
	_stack.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_bottom", 4)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(pad)
	var pages: MarginContainer = pad   # a MarginContainer stacks its children: one HBox of cards per tab
	# gather every room, bucket by tab
	var buckets: Dictionary = {}
	for t in TABS:
		buckets[t["id"]] = []
	for def in ContentStore.all_rooms():
		for t in TABS:
			if (t["cats"] as Array).has(def.category):
				(buckets[t["id"]] as Array).append(def)
	for t in TABS:
		var id: StringName = t["id"]
		if (t["cats"] as Array).is_empty():
			continue
		var items: Array[Dictionary] = []
		for def: RoomDef in buckets[id]:
			# rooms of another destination are not part of this level's catalog at all (no teaser cards)
			if def.destination_lock != &"" and def.destination_lock != _port.level.destination:
				continue
			items.append({"def": def, "reason": _port.grid.room_lock_reason(def.id)})
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["def"] as RoomDef).unlock_level < (b["def"] as RoomDef).unlock_level)
		var hb := UIKit.hbox(12)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pages.add_child(hb)
		for it in items:
			var card := PortRoomCard.new(it["def"], String(it["reason"]))
			card.pressed.connect(func(rid: StringName) -> void: card_pressed.emit(rid))
			card.blocked.connect(func(rid: StringName, why: String) -> void:
				(_cards[rid] as PortRoomCard).shake()
				card_blocked.emit(rid, why))
			card.hovered.connect(func(c: PortRoomCard) -> void: card_hovered.emit(c))
			card.unhovered.connect(func(c: PortRoomCard) -> void: card_unhovered.emit(c))
			hb.add_child(card)
			_cards[card.def.id] = card
		var tip := Label.new()
		tip.text = String(TIPS.get(id, ""))
		tip.theme_type_variation = &"OnDarkSmall"
		tip.add_theme_font_size_override("font_size", 19)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.custom_minimum_size = Vector2(280, 0)
		tip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tip.modulate = Color(1, 1, 1, 0.75)
		tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tip_pad := MarginContainer.new()
		tip_pad.add_theme_constant_override("margin_left", 14)
		tip_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_pad.add_child(tip)
		hb.add_child(tip_pad)
		hb.visible = false
		_tab_pages[id] = hb
		_tips[id] = tip_pad
	crew_panel = PortCrewPanel.new()
	crew_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stack.add_child(crew_panel)
	crew_panel.setup(_port)
	crew_panel.hire_requested.connect(func(r: StringName) -> void: hire_requested.emit(r))
	crew_panel.fire_requested.connect(func(r: StringName) -> void: fire_requested.emit(r))
	crew_panel.visible = false
	manifest_panel = PortManifestPanel.new()
	manifest_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stack.add_child(manifest_panel)
	manifest_panel.setup(_port)
	manifest_panel.visible = false
	_tab_pages[&"crew"] = crew_panel
	_tab_pages[&"manifest"] = manifest_panel


func _build_sail_column() -> Control:
	var col := UIKit.vbox(8)
	col.custom_minimum_size = Vector2(318, 0)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status = Label.new()
	_status.theme_type_variation = &"OnDarkSmall"
	_status.add_theme_font_size_override("font_size", 19)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 52)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_status)
	sail_button = UIKit.primary_button("Set Sail!")
	sail_button.custom_minimum_size = Vector2(0, 92)
	sail_button.add_theme_font_size_override("font_size", 40)
	sail_button.tooltip_text = "Check the ship and start the voyage"
	sail_button.pressed.connect(func() -> void: sail_pressed.emit())
	col.add_child(sail_button)
	return col


# ------------------------------------------------------------------------------------------------
# public API
# ------------------------------------------------------------------------------------------------
func card_for(room_id: StringName) -> PortRoomCard:
	return _cards.get(room_id) as PortRoomCard


func tab_button(id: StringName) -> Button:
	return _tab_buttons.get(id) as Button


func tab_of(room_id: StringName) -> StringName:
	var def: RoomDef = ContentStore.room(room_id)
	if def == null:
		return &"rest"
	for t in TABS:
		if (t["cats"] as Array).has(def.category):
			return t["id"]
	return &"rest"


## The helper text beside the cards only shows when there is room for it (no scrolling).
func _fit_tips() -> void:
	if _scroll == null:
		return
	for id in _tips:
		var pad: Control = _tips[id]
		var hb: Control = _tab_pages[id]
		var used: float = 0.0
		for c in hb.get_children():
			if c != pad:
				used += (c as Control).get_combined_minimum_size().x + 12.0
		pad.visible = used + pad.get_combined_minimum_size().x + 24.0 <= _scroll.size.x


func _on_tab_pressed(id: StringName) -> void:
	if collapsed:
		set_collapsed(false)
	select_tab(id)


func select_tab(id: StringName, emit: bool = true) -> void:
	current_tab = id
	for k in _tab_pages:
		(_tab_pages[k] as Control).visible = k == id
	for k in _tab_buttons:
		(_tab_buttons[k] as Button).set_pressed_no_signal(k == id)
	if _scroll != null:
		_scroll.visible = id != &"crew" and id != &"manifest"
		_scroll.scroll_horizontal = 0
	_fit_tips.call_deferred()
	if emit:
		tab_changed.emit(id)


func cycle_tab(dir: int) -> void:
	var ids: Array = []
	for t in TABS:
		if _refit and t["id"] == &"manifest":
			continue
		ids.append(t["id"])
	var i: int = ids.find(current_tab)
	select_tab(ids[wrapi(i + dir, 0, ids.size())])


func set_collapsed(value: bool) -> void:
	if value == collapsed:
		return
	collapsed = value
	if _collapse_tween != null and _collapse_tween.is_valid():
		_collapse_tween.kill()
	_collapse_tween = create_tween().set_parallel(true)
	var from_h: float = _holder.custom_minimum_size.y
	var to_h: float = 0.0 if collapsed else CONTENT_H
	_collapse_tween.tween_method(func(h: float) -> void:
		_holder.custom_minimum_size = Vector2(0, h)
		_holder.modulate.a = clampf(h / CONTENT_H * 1.4, 0.0, 1.0)
		, from_h, to_h, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_chevron_glyph.kind = &"chev_up" if collapsed else &"chev_down"
	_chevron_glyph.queue_redraw()
	_chevron.tooltip_text = "Show the build bar" if collapsed else "Hide the build bar"
	collapse_changed.emit(collapsed)


## Pixel height currently taken by the bar (for camera insets).
func occupied_height() -> float:
	return maxf(size.y, 60.0)


func refresh() -> void:
	if _port == null:
		return
	var budget: int = _port.budget
	for id in _cards:
		var card: PortRoomCard = _cards[id]
		card.set_affordable(card.def.cost <= budget or card.is_locked())
	var u: Dictionary = _port.utilities()
	power_meter.set_values(int(u["power_used"]), int(u["power_cap"]))
	water_meter.set_values(int(u["water_used"]), int(u["water_cap"]))
	if budget != _last_budget:
		_budget.set_text(fmt_money(budget), _last_budget >= 0)
		if _last_budget >= 0:
			_flash_budget(budget > _last_budget)
		_last_budget = budget
	crew_panel.refresh()
	manifest_panel.refresh()
	var b: Button = _tab_buttons.get(&"crew")
	if b != null:
		b.text = "Crew %d/%d" % [_port.staff_total(), _port.max_staff()]


func _flash_budget(gain: bool) -> void:
	if _budget_tween != null and _budget_tween.is_valid():
		_budget_tween.kill()
	_budget.modulate = Color(0.75, 1.0, 0.82) if gain else Color(1.0, 0.78, 0.74)
	_budget_tween = create_tween()
	_budget_tween.tween_property(_budget, "modulate", Color.WHITE, 0.6)


func set_armed(room_id: StringName) -> void:
	_armed_id = room_id
	for id in _cards:
		var card: PortRoomCard = _cards[id]
		card.armed = id == room_id
		if id != room_id:
			card.set_art_animated(false)
		else:
			card.set_art_animated(true)


func set_preview(power_delta: int, water_delta: int) -> void:
	power_meter.set_preview(maxi(power_delta, 0), maxi(-power_delta, 0))
	water_meter.set_preview(maxi(water_delta, 0), maxi(-water_delta, 0))


func set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func set_undo_enabled(on: bool) -> void:
	undo_button.disabled = not on
	undo_button.modulate.a = 1.0 if on else 0.45


func shake_sail() -> void:
	var tw := create_tween()
	var base: float = 0.0
	sail_button.pivot_offset = sail_button.size * 0.5
	for i in 6:
		tw.tween_property(sail_button, "rotation", deg_to_rad(2.4 * (1.0 if i % 2 == 0 else -1.0) * (1.0 - float(i) * 0.14)), 0.05)
	tw.tween_property(sail_button, "rotation", base, 0.05)


static func fmt_money(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	var cnt: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if n < 0 else "$") + out
