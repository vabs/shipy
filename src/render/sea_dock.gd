class_name SeaDock
extends RefCounted
## The port-stop scene for SeaBackground (docs/SPEC.md §13.8): a harbour town in the destination's own style on the horizon
## (whitewashed Med village with a lighthouse, snowy Arctic huts with chimney smoke, an Underworld castle with torches) and a
## wooden pier alongside the ship's gangway with a name sign, bollards, lamps, crates and a few waiting beans. Stateless drawing
## helpers; SeaBackground slides both in with `SimWorld.port_stop.dock_progress`.

const U := preload("res://src/render/art/art_util.gd")

const WOOD := Color("C98B54")
const WOOD_DARK := Color("A56A3A")
const WOOD_LIGHT := Color("E3AE7A")


# =================================================================================================
# harbour town on the horizon (screen space; `ox` = the slide offset, 0 when docked)
# =================================================================================================
static func draw_town(ci: CanvasItem, dest: StringName, pal: Dictionary, ox: float, hy: float, w: float, anim: float) -> void:
	match dest:
		&"arctic":
			_town_arctic(ci, pal, ox, hy, w, anim)
		&"underworld":
			_town_underworld(ci, pal, ox, hy, w, anim)
		_:
			_town_med(ci, pal, ox, hy, w, anim)


static func _hill(w: float, x: float, seed_v: float, lo: float, hi: float) -> float:
	var u: float = x / maxf(w, 1.0)
	return lo + (hi - lo) * (0.5 + 0.28 * sin(u * 7.0 + seed_v) + 0.14 * sin(u * 15.0 + seed_v * 2.3) + 0.08 * sin(u * 31.0))


static func _town_med(ci: CanvasItem, pal: Dictionary, ox: float, hy: float, w: float, anim: float) -> void:
	var land: Color = pal["land"]
	var dark: Color = pal["land_dark"]
	var wall: Color = pal["village_wall"]
	var roof_a: Color = pal["village_roof"]
	var roof_b: Color = pal["village_roof2"]
	var rock: Color = pal["rock"]
	var span: float = w + 160.0
	var x0: float = -80.0 + ox
	var base: float = hy + 3.0
	# two hill layers
	for layer in 2:
		var pts := PackedVector2Array()
		pts.append(Vector2(x0, base + 8.0))
		var n: int = 36
		for i in n + 1:
			var x: float = x0 + span * float(i) / float(n)
			var hh: float = _hill(span, x - x0, 1.3 + float(layer) * 2.1, 70.0 + 22.0 * float(layer), 190.0 - 36.0 * float(layer))
			pts.append(Vector2(x, base - hh))
		pts.append(Vector2(x0 + span, base + 8.0))
		U.poly(ci, pts, dark if layer == 0 else land)
	# terraced village
	var cnt: int = 40
	for i in cnt:
		var u: float = (float(i) + 0.5 + (U.hash01(i * 3 + 1) - 0.5) * 0.6) / float(cnt)
		var x: float = x0 + span * u
		var hh: float = _hill(span, x - x0, 3.4, 70.0, 150.0) * 0.6
		var by: float = base - hh * (0.35 + 0.65 * U.hash01(i * 5 + 2)) + 4.0
		var bw: float = 26.0 + 20.0 * U.hash01(i * 7 + 3)
		var bh: float = 24.0 + 30.0 * U.hash01(i * 11 + 4)
		var rk: int = int(U.hash01(i * 13 + 5) * 4.0)
		if rk == 0:
			U.circ(ci, Vector2(x, by - bh), bw * 0.4, roof_b)
		U.rect(ci, Rect2(x - bw * 0.5, by - bh, bw, bh), wall)
		U.rect(ci, Rect2(x + bw * 0.12, by - bh, bw * 0.38, bh), Color("E9DFCB"))
		match rk:
			1:
				U.rect(ci, Rect2(x - bw * 0.5 - 1.0, by - bh - 3.0, bw + 2.0, 4.0), roof_a)
			2:
				U.poly(ci, PackedVector2Array([Vector2(x - bw * 0.5 - 2.0, by - bh), Vector2(x, by - bh - bw * 0.5), Vector2(x + bw * 0.5 + 2.0, by - bh)]), roof_a)
			3:
				U.rect(ci, Rect2(x - bw * 0.5 - 1.0, by - bh - 3.0, bw + 2.0, 4.0), roof_b)
		U.rect(ci, Rect2(x - bw * 0.1, by - bh * 0.6, bw * 0.2, bh * 0.34), roof_b)
		if i % 5 == 2:
			U.ellipse(ci, Vector2(x + bw * 0.7, by - 9.0), 3.4, 11.0, Palette.shade(dark, 0.3))   # cypress
	# lighthouse on the right-hand headland
	_lighthouse(ci, Vector2(x0 + span * 0.235, base - 52.0), 2.1, anim)
	# harbour wall with little arches, boats moored in front of it
	U.rect(ci, Rect2(x0, base - 2.0, span, 14.0), rock)
	U.rect(ci, Rect2(x0, base - 2.0, span, 3.0), Palette.tint(rock, 0.35))
	var ax: float = x0 + 16.0
	while ax < x0 + span:
		U.rr(ci, Rect2(ax, base + 3.0, 16.0, 9.0), 6.0, Palette.shade(rock, 0.4))
		ax += 52.0
	for bi in 4:
		var bx: float = x0 + span * (0.16 + 0.22 * float(bi)) + sin(anim * 0.9 + float(bi)) * 3.0
		var by2: float = base + 16.0 + sin(anim * 1.4 + float(bi) * 2.0) * 1.5
		U.rr(ci, Rect2(bx - 18.0, by2 - 6.0, 36.0, 9.0), 4.0, roof_a if bi % 2 == 0 else roof_b)
		U.line(ci, Vector2(bx, by2 - 6.0), Vector2(bx, by2 - 30.0), WOOD_DARK, 1.6)
		U.poly(ci, PackedVector2Array([Vector2(bx + 1.5, by2 - 29.0), Vector2(bx + 1.5, by2 - 8.0), Vector2(bx + 15.0, by2 - 8.0)]), Color("FFFDF6"))


