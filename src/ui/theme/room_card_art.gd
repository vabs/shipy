class_name RoomCardArt
extends Control
## Draws a room preview (RoomArt) scaled to fit this Control, on a soft rounded plate. For catalog cards.
##   room_id: StringName, tier: int (1..3), width_cells: int (0 = default width for the room),
##   broken: bool, locked: bool (greyed + lock icon), animate: bool.

const U := preload("res://src/render/art/art_util.gd")

const DEFAULT_WIDTH: Dictionary = {
	&"cabin": 2, &"buffet": 4, &"toilets": 2, &"bar": 3, &"pool": 6, &"deck_chairs": 3, &"cinema": 4,
	&"gym": 3, &"arcade": 3, &"kids_club": 3, &"restaurant": 4, &"medbay": 2, &"sauna": 2, &"ice_rink": 5, &"casino": 4,
	&"crew_quarters": 2, &"stairs": 1, &"elevator": 1, &"generator": 1, &"water_tank": 1,
}
const OPEN_AIR: Array[StringName] = [&"pool", &"deck_chairs"]

var room_id: StringName = &"cabin":
	set(v):
		room_id = v
		queue_redraw()
var tier: int = 1:
	set(v):
		tier = v
		queue_redraw()
var width_cells: int = 0:
	set(v):
		width_cells = v
		queue_redraw()
var broken: bool = false:
	set(v):
		broken = v
		queue_redraw()
var locked: bool = false:
	set(v):
		locked = v
		queue_redraw()
var animate: bool = true:
	set(v):
		animate = v
		set_process(v)
var plate_color: Color = Color(0, 0, 0, 0)  # transparent = automatic (sky for open-air rooms, sand otherwise)
var _t: float = randf() * 10.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = Vector2(200, 120)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or locked:
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var plate := plate_color
	if plate.a <= 0.0:
		plate = Color("CDEFFB") if room_id in OPEN_AIR else Color("F1E4CB")
	U.rr(self, Rect2(0, 0, w, h), 14, plate)
	var cells: int = width_cells if width_cells > 0 else int(DEFAULT_WIDTH.get(room_id, 3))
	var lw: float = float(cells) * SimConst.CELL_W
	var lh: float = SimConst.DECK_H
	var is_stairs := room_id == &"stairs"
	var is_lift := room_id == &"elevator"
	if is_stairs:
		lh = SimConst.DECK_H * 2.0
	elif is_lift:
		lh = SimConst.DECK_H * 3.0
	var pad := 14.0
	var s: float = minf((w - pad * 2.0) / lw, (h - pad * 2.0) / lh)
	s = minf(s, 1.5)
	var off := Vector2((w - lw * s) * 0.5, (h - lh * s) * 0.5 + (4.0 if not (is_stairs or is_lift) else 0.0))
	if locked:
		U.alpha = 0.45
	U.begin_scaled(self, off, s)
	var rect := Rect2(0, 0, lw, lh)
	if is_stairs:
		RoomArt.draw_stairs(self, rect, _t)
	elif is_lift:
		RoomArt.draw_elevator(self, rect, 1.0 + 0.5 * sin(_t * 0.8), 3, _t)
	else:
		var st := {"broken": broken, "busy_ratio": 0.5 + 0.5 * sin(_t * 0.6), "repair_progress": 0.0, "t": _t, "highlight": 0, "invalid": false, "ghost_preview": false}
		RoomArt.draw_room(self, room_id, rect, tier, st)
		RoomArt.draw_room_front(self, room_id, rect, tier, st)
	U.end_scaled(self)
	U.alpha = 1.0
	if locked:
		U.rr(self, Rect2(0, 0, w, h), 14, Color(0.1686, 0.2275, 0.3333, 0.42))
		U.circ(self, Vector2(w * 0.5, h * 0.5 + 2), 24.0, Color(0, 0, 0, 0.18))
		U.circ(self, Vector2(w * 0.5, h * 0.5), 24.0, Palette.NAVY_LIGHT)
		IconArt.draw_icon(self, &"lock", Vector2(w * 0.5, h * 0.5), 30.0, 0.0, false)
