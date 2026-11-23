class_name RoomInteriors
extends RefCounted
## Per-room decor + slot geometry for RoomArt. Use RoomArt's API, not this class directly.
## All coordinates are ship-local px. Frame: rect R, floor top fy = R.end.y - 11, ceiling beam 5 px.

const U := preload("res://src/render/art/art_util.gd")

static func _occ(st: Dictionary, room_id: StringName, tier: int) -> int:
	var cap := RoomArt.capacity_for(room_id, tier)
	var b: float = st.get("busy_ratio", 0.0)
	var n := int(roundf(b * float(cap)))
	if b > 0.001 and n == 0:
		n = 1
	return n


static func _k(c: Color, st: Dictionary) -> Color:
	return Palette.shade(c, 0.4) if st.get("broken", false) else c


static func broken_front_dim(_ci: CanvasItem, _room_id: StringName, _R: Rect2) -> void:
	pass


# =================================================================================================
# dispatch
# =================================================================================================
static func back(ci: CanvasItem, id: StringName, R: Rect2, tier: int, st: Dictionary) -> void:
	match id:
		&"cabin": _cabin(ci, R, tier, st, false)
		&"buffet": _buffet(ci, R, tier, st)
		&"toilets": _toilets(ci, R, tier, st, false)
		&"bar": _bar(ci, R, tier, st, false)
		&"pool": _pool(ci, R, tier, st, false)
		&"deck_chairs": _deck_chairs(ci, R, tier, st)
		&"cinema": _cinema(ci, R, tier, st, false)
		&"gym": _gym(ci, R, tier, st)
		&"arcade": _arcade(ci, R, tier, st)
		&"restaurant": _restaurant(ci, R, tier, st, false)
		&"medbay": _medbay(ci, R, tier, st)
		&"sauna": _sauna(ci, R, tier, st, false)
		&"ice_rink": _ice_rink(ci, R, tier, st, false)
		&"casino": _casino(ci, R, tier, st)
		&"generator": _generator(ci, R, tier, st)
		&"water_tank": _water_tank(ci, R, tier, st)


static func front(ci: CanvasItem, id: StringName, R: Rect2, tier: int, st: Dictionary) -> void:
	match id:
		&"cabin": _cabin(ci, R, tier, st, true)
		&"toilets": _toilets(ci, R, tier, st, true)
		&"bar": _bar(ci, R, tier, st, true)
		&"pool": _pool(ci, R, tier, st, true)
		&"cinema": _cinema(ci, R, tier, st, true)
		&"restaurant": _restaurant(ci, R, tier, st, true)
		&"sauna": _sauna(ci, R, tier, st, true)
		&"ice_rink": _ice_rink(ci, R, tier, st, true)


# =================================================================================================
# slots (feet positions)
# =================================================================================================
static func _row(x_from: float, x_to: float, slot: int, n: int) -> float:
	if n <= 1:
		return (x_from + x_to) * 0.5
	return lerpf(x_from, x_to, (float(slot) + 0.5) / float(n))


static func slot_pos(id: StringName, R: Rect2, slot: int, cap: int) -> Vector2:
	var x0 := R.position.x
	var w := R.size.x
	var fy := R.end.y - 11.0
	var cx := x0 + w * 0.5
	var s := maxi(slot, 0)
	match id:
		&"cabin":
			var k := s % 4
			var extra := s / 4
			var x := (x0 + 17.0) if k % 2 == 0 else (x0 + w - 17.0)
			var y := (fy - 11.0) if k < 2 else (fy - 33.0)
			return Vector2(x + (float(extra) * 4.0 if extra % 2 == 1 else -float(extra) * 4.0), y)
		&"buffet":
			var n := maxi(cap, 1)
			var x := _row(x0 + 14.0, x0 + w - 14.0, s, n)
			var stagger := 5.0 if (n > 6 and s % 2 == 1) else 0.0
			return Vector2(x, R.end.y - 3.0 - stagger)
		&"toilets":
			var k := s % 3
			var extra := s / 3
			return Vector2(x0 + 16.0 + float(k) * 24.0 + (4.0 if extra % 2 == 1 else -4.0) * float(mini(extra, 1)), fy - 1.0)
		&"bar":
			var n := maxi(cap, 1)
			return Vector2(_row(x0 + 12.0, x0 + w - 12.0, s, n), fy - 4.0)
		&"pool":
			var n := maxi(cap, 1)
			var rows := 1 if n <= 4 else 2
			var per := int(ceil(float(n) / float(rows)))
			var row := s % rows
			var idx := s / rows
			var x := _row(x0 + 26.0, x0 + w - 26.0, idx, per) + (6.0 if row == 1 else 0.0)
			var y_s := fy - 29.0
			return Vector2(x, y_s + 10.0 + float(row) * 6.0)
		&"deck_chairs":
			var k := s % 4
			var extra := s / 4
			var x := x0 + 15.0 + float(k) * 30.0
			return Vector2(x + (5.0 if extra % 2 == 1 else -5.0) * float(mini(extra, 1)), fy - 8.0)
		&"cinema":
			var r := s / 4
			var col := s % 4
			return Vector2(cx + 14.0 + float(col) * 16.0 + float(r) * 6.0, fy - 1.0 - float(r) * 7.0)
		&"gym":
			if s < 4:
				return Vector2(x0 + 15.0 + float(s) * 30.0, fy - 4.0)
			return Vector2(x0 + 30.0 + float((s - 4) % 4) * 30.0 - 15.0, R.end.y - 2.0)
		&"arcade":
			var k := s % 4
			var row := s / 4
			return Vector2(x0 + 15.0 + float(k) * 30.0 + float(row) * 8.0, R.end.y - 3.0 - float(mini(row, 1)) * 7.0)
		&"restaurant":
			var k := s % 4
			var tbl := k / 2
			var side := k % 2
			var tx := (x0 + 36.0) if tbl == 0 else (x0 + w - 36.0)
			var extra := s / 4
			var dx := (-19.0 if side == 0 else 19.0)
			if extra > 0:
				dx += (-1.0 if side == 0 else 1.0) * 13.0 * float(extra)
			return Vector2(tx + dx, fy - 3.5)
		&"medbay":
			var k := s % 2
			return Vector2((x0 + 17.0) if k == 0 else (x0 + w - 17.0), fy - 9.0)
		&"sauna":
			var table: Array[Vector2] = [Vector2(54.0, -21.5), Vector2(70.0, -21.5), Vector2(62.0, -9.5), Vector2(46.0, -9.5)]
			var p := table[s % 4]
			return Vector2(x0 + p.x, fy + p.y)
		&"ice_rink":
			var n := maxi(cap, 1)
			var rows := 2
			var per := int(ceil(float(n) / float(rows)))
			var row := s % rows
			var idx := s / rows
			return Vector2(_row(x0 + 18.0, x0 + w - 18.0, idx, per) + (9.0 if row == 1 else 0.0), R.end.y - 3.0 - float(row) * 6.0)
		&"casino":
			var table: Array[float] = [16.0, 36.0, 98.0, 112.0, 126.0, 140.0]
			var xx := table[s % 6]
			return Vector2(x0 + xx + (4.0 if (s / 6) % 2 == 1 else 0.0), R.end.y - 3.0 - float(mini(s / 6, 1)) * 6.0)
	return Vector2(cx, R.end.y - 2.0)


# =================================================================================================
# CABIN  (80 px)
# =================================================================================================
static func _cabin(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary, front: bool) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var cx := x0 + w * 0.5
	var occ := _occ(st, &"cabin", tier)
	var bw := 28.0
	var lx := x0 + 3.0
	var rx := x0 + w - 3.0 - bw
	var blanket := _k(Palette.CORAL, st)
	if front:
		U.dyn_begin()
		for k in range(mini(occ, 4)):
			var bx := lx if k % 2 == 0 else rx
			var surf := (fy - 11.0) if k < 2 else (fy - 33.0)
			U.rr(ci, Rect2(bx + 10.0, surf - 9.0, 18.0, 9.5), 4.0, blanket)
			U.rect(ci, Rect2(bx + 14.5, surf - 8.5, 2.6, 8.5), Color(1, 1, 1, 0.45))
			U.rect(ci, Rect2(bx + 20.0, surf - 8.0, 2.6, 8.0), Color(1, 1, 1, 0.45))
			U.rr(ci, Rect2(bx + 11.0, surf - 8.2, 6.0, 3.0), 1.5, Color(1, 1, 1, 0.18))
		U.dyn_end()
		return
	# portholes (above the bunks)
	for px in [lx + 14.0, rx + 14.0]:
		var pc := Vector2(px, y0 + 20.0)
		U.circ(ci, pc, 7.6, Palette.GOLD if tier >= 3 else Palette.STEEL)
		U.circ(ci, pc, 6.0, Palette.shade(Palette.STEEL, 0.2))
		U.vgrad(ci, Rect2(px - 5.0, y0 + 15.0, 10.0, 10.0), Palette.SKY_BLUE, Color("FFE9C8"))
		# round clip approximated with a ring overlay in wall colour
		U.ring(ci, pc, 7.0, Palette.STEEL, 2.4)
		U.ellipse(ci, pc + Vector2(-1.8, -1.8), 2.2, 1.2, Color(1, 1, 1, 0.7))
		U.circ(ci, pc + Vector2(2.0, 1.4), 1.8, Color(1, 1, 1, 0.85))
	# bunks
	for side in range(2):
		var bx := lx if side == 0 else rx
		U.rr(ci, Rect2(bx - 0.5, fy - 43.0, 3.2, 42.0), 1.5, Palette.WOOD_DARK)
		U.rr(ci, Rect2(bx + bw - 2.7, fy - 43.0, 3.2, 42.0), 1.5, Palette.WOOD_DARK)
		for lvl in range(2):
			var surf := (fy - 11.0) if lvl == 0 else (fy - 33.0)
			var k := side + lvl * 2
			U.rr(ci, Rect2(bx, surf + 3.5, bw, 3.5), 1.5, Palette.WOOD)
			U.rr(ci, Rect2(bx, surf, bw, 4.5), 2.2, Color("FFFDF6"))
			U.rr(ci, Rect2(bx + 2.0, surf - 3.2, 8.5, 4.0), 2.5, Color("FFFFFF") if tier < 2 else Color("EDE4FF"))
			if k >= occ:
				U.dyn_begin()
				U.rr(ci, Rect2(bx + 10.0, surf - 3.0, 18.0, 4.2), 2.0, blanket)
				U.rect(ci, Rect2(bx + 14.5, surf - 3.0, 2.4, 4.0), Color(1, 1, 1, 0.4))
				U.rect(ci, Rect2(bx + 20.0, surf - 3.0, 2.4, 4.0), Color(1, 1, 1, 0.4))
				U.dyn_end()
		# ladder on the inner side
		var lxp := bx + bw + 0.0 if side == 0 else bx - 4.0
		U.rect(ci, Rect2(lxp, fy - 32.0, 1.6, 31.0), Palette.WOOD_LIGHT)
		U.rect(ci, Rect2(lxp + 3.2, fy - 32.0, 1.6, 31.0), Palette.WOOD_LIGHT)
		for r in range(4):
			U.rect(ci, Rect2(lxp, fy - 28.0 + float(r) * 7.5, 4.8, 1.4), Palette.WOOD)
	if tier >= 2:
		U.rr(ci, Rect2(cx - 15.0, fy + 1.5, 30.0, 5.0), 2.5, Color(Palette.CORAL.r, Palette.CORAL.g, Palette.CORAL.b, 0.75))
		U.rr(ci, Rect2(cx - 11.0, fy + 3.0, 22.0, 1.6), 0.8, Color(1, 1, 1, 0.5))
	if tier >= 3:
		# bedside lamp glow
		U.circ(ci, Vector2(cx + 15.0, fy - 28.0), 9.0, Color(1.0, 0.9, 0.5, 0.18))
		U.circ(ci, Vector2(cx + 15.0, fy - 28.0), 3.0, Color(1.0, 0.95, 0.6, 0.9))


