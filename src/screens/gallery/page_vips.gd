extends Node2D
## Gallery page `--page=vips`: the kid (propeller beanie, 0.75 scale), the three VIP kinds in every pose, matching group heart
## pins and the hover link, the VIP verdict plates, the new icons and the kids' club at every tier with kids in the ball pit.

const U := preload("res://src/render/art/art_util.gd")
const VIPS: Array[StringName] = [&"critic", &"celebrity", &"inspector"]
const POSES: Array[StringName] = [&"stand", &"walk", &"queue", &"sit", &"swim", &"lie", &"sleep", &"run", &"slip", &"storm"]
const VIP_POSES: Array[StringName] = [&"stand", &"walk", &"queue", &"sit", &"lie", &"slip", &"storm"]

var _t: float = 0.0
var _dest: StringName = &"med"


func setup(dest: StringName) -> void:
	_dest = dest


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _kid_opts(pose: StringName, sc: float) -> Dictionary:
	return {"prop": &"propeller", "body_color": Palette.archetype_color(&"kid"), "body_scale": 0.75, "facing": 1, "walk_phase": _t * 9.0,
			"pose": pose, "t": _t, "scale": sc, "slip_t": fmod(_t, 2.2)}


func _vip_opts(kind: StringName, pose: StringName, sc: float) -> Dictionary:
	var prop: StringName = &"beret"
	var col: Color = Palette.archetype_color(&"holidaymaker")
	match kind:
		&"celebrity":
			prop = &"sunglasses"
			col = Palette.archetype_color(&"film_buff")
		&"inspector":
			prop = &"inspector_cap"
			col = Palette.archetype_color(&"fitness_fan")
	return {"prop": prop, "vip": kind, "body_color": col, "facing": 1, "walk_phase": _t * 9.0, "pose": pose, "t": _t, "scale": sc,
			"slip_t": fmod(_t, 2.2)}


