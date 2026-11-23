class_name DestNode
extends Control
## One destination on the voyage map: an animated island illustration, a name plate with the stars collected,
## and (when locked) a cloud-covered island with a "10 needed" pill. Click / Enter selects it.
##   signal chosen(dest_id)      var selected: bool        refresh()  re-reads stars / lock state
## Keyboard: focusing a node also selects it (so left / right browses the three destinations).

const U := preload("res://src/render/art/art_util.gd")

signal chosen(dest_id: StringName)

var dest: StringName = &"med"
var unlocked: bool = true
var stars_have: int = 0
var stars_max: int = 18
var stars_needed: int = 0
var total_stars: int = 0
var display_name: String = ""
var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()
var _t: float = randf() * 10.0
var _hover: bool = false
var _scale_tw: Tween


func _init(dest_id: StringName = &"med") -> void:
	dest = dest_id
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(300, 260)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	focus_entered.connect(func() -> void:
		chosen.emit(dest)
		queue_redraw())
	focus_exited.connect(queue_redraw)
	resized.connect(func() -> void: pivot_offset = size * 0.5)


func _ready() -> void:
	refresh()


func refresh() -> void:
	var def: DestinationDef = ContentDB.destination(dest)
	display_name = def.display_name if def != null else String(dest).capitalize()
	unlocked = SaveManager.is_destination_unlocked(dest)
	stars_have = SaveManager.stars_in_destination(dest)
	stars_max = ContentDB.levels_for(dest).size() * 3
	stars_needed = SaveManager.stars_required(dest)
	total_stars = SaveManager.total_stars()
	tooltip_text = "" if unlocked else "Collect %d stars to unlock %s (you have %d)" % [stars_needed, display_name, total_stars]
	queue_redraw()


func _on_hover(on: bool) -> void:
	_hover = on
	_tween_scale(1.05 if on else 1.0)


func _tween_scale(s: float) -> void:
	if _scale_tw != null and _scale_tw.is_valid():
		_scale_tw.kill()
	_scale_tw = create_tween()
	_scale_tw.tween_property(self, "scale", Vector2(s, s), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		chosen.emit(dest)
		accept_event()
	elif event.is_action_pressed(&"ui_accept"):
		chosen.emit(dest)
		accept_event()


func pop(delay: float) -> void:
	modulate.a = 0.0
	scale = Vector2(0.7, 0.7)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.3).set_delay(delay)
	tw.tween_property(self, "scale", Vector2.ONE, 0.55).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func lagoon_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.5 - 22.0 * _k())


func _k() -> float:
	return minf(size.x / 400.0, size.y / 330.0)


func _draw() -> void:
	var k: float = _k()
	var c: Vector2 = lagoon_center()
	var bob: float = sin(_t * 1.1 + float(dest.length())) * 2.5 * k
	MapArt.draw_backdrop(self, dest, c, k, _t)
	# selection ring on the water
	if selected:
		var pulse: float = 1.0 + 0.02 * sin(_t * 3.0)
		U.dashed_ring(self, c + Vector2(0, 8.0 * k), 214.0 * k * pulse, 70.0 * k * pulse, Color(1, 1, 1, 0.95), 3.5, _t, 22)
	MapArt.draw_island(self, dest, c + Vector2(0, bob), k, _t, not unlocked)
	# lock pill over the clouds
	if not unlocked:
		var pw: float = 214.0 * k
		var ph: float = 50.0 * k
		var pr := Rect2(c.x - pw * 0.5, c.y - 46.0 * k, pw, ph)
		U.rr(self, Rect2(pr.position + Vector2(0, 4), pr.size), ph * 0.5, Color(0.1, 0.14, 0.26, 0.28))
		U.rr(self, pr, ph * 0.5, Palette.CORAL_DARK)
		U.rr(self, Rect2(pr.position, Vector2(pr.size.x, pr.size.y - 4.0)), ph * 0.5, Palette.CORAL)
		IconArt.draw_icon(self, &"lock", pr.position + Vector2(ph * 0.55, ph * 0.46), ph * 0.62, 0.0, false)
		IconArt.draw_icon(self, &"star", pr.position + Vector2(ph * 1.2, ph * 0.46), ph * 0.58, _t, false)
		U.text(self, "%d needed" % stars_needed, Vector2(pr.position.x + ph * 1.55, pr.position.y + ph * 0.66), int(24.0 * k), Color.WHITE)
	# name plate
	var pw2: float = minf(size.x - 20.0, 320.0 * k)
	var plate := Rect2((size.x - pw2) * 0.5, size.y - 92.0 * k, pw2, 82.0 * k)
	var fill: Color = Palette.CORAL if selected else Color("FFF8EC")
	var edge: Color = Palette.CORAL_DARK if selected else Color("EBDDC3")
	U.rr(self, Rect2(plate.position + Vector2(0, 5), plate.size), 20.0 * k, Color(0.1, 0.14, 0.26, 0.28))
	U.rr(self, plate.grow(2.5), 22.0 * k, edge)
	U.rr(self, plate, 20.0 * k, fill)
	if selected:
		U.rr(self, Rect2(plate.position + Vector2(6, 5), Vector2(plate.size.x - 12, 12.0 * k)), 6.0, Color(1, 1, 1, 0.35))
	var ink: Color = Color.WHITE if selected else UITheme.TEXT_INK
	U.text(self, display_name, Vector2(plate.position.x, plate.position.y + 38.0 * k), int(32.0 * k), ink, HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
	var sub: String = "%d / %d" % [stars_have, stars_max] if unlocked else "%d / %d stars" % [mini(total_stars, stars_needed), stars_needed]
	var sub_w: float = UITheme.font_bold().get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, int(22.0 * k)).x
	var sx: float = plate.position.x + (plate.size.x - sub_w - 30.0 * k) * 0.5
	IconArt.draw_icon(self, &"star" if unlocked else &"lock", Vector2(sx + 12.0 * k, plate.position.y + 62.0 * k), 24.0 * k, _t, false)
	U.text(self, sub, Vector2(sx + 30.0 * k, plate.position.y + 70.0 * k), int(22.0 * k), Color("FFE9E6") if selected else UITheme.TEXT_MUTED)
	# focus ring (keyboard / controller)
	if has_focus():
		U.rr_outline(self, Rect2(8, 4, size.x - 16, size.y - 8), 28.0, Palette.SUN, 4.0)