static func _lighthouse(ci: CanvasItem, p: Vector2, k: float, anim: float) -> void:
	var hgt: float = 48.0 * k
	var w0: float = 6.5 * k
	var w1: float = 4.4 * k
	U.poly(ci, PackedVector2Array([p + Vector2(-w0, 0), p + Vector2(-w1, -hgt), p + Vector2(w1, -hgt), p + Vector2(w0, 0)]), Palette.HULL_WHITE)
	for si in 2:
		var y0: float = (-10.0 - float(si) * 16.0) * k
		var y1: float = y0 - 8.0 * k
		var wa: float = lerpf(w0, w1, -y0 / hgt)
		var wb: float = lerpf(w0, w1, -y1 / hgt)
		U.poly(ci, PackedVector2Array([p + Vector2(-wa, y0), p + Vector2(-wb, y1), p + Vector2(wb, y1), p + Vector2(wa, y0)]), Palette.CORAL)
	U.rect(ci, Rect2(p.x - 6.5 * k, p.y - hgt - 3.0 * k, 13.0 * k, 3.0 * k), Palette.NAVY)
	U.rr(ci, Rect2(p.x - 4.0 * k, p.y - hgt - 11.0 * k, 8.0 * k, 8.0 * k), 2.0 * k, Palette.SUN)
	U.poly(ci, PackedVector2Array([p + Vector2(-5.5, -hgt / k - 11.0) * k, p + Vector2(0, -hgt / k - 18.0) * k, p + Vector2(5.5, -hgt / k - 11.0) * k]), Palette.CORAL)
	var pu: float = 0.6 + 0.4 * sin(anim * 2.2)
	var lamp := p + Vector2(0, -hgt - 7.0 * k)
	U.circ(ci, lamp, 22.0 * k, Palette.alpha(Palette.SUN, 0.14 * pu))
	U.circ(ci, lamp, 12.0 * k, Palette.alpha(Palette.SUN, 0.24))


