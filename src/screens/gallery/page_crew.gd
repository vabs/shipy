extends Node2D
## Gallery page: every crew role (janitor, mechanic, medic, entertainer, chef, warden) in each pose at 3x, then the same
## crew at zoom 1 on a deck strip, plus the crew quarters room with sleepers.
## Flags: --scale=3.0  --facing=1|-1

const U := preload("res://src/render/art/art_util.gd")
const ROLES: Array[StringName] = [&"janitor", &"mechanic", &"medic", &"entertainer", &"chef", &"warden"]
const POSES: Array[String] = ["stand", "walk", "active", "tired", "tired walk", "sleep"]
var _t: float = 0.0
var _dest: StringName = &"underworld"
var _scale: float = 3.0
var _facing: int = 1


func setup(dest: StringName) -> void:
	_dest = dest


func setup_params(p: Dictionary) -> void:
	_scale = float(p.get("scale", "3.0"))
	_facing = int(p.get("facing", "1"))


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## The pose that shows the role at work.
static func active_pose(role: StringName) -> StringName:
	match role:
		&"entertainer": return &"perform"
		&"chef": return &"cook"
	return &"work"


func _draw() -> void:
	var d := Palette.dest(_dest)
	U.vgrad(self, Rect2(0, 0, 1920, 1080), d["sky_top"], d["sky_bottom"])
	U.rr(self, Rect2(30, 30, 1860, 1020), 24, Palette.CREAM)
	var f := U.font_bold()
	var x0 := 250.0
	var colw := 190.0
	for pi in POSES.size():
		U.text(self, POSES[pi], Vector2(x0 + float(pi) * colw - 30.0, 78), 22, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	for r in ROLES.size():
		var role: StringName = ROLES[r]
		var y: float = 190.0 + float(r) * 128.0
		U.text(self, String(role), Vector2(60, y - 40.0), 20, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
		for pi in POSES.size():
			var o := {"role": role, "facing": _facing, "walk_phase": _t * 9.0, "t": _t, "scale": _scale, "pose": &"stand"}
			match pi:
				1: o["pose"] = &"walk"
				2: o["pose"] = active_pose(role)
				3: o["tired"] = true
				4:
					o["pose"] = &"walk"
					o["tired"] = true
				5: o["pose"] = &"sleep"
			GuestArt.draw_staff(self, Vector2(x0 + float(pi) * colw + 40.0, y), o)
	# zoom 1 strip: how they read in the ship
	U.text(self, "zoom 1", Vector2(60, 970), 18, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	U.rect(self, Rect2(150, 984, 1120, 6), Palette.FLOOR_TOP)
	for r in ROLES.size():
		for pi in 4:
			var role2: StringName = ROLES[r]
			var o2 := {"role": role2, "facing": -1 if pi % 2 == 1 else 1, "walk_phase": _t * 9.0 + float(r), "t": _t, "pose": &"stand"}
			match pi:
				1: o2["pose"] = &"walk"
				2: o2["pose"] = active_pose(role2)
				3: o2["tired"] = true
			GuestArt.draw_staff(self, Vector2(190.0 + float(r) * 190.0 + float(pi) * 36.0, 984.0), o2)
	# crew quarters, base + tier 3, with sleeping crew
	var cq := Rect2(0, 0, 80, 76)
	for k in 2:
		var tier: int = 1 + k * 2
		var origin := Vector2(1380.0 + float(k) * 240.0, 740.0)
		U.begin_scaled(self, origin, 2.6)
		var st := {"t": _t, "busy_ratio": 0.5 + 0.5 * float(k), "broken": false, "highlight": 0}
		RoomArt.draw_room(self, &"crew_quarters", cq, tier, st)
		var cap: int = RoomArt.capacity_for(&"crew_quarters", tier)
		var n: int = 1 + k * 2
		for s in mini(n, cap):
			GuestArt.draw_staff(self, RoomArt.slot_position(&"crew_quarters", cq, s, cap), {"role": ROLES[(s + k) % ROLES.size()], "pose": &"sleep", "facing": RoomArt.slot_facing(&"crew_quarters", cq, s, cap), "t": _t})
		RoomArt.draw_room_front(self, &"crew_quarters", cq, tier, st)
		U.end_scaled(self)
		U.text(self, "crew_quarters tier %d" % tier, Vector2(origin.x, origin.y + 222.0), 16, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
