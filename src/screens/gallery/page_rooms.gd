extends Node2D
## Gallery page: every room (tier 1/2/3, broken) with guests in slots + front layer.
## Flags: --mode=normal|tier2|tier3|broken|empty|full  --scale=1.6

const U := preload("res://src/render/art/art_util.gd")
const ROOMS: Array[StringName] = [
	&"cabin", &"buffet", &"toilets", &"bar", &"pool", &"deck_chairs", &"cinema", &"gym", &"arcade", &"kids_club",
	&"restaurant", &"medbay", &"sauna", &"ice_rink", &"casino", &"crew_quarters", &"generator", &"water_tank", &"stairs", &"elevator",
]
var _t: float = 0.0
var _dest: StringName = &"med"
var _mode: String = "normal"
var _scale: float = 1.6
var _only: PackedStringArray = PackedStringArray()
const PROPS: Array[StringName] = [&"sun_hat", &"headband", &"glasses_3d", &"headphones"]


func setup(dest: StringName) -> void:
	_dest = dest


func setup_params(p: Dictionary) -> void:
	_mode = String(p.get("mode", "normal"))
	_scale = float(p.get("scale", "1.6"))
	if p.has("only"):
		_only = String(p["only"]).split(",")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var d := Palette.dest(_dest)
	U.vgrad(self, Rect2(0, 0, 1920, 1080), d["sky_top"], d["sky_bottom"])
	var tier := 1
	var broken := false
	var busy := 0.6
	match _mode:
		"tier2": tier = 2
		"tier3": tier = 3
		"broken": broken = true
		"empty": busy = 0.0
		"full": busy = 1.0
	var x := 24.0
	var y := 24.0
	var row_h := 76.0 * _scale + 40.0
	var idx := 0
	for id in ROOMS:
		if _only.size() > 0 and not _only.has(String(id)):
			continue
		var wc := RoomArt.default_width(id)
		var h := 76.0 * (2.0 if id == &"stairs" else (4.0 if id == &"elevator" else 1.0))
		var wpx := float(wc) * 40.0 * _scale
		if x + wpx > 1900.0:
			x = 24.0
			y += row_h
		var rect := Rect2(0, 0, wc * 40.0, h)
		U.begin_scaled(self, Vector2(x, y + (row_h - 40.0 - h * _scale) * 0.0), _scale)
		var st := {"t": _t, "busy_ratio": busy, "broken": broken, "repair_progress": 0.4 if broken else 0.0, "highlight": 0}
		if id == &"elevator":
			st["car_deck_f"] = 1.0 + sin(_t * 0.5) * 1.0
		RoomArt.draw_room(self, id, rect, tier, st)
		# guests in slots
		var cap := RoomArt.capacity_for(id, tier)
		if cap > 0 and not broken:
			var n := int(round(busy * float(cap)))
			if busy > 0.0 and n == 0:
				n = 1
			var pose := RoomArt.slot_pose(id)
			for s in range(n):
				var feet := RoomArt.slot_position(id, rect, s, cap)
				var go := {
					"prop": PROPS[s % 4], "body_color": Palette.archetype_color([&"holidaymaker", &"fitness_fan", &"film_buff", &"gamer"][s % 4]),
					"facing": RoomArt.slot_facing(id, rect, s, cap), "pose": pose, "t": _t, "walk_phase": _t * 8.0 + s,
				}
				if id == &"kids_club" and s % 3 != 2:
					go["prop"] = &"propeller"
					go["body_color"] = Palette.archetype_color(&"kid")
					go["body_scale"] = 0.75
				GuestArt.draw_guest(self, feet, go)
		RoomArt.draw_room_front(self, id, rect, tier, st)
		U.end_scaled(self)
		U.text(self, String(id), Vector2(x, y + h * _scale + 16.0), 15, Palette.INK)
		x += wpx + 16.0
		idx += 1