static func _pine(ci: CanvasItem, p: Vector2, s: float, snow: bool) -> void:
	var g: Color = Color("3F7F73")
	U.rect(ci, Rect2(p.x - 1.6 * s, p.y - 5.0 * s, 3.2 * s, 6.0 * s), WOOD_DARK)
	for i in 3:
		var yy: float = p.y - 4.0 * s - float(i) * 9.0 * s
		var ww: float = (13.0 - float(i) * 3.2) * s
		U.poly(ci, PackedVector2Array([Vector2(p.x - ww, yy), Vector2(p.x, yy - 14.0 * s), Vector2(p.x + ww, yy)]), g)
		if snow:
			U.poly(ci, PackedVector2Array([Vector2(p.x - ww * 0.62, yy - 5.0 * s), Vector2(p.x, yy - 14.0 * s), Vector2(p.x + ww * 0.62, yy - 5.0 * s), Vector2(p.x, yy - 7.0 * s)]), Color("F6F8FF"))


static func _town_arctic(ci: CanvasItem, pal: Dictionary, ox: float, hy: float, w: float, anim: float) -> void:
	var land: Color = pal["land"]
	var dark: Color = pal["land_dark"]
	var span: float = w + 160.0
	var x0: float = -80.0 + ox
	var base: float = hy + 3.0
	# snowy mountains behind
	for layer in 2:
		var pts := PackedVector2Array()
		pts.append(Vector2(x0, base + 8.0))
		var n: int = 30
		for i in n + 1:
			var x: float = x0 + span * float(i) / float(n)
			var hh: float = _hill(span, x - x0, 0.6 + float(layer) * 1.9, 60.0 + 20.0 * float(layer), 170.0 - 34.0 * float(layer))
			pts.append(Vector2(x, base - hh))
		pts.append(Vector2(x0 + span, base + 8.0))
		U.poly(ci, pts, Palette.shade(dark, 0.18) if layer == 0 else land)
	# coloured wooden huts with snowy roofs
	var cols: Array[Color] = [Color("E8505B"), Color("F2B544"), Color("3AA0C8"), Color("F7F4EC"), Color("8FBF8A")]
	var cnt: int = 22
	for i in cnt:
		var u: float = (float(i) + 0.5 + (U.hash01(i * 3 + 9) - 0.5) * 0.5) / float(cnt)
		var x: float = x0 + span * u
		var hh: float = _hill(span, x - x0, 2.2, 40.0, 100.0) * 0.3
		var by: float = base - hh * U.hash01(i * 5 + 1) + 2.0
		var bw: float = 24.0 + 14.0 * U.hash01(i * 7 + 2)
		var bh: float = 20.0 + 14.0 * U.hash01(i * 11 + 3)
		var c: Color = cols[i % cols.size()]
		U.rect(ci, Rect2(x - bw * 0.5, by - bh, bw, bh), c)
		U.rect(ci, Rect2(x + bw * 0.1, by - bh, bw * 0.4, bh), Palette.shade(c, 0.2))
		var roof := PackedVector2Array([Vector2(x - bw * 0.62, by - bh + 1.0), Vector2(x, by - bh - bw * 0.52), Vector2(x + bw * 0.62, by - bh + 1.0)])
		U.poly(ci, roof, Color("7A5A4A"))
		U.poly(ci, PackedVector2Array([Vector2(x - bw * 0.62, by - bh + 1.0), Vector2(x, by - bh - bw * 0.52), Vector2(x + bw * 0.62, by - bh + 1.0), Vector2(x + bw * 0.4, by - bh - 2.0), Vector2(x, by - bh - bw * 0.3), Vector2(x - bw * 0.4, by - bh - 2.0)]), Color("F6F8FF"))
		U.rect(ci, Rect2(x - bw * 0.1, by - bh * 0.62, bw * 0.2, bh * 0.4), Color("FFE9A8"))
		if i % 3 == 0:
			# chimney with a drifting smoke puff
			U.rect(ci, Rect2(x + bw * 0.22, by - bh - bw * 0.42, 4.0, 10.0), Palette.shade(c, 0.4))
			for k in 3:
				var ph: float = fposmod(anim * 0.35 + float(k) * 0.33 + float(i) * 0.17, 1.0)
				U.circ(ci, Vector2(x + bw * 0.22 + 2.0 + ph * 16.0, by - bh - bw * 0.42 - 6.0 - ph * 30.0), 3.0 + 4.5 * ph, Color(1, 1, 1, 0.6 * (1.0 - ph)))
		if i % 4 == 1:
			_pine(ci, Vector2(x + bw * 0.8, by + 1.0), 0.9, true)
	# ice quay along the horizon
	U.rect(ci, Rect2(x0, base - 2.0, span, 14.0), Color("D6E6F7"))
	U.rect(ci, Rect2(x0, base - 2.0, span, 4.0), Color("F6F8FF"))
	var ix: float = x0 + 30.0
	while ix < x0 + span:
		U.poly(ci, PackedVector2Array([Vector2(ix, base + 12.0), Vector2(ix + 5.0, base + 24.0), Vector2(ix + 10.0, base + 12.0)]), Color("BBD6F0"))
		ix += 64.0