# =================================================================================================
# BUFFET (160 px)
# =================================================================================================
static func _buffet(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var t: float = st.get("t", 0.0)
	var occ := _occ(st, &"buffet", tier)
	# awning valance
	var n := int(w / 10.0)
	for i in range(n):
		var c := Palette.ORANGE if i % 2 == 0 else Palette.CREAM
		U.rect(ci, Rect2(x0 + float(i) * 10.0, y0 + CEIL(), 10.0, 5.0), c)
		U.circ(ci, Vector2(x0 + float(i) * 10.0 + 5.0, y0 + CEIL() + 5.0), 5.0, c)
	# chalkboard menu
	U.rr(ci, Rect2(x0 + 8.0, y0 + 24.0, 32.0, 21.0), 3.0, Palette.WOOD)
	U.rr(ci, Rect2(x0 + 9.6, y0 + 25.6, 28.8, 17.8), 2.0, Color("34495E"))
	U.line(ci, Vector2(x0 + 13.0, y0 + 31.0), Vector2(x0 + 30.0, y0 + 31.0), Color(1, 1, 1, 0.8), 1.2)
	U.line(ci, Vector2(x0 + 13.0, y0 + 35.0), Vector2(x0 + 26.0, y0 + 35.0), Color(1, 1, 1, 0.6), 1.2)
	U.line(ci, Vector2(x0 + 13.0, y0 + 39.0), Vector2(x0 + 33.0, y0 + 39.0), Color(1, 1, 1, 0.6), 1.2)
	U.circ(ci, Vector2(x0 + 34.0, y0 + 31.0), 1.5, Palette.SUN)
	# framed picture (fruit) at the right
	U.rr(ci, Rect2(x0 + w - 36.0, y0 + 24.0, 26.0, 20.0), 3.0, Palette.WOOD_DARK)
	U.rr(ci, Rect2(x0 + w - 34.4, y0 + 25.6, 22.8, 16.8), 2.0, Color("FFF3D1"))
	U.circ(ci, Vector2(x0 + w - 28.0, y0 + 35.0), 4.0, Palette.CORAL)
	U.circ(ci, Vector2(x0 + w - 20.0, y0 + 35.0), 3.6, Palette.SUN)
	U.rect(ci, Rect2(x0 + w - 27.0, y0 + 29.0, 1.2, 2.5), Palette.MINT_DARK)
	# counter
	U.rr(ci, Rect2(x0 + 4.0, fy - 17.0, w - 8.0, 17.0), 3.0, Color("F5A662"))
	U.rr(ci, Rect2(x0 + 4.0, fy - 17.0, w - 8.0, 5.0), 3.0, Color("FFF5E3"))
	U.rect(ci, Rect2(x0 + 5.0, fy - 11.0, w - 10.0, 1.2), Color(0.6, 0.3, 0.1, 0.25))
	var dn := int((w - 8.0) / 8.0)
	for i in range(dn):
		U.rect(ci, Rect2(x0 + 8.0 + float(i) * 8.0, fy - 9.5, 4.0, 8.0), Color(1, 1, 1, 0.18))
	# food
	var items := int(w / 26.0)
	for i in range(items):
		var fx := x0 + 18.0 + float(i) * (w - 36.0) / float(maxi(items - 1, 1))
		var fyy := fy - 17.0
		match (i + (int(x0) / 40)) % 5:
			0:  # cloche
				U.rr_ex(ci, Rect2(fx - 6.5, fyy - 11.0, 13.0, 11.0), 6.5, 6.5, 0.0, 0.0, Palette.STEEL)
				U.rr_ex(ci, Rect2(fx - 5.0, fyy - 9.5, 4.0, 7.0), 3.0, 2.0, 0.0, 0.0, Color(1, 1, 1, 0.45))
				U.circ(ci, Vector2(fx, fyy - 12.0), 1.4, Palette.STEEL_DARK)
			1:  # salad bowl
				U.rr_ex(ci, Rect2(fx - 6.5, fyy - 5.0, 13.0, 5.0), 0.0, 0.0, 6.0, 6.0, Color("FFFDF6"))
				U.circ(ci, Vector2(fx - 2.5, fyy - 6.0), 2.8, Palette.MINT)
				U.circ(ci, Vector2(fx + 2.0, fyy - 6.4), 3.0, Palette.MINT_DARK)
				U.circ(ci, Vector2(fx, fyy - 7.4), 1.5, Palette.CORAL)
			2:  # cake
				U.rr(ci, Rect2(fx - 6.0, fyy - 6.0, 12.0, 6.0), 2.0, Palette.PINK)
				U.rr(ci, Rect2(fx - 6.0, fyy - 7.2, 12.0, 2.8), 1.4, Color("FFF5E3"))
				U.circ(ci, Vector2(fx, fyy - 9.0), 1.8, Palette.CORAL)
			3:  # pizza
				U.ellipse(ci, Vector2(fx, fyy - 1.6), 7.5, 2.0, Color("D9A24A"))
				U.ellipse(ci, Vector2(fx, fyy - 2.2), 6.6, 1.6, Color("FFC857"))
				U.circ(ci, Vector2(fx - 2.5, fyy - 2.4), 1.0, Palette.CORAL)
				U.circ(ci, Vector2(fx + 2.0, fyy - 2.2), 1.0, Palette.CORAL)
			4:  # fruit basket
				U.rr_ex(ci, Rect2(fx - 6.0, fyy - 4.0, 12.0, 4.0), 0.0, 0.0, 4.0, 4.0, Palette.WOOD)
				U.circ(ci, Vector2(fx - 3.0, fyy - 5.5), 2.6, Palette.CORAL)
				U.circ(ci, Vector2(fx + 1.0, fyy - 6.2), 2.6, Palette.SUN)
				U.circ(ci, Vector2(fx + 4.0, fyy - 5.4), 2.2, Palette.MINT_DARK)
	# sneeze guard (glass)
	U.rr(ci, Rect2(x0 + 8.0, fy - 31.0, w - 16.0, 12.0), 5.0, Color(0.8, 0.95, 1.0, 0.2))
	U.pline(ci, PackedVector2Array([Vector2(x0 + 10.0, fy - 20.0), Vector2(x0 + 10.0, fy - 28.0), Vector2(x0 + w - 10.0, fy - 28.0)]), Color(1, 1, 1, 0.5), 1.4)
	# steam from the dishes (dynamic)
	U.dyn_begin()
	if not st.get("broken", false):
		for i in range(2):
			var k := fmod(t * 0.5 + float(i) * 0.5, 1.0)
			var sx := x0 + w * (0.35 + 0.3 * float(i))
			U.circ(ci, Vector2(sx + sin(k * 6.0) * 2.0, fy - 30.0 - k * 12.0), 2.0 + k * 2.0, Color(1, 1, 1, 0.35 * (1.0 - k)))
	U.dyn_end()


static func CEIL() -> float:
	return RoomArt.CEIL_H


# =================================================================================================
# TOILETS (80 px)
# =================================================================================================
static func _toilets(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary, front: bool) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var occ := _occ(st, &"toilets", tier)
	var teal := _k(Palette.TEAL, st)
	if front:
		U.dyn_begin()
		for i in range(3):
			var sx := x0 + 4.0 + float(i) * 24.0
			var open := i >= occ
			if open:
				# door swung open: just a thin slice at the side
				U.rr(ci, Rect2(sx + 1.5, fy - 21.0, 3.0, 20.0), 1.5, Palette.TEAL_DARK if not st.get("broken", false) else Color("2A4A5A"))
			else:
				U.rr(ci, Rect2(sx + 2.0, fy - 18.0, 20.0, 16.5), 3.0, teal)
				U.rr(ci, Rect2(sx + 2.0, fy - 18.0, 20.0, 3.0), 2.0, Color(1, 1, 1, 0.3))
				for r in range(3):
					U.rect(ci, Rect2(sx + 5.0, fy - 11.0 + float(r) * 2.6, 14.0, 1.1), Color(0, 0, 0, 0.16))
				U.rr(ci, Rect2(sx + 15.0, fy - 16.0, 5.0, 2.4), 1.2, Palette.CORAL)
		U.dyn_end()
		return
	# tiles
	var tile := Color(1, 1, 1, 0.35)
	for i in range(1, int(w / 10.0) + 1):
		U.rect(ci, Rect2(x0 + float(i) * 10.0 - 0.5, y0 + 6.0, 1.0, 48.0), tile)
	for j in range(1, 5):
		U.rect(ci, Rect2(x0, y0 + 6.0 + float(j) * 10.0, w, 1.0), tile)
	# stalls
	for i in range(3):
		var sx := x0 + 4.0 + float(i) * 24.0
		U.rr(ci, Rect2(sx, fy - 46.0, 24.0, 46.0), 2.0, Color("B9E6EC"))
		U.rect(ci, Rect2(sx, fy - 46.0, 24.0, 3.0), Color("9AD3DC"))
		# toilet
		U.rr(ci, Rect2(sx + 14.0, fy - 27.0, 7.0, 12.0), 2.0, Color("FFFFFF"))
		U.rr(ci, Rect2(sx + 15.0, fy - 28.0, 5.0, 2.0), 1.0, Color("DDE7EE"))
		U.rr(ci, Rect2(sx + 5.0, fy - 15.0, 17.0, 5.0), 2.5, Color("FFFFFF"))
		U.rr(ci, Rect2(sx + 7.0, fy - 10.5, 11.0, 9.5), 3.0, Color("EAF1F5"))
		U.rr(ci, Rect2(sx + 5.0, fy - 16.2, 12.0, 2.2), 1.2, Color("CFE0E8"))
		# toilet paper
		U.circ(ci, Vector2(sx + 5.0, fy - 26.0), 2.4, Palette.CREAM)
		if i % 2 == 0:
			U.circ(ci, Vector2(sx + 5.0, fy - 26.0), 0.9, Palette.STEEL)
	# dividers
	for i in range(4):
		U.rect(ci, Rect2(x0 + 3.2 + float(i) * 24.0, fy - 46.0, 1.8, 46.0), Color("73B9C6"))
	# hand-wash basin hint & mirror above door region handled by sign
	U.rr(ci, Rect2(x0 + 4.0, fy - 49.0, w - 8.0, 3.0), 1.5, Color("73B9C6"))


# =================================================================================================
# BAR (120 px)
# =================================================================================================
static func _bar(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary, front: bool) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var cx := x0 + w * 0.5
	var t: float = st.get("t", 0.0)
	var wood := _k(Color("9A5F3A"), st)
	if front:
		# counter top + front panel
		U.rr(ci, Rect2(x0 + 2.0, fy - 10.0, w - 4.0, 4.0), 2.0, _k(Color("C98B54"), st))
		U.rect(ci, Rect2(x0 + 4.0, fy - 10.0, w - 8.0, 1.2), Color(1, 1, 1, 0.3))
		U.rr(ci, Rect2(x0 + 3.0, fy - 7.0, w - 6.0, 8.0), 2.0, wood)
		var sn := int((w - 6.0) / 8.0)
		for i in range(sn):
			U.rect(ci, Rect2(x0 + 6.0 + float(i) * 8.0, fy - 6.0, 1.2, 6.0), Color(0, 0, 0, 0.18))
		U.rect(ci, Rect2(x0 + 4.0, fy - 2.2, w - 8.0, 1.4), _k(Palette.GOLD, st))
		# drinks
		var cols: Array[Color] = [Palette.CORAL, Palette.SUN, Palette.MINT, Palette.LILAC, Palette.TEAL_LIGHT]
		for i in range(5):
			var dx := x0 + 14.0 + float(i) * (w - 28.0) / 4.0 + (3.0 if i % 2 == 0 else -2.0)
			var c := cols[i % 5]
			U.rr_ex(ci, Rect2(dx - 2.8, fy - 16.5, 5.6, 7.0), 0.0, 0.0, 2.5, 2.5, Color(0.85, 0.95, 1.0, 0.8))
			U.rect(ci, Rect2(dx - 2.4, fy - 14.0, 4.8, 3.8), _k(c, st))
			U.line(ci, Vector2(dx + 1.0, fy - 16.5), Vector2(dx + 2.6, fy - 20.0), Palette.CORAL if i % 2 == 0 else Palette.MINT_DARK, 1.0)
			if i % 3 == 0:
				U.poly(ci, PackedVector2Array([Vector2(dx - 3.6, fy - 17.4), Vector2(dx, fy - 21.0), Vector2(dx + 0.6, fy - 17.4)]), Palette.CORAL_LIGHT)
		return
	var occ := _occ(st, &"bar", tier)
	# string lights
	var nl := int(w / 12.0)
	U.pline(ci, PackedVector2Array([Vector2(x0 + 2.0, y0 + 9.0), Vector2(cx, y0 + 15.0), Vector2(x0 + w - 2.0, y0 + 9.0)]), Color(0.1, 0.1, 0.2, 0.7), 1.0)
	for i in range(nl + 1):
		var f := float(i) / float(nl)
		var lx := lerpf(x0 + 2.0, x0 + w - 2.0, f)
		var ly := y0 + 9.0 + 6.0 * (1.0 - pow(2.0 * f - 1.0, 2.0)) * 1.0
		var tw := 0.55 + 0.45 * sin(t * 3.0 + float(i) * 1.7)
		var lc: Color = [Palette.SUN, Palette.CORAL_LIGHT, Palette.TEAL_LIGHT, Palette.MINT][i % 4]
		U.circ(ci, Vector2(lx, ly + 2.0), 1.8, lc)
		U.dyn_begin()
		U.circ(ci, Vector2(lx, ly + 2.0), 4.5, Color(lc.r, lc.g, lc.b, 0.18 * tw))
		U.dyn_end()
	# shelves + bottles (both sides, door in the middle)
	for side in range(2):
		var sx := x0 + 6.0 if side == 0 else cx + 22.0
		var sw := (cx - 22.0 - (x0 + 6.0)) if side == 0 else (x0 + w - 6.0 - (cx + 22.0))
		for row in range(2):
			var sy := y0 + 34.0 + float(row) * 15.0
			U.rr(ci, Rect2(sx, sy, sw, 2.4), 1.0, Color("D9A066"))
			var nb := int(sw / 7.0)
			for b in range(nb):
				var bx := sx + 3.0 + float(b) * 7.0
				var bh := 8.0 + float((b + row + side) % 3) * 2.0
				var bc: Color = [Palette.MINT, Palette.CORAL, Palette.SUN, Palette.TEAL, Palette.LILAC][(b + row * 2 + side) % 5]
				U.rr(ci, Rect2(bx, sy - bh, 4.4, bh), 1.6, _k(bc, st))
				U.rect(ci, Rect2(bx + 1.5, sy - bh - 2.6, 1.4, 3.0), Color("EAD7B7"))
				U.rect(ci, Rect2(bx + 0.8, sy - bh + 1.5, 1.0, bh * 0.5), Color(1, 1, 1, 0.35))
	# neon cocktail on the wall (heart)
	if tier >= 2:
		U.circ(ci, Vector2(cx, y0 + 37.0), 9.0, Color(1.0, 0.4, 0.7, 0.12))
	# stools (tops peek above the counter only for empty seats)
	var n := RoomArt.capacity_for(&"bar", tier)
	U.dyn_begin()
	for i in range(n):
		if i < occ:
			continue
		var sxp := _row(x0 + 12.0, x0 + w - 12.0, i, n)
		U.ellipse(ci, Vector2(sxp, fy - 9.0), 4.4, 1.6, Color("D6455D"))
	U.dyn_end()


# =================================================================================================
# POOL (240 px, open air)
# =================================================================================================
static func _pool_geom(R: Rect2) -> Dictionary:
	var fy := R.end.y - 11.0
	return {"rim": fy - 36.0, "surf": fy - 29.0, "bot": R.end.y - 1.0, "x0": R.position.x + 10.0, "x1": R.end.x - 10.0, "fy": fy}


static func _pool(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary, front: bool) -> void:
	var g := _pool_geom(R)
	var rim: float = g["rim"]
	var surf: float = g["surf"]
	var bot: float = g["bot"]
	var px0: float = g["x0"]
	var px1: float = g["x1"]
	var x0 := R.position.x
	var w := R.size.x
	var t: float = st.get("t", 0.0)
	var cx := x0 + w * 0.5
	var dim: bool = st.get("broken", false)
	if front:
		# translucent front water
		U.rr(ci, Rect2(px0, surf, px1 - px0, bot - surf - 2.0), 4.0, _k(Color(0.35, 0.8, 0.95, 0.32), st) if not dim else Color(0.2, 0.4, 0.5, 0.32))
		# light streaks + wavy lines (dynamic)
		U.dyn_begin()
		for i in range(5):
			var sx := px0 + 12.0 + float(i) * (px1 - px0 - 24.0) / 4.0 + sin(t * 0.7 + float(i) * 1.9) * 6.0
			U.poly(ci, PackedVector2Array([Vector2(sx, surf + 2.0), Vector2(sx + 7.0, surf + 2.0), Vector2(sx + 2.0, bot - 4.0), Vector2(sx - 3.0, bot - 4.0)]), Color(1, 1, 1, 0.07))
		# wavy surface line
		var pts := PackedVector2Array()
		var n := int((px1 - px0) / 8.0)
		for i in range(n + 1):
			var x := px0 + float(i) * (px1 - px0) / float(n)
			pts.append(Vector2(x, surf + sin(t * 2.2 + x * 0.12) * 1.3))
		U.pline(ci, pts, Color(1, 1, 1, 0.75), 2.2)
		var pts2 := PackedVector2Array()
		for i in range(n + 1):
			var x := px0 + float(i) * (px1 - px0) / float(n)
			pts2.append(Vector2(x, surf + 4.0 + sin(t * 1.6 + x * 0.17 + 2.0) * 1.0))
		U.pline(ci, pts2, Color(1, 1, 1, 0.22), 1.4)
		U.dyn_end()
		# front lip (glass edge)
		U.rr(ci, Rect2(px0 - 6.0, bot - 4.0, px1 - px0 + 12.0, 6.0), 3.0, _k(Color("F4FBFF"), st))
		U.rr(ci, Rect2(px0 - 6.0, bot - 1.5, px1 - px0 + 12.0, 3.5), 2.0, _k(Palette.TEAL, st))
		return
	# frame + basin back wall
	U.rr(ci, Rect2(px0 - 6.0, rim - 2.0, px1 - px0 + 12.0, bot - rim + 2.0), 8.0, _k(Color("F4FBFF"), st))
	U.rr(ci, Rect2(px0 - 2.0, rim + 2.0, px1 - px0 + 4.0, bot - rim - 3.0), 5.0, _k(Color("BFEAFB"), st))
	# back tiles above water
	for i in range(1, int((px1 - px0) / 12.0)):
		U.rect(ci, Rect2(px0 + float(i) * 12.0, rim + 2.0, 1.0, surf - rim - 2.0), Color(1, 1, 1, 0.5))
	U.rect(ci, Rect2(px0 - 2.0, rim + 6.0, px1 - px0 + 4.0, 1.0), Color(1, 1, 1, 0.5))
	# water volume
	U.vgrad(ci, Rect2(px0 - 2.0, surf, px1 - px0 + 4.0, bot - surf - 3.0), _k(Color("8CE6F2"), st), _k(Color("2F9FCB"), st))
	# caustics (dynamic)
	U.dyn_begin()
	for i in range(9):
		var cxp := px0 + float(i) * (px1 - px0) / 8.0 + sin(t * 0.9 + float(i) * 2.3) * 9.0
		var cyp := surf + 8.0 + float(i % 3) * 7.0 + sin(t * 1.3 + float(i)) * 1.5
		U.ellipse(ci, Vector2(cxp, cyp), 7.0, 1.4, Color(1, 1, 1, 0.16))
	U.dyn_end()
	# tile line along the bottom
	U.rect(ci, Rect2(px0 - 2.0, bot - 9.0, px1 - px0 + 4.0, 1.2), Color(1, 1, 1, 0.25))
	# ladder at the door position
	var lx := cx
	for dx in [-4.5, 4.5]:
		U.pline(ci, PackedVector2Array([Vector2(lx + dx, surf + 12.0), Vector2(lx + dx, rim - 7.0), Vector2(lx + dx * 0.4, rim - 11.0)]), _k(Palette.STEEL, st), 2.2)
	for r in range(4):
		U.line(ci, Vector2(lx - 4.5, surf + 2.0 + float(r) * 3.4), Vector2(lx + 4.5, surf + 2.0 + float(r) * 3.4), _k(Palette.STEEL, st), 1.6)
	U.line(ci, Vector2(lx - 4.5, rim - 7.0), Vector2(lx + 4.5, rim - 7.0), _k(Palette.STEEL, st), 1.6)
	# beach ball + duck (dynamic)
	U.dyn_begin()
	var bx := x0 + w * 0.8 + sin(t * 0.5) * 7.0
	var by := surf - 3.5 + sin(t * 1.9) * 1.3
	U.circ(ci, Vector2(bx, by), 6.4, _k(Color("FFFFFF"), st))
	for i in range(3):
		var a0 := float(i) * TAU / 3.0 + t * 0.4
		U.poly(ci, PackedVector2Array([Vector2(bx, by), Vector2(bx + cos(a0) * 6.2, by + sin(a0) * 6.2), Vector2(bx + cos(a0 + 0.9) * 6.2, by + sin(a0 + 0.9) * 6.2)]), _k([Palette.CORAL, Palette.SUN, Palette.TEAL][i], st))
	U.ellipse(ci, Vector2(bx - 2.0, by - 2.5), 2.0, 1.2, Color(1, 1, 1, 0.55))
	var dxp := x0 + w * 0.2 + sin(t * 0.4 + 1.0) * 5.0
	var dyp := surf - 1.2 + sin(t * 2.3) * 1.0
	U.ellipse(ci, Vector2(dxp, dyp), 5.0, 3.2, _k(Palette.SUN, st))
	U.circ(ci, Vector2(dxp + 3.6, dyp - 3.6), 2.8, _k(Palette.SUN, st))
	U.poly(ci, PackedVector2Array([Vector2(dxp + 5.8, dyp - 3.8), Vector2(dxp + 8.4, dyp - 3.0), Vector2(dxp + 5.8, dyp - 2.4)]), _k(Palette.ORANGE, st))
	U.circ(ci, Vector2(dxp + 4.2, dyp - 4.4), 0.7, Palette.INK)
	U.dyn_end()
	# flag pole banner shadow
	U.rect(ci, Rect2(px0 - 6.0, rim - 2.0, 3.0, bot - rim + 2.0), Color(0, 0, 0, 0.06))


# =================================================================================================
# DECK CHAIRS (120 px, open air)
# =================================================================================================
static func _deck_chairs(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var t: float = st.get("t", 0.0)
	var cols_a: Array[Color] = [Palette.CORAL, Palette.TEAL]
	# umbrellas
	for u in range(2):
		var ux := x0 + w * (0.25 if u == 0 else 0.75)
		var uy := y0 + 30.0
		U.rr(ci, Rect2(ux - 1.0, uy, 2.2, fy - uy), 1.0, _k(Palette.STEEL, st))
		var wedges := 6
		for i in range(wedges):
			var a0 := PI + float(i) * PI / float(wedges)
			var a1 := PI + float(i + 1) * PI / float(wedges)
			var c := _k(cols_a[u], st) if i % 2 == 0 else _k(Palette.HULL_WHITE, st)
			U.poly(ci, PackedVector2Array([Vector2(ux, uy - 11.0), Vector2(ux + cos(a0) * 21.0, uy + sin(a0) * 11.0), Vector2(ux + cos((a0 + a1) * 0.5) * 21.5, uy + sin((a0 + a1) * 0.5) * 11.5), Vector2(ux + cos(a1) * 21.0, uy + sin(a1) * 11.0)]), c)
		# scalloped hem
		for i in range(6):
			var hx := ux - 21.0 + float(i) * 7.0
			U.circ(ci, Vector2(hx + 3.5, uy + 0.5), 3.6, _k(cols_a[u], st) if i % 2 == 0 else _k(Palette.HULL_WHITE, st))
		U.circ(ci, Vector2(ux, uy - 12.0), 2.0, _k(Palette.SUN, st))
		U.ellipse(ci, Vector2(ux - 8.0, uy - 6.0), 5.0, 1.8, Color(1, 1, 1, 0.25))
	# sunbeds
	for i in range(4):
		var bx := x0 + 15.0 + float(i) * 30.0
		var base_c := _k(Palette.TEAL if (i % 2 == 0) else Palette.CORAL, st)
		U.rect(ci, Rect2(bx - 12.0, fy - 5.0, 1.8, 5.0), _k(Palette.STEEL, st))
		U.rect(ci, Rect2(bx + 10.0, fy - 5.0, 1.8, 5.0), _k(Palette.STEEL, st))
		U.rr(ci, Rect2(bx - 14.0, fy - 9.0, 28.0, 5.0), 2.5, _k(Color("FFFDF6"), st))
		for s in range(4):
			U.rect(ci, Rect2(bx - 8.0 + float(s) * 6.0, fy - 9.0, 3.0, 5.0), base_c)
		U.poly(ci, PackedVector2Array([Vector2(bx - 14.0, fy - 8.5), Vector2(bx - 12.0, fy - 14.0), Vector2(bx - 6.0, fy - 12.0), Vector2(bx - 5.0, fy - 8.5)]), _k(Color("FFFDF6"), st))
		U.rect(ci, Rect2(bx - 11.5, fy - 13.0, 3.0, 4.0), base_c)
	# drink on a tiny table (between the two beds on the right, hidden if tier 1? always)
	if tier >= 2:
		U.rr(ci, Rect2(x0 + w * 0.5 - 4.0, fy - 8.0, 8.0, 8.0), 2.0, _k(Palette.WOOD, st))
		U.rr_ex(ci, Rect2(x0 + w * 0.5 - 2.0, fy - 14.0, 4.0, 6.0), 0.0, 0.0, 2.0, 2.0, Color(1, 0.7, 0.4, 0.9))


# =================================================================================================
# CINEMA (160 px)
# =================================================================================================
static func _cinema(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary, front: bool) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var cx := x0 + w * 0.5
	var t: float = st.get("t", 0.0)
	var cap := RoomArt.capacity_for(&"cinema", tier)
	var occ := _occ(st, &"cinema", tier)
	var rows := int(ceil(float(cap) / 4.0))
	if front:
		# popcorn buckets on laps (occupied slots)
		U.dyn_begin()
		for s in range(mini(occ, cap)):
			var p := slot_pos(&"cinema", R, s, cap)
			var bx := p.x - 5.5
			var by := p.y - 6.0
			U.rr_ex(ci, Rect2(bx - 3.0, by, 6.0, 5.5), 0.0, 0.0, 1.5, 1.5, _k(Palette.CREAM, st))
			U.rect(ci, Rect2(bx - 1.5, by, 1.4, 5.5), _k(Palette.CORAL, st))
			U.rect(ci, Rect2(bx + 1.2, by, 1.4, 5.5), _k(Palette.CORAL, st))
			U.circ(ci, Vector2(bx - 1.6, by - 0.8), 1.6, Color("FFF3C2"))
			U.circ(ci, Vector2(bx + 1.4, by - 1.2), 1.6, Color("FFF3C2"))
			U.circ(ci, Vector2(bx, by - 2.0), 1.4, Color("FFF3C2"))
		U.dyn_end()
		return
	# curtains + screen on the left
	var sx := x0 + 9.0
	var sy := y0 + 12.0
	var sw := 54.0
	var sh := 34.0
	U.rr(ci, Rect2(sx - 4.0, sy - 5.0, sw + 8.0, sh + 9.0), 4.0, _k(Color("2A2147"), st))
	var busy := float(st.get("busy_ratio", 0.0))
	var glow := 0.55 + 0.45 * busy
	if st.get("broken", false):
		glow = 0.1
	U.rect(ci, Rect2(sx, sy, sw, sh), Color("3A2F66"))
	U.dyn_begin()
	var hue := fmod(t * 0.08, 1.0)
	var c1 := Color.from_hsv(hue, 0.55, 1.0)
	var c2 := Color.from_hsv(fmod(hue + 0.25, 1.0), 0.6, 0.95)
	U.vgrad(ci, Rect2(sx + 4.0, sy, sw - 8.0, sh), Palette.tint(c1, 0.3).lerp(Color("2A2147"), 1.0 - glow), c2.lerp(Color("2A2147"), 1.0 - glow))
	# movie scene: moving blobs + sun
	if not st.get("broken", false):
		U.ellipse(ci, Vector2(sx + 16.0 + sin(t * 0.6) * 4.0, sy + 24.0), 11.0, 5.0, Color(1, 1, 1, 0.18))
		U.circ(ci, Vector2(sx + sw - 14.0, sy + 11.0 + sin(t * 0.5) * 1.5), 5.0, Color(1.0, 0.95, 0.7, 0.9))
		U.poly(ci, PackedVector2Array([Vector2(sx + 4.0, sy + sh), Vector2(sx + 14.0, sy + 20.0), Vector2(sx + 24.0, sy + sh)]), Color(0.15, 0.1, 0.3, 0.5))
		U.poly(ci, PackedVector2Array([Vector2(sx + 16.0, sy + sh), Vector2(sx + 32.0, sy + 16.0), Vector2(sx + sw - 4.0, sy + sh)]), Color(0.15, 0.1, 0.3, 0.4))
	U.rr(ci, Rect2(sx + 4.0, sy, sw - 8.0, 6.0), 3.0, Color(1, 1, 1, 0.12))
	U.dyn_end()
	# curtains
	U.rr_ex(ci, Rect2(sx - 5.0, sy - 6.0, 9.0, sh + 11.0), 3.0, 0.0, 0.0, 3.0, _k(Palette.CORAL, st))
	U.rr_ex(ci, Rect2(sx + sw - 4.0, sy - 6.0, 9.0, sh + 11.0), 0.0, 3.0, 3.0, 0.0, _k(Palette.CORAL, st))
	U.rect(ci, Rect2(sx - 1.0, sy - 6.0, 1.6, sh + 11.0), Color(0, 0, 0, 0.18))
	U.rect(ci, Rect2(sx + sw - 1.0, sy - 6.0, 1.6, sh + 11.0), Color(0, 0, 0, 0.18))
	# projector beam (dynamic flicker)
	U.dyn_begin()
	if not st.get("broken", false):
		var fl := 0.07 + 0.02 * sin(t * 17.0)
		U.poly(ci, PackedVector2Array([Vector2(x0 + w - 12.0, y0 + 16.0), Vector2(sx + sw + 4.0, sy), Vector2(sx + sw + 4.0, sy + sh)]), Color(1, 1, 1, fl * glow))
	U.dyn_end()
	U.rr(ci, Rect2(x0 + w - 19.0, y0 + 11.0, 14.0, 9.0), 2.5, _k(Palette.STEEL, st))
	U.circ(ci, Vector2(x0 + w - 19.0, y0 + 15.5), 3.0, _k(Palette.STEEL_DARK, st))
	U.circ(ci, Vector2(x0 + w - 19.0, y0 + 15.5), 1.4, Color("FFF3C2"))
	# risers + seats (rows rising to the right)
	for r in range(rows - 1, -1, -1):
		var rx := cx + 9.0 + float(r) * 6.0
		var top_y := fy - float(r) * 7.0
		if r > 0:
			U.rr(ci, Rect2(rx, top_y, x0 + w - 3.0 - rx, float(r) * 7.0 + 7.0), 1.0, _k(Color("3F3366"), st))
			U.rect(ci, Rect2(rx, top_y, x0 + w - 3.0 - rx, 1.4), Color(1, 1, 1, 0.15))
			U.rect(ci, Rect2(rx, top_y + 1.4, 1.4, float(r) * 7.0), Color(0, 0, 0, 0.2))
		for col in range(4):
			var sp := Vector2(cx + 14.0 + float(col) * 16.0 + float(r) * 6.0, top_y - 1.0)
			# seat back (to the right of the sitter) + cushion
			U.rr(ci, Rect2(sp.x + 3.5, sp.y - 18.0, 6.0, 18.0), 3.0, _k(Color("D6455D"), st))
			U.rr(ci, Rect2(sp.x + 3.5, sp.y - 18.0, 2.0, 14.0), 1.0, Color(1, 1, 1, 0.2))
			U.rr(ci, Rect2(sp.x - 7.0, sp.y - 3.5, 15.0, 4.4), 2.0, _k(Color("B8344E"), st))


# =================================================================================================
# GYM (120 px)
# =================================================================================================
static func _gym(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var cx := x0 + w * 0.5
	var t: float = st.get("t", 0.0)
	var busy := float(st.get("busy_ratio", 0.0))
	# mirror
	U.rr(ci, Rect2(x0 + 8.0, y0 + 14.0, cx - x0 - 24.0, 28.0), 3.0, _k(Palette.STEEL_DARK, st))
	U.rr(ci, Rect2(x0 + 10.0, y0 + 16.0, cx - x0 - 28.0, 24.0), 2.0, _k(Color("E9F6FF"), st))
	U.poly(ci, PackedVector2Array([Vector2(x0 + 14.0, y0 + 40.0), Vector2(x0 + 26.0, y0 + 16.0), Vector2(x0 + 32.0, y0 + 16.0), Vector2(x0 + 20.0, y0 + 40.0)]), Color(1, 1, 1, 0.7))
	U.poly(ci, PackedVector2Array([Vector2(x0 + 30.0, y0 + 40.0), Vector2(x0 + 39.0, y0 + 16.0), Vector2(x0 + 41.0, y0 + 16.0), Vector2(x0 + 32.0, y0 + 40.0)]), Color(1, 1, 1, 0.5))
	# barbell + weights on wall right
	var bx := cx + 14.0
	var by := y0 + 26.0
	U.line(ci, Vector2(bx, by), Vector2(bx + 38.0, by), _k(Palette.STEEL_DARK, st), 2.0)
	for sx in [bx + 3.0, bx + 35.0]:
		U.rr(ci, Rect2(sx - 2.6, by - 7.0, 5.2, 14.0), 2.0, _k(Palette.CORAL, st))
	for sx2 in [bx + 9.0, bx + 29.0]:
		U.rr(ci, Rect2(sx2 - 2.0, by - 5.0, 4.0, 10.0), 1.5, _k(Palette.TEAL, st))
	# poster
	U.rr(ci, Rect2(cx + 18.0, y0 + 36.0, 20.0, 14.0), 2.0, _k(Palette.SUN, st))
	U.star(ci, Vector2(cx + 28.0, y0 + 43.0), 4.0, _k(Palette.CORAL, st))
	# treadmills
	for i in range(4):
		var tx := x0 + 15.0 + float(i) * 30.0
		# base + belt
		U.rr(ci, Rect2(tx - 13.0, fy - 3.0, 26.0, 3.5), 1.8, _k(Palette.STEEL, st))
		U.rr(ci, Rect2(tx - 12.0, fy - 5.0, 24.0, 3.0), 1.5, _k(Color("3D4660"), st))
		var running := float(i) < busy * float(RoomArt.capacity_for(&"gym", tier)) + 0.5 and busy > 0.0
		var off := fmod(t * (30.0 if running else 0.0), 6.0)
		U.dyn_begin()
		for s in range(5):
			var sx3 := tx - 12.0 - 6.0 + float(s) * 6.0 + off
			if sx3 > tx - 12.0 and sx3 < tx + 10.0:
				U.rect(ci, Rect2(sx3, fy - 4.5, 2.0, 2.0), Color(1, 1, 1, 0.45))
		U.dyn_end()
		# console + handles (front = right)
		U.rr(ci, Rect2(tx + 9.0, fy - 27.0, 2.6, 24.0), 1.2, _k(Palette.STEEL, st))
		U.rr(ci, Rect2(tx + 4.0, fy - 31.0, 11.0, 6.5), 2.5, _k(Palette.NAVY, st))
		var lit := 0.6 + 0.4 * sin(t * 4.0 + float(i)) if running else 0.2
		U.dyn_begin()
		U.rect(ci, Rect2(tx + 6.0, fy - 28.6, 7.0 * lit, 1.8), _k(Palette.MINT, st))
		U.dyn_end()
		U.line(ci, Vector2(tx + 10.0, fy - 22.0), Vector2(tx + 3.0, fy - 19.0), _k(Palette.CORAL, st), 1.8)


# =================================================================================================
# ARCADE (120 px)
# =================================================================================================
static func _arcade(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var t: float = st.get("t", 0.0)
	var busy := float(st.get("busy_ratio", 0.0))
	# neon strips on the wall
	var pulse := 0.65 + 0.35 * sin(t * 2.0)
	U.dyn_begin()
	U.rr(ci, Rect2(x0 + 6.0, y0 + 9.0, w - 12.0, 2.6), 1.3, Color(1.0, 0.35, 0.7, 0.9 * pulse))
	U.rr(ci, Rect2(x0 + 6.0, y0 + 9.0, w - 12.0, 2.6), 1.3, Color(1, 1, 1, 0.2))
	U.rr(ci, Rect2(x0 + 10.0, y0 + 14.0, w - 20.0, 1.8), 0.9, Color(0.3, 0.9, 1.0, 0.7 * (1.2 - pulse)))
	U.dyn_end()
	# star carpet dots on floor
	for i in range(int(w / 10.0)):
		U.circ(ci, Vector2(x0 + 6.0 + float(i) * 10.0, fy + 3.0 + float(i % 2) * 3.0), 1.0, Color(1, 1, 1, 0.22))
	var cols: Array[Color] = [Palette.CORAL, Palette.TEAL, Palette.SUN_DEEP, Palette.LILAC]
	var occ := _occ(st, &"arcade", tier)
	for i in range(4):
		var cxp := x0 + 15.0 + float(i) * 30.0
		var c := _k(cols[i], st)
		# body
		U.rr_ex(ci, Rect2(cxp - 12.0, fy - 40.0, 24.0, 40.0), 5.0, 5.0, 0.0, 0.0, Palette.shade(c, 0.35))
		U.rr_ex(ci, Rect2(cxp - 11.0, fy - 40.0, 22.0, 40.0), 5.0, 5.0, 0.0, 0.0, c)
		U.rect(ci, Rect2(cxp - 11.0, fy - 40.0, 3.0, 40.0), Color(1, 1, 1, 0.14))
		# marquee
		var blink := 0.6 + 0.4 * sin(t * 5.0 + float(i) * 1.3)
		U.rr(ci, Rect2(cxp - 9.0, fy - 38.0, 18.0, 5.5), 2.0, Color(1.0, 0.95, 0.6, 0.6) if not st.get("broken", false) else Color(0.3, 0.3, 0.4))
		U.dyn_begin()
		U.rr(ci, Rect2(cxp - 9.0, fy - 38.0, 18.0, 5.5), 2.0, Color(1.0, 1.0, 0.85, 0.5 * blink if not st.get("broken", false) else 0.0))
		U.dyn_end()
		# screen
		U.rr(ci, Rect2(cxp - 8.5, fy - 31.0, 17.0, 13.0), 2.5, Color("141026"))
		U.dyn_begin()
		if not st.get("broken", false):
			var seed := int(t * 3.0) + i * 7
			for k in range(5):
				var px := cxp - 6.5 + U.hash01(seed * 5 + k * 13) * 12.0
				var py := fy - 29.0 + U.hash01(seed * 3 + k * 29) * 9.0
				var pc: Color = [Palette.MINT, Palette.SUN, Palette.CORAL_LIGHT, Palette.TEAL_LIGHT, Color.WHITE][k]
				U.rect(ci, Rect2(px, py, 2.4, 2.4), pc)
			if float(i) < busy * 4.0 + 0.5 and busy > 0.0:
				U.rect(ci, Rect2(cxp - 8.0, fy - 30.5, 16.0, 12.0), Color(1, 1, 1, 0.06 + 0.04 * sin(t * 12.0)))
		U.dyn_end()
		# control panel
		U.poly(ci, PackedVector2Array([Vector2(cxp - 11.0, fy - 17.0), Vector2(cxp + 11.0, fy - 17.0), Vector2(cxp + 12.0, fy - 12.0), Vector2(cxp - 12.0, fy - 12.0)]), Palette.shade(c, 0.5))
		U.line(ci, Vector2(cxp - 4.0, fy - 15.0), Vector2(cxp - 4.0, fy - 20.0), Color("2B2347"), 1.6)
		U.circ(ci, Vector2(cxp - 4.0, fy - 21.0), 2.4, Palette.CORAL_LIGHT if i % 2 == 0 else Palette.SUN)
		U.circ(ci, Vector2(cxp + 4.0, fy - 14.6), 1.5, Palette.SUN)
		U.circ(ci, Vector2(cxp + 8.0, fy - 14.6), 1.5, Palette.MINT)
		# coin door
		U.rr(ci, Rect2(cxp - 4.0, fy - 8.0, 8.0, 6.0), 1.5, Color(0, 0, 0, 0.25))
		U.rect(ci, Rect2(cxp - 0.5, fy - 7.0, 1.0, 3.0), Palette.GOLD)


# =================================================================================================
# RESTAURANT (160 px)
# =================================================================================================
static func _restaurant(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary, front: bool) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var t: float = st.get("t", 0.0)
	var cloth := _k(Color("FFFDF6"), st)
	var accent := _k(Palette.CORAL_DARK, st)
	var occ := _occ(st, &"restaurant", tier)
	if front:
		for tb in range(2):
			var tx := (x0 + 36.0) if tb == 0 else (x0 + w - 36.0)
			# tablecloth
			U.rr(ci, Rect2(tx - 13.0, fy - 12.0, 26.0, 3.2), 1.6, cloth)
			U.rr_ex(ci, Rect2(tx - 12.0, fy - 9.5, 24.0, 8.5), 1.0, 1.0, 5.0, 5.0, cloth)
			for i in range(5):
				U.circ(ci, Vector2(tx - 9.6 + float(i) * 4.8, fy - 1.2), 2.4, accent)
			U.rect(ci, Rect2(tx - 12.0, fy - 6.0, 24.0, 1.3), Color(accent.r, accent.g, accent.b, 0.35))
			# plates
			U.ellipse(ci, Vector2(tx - 7.0, fy - 12.4), 4.0, 1.2, Color("EAF1F5"))
			U.ellipse(ci, Vector2(tx + 7.0, fy - 12.4), 4.0, 1.2, Color("EAF1F5"))
			U.dyn_begin()
			if tb * 2 < occ:
				U.ellipse(ci, Vector2(tx - 7.0, fy - 13.2), 2.5, 0.9, Palette.CORAL_LIGHT)
			if tb * 2 + 1 < occ:
				U.ellipse(ci, Vector2(tx + 7.0, fy - 13.2), 2.5, 0.9, Palette.SUN)
			U.dyn_end()
			# candle
			U.rr(ci, Rect2(tx - 1.2, fy - 18.0, 2.4, 6.0), 1.0, Color("FFF3D6"))
			U.dyn_begin()
			if not st.get("broken", false):
				var fl := 1.0 + 0.25 * sin(t * 9.0 + float(tb) * 2.0)
				U.circ(ci, Vector2(tx, fy - 22.5), 6.0, Color(1.0, 0.8, 0.4, 0.2))
				U.ellipse(ci, Vector2(tx, fy - 20.4), 1.3, 2.2 * fl, Color("FFC857"))
				U.ellipse(ci, Vector2(tx, fy - 20.0), 0.7, 1.2 * fl, Color("FFF3C2"))
			U.dyn_end()
		return
	# wallpaper stripes
	for i in range(int(w / 12.0)):
		if i % 2 == 0:
			U.rect(ci, Rect2(x0 + float(i) * 12.0, y0 + 7.0, 6.0, 47.0), Color(1, 1, 1, 0.22))
	# picture frames + window
	U.rr(ci, Rect2(x0 + 8.0, y0 + 16.0, 24.0, 18.0), 3.0, _k(Palette.WOOD_DARK, st))
	U.vgrad(ci, Rect2(x0 + 10.0, y0 + 18.0, 20.0, 14.0), _k(Palette.SKY_BLUE, st), _k(Color("FFE2B8"), st))
	U.poly(ci, PackedVector2Array([Vector2(x0 + 10.0, y0 + 32.0), Vector2(x0 + 17.0, y0 + 24.0), Vector2(x0 + 22.0, y0 + 29.0), Vector2(x0 + 26.0, y0 + 25.0), Vector2(x0 + 30.0, y0 + 32.0)]), _k(Palette.MINT_DARK, st))
	U.rr(ci, Rect2(x0 + w - 32.0, y0 + 16.0, 24.0, 18.0), 3.0, _k(Palette.WOOD_DARK, st))
	U.rr(ci, Rect2(x0 + w - 30.0, y0 + 18.0, 20.0, 14.0), 2.0, _k(Color("FFF3D6"), st))
	U.circ(ci, Vector2(x0 + w - 20.0, y0 + 25.0), 4.5, _k(Palette.CORAL, st))
	U.circ(ci, Vector2(x0 + w - 20.0, y0 + 25.0), 2.0, _k(Palette.SUN, st))
	# chandeliers (warm glow)
	for cxp in [x0 + w * 0.3, x0 + w * 0.7]:
		U.line(ci, Vector2(cxp, y0 + 5.0), Vector2(cxp, y0 + 13.0), Palette.STEEL_DARK, 1.2)
		if not st.get("broken", false):
			U.circ(ci, Vector2(cxp, y0 + 20.0), 13.0, Color(1.0, 0.85, 0.5, 0.13))
		U.rr_ex(ci, Rect2(cxp - 7.0, y0 + 13.0, 14.0, 6.0), 6.0, 6.0, 1.0, 1.0, _k(Palette.GOLD, st))
		U.circ(ci, Vector2(cxp, y0 + 20.0), 1.6, Color("FFF3C2"))
	# tables (pedestal) + chairs
	for tb in range(2):
		var tx := (x0 + 36.0) if tb == 0 else (x0 + w - 36.0)
		U.rect(ci, Rect2(tx - 1.6, fy - 4.0, 3.2, 4.0), _k(Palette.WOOD_DARK, st))
		U.ellipse(ci, Vector2(tx, fy - 0.5), 8.0, 1.8, _k(Palette.WOOD_DARK, st))
		for side in range(2):
			var dir := -1.0 if side == 0 else 1.0
			var cxx := tx + dir * 19.0
			var ch := _k(Palette.WOOD, st)
			U.rr(ci, Rect2(cxx + dir * 8.0 - 1.8, fy - 20.0, 3.6, 20.0), 1.5, ch)
			U.rr(ci, Rect2(cxx + dir * 8.0 - 2.6, fy - 21.0, 5.2, 8.0), 2.0, _k(Color("D6455D"), st))
			U.rr(ci, Rect2(cxx - 8.0, fy - 6.0, 16.0, 2.6), 1.2, _k(Color("B8344E"), st))
			U.rect(ci, Rect2(cxx - 7.0, fy - 3.6, 1.8, 3.6), ch)
			U.rect(ci, Rect2(cxx + 5.2, fy - 3.6, 1.8, 3.6), ch)
	if tier >= 2:
		var vx := x0 + w * 0.5
		U.rr_ex(ci, Rect2(vx - 3.0, fy - 9.0, 6.0, 9.0), 1.0, 1.0, 3.0, 3.0, _k(Palette.TEAL_LIGHT, st))
		U.circ(ci, Vector2(vx - 1.6, fy - 11.0), 2.4, _k(Palette.CORAL, st))
		U.circ(ci, Vector2(vx + 1.8, fy - 11.6), 2.2, _k(Palette.SUN, st))


# =================================================================================================
# MEDBAY (80 px)
# =================================================================================================
static func _medbay(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var cx := x0 + w * 0.5
	var t: float = st.get("t", 0.0)
	var occ := _occ(st, &"medbay", tier)
	var white := _k(Color("FFFFFF"), st)
	# wall cross
	U.rr(ci, Rect2(x0 + 4.0, y0 + 14.0, 14.0, 14.0), 3.0, white)
	U.rr(ci, Rect2(x0 + 9.0, y0 + 16.0, 4.0, 10.0), 1.0, _k(Palette.CORAL, st))
	U.rr(ci, Rect2(x0 + 6.0, y0 + 19.0, 10.0, 4.0), 1.0, _k(Palette.CORAL, st))
	# monitor on the right wall with pulse line
	var mx := x0 + w - 22.0
	U.rr(ci, Rect2(mx, y0 + 14.0, 18.0, 13.0), 3.0, _k(Palette.NAVY, st))
	U.rr(ci, Rect2(mx + 1.6, y0 + 15.6, 14.8, 9.8), 2.0, Color("0F2A22"))
	U.dyn_begin()
	if not st.get("broken", false):
		var pts := PackedVector2Array()
		var sweep := fmod(t * 0.9, 1.0)
		for i in range(13):
			var f := float(i) / 12.0
			var yy := y0 + 20.5
			var ph := fmod(f * 2.0 + 1.0 - sweep * 2.0, 1.0)
			if ph > 0.40 and ph < 0.46:
				yy -= 4.0
			elif ph >= 0.46 and ph < 0.52:
				yy += 3.0
			pts.append(Vector2(mx + 2.4 + f * 13.0, yy))
		U.pline(ci, pts, Palette.MINT, 1.3)
	U.dyn_end()
	# beds
	for k in range(2):
		var bx := (x0 + 3.0) if k == 0 else (x0 + w - 31.0)
		var surf := fy - 9.0
		# headboard at outer side
		var hb := bx - 0.5 if k == 0 else bx + 28.0 - 2.0
		U.rr(ci, Rect2(hb, surf - 14.0, 3.0, 22.0), 1.5, _k(Palette.STEEL, st))
		U.rr(ci, Rect2(bx + 1.0, surf + 4.0, 26.0, 2.2), 1.0, _k(Palette.STEEL, st))
		U.rect(ci, Rect2(bx + 3.0, surf + 6.0, 1.8, 4.0), _k(Palette.STEEL_DARK, st))
		U.rect(ci, Rect2(bx + 22.0, surf + 6.0, 1.8, 4.0), _k(Palette.STEEL_DARK, st))
		U.rr(ci, Rect2(bx, surf, 28.0, 5.0), 2.5, white)
		var pw := bx + 2.0 if k == 0 else bx + 28.0 - 10.5
		U.rr(ci, Rect2(pw, surf - 3.0, 8.5, 4.0), 2.5, white)
		if k >= occ:
			U.dyn_begin()
			U.rr(ci, Rect2(bx + 10.0, surf - 3.0, 17.0, 4.2), 2.0, _k(Palette.TEAL_LIGHT, st))
			U.rect(ci, Rect2(bx + 10.0, surf - 3.0, 17.0, 1.2), Color(1, 1, 1, 0.5))
			U.dyn_end()
		# IV stand
		var ix := bx + 31.0 if k == 0 else bx - 3.0
		if k == 0 and ix > cx - 12.0:
			ix = bx + 28.5
		U.line(ci, Vector2(ix, surf + 8.0), Vector2(ix, surf - 28.0), _k(Palette.STEEL, st), 1.4)
		U.rr_ex(ci, Rect2(ix - 3.0, surf - 28.0, 6.0, 9.0), 3.0, 3.0, 2.0, 2.0, Color(0.7, 0.9, 1.0, 0.85))
		U.rect(ci, Rect2(ix - 2.2, surf - 23.0, 4.4, 3.5), _k(Palette.TEAL, st))
	if tier >= 2:
		U.rr(ci, Rect2(cx + 4.0, fy - 38.0, 10.0, 10.0), 2.0, white)
		U.rr(ci, Rect2(cx + 7.4, fy - 36.0, 3.2, 6.0), 1.0, _k(Palette.CORAL, st))
		U.rr(ci, Rect2(cx + 5.6, fy - 34.0, 6.8, 3.2), 1.0, _k(Palette.CORAL, st))


# =================================================================================================
# SAUNA (80 px)
# =================================================================================================
static func _sauna(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary, front: bool) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var t: float = st.get("t", 0.0)
	var broken: bool = st.get("broken", false)
	if front:
		# steam puffs from the stove, drifting right over the benches
		if broken:
			return
		U.dyn_begin()
		for i in range(5):
			var k := fmod(t * 0.28 + float(i) * 0.2, 1.0)
			var p := Vector2(x0 + 14.0 + k * 34.0 + sin(k * 7.0 + float(i)) * 3.0, fy - 18.0 - k * 34.0)
			U.circ(ci, p, 4.0 + k * 9.0, Color(1, 1, 1, 0.28 * (1.0 - k)))
		U.dyn_end()
		return
	# planks
	for i in range(int(w / 8.0) + 1):
		U.rect(ci, Rect2(x0 + float(i) * 8.0, y0 + 5.0, 1.0, fy - y0 - 5.0), Color(0.35, 0.2, 0.1, 0.16))
	for i in range(0, int(w / 16.0)):
		U.rect(ci, Rect2(x0 + 4.0 + float(i) * 16.0, y0 + 5.0, 6.0, fy - y0 - 5.0), Color(1, 1, 1, 0.05))
	# stove
	U.rr(ci, Rect2(x0 + 4.0, fy - 17.0, 22.0, 17.0), 3.0, _k(Color("4A4F63"), st))
	U.rr(ci, Rect2(x0 + 4.0, fy - 17.0, 22.0, 4.0), 2.0, _k(Color("6A7088"), st))
	for i in range(5):
		var rc := Vector2(x0 + 8.0 + float(i) * 3.6, fy - 20.0 + float(i % 2))
		U.circ(ci, rc, 3.4, _k(Color("7A8099"), st))
		if not broken:
			U.dyn_begin()
			U.circ(ci, rc + Vector2(0, 0.6), 1.6, Color(1.0, 0.55, 0.2, 0.55 + 0.25 * sin(t * 3.0 + float(i))))
			U.dyn_end()
	U.rect(ci, Rect2(x0 + 14.0, fy - 17.0, 3.0, 15.0), Color(0, 0, 0, 0.15))
	if not broken:
		U.dyn_begin()
		U.circ(ci, Vector2(x0 + 15.0, fy - 8.0), 2.0, Color(1.0, 0.6, 0.2, 0.7 + 0.2 * sin(t * 6.0)))
		U.dyn_end()
	# bucket + ladle
	U.rr_ex(ci, Rect2(x0 + 29.0, fy - 8.0, 8.0, 8.0), 0.0, 0.0, 2.0, 2.0, _k(Palette.WOOD_LIGHT, st))
	U.rect(ci, Rect2(x0 + 29.0, fy - 6.0, 8.0, 1.2), _k(Palette.WOOD_DARK, st))
	U.line(ci, Vector2(x0 + 36.0, fy - 6.0), Vector2(x0 + 40.0, fy - 18.0), _k(Palette.WOOD_DARK, st), 1.2)
	# benches
	U.rr(ci, Rect2(x0 + 44.0, fy - 24.0, w - 46.0, 3.6), 1.6, _k(Palette.WOOD_LIGHT, st))
	U.rect(ci, Rect2(x0 + 44.0, fy - 21.0, w - 46.0, 1.2), _k(Palette.WOOD_DARK, st))
	U.rect(ci, Rect2(x0 + w - 5.0, fy - 21.0, 2.0, 21.0), _k(Palette.WOOD_DARK, st))
	U.rr(ci, Rect2(x0 + 40.0, fy - 12.0, w - 42.0, 3.6), 1.6, _k(Palette.WOOD_LIGHT, st))
	U.rect(ci, Rect2(x0 + 40.0, fy - 9.0, w - 42.0, 1.2), _k(Palette.WOOD_DARK, st))
	U.rect(ci, Rect2(x0 + 44.0, fy - 9.0, 2.0, 9.0), _k(Palette.WOOD_DARK, st))
	U.rect(ci, Rect2(x0 + w - 5.0, fy - 9.0, 2.0, 9.0), _k(Palette.WOOD_DARK, st))
	# back rest slats
	for i in range(3):
		U.rr(ci, Rect2(x0 + 46.0, fy - 38.0 + float(i) * 5.0, w - 50.0, 2.6), 1.0, _k(Palette.WOOD, st))
	# thermometer
	U.rr(ci, Rect2(x0 + w - 10.0, y0 + 14.0, 4.0, 22.0), 2.0, Color("FFF8EC"))
	U.rect(ci, Rect2(x0 + w - 8.8, y0 + 18.0 - 0.0, 1.6, 17.0), _k(Palette.CORAL, st))
	U.circ(ci, Vector2(x0 + w - 8.0, y0 + 36.0), 3.2, _k(Palette.CORAL, st))


# =================================================================================================
# ICE RINK (200 px)
# =================================================================================================
static func _ice_rink(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary, front: bool) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var t: float = st.get("t", 0.0)
	var broken: bool = st.get("broken", false)
	if front:
		# gloss + sparkles over the skaters' feet
		U.rr(ci, Rect2(x0 + 6.0, fy - 2.0, w - 12.0, 12.0), 6.0, Color(0.85, 0.97, 1.0, 0.16))
		if not broken:
			U.dyn_begin()
			for i in range(9):
				var k := fmod(t * 0.7 + float(i) * 0.37, 1.0)
				var sxp := x0 + 14.0 + U.hash01(i * 17 + 3) * (w - 28.0)
				var syp := fy + 1.0 + U.hash01(i * 31 + 7) * 8.0
				var a := sin(k * PI)
				U.star(ci, Vector2(sxp, syp), 1.0 + 2.0 * a, Color(1, 1, 1, a * 0.9), t, 0.35)
			U.dyn_end()
		return
	# pennants
	var n := int(w / 12.0)
	U.pline(ci, PackedVector2Array([Vector2(x0 + 2.0, y0 + 8.0), Vector2(x0 + w * 0.5, y0 + 17.0), Vector2(x0 + w - 2.0, y0 + 8.0)]), Color(0.3, 0.4, 0.6, 0.7), 1.0)
	for i in range(1, n):
		var f := float(i) / float(n)
		var px := lerpf(x0 + 2.0, x0 + w - 2.0, f)
		var py := y0 + 8.0 + 9.0 * (1.0 - pow(2.0 * f - 1.0, 2.0))
		var c: Color = [Palette.CORAL, Palette.TEAL, Palette.SUN, Palette.MINT][i % 4]
		U.poly(ci, PackedVector2Array([Vector2(px - 3.5, py), Vector2(px + 3.5, py), Vector2(px, py + 8.0)]), _k(c, st))
	# back boards
	U.rr(ci, Rect2(x0 + 3.0, fy - 16.0, w - 6.0, 12.0), 3.0, _k(Color("F4FBFF"), st))
	var bn := int((w - 8.0) / 20.0)
	for i in range(bn):
		var c: Color = [Palette.CORAL, Palette.TEAL][i % 2]
		U.rr(ci, Rect2(x0 + 6.0 + float(i) * 20.0, fy - 13.5, 16.0, 5.5), 2.0, _k(c, st))
	# ice sheet over the floor band
	U.vgrad(ci, Rect2(x0 + 3.0, fy - 4.0, w - 6.0, 15.0), _k(Color("F2FCFF"), st), _k(Color("BEE5F7"), st))
	U.rect(ci, Rect2(x0 + 3.0, fy - 4.0, w - 6.0, 1.2), Color(1, 1, 1, 0.8))
	# skate marks
	for i in range(5):
		var sx := x0 + 14.0 + float(i) * (w - 28.0) / 4.0
		U.pline(ci, PackedVector2Array([Vector2(sx - 16.0, fy + 8.0), Vector2(sx, fy + 4.0 + float(i % 2) * 2.0), Vector2(sx + 18.0, fy + 9.0)]), Color(0.45, 0.65, 0.85, 0.28), 1.0)
	if tier >= 2:
		U.circ(ci, Vector2(x0 + w * 0.5, fy + 5.0), 6.0, Color(0.9, 0.3, 0.35, 0.18))


# =================================================================================================
# CASINO (160 px)
# =================================================================================================
static func _casino(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var cx := x0 + w * 0.5
	var t: float = st.get("t", 0.0)
	var broken: bool = st.get("broken", false)
	# ghostly purple glow
	if not broken:
		U.dyn_begin()
		U.ellipse(ci, Vector2(cx + 30.0, y0 + 30.0), 60.0, 24.0, Color(0.7, 0.45, 1.0, 0.1 + 0.03 * sin(t * 1.5)))
		U.ellipse(ci, Vector2(x0 + 36.0, y0 + 36.0), 40.0, 18.0, Color(0.5, 0.9, 0.7, 0.07))
		U.dyn_end()
	# gold trim arches on wall
	for i in range(int(w / 26.0)):
		var ax := x0 + 4.0 + float(i) * 26.0
		U.arc(ci, Vector2(ax + 13.0, y0 + 24.0), 11.0, PI, TAU, _k(Palette.GOLD, st), 2.0, 12)
		U.line(ci, Vector2(ax + 2.0, y0 + 24.0), Vector2(ax + 2.0, y0 + 40.0), Color(Palette.GOLD.r, Palette.GOLD.g, Palette.GOLD.b, 0.5), 1.4)
	# slot machines
	for i in range(2):
		var mx := x0 + 8.0 + float(i) * 20.0
		var c := _k(Palette.CORAL if i == 0 else Palette.LILAC_DARK, st)
		U.rr_ex(ci, Rect2(mx, fy - 38.0, 18.0, 38.0), 4.0, 4.0, 0.0, 0.0, Palette.shade(c, 0.4))
		U.rr_ex(ci, Rect2(mx + 1.0, fy - 38.0, 16.0, 38.0), 4.0, 4.0, 0.0, 0.0, c)
		U.rect(ci, Rect2(mx + 1.0, fy - 38.0, 3.0, 38.0), Color(1, 1, 1, 0.14))
		# bulbs
		for b in range(3):
			var on := (int(t * 4.0) + b + i) % 3 == 0 and not broken
			U.circ(ci, Vector2(mx + 4.5 + float(b) * 4.5, fy - 34.0), 1.6, _k(Palette.SUN_DEEP, st))
			if on:
				U.dyn_begin()
				U.circ(ci, Vector2(mx + 4.5 + float(b) * 4.5, fy - 34.0), 1.6, Palette.SUN)
				U.dyn_end()
		# reels
		U.rr(ci, Rect2(mx + 2.5, fy - 29.0, 13.0, 10.0), 2.0, _k(Color("FFF8EC"), st))
		for r in range(3):
			var sym := int(t * 2.0 + float(r) * 1.7 + float(i) * 3.0) % 4
			var sc: Color = [Palette.CORAL, Palette.SUN_DEEP, Palette.MINT_DARK, Palette.TEAL][sym]
			if not broken:
				U.dyn_begin()
				U.circ(ci, Vector2(mx + 5.5 + float(r) * 3.8, fy - 24.0), 1.5, sc)
				U.dyn_end()
		U.rr(ci, Rect2(mx + 3.0, fy - 14.0, 12.0, 4.0), 1.5, Color(0, 0, 0, 0.3))
		U.rect(ci, Rect2(mx + 8.0, fy - 14.0, 2.0, 4.0), Palette.GOLD)
		# lever
		U.line(ci, Vector2(mx + 18.5, fy - 22.0), Vector2(mx + 21.0, fy - 31.0), _k(Palette.STEEL, st), 1.4)
		U.circ(ci, Vector2(mx + 21.0, fy - 31.5), 2.0, _k(Palette.CORAL_LIGHT, st))
	# roulette table
	var tx := x0 + w - 70.0
	U.rr(ci, Rect2(tx, fy - 14.0, 62.0, 14.0), 3.0, _k(Color("5B3A8C"), st))
	U.rect(ci, Rect2(tx, fy - 14.0, 62.0, 1.6), _k(Palette.GOLD, st))
	U.rect(ci, Rect2(tx, fy - 3.0, 62.0, 1.4), _k(Palette.GOLD, st))
	U.rr(ci, Rect2(tx - 2.0, fy - 19.0, 66.0, 6.0), 3.0, _k(Color("3C9D6B"), st))
	U.rr(ci, Rect2(tx - 2.0, fy - 19.0, 66.0, 2.0), 2.0, Color(1, 1, 1, 0.16))
	# wheel
	var wc := Vector2(tx + 20.0, fy - 20.5)
	U.ellipse(ci, wc, 13.0, 4.2, _k(Palette.WOOD_DARK, st))
	U.ellipse(ci, wc, 10.6, 3.2, _k(Palette.CORAL, st))
	U.ellipse(ci, wc, 3.4, 1.2, _k(Palette.GOLD, st))
	U.dyn_begin()
	for i in range(8):
		var a := float(i) * TAU / 8.0 + t * (0.8 if not broken else 0.0)
		var p1 := wc + Vector2(cos(a) * 9.5, sin(a) * 2.8)
		U.line(ci, wc + Vector2(cos(a) * 4.0, sin(a) * 1.2), p1, Palette.INK if i % 2 == 0 else Color("FFF8EC"), 1.6)
	U.circ(ci, wc + Vector2(cos(t * 3.0) * 8.0, sin(t * 3.0) * 2.4), 0.9, Color.WHITE)
	U.dyn_end()
	# chips + cards
	for i in range(3):
		U.rr(ci, Rect2(tx + 42.0 + float(i) * 5.0, fy - 24.0 - float(i % 2) * 2.0, 4.0, 5.0), 1.0, _k([Palette.CORAL, Palette.SUN, Palette.TEAL][i], st))
	U.rr(ci, Rect2(tx + 36.0, fy - 21.0, 6.0, 2.0), 0.8, Color("FFF8EC"))
	# lamp over table
	U.line(ci, Vector2(tx + 32.0, y0 + 5.0), Vector2(tx + 32.0, y0 + 20.0), Palette.STEEL_DARK, 1.0)
	U.rr_ex(ci, Rect2(tx + 22.0, y0 + 20.0, 20.0, 8.0), 8.0, 8.0, 1.0, 1.0, _k(Palette.GOLD, st))
	if not broken:
		U.poly(ci, PackedVector2Array([Vector2(tx + 24.0, y0 + 28.0), Vector2(tx + 40.0, y0 + 28.0), Vector2(tx + 52.0, fy - 18.0), Vector2(tx + 12.0, fy - 18.0)]), Color(1.0, 0.95, 0.7, 0.1))


# =================================================================================================
# GENERATOR / WATER TANK (40 px)
# =================================================================================================
static func _generator(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var cx := x0 + w * 0.5
	var t: float = st.get("t", 0.0)
	var broken: bool = st.get("broken", false)
	var spin := 0.0 if broken else t * (9.0 + 8.0 * float(st.get("busy_ratio", 0.0)))
	# body
	U.rr(ci, Rect2(x0 + 3.0, fy - 38.0, w - 6.0, 38.0), 6.0, _k(Palette.shade(Palette.ORANGE, 0.3), st))
	U.rr(ci, Rect2(x0 + 3.0, fy - 38.0, w - 6.0, 36.0), 6.0, _k(Palette.ORANGE, st))
	U.rr(ci, Rect2(x0 + 5.0, fy - 36.0, 5.0, 28.0), 2.5, Color(1, 1, 1, 0.2))
	# fan housing + blades
	var fc := Vector2(cx, fy - 23.0)
	U.circ(ci, fc, 12.0, _k(Palette.NAVY_DARK, st))
	U.circ(ci, fc, 10.5, _k(Color("2A3350"), st))
	U.dyn_begin()
	for i in range(4):
		var a := spin + float(i) * PI * 0.5
		U.poly(ci, PackedVector2Array([fc, fc + Vector2(cos(a - 0.35), sin(a - 0.35)) * 10.0, fc + Vector2(cos(a + 0.35), sin(a + 0.35)) * 10.0]), _k(Palette.STEEL, st))
	U.dyn_end()
	U.circ(ci, fc, 2.4, _k(Palette.SUN, st))
	U.ring(ci, fc, 11.2, _k(Palette.STEEL_DARK, st), 1.6)
	# panel
	U.rr(ci, Rect2(x0 + 8.0, fy - 8.0, w - 16.0, 6.0), 2.0, _k(Palette.NAVY_DARK, st))
	var blink := not broken and sin(t * 6.0) > 0.0
	U.circ(ci, Vector2(x0 + 12.0, fy - 5.0), 1.4, Palette.MINT if not broken else Palette.CORAL)
	U.dyn_begin()
	U.circ(ci, Vector2(x0 + 17.0, fy - 5.0), 1.4, Palette.SUN if blink else _k(Palette.SUN_DEEP, st))
	U.dyn_end()
	U.circ(ci, Vector2(x0 + 22.0, fy - 5.0), 1.4, Palette.CORAL_LIGHT)
	# exhaust
	U.rr(ci, Rect2(x0 + w - 11.0, y0 + 30.0, 5.0, 8.0), 1.5, _k(Palette.STEEL_DARK, st))
	if not broken:
		U.dyn_begin()
		for i in range(3):
			var k := fmod(t * 0.7 + float(i) / 3.0, 1.0)
			U.circ(ci, Vector2(x0 + w - 8.5 + sin(k * 6.0) * 2.0, y0 + 28.0 - k * 10.0), 2.0 + k * 3.0, Color(0.85, 0.88, 0.95, 0.5 * (1.0 - k)))
		U.dyn_end()


static func _water_tank(ci: CanvasItem, R: Rect2, tier: int, st: Dictionary) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var cx := x0 + w * 0.5
	var t: float = st.get("t", 0.0)
	var broken: bool = st.get("broken", false)
	var tank_c := _k(Palette.TEAL, st)
	# tank
	U.rr(ci, Rect2(x0 + 5.0, fy - 44.0, w - 10.0, 42.0), 9.0, Palette.shade(tank_c, 0.35))
	U.rr(ci, Rect2(x0 + 5.0, fy - 44.0, w - 10.0, 40.0), 9.0, tank_c)
	U.rr(ci, Rect2(x0 + 8.0, fy - 41.0, 4.5, 33.0), 2.2, Color(1, 1, 1, 0.28))
	for i in range(2):
		U.rect(ci, Rect2(x0 + 5.0, fy - 34.0 + float(i) * 14.0, w - 10.0, 2.0), Palette.shade(tank_c, 0.3))
	for i in range(3):
		U.circ(ci, Vector2(x0 + 9.0 + float(i) * 11.0, fy - 34.0), 0.9, Color(1, 1, 1, 0.5))
	# gauge window
	U.rr(ci, Rect2(cx - 3.0, fy - 38.0, 12.0, 28.0), 4.0, Color("FFF8EC"))
	var lvl := 0.55 + 0.1 * sin(t * 1.2) if not broken else 0.15
	var gh := 24.0
	U.dyn_begin()
	U.rr(ci, Rect2(cx - 1.4, fy - 36.0 + gh * (1.0 - lvl), 9.0, gh * lvl), 3.0, _k(Color("3AA0F0"), st))
	U.rect(ci, Rect2(cx - 1.4, fy - 36.0 + gh * (1.0 - lvl), 9.0, 1.2), Color(1, 1, 1, 0.7))
	U.dyn_end()
	# pipes + valve
	U.rr(ci, Rect2(x0 + 2.0, fy - 8.0, w - 4.0, 4.5), 2.0, _k(Palette.STEEL, st))
	U.circ(ci, Vector2(x0 + 11.0, fy - 5.7), 4.0, _k(Palette.CORAL, st))
	U.line(ci, Vector2(x0 + 8.0, fy - 5.7), Vector2(x0 + 14.0, fy - 5.7), Palette.CORAL_DARK, 1.2)
	U.line(ci, Vector2(x0 + 11.0, fy - 8.7), Vector2(x0 + 11.0, fy - 2.7), Palette.CORAL_DARK, 1.2)
	# drip (dynamic)
	U.dyn_begin()
	if not broken:
		var k := fmod(t * 0.9, 1.0)
		U.circ(ci, Vector2(x0 + w - 8.0, fy - 3.0 + k * 6.0), 1.3 * (1.0 - k * 0.4), Color(0.5, 0.8, 1.0, 1.0 - k))
	else:
		for i in range(3):
			var k2 := fmod(t * 1.4 + float(i) * 0.33, 1.0)
			U.circ(ci, Vector2(x0 + 14.0 + float(i) * 8.0, fy - 6.0 + k2 * 8.0), 1.3, Color(0.5, 0.8, 1.0, 1.0 - k2))
	U.dyn_end()
