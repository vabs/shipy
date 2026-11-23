class_name PortPopover
extends Control
## Popover anchored to a placed room: name + tier, Move (free), Upgrade (cost + what it adds) and
## Sell (+refund). Disabled actions explain why. Locked preset rooms show a lock banner instead.

signal move_requested(uid: int)
signal upgrade_requested(uid: int)
signal sell_requested(uid: int)

const TAIL_H: float = 12.0

var uid: int = -1
var flipped: bool = false      # true = popover sits BELOW the room (tail points up)
var tail_x: float = 0.0        # tail position inside this control

var move_button: Button
var upgrade_button: Button
var sell_button: Button

var _port: PortState
var _card: PanelContainer
var _tail: _Tail
var _tween: Tween


class _Tail extends Control:
	var up: bool = false
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(28, PortPopover.TAIL_H)
	func _draw() -> void:
		var c := UITheme.CARD
		var pts: PackedVector2Array
		if up:
			pts = PackedVector2Array([Vector2(0, size.y + 2), Vector2(size.x, size.y + 2), Vector2(size.x * 0.5, 0)])
		else:
			pts = PackedVector2Array([Vector2(0, -2), Vector2(size.x, -2), Vector2(size.x * 0.5, size.y)])
		ArtUtil.poly(self, pts, c)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 40


func is_open() -> bool:
	return visible and uid >= 0


func open_for(port: PortState, room_uid: int) -> void:
	_port = port
	uid = room_uid
	_rebuild()
	visible = true
	pop_in()


func close() -> void:
	uid = -1
	visible = false


func pop_in() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	pivot_offset = Vector2(size.x * 0.5, size.y if not flipped else 0.0)
	scale = Vector2(0.82, 0.82)
	modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.1)


func refresh() -> void:
	if uid >= 0 and _port != null:
		if _port.layout.get_room(uid) == null:
			close()
			return
		_rebuild()


func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var room: PlacedRoom = _port.layout.get_room(uid)
	if room == null:
		return
	var def: RoomDef = room.def
	_card = UIKit.card()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_theme_stylebox_override("panel", UITheme.flat(UITheme.CARD, 18, UITheme.CARD_EDGE, 2, Color(0.05, 0.08, 0.16, 0.38), 16, Vector2(0, 6), Vector4(16, 12, 16, 14)))
	add_child(_card)
	var v := UIKit.vbox(8)
	_card.add_child(v)
	# header
	var head := UIKit.hbox(10)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(46, 46)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.draw.connect(func() -> void: IconArt.draw_room_icon(badge, def.id, Vector2(23, 23), 44.0))
	head.add_child(badge)
	var names := UIKit.vbox(0)
	var nm := UIKit.header_label(def.display_name)
	names.add_child(nm)
	var sub := UIKit.small_label(_subtitle(room))
	sub.add_theme_font_size_override("font_size", 17)
	names.add_child(sub)
	head.add_child(names)
	head.add_child(UIKit.h_spacer(10.0))
	if def.max_tier() > 0:
		var stars := UIKit.star_row(room.tier + 1, 26.0)
		stars.max_stars = def.max_tier() + 1
		stars.tooltip_text = "Tier %s" % ["I", "II", "III"][clampi(room.tier, 0, 2)]
		stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(stars)
	v.add_child(head)
	if room.locked:
		var lock := UIKit.hbox(8)
		var li := IconView.new()
		li.icon = &"lock"
		li.icon_size = 26.0
		lock.add_child(li)
		var ll := UIKit.small_label("Part of the ship. Can't be moved or sold.")
		ll.add_theme_font_size_override("font_size", 17)
		lock.add_child(ll)
		v.add_child(lock)
	# actions
	var acts := UIKit.hbox(10)
	v.add_child(acts)
	move_button = null
	sell_button = null
	upgrade_button = null
	if not room.locked:
		var mv := _action_column(UIKit.secondary_button("Move"), "Free", Palette.TEAL_DARK)
		move_button = mv["button"]
		move_button.pressed.connect(func() -> void: move_requested.emit(uid))
		acts.add_child(mv["box"])
	if def.max_tier() > 0:
		var up_info: Dictionary = _upgrade_info(room)
		var up := _action_column(UIKit.sun_button(String(up_info["text"])), String(up_info["hint"]), Palette.CORAL_DARK if bool(up_info["bad"]) else UITheme.TEXT_MUTED)
		upgrade_button = up["button"]
		upgrade_button.disabled = not bool(up_info["ok"])
		upgrade_button.pressed.connect(func() -> void: upgrade_requested.emit(uid))
		acts.add_child(up["box"])
	if not room.locked:
		var chk: Dictionary = _port.grid.can_sell(uid)
		var refund: int = _port.grid.refund_for(uid)
		var hint: String = "%d%% back" % int(round(SimConst.SELL_REFUND * 100.0)) if bool(chk["ok"]) else String(chk["reason"])
		var sl := _action_column(UIKit.danger_button("Sell  +$%d" % refund), hint, UITheme.TEXT_MUTED if bool(chk["ok"]) else Palette.CORAL_DARK)
		sell_button = sl["button"]
		sell_button.disabled = not bool(chk["ok"])
		sell_button.pressed.connect(func() -> void: sell_requested.emit(uid))
		acts.add_child(sl["box"])
	# tail
	_tail = _Tail.new()
	_tail.up = flipped
	add_child(_tail)
	_card.reset_size()
	_layout()