static func _town_underworld(ci: CanvasItem, pal: Dictionary, ox: float, hy: float, w: float, anim: float) -> void:
	var rock: Color = pal["rock"]
	var dark: Color = pal["land_dark"]
	var lan: Color = pal["lantern"]
	var wisp: Color = pal["wisp"]
	var span: float = w + 160.0
	var x0: float = -80.0 + ox
	var base: float = hy + 3.0
	# jagged basalt cliffs in two layers
	for layer in 2:
		var pts := PackedVector2Array()
		pts.append(Vector2(x0, base + 8.0))
		var x: float = x0
		var i: int = 0
		while x < x0 + span:
			var hh: float = (50.0 + 90.0 * U.hash01(i * 7 + layer * 31)) * (1.0 - 0.25 * float(layer))
			pts.append(Vector2(x, base - hh))
			x += 22.0 + 36.0 * U.hash01(i * 5 + 3 + layer)
			i += 1
		pts.append(Vector2(x0 + span, base - 40.0))
		pts.append(Vector2(x0 + span, base + 8.0))
		U.poly(ci, pts, Palette.shade(dark, 0.3) if layer == 0 else Palette.shade(rock, 0.45))
	# a spooky castle with glowing windows on the right
	var cx: float = x0 + span * 0.2
	var cc: Color = Color("2B1B45")
	U.rect(ci, Rect2(cx - 90.0, base - 84.0, 180.0, 86.0), cc)
	for tw in [-100.0, -30.0, 50.0, 106.0]:
		var th: float = 60.0 + 40.0 * U.hash01(int(tw) + 5)
		U.rect(ci, Rect2(cx + tw - 14.0, base - 84.0 - th, 28.0, th), cc)
		U.poly(ci, PackedVector2Array([Vector2(cx + tw - 19.0, base - 84.0 - th), Vector2(cx + tw, base - 84.0 - th - 30.0), Vector2(cx + tw + 19.0, base - 84.0 - th)]), Color("3A2460"))
		var fl: float = 0.6 + 0.4 * sin(anim * 3.1 + tw)
		U.rr(ci, Rect2(cx + tw - 4.0, base - 84.0 - th + 14.0, 8.0, 14.0), 4.0, Palette.alpha(lan, 0.55 + 0.4 * fl))
	for k in 6:
		var fl2: float = 0.5 + 0.5 * sin(anim * 2.4 + float(k) * 1.7)
		U.rr(ci, Rect2(cx - 78.0 + float(k) * 28.0, base - 60.0, 9.0, 15.0), 4.0, Palette.alpha(lan, 0.5 + 0.45 * fl2))
	# arched gate in the harbour wall + torches with green flames
	U.rect(ci, Rect2(x0, base - 2.0, span, 14.0), Palette.shade(rock, 0.5))
	U.rect(ci, Rect2(x0, base - 2.0, span, 3.0), Palette.tint(rock, 0.1))
	var tx: float = x0 + 40.0
	var ti: int = 0
	while tx < x0 + span:
		U.rect(ci, Rect2(tx - 1.6, base - 40.0, 3.2, 40.0), Palette.INK)
		var fp: float = 0.7 + 0.3 * sin(anim * 5.0 + float(ti) * 2.1)
		U.circ(ci, Vector2(tx, base - 46.0), 20.0, Palette.alpha(wisp, 0.12 * fp))
		U.circ(ci, Vector2(tx, base - 46.0), 10.0, Palette.alpha(wisp, 0.26 * fp))
		U.poly(ci, PackedVector2Array([Vector2(tx - 5.0, base - 41.0), Vector2(tx, base - 56.0 - 4.0 * fp), Vector2(tx + 5.0, base - 41.0)]), Palette.alpha(wisp.lerp(Color.WHITE, 0.3), 0.95))
		tx += 150.0
		ti += 1
	# wisps drifting about
	for k in 5:
		var wx: float = x0 + fposmod(U.hash01(k * 9) * span + anim * (8.0 + 3.0 * float(k)), span)
		var wy: float = base - 40.0 - 90.0 * U.hash01(k * 5 + 1) + sin(anim * 1.3 + float(k)) * 8.0
		U.circ(ci, Vector2(wx, wy), 12.0, Palette.alpha(wisp, 0.12))
		U.circ(ci, Vector2(wx, wy), 4.5, Palette.alpha(wisp.lerp(Color.WHITE, 0.4), 0.9))