func _draw() -> void:
	var d := Palette.dest(_dest)
	U.vgrad(self, Rect2(0, 0, 1920, 1080), d["sky_top"], d["sky_bottom"])
	U.rr(self, Rect2(30, 30, 1860, 1020), 24, Palette.CREAM)
	var f := U.font_bold()
	var x0 := 190.0
	for pi in POSES.size():
		U.text(self, String(POSES[pi]), Vector2(x0 + pi * 150 - 20, 68), 20, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	# row 0: the kid next to a grown-up, then the three VIPs, every pose
	U.text(self, "kid (0.75)", Vector2(60, 160), 18, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	for pi in POSES.size():
		GuestArt.draw_guest(self, Vector2(x0 + pi * 150 + 40, 170), _kid_opts(POSES[pi], 2.4))
		GuestArt.draw_guest(self, Vector2(x0 + pi * 150 + 84, 170), {"prop": &"sun_hat", "body_color": Palette.archetype_color(&"holidaymaker"), "pose": POSES[pi], "t": _t, "scale": 2.4, "walk_phase": _t * 9.0, "slip_t": fmod(_t, 2.2)})
	for r in VIPS.size():
		var y := 300.0 + float(r) * 120.0
		U.text(self, String(VIPS[r]), Vector2(60, y - 10), 18, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
		for pi in VIP_POSES.size():
			GuestArt.draw_guest(self, Vector2(x0 + pi * 150 + 40, y), _vip_opts(VIPS[r], VIP_POSES[pi], 2.4))
	# zoom 1 strip: how they read in the ship
	U.text(self, "zoom 1", Vector2(60, 700), 18, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	U.rect(self, Rect2(150, 714, 700, 5), Palette.FLOOR_TOP)
	for k in 3:
		GuestArt.draw_guest(self, Vector2(190.0 + k * 40.0, 714), _kid_opts(&"stand" if k != 1 else &"walk", 1.0))
	for k in 3:
		GuestArt.draw_guest(self, Vector2(340.0 + k * 60.0, 714), _vip_opts(VIPS[k], &"stand" if k != 1 else &"walk", 1.0))
	for k in 3:
		var o := _vip_opts(VIPS[k], &"stand", 1.0)
		o["facing"] = -1
		o["highlight"] = k
		GuestArt.draw_guest(self, Vector2(560.0 + k * 60.0, 714), o)
	# groups: matching heart pins in every group colour, and the hover link
	U.text(self, "group pins", Vector2(60, 790), 18, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	for g in Palette.GROUP_COLORS.size():
		var gc: Color = Palette.group_color(g + 1)
		var bx := 190.0 + float(g) * 150.0
		var pair := [{"prop": &"sun_hat", "c": &"holidaymaker"}, {"prop": &"glasses_3d", "c": &"film_buff"}]
		for i in 2:
			GuestArt.draw_guest(self, Vector2(bx + float(i) * 34.0, 850), {"prop": pair[i]["prop"], "body_color": Palette.archetype_color(pair[i]["c"]), "pose": &"stand", "t": _t, "scale": 1.8, "group_color": gc, "facing": 1 if i == 0 else -1})
		var kid_o := _kid_opts(&"stand", 1.8)
		kid_o["group_color"] = gc
		kid_o["facing"] = -1
		GuestArt.draw_guest(self, Vector2(bx + 76.0, 850), kid_o)
	# hover link between family members (the renderer draws the same curve, rings and heart)
	U.text(self, "hover link", Vector2(60, 930), 18, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	var link_c := Palette.group_color(3)
	var fam_x: Array[float] = [210.0, 300.0, 380.0]
	for i in 3:
		var fo := _kid_opts(&"stand", 1.8) if i == 2 else {"prop": &"sun_hat" if i == 0 else &"glasses_3d", "body_color": Palette.archetype_color(&"holidaymaker" if i == 0 else &"film_buff"), "pose": &"stand", "t": _t, "scale": 1.8}
		fo["group_color"] = link_c
		U.ellipse(self, Vector2(fam_x[i], 1000.0), 22.0, 7.0, Color(link_c.r, link_c.g, link_c.b, 0.28))
		U.dashed_ring(self, Vector2(fam_x[i], 1000.0), 22.0, 7.0, link_c, 2.4, _t * 0.6, 10)
		GuestArt.draw_guest(self, Vector2(fam_x[i], 1000.0), fo)
	for k in 2:
		var a := Vector2(fam_x[0], 960.0)
		var b := Vector2(fam_x[k + 1], 960.0)
		var ctrl := (a + b) * 0.5 + Vector2(0, -22.0 - a.distance_to(b) * 0.18)
		var curve := PackedVector2Array()
		for j in 13:
			var u := float(j) / 12.0
			curve.append(a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u))
		U.pline(self, curve, Color(link_c.r, link_c.g, link_c.b, 0.85), 3.0)
		GuestArt.draw_heart(self, curve[6] + Vector2(0, -2.0 + sin(_t * 3.0 + float(k)) * 2.0), 11.0, link_c)
	# verdict plates (the ones that float above a VIP)
	var grades: Array[StringName] = [&"great", &"ok", &"bad"]
	var titles: Array[String] = ["Food critic", "Celebrity", "Inspector"]
	var subs: Array[String] = ["+$250", "", "-$150"]
	var cols: Array[Color] = [Palette.MINT_DARK, Palette.TEAL_DARK, Palette.CORAL_DARK]
	for i in 3:
		FxArt.draw_vip_stamp(self, Vector2(1290.0 + i * 190.0, 380.0), 0.3, titles[i], grades[i], subs[i], cols[i])
	# icons
	var icon_ids: Array[StringName] = [&"vip", &"critic", &"celebrity", &"inspector", &"kid", &"family"]
	for i in icon_ids.size():
		var c := Vector2(1240.0 + i * 98.0, 500.0)
		IconArt.draw_icon(self, icon_ids[i], c, 72.0, _t)
		IconArt.draw_icon(self, icon_ids[i], c + Vector2(0, 62), 24.0, _t)
		U.text(self, String(icon_ids[i]), c + Vector2(-30, 94), 16, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	IconArt.draw_room_icon(self, &"kids_club", Vector2(1240.0 + 6.0 * 98.0, 500.0), 72.0)
	# kids' club, tiers I-III, kids and a grown-up in the ball pit
	for k in 3:
		var tier: int = 1 + k
		var rect := Rect2(0, 0, 120, 76)
		var origin := Vector2(1140.0 + float(k) * 245.0, 640.0)
		U.begin_scaled(self, origin, 1.9)
		var st := {"t": _t, "busy_ratio": 0.35 + 0.3 * float(k), "broken": false, "highlight": 0}
		RoomArt.draw_room(self, &"kids_club", rect, tier, st)
		var cap: int = RoomArt.capacity_for(&"kids_club", tier)
		var n: int = mini(2 + k * 2, cap)
		for s in n:
			var o := _kid_opts(RoomArt.slot_pose(&"kids_club"), 1.0)
			o["facing"] = RoomArt.slot_facing(&"kids_club", rect, s, cap)
			if s == 3:
				o = {"prop": &"headphones", "body_color": Palette.archetype_color(&"gamer"), "pose": &"stand", "t": _t, "facing": -1}
			GuestArt.draw_guest(self, RoomArt.slot_position(&"kids_club", rect, s, cap), o)
		RoomArt.draw_room_front(self, &"kids_club", rect, tier, st)
		U.end_scaled(self)
		U.text(self, "kids_club tier %d" % tier, Vector2(origin.x, origin.y + 170.0), 16, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	U.text(self, "kids_club broken", Vector2(1140, 880), 16, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	U.begin_scaled(self, Vector2(1140, 890), 1.9)
	RoomArt.draw_room(self, &"kids_club", Rect2(0, 0, 120, 76), 1, {"t": _t, "busy_ratio": 0.0, "broken": true, "repair_progress": 0.4})
	RoomArt.draw_room_front(self, &"kids_club", Rect2(0, 0, 120, 76), 1, {"t": _t, "busy_ratio": 0.0, "broken": true})
	U.end_scaled(self)