func _layout() -> void:
	var cs: Vector2 = _card.get_combined_minimum_size()
	_card.size = cs
	size = Vector2(cs.x, cs.y + TAIL_H)
	custom_minimum_size = size
	_apply_tail()


func set_flipped(f: bool) -> void:
	if f == flipped:
		return
	flipped = f
	if _tail != null:
		_tail.up = f
		_apply_tail()


func set_tail_x(x: float) -> void:
	tail_x = x
	_apply_tail()


func _apply_tail() -> void:
	if _card == null or _tail == null:
		return
	var cs: Vector2 = _card.size
	if flipped:
		_card.position = Vector2(0, TAIL_H)
		_tail.position = Vector2(clampf(tail_x, 24.0, cs.x - 24.0) - 14.0, 0)
	else:
		_card.position = Vector2.ZERO
		_tail.position = Vector2(clampf(tail_x, 24.0, cs.x - 24.0) - 14.0, cs.y)
	_tail.size = Vector2(28, TAIL_H)
	_tail.queue_redraw()


func _subtitle(room: PlacedRoom) -> String:
	var def: RoomDef = room.def
	var bits: PackedStringArray = []
	if def.max_tier() > 0:
		bits.append("Tier %s" % ["I", "II", "III"][clampi(room.tier, 0, 2)])
	if def.capacity > 0 and not def.is_transport():
		bits.append(("Sleeps %d" % room.capacity()) if def.id == &"cabin" else ("Holds %d" % room.capacity()))
	if def.is_transport():
		bits.append("Joins decks")
	if def.spend > 0:
		bits.append("$%d / visit" % def.spend)
	if def.power < 0:
		bits.append("+%d power" % -def.power)
	if def.water < 0:
		bits.append("+%d water" % -def.water)
	if bits.is_empty():
		bits.append(def.description)
	return "  -  ".join(bits)


func _upgrade_info(room: PlacedRoom) -> Dictionary:
	var def: RoomDef = room.def
	var cost: int = def.upgrade_cost(room.tier)
	if cost < 0:
		return {"ok": false, "bad": false, "text": "Maxed out", "hint": "Fully upgraded"}
	var chk: Dictionary = _port.grid.can_upgrade(uid)
	var tb: Dictionary = def.tier_bonus[room.tier]
	var bits: PackedStringArray = []
	var ca: int = int(tb.get("capacity_add", 0))
	if ca > 0:
		bits.append("+%d %s" % [ca, "sleepers" if def.id == &"cabin" else "capacity"])
	var sm: float = float(tb.get("speed_mult", 1.0))
	if sm > 1.001:
		bits.append("%s faster" % ("x%.2f" % sm).trim_suffix("0"))
	var gain: String = ", ".join(bits)
	var hint: String = gain
	var bad: bool = false
	if not bool(chk["ok"]):
		bad = true
		hint = String(chk["reason"])
	return {"ok": bool(chk["ok"]), "bad": bad, "text": "Upgrade  $%d" % cost, "hint": hint}


func _action_column(btn: Button, hint: String, hint_color: Color) -> Dictionary:
	var box := UIKit.vbox(3)
	btn.custom_minimum_size = Vector2(150, 50)
	btn.add_theme_font_size_override("font_size", 20)
	box.add_child(btn)
	var h := Label.new()
	h.text = hint
	h.add_theme_font_size_override("font_size", 16)
	h.add_theme_color_override("font_color", hint_color)
	h.add_theme_font_override("font", UITheme.font())
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.custom_minimum_size = Vector2(150, 0)
	box.add_child(h)
	return {"box": box, "button": btn}