# =================================================================================================
# pier alongside the gangway
# =================================================================================================
## `g`: ex (screen x of the pier's ship-side edge, slide included), ty (screen y of the plank top), z (zoom), wy (waterline y),
## w (screen width), name (String on the sign).
static func draw_pier(ci: CanvasItem, dest: StringName, pal: Dictionary, g: Dictionary, anim: float, rope_to: Vector2) -> void:
	var ex: float = float(g["ex"])
	var ty: float = float(g["ty"])
	var z: float = float(g["z"])
	var wy: float = float(g["wy"])
	var left: float = ex - 1500.0
	var th: float = 15.0 * z
	var dark: Color = WOOD_DARK
	var plank: Color = WOOD
	var edge: Color = WOOD_LIGHT
	if dest == &"underworld":
		dark = Color("2F2646")
		plank = Color("4A3C6B")
		edge = Color("6A5A92")
	elif dest == &"arctic":
		dark = Color("7A5A4A")
		plank = Color("A98366")
		edge = Color("C9A687")
	# water shadow + posts
	var depth: float = maxf(wy + 46.0 * z, ty + 60.0 * z)
	U.rect(ci, Rect2(left, wy - 2.0 * z, ex - left, 16.0 * z), Color(0.04, 0.1, 0.2, 0.25))
	var px: float = ex - 14.0 * z
	while px > left:
		U.rr(ci, Rect2(px - 6.0 * z, ty + th, 12.0 * z, depth - ty - th), 2.0 * z, dark)
		U.rect(ci, Rect2(px - 6.0 * z, ty + th, 3.0 * z, depth - ty - th), Palette.tint(dark, 0.18))
		px -= 96.0 * z
	# fascia + deck
	U.rect(ci, Rect2(left, ty + th, ex - left, 13.0 * z), dark)
	U.rect(ci, Rect2(left, ty + th + 10.0 * z, ex - left, 3.0 * z), Palette.shade(dark, 0.3))
	U.rr(ci, Rect2(left, ty, ex - left + 4.0 * z, th), 3.0 * z, plank)
	U.rect(ci, Rect2(left, ty, ex - left + 4.0 * z, 3.5 * z), edge)
	var jx: float = ex - fposmod(ex, 40.0 * z)
	while jx > left:
		U.rect(ci, Rect2(jx, ty + 3.5 * z, 1.4 * z, th - 3.5 * z), Color(0.25, 0.13, 0.05, 0.3))
		jx -= 40.0 * z
	if dest == &"arctic":
		# snow drifted along the planks
		var sx: float = ex - 30.0 * z
		var si: int = 0
		while sx > left:
			U.ellipse(ci, Vector2(sx, ty + 1.0 * z), (22.0 + 14.0 * U.hash01(si)) * z, 5.0 * z, Color("F6F8FF"))
			sx -= 120.0 * z
			si += 1
	# mooring bollard + rope to the ship's gangway platform
	var bx: float = ex - 26.0 * z
	U.rr(ci, Rect2(bx - 6.0 * z, ty - 15.0 * z, 12.0 * z, 17.0 * z), 4.0 * z, Palette.NAVY)
	U.rr(ci, Rect2(bx - 8.0 * z, ty - 18.0 * z, 16.0 * z, 5.0 * z), 2.5 * z, Palette.NAVY_LIGHT)
	var a: Vector2 = Vector2(bx, ty - 14.0 * z)
	var b: Vector2 = rope_to
	var pts := PackedVector2Array()
	for i in 13:
		var u: float = float(i) / 12.0
		pts.append(a.lerp(b, u) + Vector2(0, sin(u * PI) * 11.0 * z))
	U.pline(ci, pts, Color("D9B98A"), 2.6 * z)
	# lamp posts
	for lx in [ex - 215.0 * z, ex - 440.0 * z]:
		_lamp(ci, Vector2(lx, ty), z, dest, anim)
	# the sign
	_sign(ci, Vector2(ex - 328.0 * z, ty), z, String(g.get("name", "")), dest, pal)
	# crates, and a destination-flavoured prop right next to the ship
	_crate(ci, Vector2(ex - 58.0 * z, ty), z, 0.8, dest)
	_crate(ci, Vector2(ex - 560.0 * z, ty), z, 1.1, dest)
	match dest:
		&"arctic":
			_sled(ci, Vector2(ex - 128.0 * z, ty), z)
		&"underworld":
			_cauldron(ci, Vector2(ex - 128.0 * z, ty), z, anim, pal)
		_:
			_kiosk(ci, Vector2(ex - 128.0 * z, ty), z, pal)
	# bunting between the lamps (Med / Arctic)
	if dest != &"underworld":
		var l1: Vector2 = Vector2(ex - 215.0 * z, ty - 100.0 * z)
		var l2: Vector2 = Vector2(ex - 440.0 * z, ty - 100.0 * z)
		var flags: Array[Color] = [Palette.CORAL, Palette.SUN, Palette.TEAL, Palette.MINT, Palette.LILAC]
		var line := PackedVector2Array()
		for i in 15:
			var u2: float = float(i) / 14.0
			line.append(l1.lerp(l2, u2) + Vector2(0, sin(u2 * PI) * 16.0 * z))
		U.pline(ci, line, Palette.NAVY, 1.4 * z)
		for i in range(1, 14):
			var p0: Vector2 = line[i]
			var sway: float = sin(anim * 2.0 + float(i) * 0.7) * 2.0 * z
			U.poly(ci, PackedVector2Array([p0, p0 + Vector2(10.0 * z, sway), p0 + Vector2(4.0 * z, 14.0 * z)]), flags[i % flags.size()])
	# waiting beans
	for k in 3:
		var fx: float = ex - (186.0 + 34.0 * float(k) + (200.0 if k == 2 else 0.0)) * z
		var o: Dictionary = {"body_color": [Palette.archetype_color(&"holidaymaker"), Palette.archetype_color(&"film_buff"), Palette.archetype_color(&"gamer")][k],
				"prop": [&"sun_hat", &"", &"headband"][k], "pose": &"stand", "facing": 1, "t": anim + float(k) * 0.9, "scale": z * 1.1}
		GuestArt.draw_guest(ci, Vector2(fx, ty + 2.0 * z), o)


