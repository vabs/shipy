class_name MapArt
extends RefCounted
## Drawing library for the voyage map: the chart-style sea, the three destination islands (sunny Mediterranean,
## icy Arctic with aurora, spooky Underworld with lanterns), a tiny cruise-ship marker and a compass rose.
## Everything is drawn in code through ArtUtil. Islands are drawn in a local space centred on the lagoon
## (roughly +-190 px wide, 150 px tall above the centre).
##
##   MapArt.draw_sea(ci, rect, t)
##   MapArt.draw_island(ci, dest, center, scale, t, fogged := false)
##   MapArt.draw_backdrop(ci, dest, center, scale, t)      # aurora / haze drawn BEHIND the island
##   MapArt.draw_ship(ci, pos, facing, t, scale := 1.0)
##   MapArt.draw_compass(ci, center, r, t)

const U := preload("res://src/render/art/art_util.gd")


# ---- helpers --------------------------------------------------------------------------------------
static func _tr(pts: PackedVector2Array, off: Vector2, sx: float = 1.0, sy: float = 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.x * sx, p.y * sy) + off)
	return out


static func _dome(w: float, h: float, n: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var a: float = PI - PI * float(i) / float(n)
		pts.append(Vector2(cos(a) * w * 0.5, -sin(a) * h))
	return pts


static func _shade(c: Color, f: float) -> Color:
	return Palette.shade(c, f)


static func _lagoon(ci: CanvasItem, shallow: Color, foam: Color, t: float, rx: float, ry: float) -> void:
	var pulse: float = 1.0 + 0.012 * sin(t * 1.4)
	U.ellipse(ci, Vector2(0, 8), rx * pulse + 16.0, ry * pulse + 10.0, Color(foam.r, foam.g, foam.b, 0.34))
	U.ellipse(ci, Vector2(0, 6), rx * pulse + 6.0, ry * pulse + 4.0, Color(foam.r, foam.g, foam.b, 0.8))
	U.ellipse(ci, Vector2(0, 6), rx * pulse, ry * pulse, shallow)
	U.ellipse(ci, Vector2(0, 2), rx * 0.78 * pulse, ry * 0.72 * pulse, Color(1, 1, 1, 0.14))


static func _sparkle(ci: CanvasItem, p: Vector2, t: float, phase: float, size: float = 5.0) -> void:
	var k: float = 0.5 + 0.5 * sin(t * 2.4 + phase)
	if k < 0.55:
		return
	var r: float = size * (k - 0.4)
	U.line(ci, p + Vector2(-r, 0), p + Vector2(r, 0), Color(1, 1, 1, 0.9), 1.8)
	U.line(ci, p + Vector2(0, -r), p + Vector2(0, r), Color(1, 1, 1, 0.9), 1.8)


# ---- sea / compass / ship -------------------------------------------------------------------------
static func draw_sea(ci: CanvasItem, r: Rect2, t: float) -> void:
	U.vgrad(ci, r, Color("86D9EE"), Color("2F94C4"))
	# soft light blotches
	for i in range(7):
		var fx: float = U.hash01(i * 13 + 1)
		var fy: float = U.hash01(i * 29 + 7)
		var c := Vector2(r.position.x + fx * r.size.x + sin(t * 0.07 + float(i)) * 30.0, r.position.y + fy * r.size.y)
		U.ellipse(ci, c, 220.0 + 70.0 * U.hash01(i * 5), 90.0 + 30.0 * U.hash01(i * 3), Color(1, 1, 1, 0.045))
	# chart grid
	var step: float = 150.0
	var gx: float = fmod(r.position.x, step)
	var x: float = r.position.x - gx + step * 0.5
	while x < r.end.x:
		U.rect(ci, Rect2(x, r.position.y, 1.6, r.size.y), Color(1, 1, 1, 0.07))
		x += step
	var y: float = r.position.y + step * 0.4
	while y < r.end.y:
		U.rect(ci, Rect2(r.position.x, y, r.size.x, 1.6), Color(1, 1, 1, 0.07))
		y += step
	# wave squiggles
	for i in range(46):
		var wx: float = r.position.x + U.hash01(i * 7 + 3) * r.size.x
		var wy: float = r.position.y + U.hash01(i * 11 + 5) * r.size.y
		var sc: float = 0.7 + U.hash01(i * 17) * 0.8
		var bob: float = sin(t * 0.8 + float(i) * 1.7) * 2.0
		var pts := PackedVector2Array()
		for k in range(7):
			var kx: float = float(k) * 6.0 * sc
			pts.append(Vector2(wx + kx, wy + bob + sin(float(k) * 1.2) * 2.6 * sc))
		U.pline(ci, pts, Color(1, 1, 1, 0.26), 2.2)


static func draw_compass(ci: CanvasItem, c: Vector2, r: float, t: float) -> void:
	U.circ(ci, c + Vector2(0, 4), r + 6.0, Color(0.05, 0.1, 0.22, 0.2))
	U.circ(ci, c, r + 6.0, Color(1, 1, 1, 0.22))
	U.circ(ci, c, r, Color("FFF3DA"))
	U.ring(ci, c, r - 7.0, Color("C9A66B"), 2.0)
	for i in range(16):
		var a: float = float(i) * TAU / 16.0
		var d := Vector2(sin(a), -cos(a))
		var l0: float = r - 7.0
		var l1: float = r - (14.0 if i % 4 == 0 else 11.0)
		U.line(ci, c + d * l0, c + d * l1, Color("A98448"), 2.0)
	var sway: float = sin(t * 0.6) * 0.06
	for i in range(4):
		var a2: float = float(i) * PI * 0.5 + sway
		var d2 := Vector2(sin(a2), -cos(a2))
		var n2 := Vector2(-d2.y, d2.x)
		var pts := PackedVector2Array([c + d2 * (r - 12.0), c + n2 * 9.0, c - n2 * 9.0])
		U.poly(ci, pts, Palette.CORAL if i == 0 else Color("6C7A96"))
	for i in range(4):
		var a3: float = PI * 0.25 + float(i) * PI * 0.5 + sway
		var d3 := Vector2(sin(a3), -cos(a3))
		var n3 := Vector2(-d3.y, d3.x)
		U.poly(ci, PackedVector2Array([c + d3 * (r * 0.55), c + n3 * 5.0, c - n3 * 5.0]), Color("B8C2D6"))
	U.circ(ci, c, 5.0, Palette.SUN)
	U.circ(ci, c, 2.4, Color("A98448"))


## Tiny cruise ship (about 74 px wide at scale 1) facing `facing` (+1 = bow right).
static func draw_ship(ci: CanvasItem, pos: Vector2, facing: float, t: float, s: float = 1.0) -> void:
	var f: float = 1.0 if facing >= 0.0 else -1.0
	var bob: float = sin(t * 2.2) * 1.8 * s
	var p := pos + Vector2(0, bob)
	# wake
	for i in range(4):
		var k: float = fmod(t * 0.9 + float(i) * 0.25, 1.0)
		U.ellipse(ci, p + Vector2(-f * (30.0 + k * 40.0) * s, 12.0 * s), (10.0 + k * 10.0) * s, 3.0 * s, Color(1, 1, 1, 0.5 * (1.0 - k)))
	U.ellipse(ci, p + Vector2(0, 14.0 * s), 38.0 * s, 6.0 * s, Color(0.05, 0.1, 0.22, 0.25))
	# hull
	var hull := PackedVector2Array([Vector2(-36 * f, 0), Vector2(36 * f, 0), Vector2(28 * f, 14), Vector2(-30 * f, 14)])
	U.poly(ci, _tr(hull, p, s, s), Palette.NAVY)
	U.poly(ci, _tr(PackedVector2Array([Vector2(-34 * f, 0), Vector2(34 * f, 0), Vector2(33 * f, 3.5), Vector2(-33 * f, 3.5)]), p, s, s), Palette.CORAL)
	# bow point
	U.poly(ci, _tr(PackedVector2Array([Vector2(34 * f, 0), Vector2(46 * f, -3), Vector2(30 * f, 14), Vector2(28 * f, 14)]), p, s, s), Palette.NAVY)
	# decks
	U.rr(ci, Rect2(p.x + (-30.0 if f > 0.0 else -24.0) * s, p.y - 11.0 * s, 54.0 * s, 11.0 * s), 3.0 * s, Palette.HULL_WHITE)
	U.rr(ci, Rect2(p.x + (-22.0 if f > 0.0 else -18.0) * s, p.y - 21.0 * s, 40.0 * s, 10.0 * s), 3.0 * s, Color.WHITE)
	for i in range(6):
		U.rr(ci, Rect2(p.x + (-26.0 + float(i) * 8.0) * s * 1.0 + (0.0 if f > 0.0 else 2.0 * s), p.y - 8.0 * s, 4.0 * s, 4.0 * s), 1.0, Palette.TEAL)
	for i in range(4):
		U.rr(ci, Rect2(p.x + (-18.0 + float(i) * 9.0) * s + (0.0 if f > 0.0 else 2.0 * s), p.y - 18.5 * s, 5.0 * s, 4.0 * s), 1.0, Palette.TEAL_LIGHT)
	# funnel
	U.rr(ci, Rect2(p.x - 5.0 * s * f - 4.0 * s, p.y - 33.0 * s, 9.0 * s, 13.0 * s), 2.0 * s, Palette.CORAL)
	U.rect(ci, Rect2(p.x - 5.0 * s * f - 4.0 * s, p.y - 29.0 * s, 9.0 * s, 2.5 * s), Palette.SUN)
	var sm: float = fmod(t * 0.7, 1.0)
	U.circ(ci, p + Vector2(-f * (6.0 + sm * 18.0) * s, -36.0 * s - sm * 14.0 * s), (3.0 + sm * 4.0) * s, Color(1, 1, 1, 0.65 * (1.0 - sm)))


# ---- islands --------------------------------------------------------------------------------------
static func draw_backdrop(ci: CanvasItem, dest: StringName, c: Vector2, s: float, t: float) -> void:
	match dest:
		&"arctic":
			_aurora(ci, c, s, t)
		&"underworld":
			U.ellipse(ci, c + Vector2(0, -70.0 * s), 170.0 * s, 100.0 * s, Color(1.0, 0.45, 0.7, 0.10))
			U.ellipse(ci, c + Vector2(0, -60.0 * s), 110.0 * s, 70.0 * s, Color(1.0, 0.45, 0.7, 0.10))
		_:
			U.circ(ci, c + Vector2(80.0 * s, -150.0 * s), 38.0 * s, Color(1.0, 0.92, 0.6, 0.0))


static func _aurora(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var cols: Array[Color] = [Color("5BE8A0"), Color("4FD6F0"), Color("C08BFF")]
	for k in range(3):
		var base_y: float = c.y - (84.0 + float(k) * 13.0) * s
		var steps: int = 14
		var x0: float = c.x - 190.0 * s
		var w: float = 380.0 * s
		for i in range(steps):
			var xa: float = x0 + w * float(i) / float(steps)
			var xb: float = x0 + w * float(i + 1) / float(steps)
			var ya: float = base_y + sin(xa * 0.018 + t * 0.9 + float(k) * 1.7) * 16.0 * s
			var yb: float = base_y + sin(xb * 0.018 + t * 0.9 + float(k) * 1.7) * 16.0 * s
			var edge: float = sin(PI * (float(i) + 0.5) / float(steps))
			var a_top: float = 0.0
			var a_bot: float = 0.9 * edge * (0.75 + 0.25 * sin(t * 1.3 + float(i) * 0.5 + float(k)))
			var h: float = (52.0 + 16.0 * sin(float(i) * 0.7 + t + float(k))) * s
			var cc: Color = cols[k]
			var pts := PackedVector2Array([Vector2(xa, ya - h), Vector2(xb, yb - h), Vector2(xb, yb), Vector2(xa, ya)])
			var col_arr := PackedColorArray([Color(cc.r, cc.g, cc.b, a_top), Color(cc.r, cc.g, cc.b, a_top), Color(cc.r, cc.g, cc.b, a_bot), Color(cc.r, cc.g, cc.b, a_bot)])
			U.polyc(ci, pts, col_arr)


static func draw_island(ci: CanvasItem, dest: StringName, c: Vector2, s: float, t: float, fogged: bool = false) -> void:
	var prev_alpha: float = U.alpha
	if fogged:
		U.alpha = 0.55
	U.begin_scaled(ci, c, s)
	match dest:
		&"arctic": _arctic(ci, t)
		&"underworld": _underworld(ci, t)
		_: _med(ci, t)
	U.end_scaled(ci)
	U.alpha = prev_alpha
	if fogged:
		_fog(ci, c, s, t)


static func _fog(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var puffs: Array[Vector3] = [Vector3(-118, -12, 0.95), Vector3(-52, -34, 1.05), Vector3(22, -18, 1.1), Vector3(98, -34, 1.0), Vector3(140, -4, 0.8), Vector3(-6, 6, 1.2)]
	for i in range(puffs.size()):
		var p: Vector3 = puffs[i]
		var drift: float = sin(t * 0.5 + float(i) * 1.3) * 7.0
		var pc := c + Vector2(p.x + drift, p.y) * s
		var r: float = 44.0 * p.z * s
		U.ellipse(ci, pc + Vector2(0, 5.0 * s), r * 1.3, r * 0.72, Color(0.35, 0.45, 0.65, 0.18))
		U.ellipse(ci, pc, r * 1.3, r * 0.72, Color(0.93, 0.96, 1.0, 0.9))
		U.circ(ci, pc + Vector2(-r * 0.45, -r * 0.3), r * 0.55, Color(0.97, 0.98, 1.0, 0.95))
		U.circ(ci, pc + Vector2(r * 0.35, -r * 0.4), r * 0.62, Color(0.97, 0.98, 1.0, 0.95))


# ---- Mediterranean --------------------------------------------------------------------------------
static func _house(ci: CanvasItem, p: Vector2, w: float, h: float, roof: Color) -> void:
	U.rr(ci, Rect2(p.x - w * 0.5, p.y - h, w, h), 2.5, Color("FFFDF6"))
	U.rect(ci, Rect2(p.x - w * 0.5, p.y - h * 0.3, w, h * 0.3), Color("F1E7D2"))
	U.poly(ci, PackedVector2Array([Vector2(p.x - w * 0.62, p.y - h), Vector2(p.x + w * 0.62, p.y - h), Vector2(p.x, p.y - h - w * 0.5)]), roof)
	U.rr(ci, Rect2(p.x - w * 0.18, p.y - h * 0.62, w * 0.36, h * 0.3), 1.5, Palette.TEAL)
	U.rr(ci, Rect2(p.x - w * 0.12, p.y - h * 0.28, w * 0.24, h * 0.28), 1.5, Palette.WOOD)


static func _palm(ci: CanvasItem, base: Vector2, lean: float, h: float, t: float) -> void:
	var top := base + Vector2(lean, -h)
	var mid := base + Vector2(lean * 0.2, -h * 0.55)
	var pts := PackedVector2Array([base, mid, top])
	U.pline(ci, pts, Palette.WOOD_DARK, 5.5)
	U.pline(ci, pts, Palette.WOOD, 3.6)
	var leaf := PackedVector2Array([Vector2(0, 0), Vector2(0.35, -0.24), Vector2(0.75, -0.2), Vector2(1.0, 0.14), Vector2(0.68, 0.0), Vector2(0.35, -0.05)])
	for k in range(6):
		var a: float = -PI * 0.5 + (float(k) - 2.5) * 0.62 + sin(t * 1.3 + float(k)) * 0.05
		var flip: float = 1.0 if cos(a) >= 0.0 else -1.0
		var col: Color = Color("4DB583") if k % 2 == 0 else Color("66C98E")
		U.poly_xf(ci, leaf, top, a, Vector2(26.0, 26.0 * flip), col)
	U.circ(ci, top + Vector2(0, 2), 3.0, Palette.WOOD_DARK)


static func _med(ci: CanvasItem, t: float) -> void:
	var pal: Dictionary = Palette.dest(&"med")
	_lagoon(ci, Color("A6EEF0"), Color.WHITE, t, 182.0, 56.0)
	# sand
	U.ellipse(ci, Vector2(0, 10), 150.0, 40.0, Color("E6C487"))
	U.ellipse(ci, Vector2(0, 4), 148.0, 38.0, Color("F8E4B4"))
	# hills
	var land: Color = pal["land"]
	var land_d: Color = pal["land_dark"]
	U.poly(ci, _tr(_dome(190.0, 96.0, 18), Vector2(-48, 8)), land_d)
	U.poly(ci, _tr(_dome(176.0, 90.0, 18), Vector2(-50, 10), 1.0, 1.0), land)
	U.poly(ci, _tr(_dome(100.0, 40.0, 14), Vector2(-78, -22)), Color("A9DE9E"))
	U.poly(ci, _tr(_dome(150.0, 66.0, 16), Vector2(62, 8)), land_d)
	U.poly(ci, _tr(_dome(138.0, 60.0, 16), Vector2(60, 10)), Color("7CC98F"))
	U.poly(ci, _tr(_dome(70.0, 26.0, 12), Vector2(46, -14)), Color("9BDCA0"))
	# village
	_house(ci, Vector2(-84, -50), 24.0, 18.0, pal["village_roof"])
	_house(ci, Vector2(-58, -64), 26.0, 20.0, pal["village_roof2"])
	_house(ci, Vector2(-34, -48), 22.0, 17.0, pal["village_roof"])
	_house(ci, Vector2(-62, -40), 20.0, 15.0, pal["village_roof2"])
	# trees
	_palm(ci, Vector2(-132, 4), -8.0, 54.0, t)
	_palm(ci, Vector2(118, -2), 10.0, 46.0, t + 1.0)
	U.circ(ci, Vector2(-4, -20), 9.0, Color("4DB583"))
	U.circ(ci, Vector2(10, -24), 7.0, Color("5CC48F"))
	# lighthouse
	var lx: float = 78.0
	var ly: float = -42.0
	U.poly(ci, PackedVector2Array([Vector2(lx - 8, ly), Vector2(lx + 8, ly), Vector2(lx + 5.5, ly - 44), Vector2(lx - 5.5, ly - 44)]), Color.WHITE)
	U.poly(ci, PackedVector2Array([Vector2(lx - 7.2, ly - 12), Vector2(lx + 7.2, ly - 12), Vector2(lx + 6.6, ly - 22), Vector2(lx - 6.6, ly - 22)]), Palette.CORAL)
	U.poly(ci, PackedVector2Array([Vector2(lx - 6.0, ly - 30), Vector2(lx + 6.0, ly - 30), Vector2(lx + 5.5, ly - 38), Vector2(lx - 5.5, ly - 38)]), Palette.CORAL)
	U.rr(ci, Rect2(lx - 7, ly - 52, 14, 9), 2.0, Palette.SUN)
	U.poly(ci, PackedVector2Array([Vector2(lx - 9, ly - 52), Vector2(lx + 9, ly - 52), Vector2(lx, ly - 63)]), Palette.CORAL_DARK)
	var glow: float = 0.5 + 0.5 * sin(t * 2.0)
	U.circ(ci, Vector2(lx, ly - 47), 17.0 + glow * 6.0, Color(1.0, 0.95, 0.6, 0.20 + 0.12 * glow))
	# pier + boat
	U.rr(ci, Rect2(-24, 14, 42, 5), 2.0, Palette.WOOD)
	U.rect(ci, Rect2(-20, 18, 3, 9), Palette.WOOD_DARK)
	U.rect(ci, Rect2(10, 18, 3, 9), Palette.WOOD_DARK)
	var bob: float = sin(t * 1.8) * 1.6
	U.poly(ci, PackedVector2Array([Vector2(26, 24 + bob), Vector2(54, 24 + bob), Vector2(48, 32 + bob), Vector2(32, 32 + bob)]), Palette.CORAL)
	U.line(ci, Vector2(40, 24 + bob), Vector2(40, 6 + bob), Palette.WOOD_DARK, 2.0)
	U.poly(ci, PackedVector2Array([Vector2(41, 8 + bob), Vector2(41, 22 + bob), Vector2(54, 22 + bob)]), Color.WHITE)
	_sparkle(ci, Vector2(-120, -6), t, 0.0)
	_sparkle(ci, Vector2(130, 18), t, 1.7)
	_sparkle(ci, Vector2(-20, 30), t, 3.1)


# ---- Arctic ---------------------------------------------------------------------------------------
static func _berg(ci: CanvasItem, off: Vector2, sc: float, flip: float = 1.0) -> void:
	var f: float = flip
	var m := func(x: float, y: float) -> Vector2: return Vector2(x * f * sc, y * sc) + off
	# lit side
	U.poly(ci, PackedVector2Array([m.call(-100, 0), m.call(-92, -38), m.call(-62, -60), m.call(-38, -98), m.call(-14, -132), m.call(-8, 0)]), Color("F7FBFF") if f > 0.0 else Color("CFE3F6"))
	# shaded side
	U.poly(ci, PackedVector2Array([m.call(-14, -132), m.call(8, -100), m.call(34, -112), m.call(60, -68), m.call(88, -54), m.call(106, -8), m.call(106, 0), m.call(-8, 0)]), Color("CFE3F6") if f > 0.0 else Color("F7FBFF"))
	# mid facets
	U.poly(ci, PackedVector2Array([m.call(-38, -98), m.call(-14, -132), m.call(-12, -50), m.call(-52, -40)]), Color("E3F0FB"))
	U.poly(ci, PackedVector2Array([m.call(34, -112), m.call(60, -68), m.call(30, -40), m.call(10, -60)]), Color("B9D6F0"))
	U.poly(ci, PackedVector2Array([m.call(60, -68), m.call(88, -54), m.call(106, -8), m.call(70, -20)]), Color("A9CAEA"))
	# waterline band
	U.poly(ci, PackedVector2Array([m.call(-100, 0), m.call(-98, -14), m.call(104, -14), m.call(106, 0)]), Color(0.55, 0.74, 0.92, 0.75))
	# snow cap shine
	U.poly(ci, PackedVector2Array([m.call(-14, -132), m.call(-24, -110), m.call(-6, -112)]), Color.WHITE)


static func _penguin(ci: CanvasItem, p: Vector2, t: float, phase: float) -> void:
	var wob: float = sin(t * 3.0 + phase) * 0.08
	var xf := Transform2D(wob, Vector2.ONE, 0.0, p)
	var pt := func(v: Vector2) -> Vector2: return xf * v
	U.ellipse(ci, p + Vector2(0, 2), 8.0, 2.5, Color(0.2, 0.3, 0.5, 0.25))
	U.rr(ci, Rect2(pt.call(Vector2(-6, 0)).x, pt.call(Vector2(-6, 0)).y - 2, 5, 3), 1.5, Palette.ORANGE)
	U.rr(ci, Rect2(pt.call(Vector2(1, 0)).x, pt.call(Vector2(1, 0)).y - 2, 5, 3), 1.5, Palette.ORANGE)
	U.ellipse(ci, pt.call(Vector2(0, -11)), 8.0, 11.0, Palette.NAVY_DARK)
	U.ellipse(ci, pt.call(Vector2(0.5, -9)), 5.2, 8.0, Color.WHITE)
	U.circ(ci, pt.call(Vector2(-2.2, -18)), 1.4, Color.WHITE)
	U.circ(ci, pt.call(Vector2(2.2, -18)), 1.4, Color.WHITE)
	U.circ(ci, pt.call(Vector2(-2.2, -18)), 0.7, Palette.INK)
	U.circ(ci, pt.call(Vector2(2.2, -18)), 0.7, Palette.INK)
	U.poly(ci, PackedVector2Array([pt.call(Vector2(-2, -15.5)), pt.call(Vector2(2, -15.5)), pt.call(Vector2(0, -12.5))]), Palette.ORANGE)


static func _arctic(ci: CanvasItem, t: float) -> void:
	_lagoon(ci, Color("D6F1FF"), Color.WHITE, t, 182.0, 56.0)
	# floating floes
	for i in range(5):
		var fx: float = -150.0 + float(i) * 76.0 + sin(t * 0.5 + float(i)) * 4.0
		var fy: float = 26.0 + float((i * 5) % 3) * 6.0
		U.ellipse(ci, Vector2(fx, fy), 20.0, 5.5, Color(1, 1, 1, 0.8))
	# side bergs
	_berg(ci, Vector2(-132, 4), 0.5, -1.0)
	_berg(ci, Vector2(136, 8), 0.42, 1.0)
	# main berg
	_berg(ci, Vector2(0, 8), 1.0, 1.0)
	# ice shelf in front
	U.ellipse(ci, Vector2(-14, 18), 112.0, 18.0, Color("B6D6F0"))
	U.ellipse(ci, Vector2(-14, 14), 110.0, 16.0, Color("F2F9FF"))
	# igloo
	U.poly(ci, _tr(_dome(46.0, 24.0, 14), Vector2(-62, 14)), Color("E3F0FB"))
	U.poly(ci, _tr(_dome(40.0, 21.0, 14), Vector2(-62, 14)), Color.WHITE)
	U.arc(ci, Vector2(-62, 14), 14.0, PI, TAU, Color("C9DEF2"), 1.6, 10)
	U.poly(ci, _tr(_dome(14.0, 11.0, 10), Vector2(-52, 14)), Color("5E7BA3"))
	# penguins
	_penguin(ci, Vector2(14, 14), t, 0.0)
	_penguin(ci, Vector2(36, 16), t, 1.6)
	# little flag
	U.line(ci, Vector2(-28, 12), Vector2(-28, -8), Palette.WOOD_DARK, 2.0)
	var fl: float = sin(t * 4.0) * 2.0
	U.poly(ci, PackedVector2Array([Vector2(-27, -8), Vector2(-12, -4 + fl), Vector2(-27, 0)]), Palette.CORAL)
	_sparkle(ci, Vector2(-30, -92), t, 0.4, 7.0)
	_sparkle(ci, Vector2(60, -66), t, 2.2, 6.0)
	_sparkle(ci, Vector2(100, 8), t, 3.9)
	# snow flurries
	for i in range(12):
		var k: float = fmod(t * 0.12 + U.hash01(i * 3 + 1), 1.0)
		var sx: float = -170.0 + U.hash01(i * 5 + 2) * 340.0 + sin(t + float(i)) * 8.0
		U.circ(ci, Vector2(sx, -150.0 + k * 170.0), 1.6 + U.hash01(i) * 1.2, Color(1, 1, 1, 0.8 * sin(k * PI)))


# ---- Underworld -----------------------------------------------------------------------------------
static func _rock(ci: CanvasItem, off: Vector2, sc: float, flip: float = 1.0) -> void:
	var f: float = flip
	var m := func(x: float, y: float) -> Vector2: return Vector2(x * f * sc, y * sc) + off
	U.poly(ci, PackedVector2Array([m.call(-64, 0), m.call(-74, -40), m.call(-52, -62), m.call(-56, -100), m.call(-32, -82), m.call(-26, -138), m.call(-6, -96), m.call(10, -116), m.call(16, -72), m.call(42, -86), m.call(48, -46), m.call(74, -54), m.call(82, 0)]), Color("3B2058"))
	U.poly(ci, PackedVector2Array([m.call(-64, 0), m.call(-74, -40), m.call(-52, -62), m.call(-56, -100), m.call(-32, -82), m.call(-26, -138), m.call(-20, -60), m.call(-24, 0)]), Color("5B3680"))
	U.poly(ci, PackedVector2Array([m.call(-6, -96), m.call(10, -116), m.call(16, -72), m.call(12, 0), m.call(-4, 0)]), Color("4B2A6E"))
	U.poly(ci, PackedVector2Array([m.call(16, -72), m.call(42, -86), m.call(48, -46), m.call(74, -54), m.call(82, 0), m.call(12, 0)]), Color("2C1642"))
	# rim light on the ridges
	U.pline(ci, PackedVector2Array([m.call(-56, -100), m.call(-32, -82), m.call(-26, -138)]), Color("9A66C9"), 2.4)
	# glowing cracks
	U.pline(ci, PackedVector2Array([m.call(-30, -60), m.call(-34, -40), m.call(-28, -22)]), Color("FF8A5C"), 2.2)


static func _lantern(ci: CanvasItem, p: Vector2, t: float, phase: float) -> void:
	U.line(ci, p + Vector2(0, 30), p + Vector2(0, -4), Color("2B1740"), 3.0)
	U.pline(ci, PackedVector2Array([p + Vector2(0, -4), p + Vector2(8, -10), p + Vector2(8, -14)]), Color("2B1740"), 2.6)
	var k: float = 0.5 + 0.5 * sin(t * 3.0 + phase)
	var lp := p + Vector2(8, -22)
	U.circ(ci, lp, 20.0 + k * 5.0, Color(1.0, 0.7, 0.3, 0.16 + 0.10 * k))
	U.circ(ci, lp, 12.0, Color(1.0, 0.7, 0.3, 0.25))
	U.rr(ci, Rect2(lp.x - 6, lp.y - 8, 12, 16), 4.0, Color("FFB347"))
	U.rr(ci, Rect2(lp.x - 3, lp.y - 5, 6, 10), 3.0, Color("FFE49A"))
	U.rect(ci, Rect2(lp.x - 7, lp.y - 10, 14, 3), Color("3A2152"))
	U.rect(ci, Rect2(lp.x - 7, lp.y + 7, 14, 3), Color("3A2152"))


static func _underworld(ci: CanvasItem, t: float) -> void:
	_lagoon(ci, Color("40308A"), Color("B79BFF"), t, 182.0, 56.0)
	U.ellipse(ci, Vector2(0, 8), 150.0, 40.0, Color("24123D"))
	_rock(ci, Vector2(-128, 8), 0.55, -1.0)
	_rock(ci, Vector2(138, 10), 0.48, 1.0)
	_rock(ci, Vector2(0, 8), 1.0, 1.0)
	# gate portal in front of the main spire
	U.rr(ci, Rect2(-30, -66, 12, 70), 3.0, Color("4A2B66"))
	U.rr(ci, Rect2(18, -66, 12, 70), 3.0, Color("4A2B66"))
	U.rr(ci, Rect2(-36, -78, 72, 15), 5.0, Color("5E3A80"))
	U.rr(ci, Rect2(-8, -86, 16, 10), 3.0, Color("6E479A"))
	var pk: float = 0.5 + 0.5 * sin(t * 2.2)
	U.ellipse(ci, Vector2(0, -34), 15.0, 30.0, Color(1.0, 0.35, 0.65, 0.55 + 0.2 * pk))
	U.ellipse(ci, Vector2(0, -34), 9.0, 22.0, Color(1.0, 0.7, 0.85, 0.65))
	U.ellipse(ci, Vector2(0, -34), 4.0, 12.0, Color(1.0, 0.95, 1.0, 0.8))
	# lanterns
	_lantern(ci, Vector2(-96, -8), t, 0.0)
	_lantern(ci, Vector2(104, -6), t, 1.8)
	_lantern(ci, Vector2(-58, 14), t, 3.1)
	# wisps
	for i in range(4):
		var a: float = t * (0.6 + float(i) * 0.15) + float(i) * 1.7
		var wp := Vector2(cos(a) * (120.0 - float(i) * 14.0), -40.0 - float(i) * 18.0 + sin(a * 1.3) * 18.0)
		U.circ(ci, wp, 9.0, Color(0.55, 1.0, 0.76, 0.18))
		U.circ(ci, wp, 4.6, Color(0.7, 1.0, 0.85, 0.85))
		U.circ(ci, wp + Vector2(-sin(a) * 6.0, 4.0), 2.6, Color(0.55, 1.0, 0.76, 0.35))
	# ghost
	ProblemArt.draw_ghost(ci, Vector2(66.0 + sin(t * 0.7) * 12.0, -104.0 + sin(t * 1.4) * 4.0), t, 0.8, 1)
	# embers
	for i in range(10):
		var k: float = fmod(t * 0.18 + U.hash01(i * 7 + 1), 1.0)
		var ex: float = -150.0 + U.hash01(i * 3 + 2) * 300.0 + sin(t + float(i)) * 6.0
		U.circ(ci, Vector2(ex, 20.0 - k * 150.0), 1.8, Color(1.0, 0.7, 0.35, 0.9 * sin(k * PI)))


# ---- decorations ------------------------------------------------------------------------------------
static func draw_sailboat(ci: CanvasItem, p: Vector2, s: float, t: float, phase: float) -> void:
	var bob: float = sin(t * 1.5 + phase) * 2.0 * s
	var q := p + Vector2(0, bob)
	U.ellipse(ci, q + Vector2(0, 11.0 * s), 28.0 * s, 4.0 * s, Color(0.05, 0.2, 0.4, 0.18))
	U.poly(ci, PackedVector2Array([q + Vector2(-20, 0) * s, q + Vector2(22, 0) * s, q + Vector2(15, 9) * s, q + Vector2(-14, 9) * s]), Palette.CORAL)
	U.line(ci, q + Vector2(0, 0), q + Vector2(0, -32.0 * s), Palette.WOOD_DARK, 2.2 * s)
	U.poly(ci, PackedVector2Array([q + Vector2(2, -30) * s, q + Vector2(2, -4) * s, q + Vector2(20, -4) * s]), Color.WHITE)
	U.poly(ci, PackedVector2Array([q + Vector2(-2, -26) * s, q + Vector2(-2, -4) * s, q + Vector2(-15, -4) * s]), Color("EAF4FF"))
	U.poly(ci, PackedVector2Array([q + Vector2(0, -32) * s, q + Vector2(9, -29) * s, q + Vector2(0, -26) * s]), Palette.SUN)


static func draw_whale(ci: CanvasItem, p: Vector2, s: float, t: float) -> void:
	var k: float = fmod(t * 0.16, 1.0)
	var dive: float = sin(clampf(k * 1.5, 0.0, 1.0) * PI)
	if dive <= 0.03:
		return
	var body := Color("3E6FA8")
	var rise: float = (1.0 - dive) * 26.0 * s
	var q := p + Vector2(0, rise)
	# ripple
	U.ellipse(ci, p + Vector2(0, 10.0 * s), 62.0 * s * dive, 9.0 * s * dive, Color(1, 1, 1, 0.45))
	# back (dome) + tail fluke
	U.poly(ci, _tr(_dome(70.0, 22.0, 14), q + Vector2(0, 8.0 * s), s, s), body)
	U.poly(ci, _tr(_dome(52.0, 12.0, 12), q + Vector2(6.0 * s, 8.0 * s), s, s), Color("6A9AD0"))
	U.poly(ci, PackedVector2Array([q + Vector2(32, 6) * s, q + Vector2(52, -10) * s, q + Vector2(46, 8) * s, q + Vector2(58, 4) * s, q + Vector2(44, 10) * s]), body)
	U.circ(ci, q + Vector2(-20, -2) * s, 2.2 * s, Palette.INK)
	# spout
	for i in range(6):
		var u: float = fmod(t * 1.1 + float(i) * 0.17, 1.0)
		U.circ(ci, q + Vector2(-8.0 * s + sin(float(i) * 2.0) * 7.0 * s * u, -12.0 * s - u * 36.0 * s * dive), (3.4 - u * 2.0) * s, Color(1, 1, 1, 0.85 * (1.0 - u)))
