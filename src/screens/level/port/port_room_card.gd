class_name PortRoomCard
extends PanelContainer
## One buildable room in the bottom bar: live art preview, name, width pips and cost / power / water /
## capacity. States: normal, hover (lift), armed (coral glow), unaffordable (dim + red cost), locked.

signal pressed(room_id: StringName)
signal blocked(room_id: StringName, reason: String)
signal hovered(card: PortRoomCard)
signal unhovered(card: PortRoomCard)

const U := preload("res://src/render/art/art_util.gd")
const CARD_W: float = 196.0
const CARD_H: float = 182.0

var def: RoomDef
var lock_reason: String = ""
var affordable: bool = true
var armed: bool = false:
	set(v):
		armed = v
		_restyle()
var _art: RoomCardArt
var _cost_label: Label
var _hover: bool = false
var _tween: Tween
var _shake_tween: Tween
var _pips: _Pips


## Width in cells as little blocks.
class _Pips extends Control:
	var cells: int = 1
	var color: Color = Palette.TEAL

	func _init(n: int = 1) -> void:
		cells = n
		custom_minimum_size = Vector2(float(n) * 11.0 + 2.0, 16.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in cells:
			ArtUtil.rr(self, Rect2(1.0 + float(i) * 11.0, 3.0, 9.0, 10.0), 3.0, color)


func _init(room_def: RoomDef = null, reason: String = "") -> void:
	def = room_def
	lock_reason = reason
	custom_minimum_size = Vector2(CARD_W, CARD_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if def != null:
		_build()


func is_locked() -> bool:
	return lock_reason != ""


func _build() -> void:
	var v := UIKit.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	_art = RoomCardArt.new()
	_art.room_id = def.id
	_art.locked = is_locked()
	_art.animate = false
	_art.custom_minimum_size = Vector2(0, 98)
	_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_art)
	var name_row := UIKit.hbox(6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := Label.new()
	nm.text = def.display_name
	nm.theme_type_variation = &"HeaderLabel"
	nm.add_theme_font_size_override("font_size", 21)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(nm)
	_pips = _Pips.new(def.width if not def.is_elevator() else 1)
	_pips.color = IconArt.room_badge_color(def.id) if def.id != &"medbay" else Palette.CORAL
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if def.is_stairs():
		_pips.tooltip_text = ""
	name_row.add_child(_pips)
	v.add_child(name_row)
	if is_locked():
		var l := UIKit.small_label(lock_reason)
		l.add_theme_font_size_override("font_size", 17)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	else:
		var stats := UIKit.hbox(7)
		stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cost_box := _stat(&"coin", "$%d" % def.cost, Palette.INK)
		_cost_label = cost_box.get_child(1) as Label
		stats.add_child(cost_box)
		if def.power != 0:
			stats.add_child(_stat(&"power", ("+%d" % -def.power) if def.power < 0 else str(def.power), Palette.MINT_DARK if def.power < 0 else Palette.INK))
		if def.water != 0:
			stats.add_child(_stat(&"water", ("+%d" % -def.water) if def.water < 0 else str(def.water), Palette.MINT_DARK if def.water < 0 else Palette.INK))
		if def.capacity > 0 and not def.is_transport():
			stats.add_child(_stat(&"guest", str(def.capacity), Palette.INK))
		v.add_child(stats)
	_restyle()
	resized.connect(func() -> void: pivot_offset = Vector2(size.x * 0.5, size.y))
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)


func _stat(icon: StringName, text: String, color: Color) -> HBoxContainer:
	var h := UIKit.hbox(3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := IconView.new()
	ic.icon = icon
	ic.icon_size = 20.0
	h.add_child(ic)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", UITheme.font_bold())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return h


func set_affordable(ok: bool) -> void:
	if ok == affordable:
		return
	affordable = ok
	_restyle()


func _restyle() -> void:
	if def == null:
		return
	var bg: Color = UITheme.CARD if affordable or is_locked() else Color("EBE4D6")
	var edge: Color = UITheme.CARD_EDGE
	var ew: int = 2
	var shadow_c := Color(0.05, 0.08, 0.16, 0.30)
	var shadow_s: int = 8
	if armed:
		edge = Palette.CORAL
		ew = 4
		bg = Color("FFF1E0")
		shadow_c = Color(Palette.CORAL.r, Palette.CORAL.g, Palette.CORAL.b, 0.5)
		shadow_s = 14
	elif _hover and not is_locked():
		edge = Color.WHITE
		bg = Color("FFFDF6")
		shadow_s = 12
	add_theme_stylebox_override("panel", UITheme.flat(bg, 16, edge, ew, shadow_c, shadow_s, Vector2(0, 4), Vector4(12, 10, 12, 10)))
	if _cost_label != null:
		_cost_label.add_theme_color_override("font_color", Palette.CORAL if not affordable else Palette.INK)
	if is_locked():
		modulate = Color(0.72, 0.74, 0.8, 0.92)
	else:
		modulate = Color.WHITE
	if _art != null and not is_locked():
		_art.modulate = Color(0.72, 0.72, 0.78, 0.85) if (not affordable and not armed) else Color.WHITE


func _on_enter() -> void:
	_hover = true
	_restyle()
	if _art != null and not is_locked():
		_art.animate = true
	_scale_to(1.05 if not is_locked() else 1.0, 0.12)
	hovered.emit(self)


func _on_exit() -> void:
	_hover = false
	_restyle()
	if _art != null and not armed:
		_art.animate = false
	_scale_to(1.0, 0.14)
	unhovered.emit(self)


func _scale_to(s: float, dur: float) -> void:
	if not is_inside_tree():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(s, s), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func set_art_animated(on: bool) -> void:
	if _art != null:
		_art.animate = on


func shake() -> void:
	if not is_inside_tree():
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	var base_rot: float = 0.0
	for i in 5:
		_shake_tween.tween_property(self, "rotation", deg_to_rad(3.2 * (1.0 if i % 2 == 0 else -1.0) * (1.0 - float(i) * 0.18)), 0.045)
	_shake_tween.tween_property(self, "rotation", base_rot, 0.05)


func pop() -> void:
	if not is_inside_tree():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	scale = Vector2(0.94, 0.94)
	_tween.tween_property(self, "scale", Vector2(1.05, 1.05) if _hover else Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	accept_event()
	if is_locked():
		blocked.emit(def.id, lock_reason)
		return
	if not affordable and not armed:
		blocked.emit(def.id, "Not enough money")
		return
	pressed.emit(def.id)