static func _lamp(ci: CanvasItem, base: Vector2, z: float, dest: StringName, anim: float) -> void:
	var top: Vector2 = base + Vector2(0, -88.0 * z)
	U.line(ci, base, top, Palette.NAVY, 4.0 * z)
	U.rr(ci, Rect2(base.x - 8.0 * z, base.y - 6.0 * z, 16.0 * z, 8.0 * z), 3.0 * z, Palette.NAVY_LIGHT)
	var glow: Color = Palette.SUN if dest != &"underworld" else Color("8BFFC2")
	var fl: float = 0.85 + 0.15 * sin(anim * 5.0 + base.x)
	U.circ(ci, top + Vector2(0, -2.0 * z), 30.0 * z, Palette.alpha(glow, 0.1 * fl))
	U.circ(ci, top + Vector2(0, -2.0 * z), 16.0 * z, Palette.alpha(glow, 0.22 * fl))
	U.rr(ci, Rect2(top.x - 7.0 * z, top.y - 13.0 * z, 14.0 * z, 16.0 * z), 4.0 * z, Palette.alpha(glow, 0.95))
	U.rr(ci, Rect2(top.x - 9.0 * z, top.y - 17.0 * z, 18.0 * z, 5.0 * z), 2.0 * z, Palette.NAVY)


static func _sign(ci: CanvasItem, base: Vector2, z: float, text: String, dest: StringName, pal: Dictionary) -> void:
	var f: Font = U.font_bold()
	var fs: int = int(clampf(22.0 * z, 14.0, 34.0))
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var bw: float = maxf(tw + 40.0 * z, 120.0 * z)
	var bh: float = 40.0 * z
	var top: float = base.y - 70.0 * z
	U.rect(ci, Rect2(base.x - bw * 0.5 + 8.0 * z, top + bh, 6.0 * z, 70.0 * z - bh), WOOD_DARK)
	U.rect(ci, Rect2(base.x + bw * 0.5 - 14.0 * z, top + bh, 6.0 * z, 70.0 * z - bh), WOOD_DARK)
	var col: Color = Color("FFF8EC")
	var rim: Color = pal.get("accent", Palette.SUN)
	if dest == &"underworld":
		col = Color("2B1650")
		rim = Color("8BFFC2")
	var r := Rect2(base.x - bw * 0.5, top, bw, bh)
	U.rr(ci, Rect2(r.position + Vector2(0, 3.0 * z), r.size), 9.0 * z, Color(0.05, 0.08, 0.16, 0.28))
	U.rr(ci, r, 9.0 * z, col)
	U.rr_outline(ci, r, 9.0 * z, rim, 3.0 * z)
	var ink: Color = Palette.NAVY if dest != &"underworld" else Color("DFFFE9")
	U.text(ci, text, Vector2(base.x - tw * 0.5, top + bh * 0.5 + float(fs) * 0.34), fs, ink, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f)


static func _crate(ci: CanvasItem, base: Vector2, z: float, s: float, dest: StringName) -> void:
	var sz: float = 26.0 * z * s
	var c: Color = WOOD_LIGHT if dest != &"underworld" else Color("5A4A80")
	var r := Rect2(base.x - sz * 0.5, base.y - sz, sz, sz)
	U.rect(ci, r, c)
	U.rr_outline(ci, r, 2.0 * z, Palette.shade(c, 0.5), 2.0 * z)
	U.line(ci, r.position, r.end, Palette.shade(c, 0.4), 1.6 * z)
	U.line(ci, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Palette.shade(c, 0.4), 1.6 * z)


static func _kiosk(ci: CanvasItem, base: Vector2, z: float, pal: Dictionary) -> void:
	var w: float = 96.0 * z
	var h: float = 64.0 * z
	U.rect(ci, Rect2(base.x - w * 0.5, base.y - h, w, h), Color("FFFDF6"))
	U.rect(ci, Rect2(base.x - w * 0.5 + 6.0 * z, base.y - h * 0.62, w - 12.0 * z, h * 0.34), Color("BFEAFB"))
	# striped awning
	var n: int = 6
	for i in n:
		var c: Color = Palette.CORAL if i % 2 == 0 else Color("FFFDF6")
		var x: float = base.x - w * 0.56 + (w * 1.12) * float(i) / float(n)
		U.poly(ci, PackedVector2Array([Vector2(x, base.y - h - 4.0 * z), Vector2(x + w * 1.12 / float(n), base.y - h - 4.0 * z), Vector2(x + w * 1.12 / float(n) + 3.0 * z, base.y - h + 14.0 * z), Vector2(x + 3.0 * z, base.y - h + 14.0 * z)]), c)
	# potted palm
	var px: float = base.x + w * 0.7
	U.rr(ci, Rect2(px - 7.0 * z, base.y - 14.0 * z, 14.0 * z, 14.0 * z), 3.0 * z, Palette.CORAL_DARK)
	var top := Vector2(px + 2.0 * z, base.y - 52.0 * z)
	U.pline(ci, PackedVector2Array([Vector2(px, base.y - 14.0 * z), Vector2(px - 1.0 * z, base.y - 32.0 * z), top]), WOOD_DARK, 3.0 * z)
	for a in [-2.9, -2.2, -1.57, -0.9, -0.25]:
		var tip := top + Vector2(cos(a), sin(a) * 0.7) * 22.0 * z
		U.pline(ci, PackedVector2Array([top, top.lerp(tip, 0.5) + Vector2(0, -5.0 * z), tip]), Palette.MINT_DARK, 4.0 * z)


static func _sled(ci: CanvasItem, base: Vector2, z: float) -> void:
	U.rr(ci, Rect2(base.x - 44.0 * z, base.y - 8.0 * z, 88.0 * z, 6.0 * z), 3.0 * z, WOOD_DARK)
	U.pline(ci, PackedVector2Array([Vector2(base.x - 52.0 * z, base.y - 4.0 * z), Vector2(base.x - 44.0 * z, base.y)]), Palette.STEEL, 3.0 * z)
	U.rr(ci, Rect2(base.x - 36.0 * z, base.y - 30.0 * z, 34.0 * z, 22.0 * z), 4.0 * z, Palette.CORAL)
	U.rr(ci, Rect2(base.x + 2.0 * z, base.y - 24.0 * z, 28.0 * z, 16.0 * z), 4.0 * z, Palette.TEAL)
	U.ellipse(ci, Vector2(base.x - 18.0 * z, base.y - 31.0 * z), 18.0 * z, 5.0 * z, Color("F6F8FF"))
	U.ellipse(ci, Vector2(base.x + 16.0 * z, base.y - 25.0 * z), 14.0 * z, 4.0 * z, Color("F6F8FF"))


static func _cauldron(ci: CanvasItem, base: Vector2, z: float, anim: float, pal: Dictionary) -> void:
	var wisp: Color = pal["wisp"]
	U.ellipse(ci, Vector2(base.x, base.y - 20.0 * z), 26.0 * z, 22.0 * z, Palette.INK)
	U.rect(ci, Rect2(base.x - 30.0 * z, base.y - 34.0 * z, 60.0 * z, 6.0 * z), Palette.NAVY_LIGHT)
	U.ellipse(ci, Vector2(base.x, base.y - 33.0 * z), 26.0 * z, 5.0 * z, Palette.alpha(wisp, 0.9))
	for k in 4:
		var ph: float = fposmod(anim * 0.6 + float(k) * 0.25, 1.0)
		U.circ(ci, Vector2(base.x + sin(anim * 2.0 + float(k) * 2.0) * 9.0 * z, base.y - 36.0 * z - ph * 46.0 * z), (3.0 + 5.0 * (1.0 - ph)) * z, Palette.alpha(wisp, 0.5 * (1.0 - ph)))
	U.line(ci, Vector2(base.x - 18.0 * z, base.y - 4.0 * z), Vector2(base.x - 24.0 * z, base.y), Palette.INK, 4.0 * z)
	U.line(ci, Vector2(base.x + 18.0 * z, base.y - 4.0 * z), Vector2(base.x + 24.0 * z, base.y), Palette.INK, 4.0 * z)
