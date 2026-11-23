class_name IconArt
extends RefCounted
## Flat vector icons drawn in code. Every icon is drawn in a unit space (radius 1 = size/2) around `center`.
##
## API
##   IconArt.draw_icon(ci, icon: StringName, center: Vector2, size: float, t := 0.0, colorblind := false)
##       icon ids: mess breakdown sick angry ghost coin star star_empty heart smile meh frown
##                 need_rest need_hunger need_fun need_hygiene power water wrench mop clock
##                 pause play fast faster lock warning guest staff event
##   IconArt.draw_room_icon(ci, room_id: StringName, center: Vector2, size: float)   # white glyph on a coloured badge
##   IconArt.draw_bubble(ci, anchor: Vector2, icon: StringName, t := 1.0, alpha := 1.0, k := 1.0,
##                       colorblind := false, problem := false)
##       mood bubble whose tail tip is `anchor` (just above a guest's head). t = seconds since it appeared
##       (pop-in over 0.25 s), alpha 0..1 for fading out, k = size counter-scale, problem = "needs you" styling.
##   IconArt.ICONS: Array[StringName]   all icon ids      IconArt.ROOM_ICONS: Array[StringName]  all room ids
##   IconArt.room_badge_color(room_id) -> Color

const U := preload("res://src/render/art/art_util.gd")

const ICONS: Array[StringName] = [
	&"mess", &"breakdown", &"sick", &"angry", &"ghost", &"coin", &"star", &"star_empty", &"heart",
	&"smile", &"meh", &"frown", &"need_rest", &"need_hunger", &"need_fun", &"need_hygiene", &"power",
	&"water", &"wrench", &"mop", &"clock", &"pause", &"play", &"fast", &"faster", &"lock", &"warning",
	&"guest", &"staff", &"event",
]
const ROOM_ICONS: Array[StringName] = [
	&"cabin", &"buffet", &"toilets", &"bar", &"pool", &"deck_chairs", &"cinema", &"gym", &"arcade",
	&"restaurant", &"medbay", &"sauna", &"ice_rink", &"casino", &"stairs", &"elevator", &"generator",
	&"water_tank",
]

const _BADGE: Dictionary = {
	&"cabin": Color("6C8CD5"), &"buffet": Color("F58A3C"), &"toilets": Color("3AA0C8"),
	&"bar": Color("D9548F"), &"pool": Color("2FA3CC"), &"deck_chairs": Color("F2A93B"),
	&"cinema": Color("7B63B5"), &"gym": Color("4DB583"), &"arcade": Color("E8505B"),
	&"restaurant": Color("C0415A"), &"medbay": Color("FFFFFF"), &"sauna": Color("C9803E"),
	&"ice_rink": Color("5BB4E8"), &"casino": Color("6A4BA8"), &"stairs": Color("8A9BB5"),
	&"elevator": Color("6F7E96"), &"generator": Color("F2A93B"), &"water_tank": Color("3AA0C8"),
}

static var _cache: Dictionary = {}


static func room_badge_color(room_id: StringName) -> Color:
	return _BADGE.get(room_id, Palette.TEAL)


# ---- cached shapes (unit space) -----------------------------------------------------------------
static func _gear(teeth: int, r_out: float, r_in: float) -> PackedVector2Array:
	var key := "gear%d_%d_%d" % [teeth, int(r_out * 100), int(r_in * 100)]
	if _cache.has(key):
		return _cache[key]
	var p := PackedVector2Array()
	var step := TAU / float(teeth)
	for i in range(teeth):
		var a := float(i) * step
		p.append(Vector2(cos(a - step * 0.22), sin(a - step * 0.22)) * r_in)
		p.append(Vector2(cos(a - step * 0.13), sin(a - step * 0.13)) * r_out)
		p.append(Vector2(cos(a + step * 0.13), sin(a + step * 0.13)) * r_out)
		p.append(Vector2(cos(a + step * 0.22), sin(a + step * 0.22)) * r_in)
	_cache[key] = p
	return p


static func _burst(points: int, r_out: float, r_in: float) -> PackedVector2Array:
	var key := "burst%d_%d" % [points, int(r_in * 100)]
	if _cache.has(key):
		return _cache[key]
	var p := PackedVector2Array()
	for i in range(points * 2):
		var a := -PI * 0.5 + float(i) * PI / float(points)
		var wob := 1.0 + 0.12 * sin(float(i) * 2.7)
		var r := (r_out * wob) if i % 2 == 0 else r_in
		p.append(Vector2(cos(a), sin(a)) * r)
	_cache[key] = p
	return p


static func _heart() -> PackedVector2Array:
	if _cache.has("heart"):
		return _cache["heart"]
	var p := PackedVector2Array()
	for i in range(40):
		var a := TAU * float(i) / 40.0
		var x := 16.0 * pow(sin(a), 3.0)
		var y := -(13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a))
		p.append(Vector2(x, y + 1.5) / 17.0)
	_cache["heart"] = p
	return p


static func _drop() -> PackedVector2Array:
	if _cache.has("drop"):
		return _cache["drop"]
	var p := PackedVector2Array()
	p.append(Vector2(0.0, -1.0))
	var cy := 0.22
	var r := 0.74
	var a0 := deg_to_rad(52.0)
	var a1 := deg_to_rad(308.0)
	for i in range(21):
		var a := lerpf(a0, a1, float(i) / 20.0)
		p.append(Vector2(r * sin(a), cy - r * cos(a)))
	_cache["drop"] = p
	return p


static func _splat() -> PackedVector2Array:
	if _cache.has("splat"):
		return _cache["splat"]
	var p := PackedVector2Array()
	for i in range(36):
		var a := TAU * float(i) / 36.0
		var r := 0.62 + 0.17 * sin(3.0 * a + 1.0) + 0.1 * sin(5.0 * a + 2.0) + 0.07 * sin(7.0 * a)
		p.append(Vector2(cos(a) * r * 1.2, sin(a) * r * 0.82 + 0.12))
	_cache["splat"] = p
	return p


static func _bolt() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.15, -1.0), Vector2(0.65, -1.0), Vector2(0.22, -0.2), Vector2(0.58, -0.2),
		Vector2(-0.25, 1.0), Vector2(-0.08, 0.15), Vector2(-0.52, 0.15)])


static func _ghost_body() -> PackedVector2Array:
	if _cache.has("ghost"):
		return _cache["ghost"]
	var p := PackedVector2Array()
	for i in range(21):
		var a := PI + PI * float(i) / 20.0
		p.append(Vector2(cos(a) * 0.62, -0.18 + sin(a) * 0.72))
	# wavy bottom going right -> left
	var bottom_y := 0.82
	p.append(Vector2(0.62, bottom_y - 0.05))
	for i in range(1, 12):
		var x := 0.62 - 1.24 * float(i) / 11.0
		p.append(Vector2(x, bottom_y + 0.12 * sin(float(i) / 11.0 * TAU * 1.5 + 1.0)))
	_cache["ghost"] = p
	return p


# ---- helpers ------------------------------------------------------------------------------------
static func _hl(ci: CanvasItem, pos: Vector2, rx: float, ry: float, a: float = 0.45) -> void:
	U.ellipse(ci, pos, rx, ry, Color(1, 1, 1, a))


static func _ol(cb: bool) -> Color:
	return Palette.INK


static func _spiral(ci: CanvasItem, c: Vector2, r_max: float, turns: float, col: Color, w: float, rot: float) -> void:
	var pts := PackedVector2Array()
	var n := 18
	for i in range(n + 1):
		var f := float(i) / float(n)
		var a := rot + f * TAU * turns
		pts.append(c + Vector2(cos(a), sin(a)) * r_max * f)
	U.pline(ci, pts, col, w)


# ---- public -------------------------------------------------------------------------------------
static func draw_icon(ci: CanvasItem, icon: StringName, center: Vector2, size: float, t: float = 0.0, colorblind: bool = false) -> void:
	var s := size * 0.5
	U.xf(ci, center, 0.0, Vector2(s, s))
	match icon:
		&"mess": _mess(ci, colorblind)
		&"breakdown": _breakdown(ci, t, colorblind)
		&"sick": _sick(ci, t, colorblind)
		&"angry": _angry(ci, t, colorblind)
		&"ghost": _ghost(ci, t, colorblind)
		&"coin": _coin(ci)
		&"star": _star(ci, true)
		&"star_empty": _star(ci, false)
		&"heart": _heart_icon(ci)
		&"smile": _face(ci, 0)
		&"meh": _face(ci, 1)
		&"frown": _face(ci, 2)
		&"need_rest": _need_rest(ci)
		&"need_hunger": _need_hunger(ci)
		&"need_fun": _need_fun(ci)
		&"need_hygiene": _need_hygiene(ci)
		&"power": _power(ci)
		&"water": _water(ci)
		&"wrench": _wrench(ci)
		&"mop": _mop(ci)
		&"clock": _clock(ci, t)
		&"pause": _glyph_pause(ci)
		&"play": _glyph_play(ci)
		&"fast": _glyph_fast(ci, 2)
		&"faster": _glyph_fast(ci, 3)
		&"lock": _lock(ci)
		&"warning": _warning(ci)
		&"guest": _guest(ci)
		&"staff": _staff(ci)
		&"event": _event(ci)
		_:
			U.circ(ci, Vector2.ZERO, 0.8, Palette.STEEL)
			U.circ(ci, Vector2.ZERO, 0.4, Palette.CREAM)
	U.xf_end(ci)


## Mood bubble. `anchor` = tail tip. t = seconds since the bubble appeared.
##   k            screen-size counter scale (renderer passes ~1/zoom^0.7); the tail tip stays on `anchor`.
##   colorblind   high-contrast palette for the icon (angry / sick) and the problem outline.
##   problem      true = a "needs you" bubble (angry / sick): tinted disc + coloured outline. Ambient mood
##                bubbles (hungry, happy, ...) stay plain cream so problems read first.
static func draw_bubble(ci: CanvasItem, anchor: Vector2, icon: StringName, t: float = 1.0, alpha: float = 1.0,
		k: float = 1.0, colorblind: bool = false, problem: bool = false) -> void:
	var pop := U.ease_out_back(clampf(t / 0.28, 0.0, 1.0)) * k
	if pop <= 0.01 or alpha <= 0.01:
		return
	var old_alpha := U.alpha
	U.alpha = old_alpha * alpha
	var bob := sin(t * 3.2) * 1.2 * k
	U.xf(ci, anchor + Vector2(0, bob), 0.0, Vector2(pop, pop))
	var cy := -21.0
	var fill: Color = Palette.CREAM
	if problem:
		var edge: Color = Palette.alert_color(colorblind)
		fill = Color("FFF0EC") if not colorblind else Color.WHITE
		U.circ(ci, Vector2(0, cy), 17.6, edge)
		U.poly(ci, PackedVector2Array([Vector2(-7.2, cy + 10.5), Vector2(7.2, cy + 10.5), Vector2(0, 1.4)]), edge)
	U.circ(ci, Vector2(0, cy + 2.0), 15.5, Color(0.12, 0.18, 0.32, 0.18))
	U.poly(ci, PackedVector2Array([Vector2(-5.5, cy + 10.0), Vector2(5.5, cy + 10.0), Vector2(0, -0.5)]), Color(0.12, 0.18, 0.32, 0.18))
	U.poly(ci, PackedVector2Array([Vector2(-5.0, cy + 9.0), Vector2(5.0, cy + 9.0), Vector2(0, -2.0)]), fill)
	U.circ(ci, Vector2(0, cy), 15.0, fill)
	U.circ(ci, Vector2(-4.0, cy - 5.0), 6.0, Color(1, 1, 1, 0.55))
	U.xf_end(ci)
	draw_icon(ci, icon, anchor + Vector2(0, bob + cy * pop), 21.0 * pop, t, colorblind)
	U.alpha = old_alpha


# ---- problem icons ------------------------------------------------------------------------------
static func _mess(ci: CanvasItem, cb: bool) -> void:
	var c := Palette.problem_color(&"mess", cb)
	var sp := _splat()
	U.poly_xf(ci, sp, Vector2(0.04, 0.1), 0.0, Vector2(1.0, 1.0), Palette.shade(c, 0.35))
	U.poly(ci, sp, c)
	U.circ(ci, Vector2(-0.72, -0.5), 0.14, c)
	U.circ(ci, Vector2(0.7, -0.42), 0.11, c)
	U.circ(ci, Vector2(0.08, -0.78), 0.09, c)
	var b1 := Color.WHITE if cb else Palette.TEAL
	var b2 := Color("D8EEFF") if cb else Palette.TEAL_LIGHT
	U.circ(ci, Vector2(-0.22, 0.02), 0.2, b1)
	U.circ(ci, Vector2(0.3, 0.2), 0.13, b2)
	U.circ(ci, Vector2(-0.28, -0.04), 0.07, Color(1, 1, 1, 0.8))
	_hl(ci, Vector2(-0.45, -0.18), 0.2, 0.09, 0.3)
	if cb:
		U.pline(ci, _closed(sp), _ol(cb), 0.07)


static func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	q.append(p[0])
	return q


static func _breakdown(ci: CanvasItem, t: float, cb: bool) -> void:
	var c := Palette.problem_color(&"breakdown", cb)
	var g := _gear(8, 1.0, 0.78)
	U.poly_xf(ci, g, Vector2(0.03, 0.06), t * 0.6, Vector2.ONE, Palette.shade(c, 0.4))
	U.poly_xf(ci, g, Vector2.ZERO, t * 0.6, Vector2.ONE, c)
	U.circ(ci, Vector2.ZERO, 0.52, Palette.shade(c, 0.45))
	U.circ(ci, Vector2.ZERO, 0.46, Palette.tint(c, 0.25))
	var bolt := _bolt()
	U.poly_xf(ci, bolt, Vector2(0.02, 0.03), 0.0, Vector2(0.4, 0.42), Palette.INK)
	U.poly_xf(ci, bolt, Vector2.ZERO, 0.0, Vector2(0.4, 0.42), Color.WHITE if cb else Palette.SUN)
	if cb:
		U.pline(ci, _closed(_gear(8, 1.0, 0.78)), _ol(cb), 0.07)


static func _sick(ci: CanvasItem, t: float, cb: bool) -> void:
	var c := Palette.problem_color(&"sick", cb)
	var d := _drop()
	U.poly_xf(ci, d, Vector2(0.04, 0.05), 0.0, Vector2.ONE, Palette.shade(c, 0.4))
	U.poly(ci, d, c)
	_hl(ci, Vector2(-0.34, 0.0), 0.1, 0.22, 0.45)
	var sc := Color.BLACK if cb else Color(0.12, 0.45, 0.3)
	_spiral(ci, Vector2(0.05, 0.24), 0.42, 2.1, sc, 0.12, t * 3.0)
	if cb:
		U.pline(ci, _closed(d), _ol(cb), 0.08)


static func _angry(ci: CanvasItem, t: float, cb: bool) -> void:
	var c := Palette.problem_color(&"angry", cb)
	var k := 1.0 + 0.04 * sin(t * 9.0)
	var b := _burst(10, 1.0, 0.64)
	U.poly_xf(ci, b, Vector2(0.03, 0.05), 0.0, Vector2(k, k), Palette.shade(c, 0.4))
	U.poly_xf(ci, b, Vector2.ZERO, 0.0, Vector2(k, k), c)
	var f := Color.WHITE if not cb else Color.WHITE
	U.line(ci, Vector2(-0.42, -0.3), Vector2(-0.08, -0.12), f, 0.15)
	U.line(ci, Vector2(0.42, -0.3), Vector2(0.08, -0.12), f, 0.15)
	U.circ(ci, Vector2(-0.24, 0.0), 0.1, f)
	U.circ(ci, Vector2(0.24, 0.0), 0.1, f)
	U.arc(ci, Vector2(0, 0.52), 0.28, PI + 0.5, TAU - 0.5, f, 0.15, 10)


static func _ghost(ci: CanvasItem, t: float, cb: bool) -> void:
	var c := Palette.problem_color(&"ghost", cb)
	var yb := sin(t * 3.0) * 0.05
	var prev := U.xf_push(ci, Vector2(0, yb), 0.0, Vector2.ONE)
	var gb := _ghost_body()
	U.poly(ci, gb, Palette.shade(c, 0.25) if not cb else c)
	U.poly_xf(ci, gb, Vector2(-0.03, -0.03), 0.0, Vector2(0.95, 0.95), c if not cb else Color("56B4E9").lightened(0.4))
	U.pline(ci, _closed(gb), Palette.LILAC_DARK if not cb else Color.BLACK, 0.07)
	U.ellipse(ci, Vector2(-0.22, -0.2), 0.1, 0.15, Palette.INK)
	U.ellipse(ci, Vector2(0.22, -0.2), 0.1, 0.15, Palette.INK)
	U.ellipse(ci, Vector2(0.0, 0.12), 0.1, 0.13, Palette.INK)
	U.circ(ci, Vector2(-0.4, 0.02), 0.09, Color(1.0, 0.65, 0.75, 0.6))
	U.circ(ci, Vector2(0.4, 0.02), 0.09, Color(1.0, 0.65, 0.75, 0.6))
	U.xf_load(ci, prev)


static func _coin(ci: CanvasItem) -> void:
	U.circ(ci, Vector2(0.03, 0.06), 0.96, Palette.shade(Palette.SUN_DEEP, 0.3))
	U.circ(ci, Vector2.ZERO, 0.95, Palette.SUN_DEEP)
	U.circ(ci, Vector2.ZERO, 0.8, Palette.SUN)
	U.arc(ci, Vector2.ZERO, 0.62, 0.0, TAU, Palette.SUN_DEEP, 0.08, 24)
	U.star(ci, Vector2(0, 0.02), 0.42, Palette.SUN_DEEP, 0.0, 0.5)
	U.star(ci, Vector2(0, -0.02), 0.38, Palette.tint(Palette.SUN, 0.5), 0.0, 0.5)
	_hl(ci, Vector2(-0.4, -0.52), 0.22, 0.09, 0.55)


static func _star(ci: CanvasItem, filled: bool) -> void:
	if filled:
		U.star(ci, Vector2(0.03, 0.08), 1.0, Palette.SUN_DEEP, 0.0, 0.5)
		U.star(ci, Vector2.ZERO, 0.97, Palette.SUN, 0.0, 0.5)
		U.star(ci, Vector2(-0.08, -0.12), 0.45, Palette.tint(Palette.SUN, 0.55), 0.0, 0.5)
	else:
		U.star(ci, Vector2(0, 0.04), 0.97, Color(0.12, 0.18, 0.32, 0.12), 0.0, 0.5)
		U.star(ci, Vector2.ZERO, 0.97, Color("E9DEC8"), 0.0, 0.5)
		U.star(ci, Vector2.ZERO, 0.72, Color("F7F0E2"), 0.0, 0.5)


static func _heart_icon(ci: CanvasItem) -> void:
	var h := _heart()
	U.poly_xf(ci, h, Vector2(0.03, 0.06), 0.0, Vector2(1.0, 1.0), Color("C93759"))
	U.poly(ci, h, Color("FF5C7A"))
	_hl(ci, Vector2(-0.4, -0.38), 0.2, 0.1, 0.55)


static func _face(ci: CanvasItem, kind: int) -> void:
	var base: Color = [Palette.SUN, Color("FFB88C"), Color("9CB8F2")][kind]
	var dark: Color = Palette.shade(base, 0.4)
	U.circ(ci, Vector2(0.03, 0.06), 0.97, dark)
	U.circ(ci, Vector2.ZERO, 0.95, base)
	_hl(ci, Vector2(-0.38, -0.5), 0.3, 0.12, 0.45)
	var ink := Palette.INK
	if kind == 0:
		U.ellipse(ci, Vector2(-0.33, -0.15), 0.1, 0.14, ink)
		U.ellipse(ci, Vector2(0.33, -0.15), 0.1, 0.14, ink)
		U.arc(ci, Vector2(0, 0.08), 0.5, 0.35, PI - 0.35, ink, 0.13, 12)
		U.circ(ci, Vector2(-0.6, 0.15), 0.12, Color(1.0, 0.5, 0.55, 0.6))
		U.circ(ci, Vector2(0.6, 0.15), 0.12, Color(1.0, 0.5, 0.55, 0.6))
	elif kind == 1:
		U.circ(ci, Vector2(-0.33, -0.1), 0.1, ink)
		U.circ(ci, Vector2(0.33, -0.1), 0.1, ink)
		U.line(ci, Vector2(-0.46, -0.28), Vector2(-0.2, -0.28), dark, 0.1)
		U.line(ci, Vector2(0.2, -0.28), Vector2(0.46, -0.28), dark, 0.1)
		U.line(ci, Vector2(-0.34, 0.45), Vector2(0.34, 0.45), ink, 0.13)
	else:
		U.ellipse(ci, Vector2(-0.33, -0.15), 0.1, 0.14, ink)
		U.ellipse(ci, Vector2(0.33, -0.15), 0.1, 0.14, ink)
		U.line(ci, Vector2(-0.48, -0.38), Vector2(-0.18, -0.3), ink, 0.09)
		U.line(ci, Vector2(0.48, -0.38), Vector2(0.18, -0.3), ink, 0.09)
		U.arc(ci, Vector2(0, 0.68), 0.4, PI + 0.4, TAU - 0.4, ink, 0.13, 12)
		var tear := _drop()
		U.poly_xf(ci, tear, Vector2(0.52, 0.18), 0.0, Vector2(0.16, 0.2), Palette.TEAL_LIGHT)


# ---- needs --------------------------------------------------------------------------------------
static func _need_rest(ci: CanvasItem) -> void:
	# crescent moon + two z
	var c := Palette.LILAC
	if not _cache.has("crescent"):
		var outer := PackedVector2Array()
		var cut := PackedVector2Array()
		for i in range(40):
			var a := TAU * float(i) / 40.0
			outer.append(Vector2(-0.1, 0.1) + Vector2(cos(a), sin(a)) * 0.78)
			cut.append(Vector2(0.22, -0.14) + Vector2(cos(a), sin(a)) * 0.64)
		_cache["crescent"] = Geometry2D.clip_polygons(outer, cut)
	var res: Array = _cache["crescent"]
	for poly in res:
		U.poly(ci, poly, c)
	# z letters
	var zc := Palette.LILAC_DARK
	U.pline(ci, PackedVector2Array([Vector2(0.28, -0.1), Vector2(0.62, -0.1), Vector2(0.28, 0.28), Vector2(0.64, 0.28)]), zc, 0.14)
	U.pline(ci, PackedVector2Array([Vector2(0.52, -0.72), Vector2(0.78, -0.72), Vector2(0.52, -0.44), Vector2(0.8, -0.44)]), zc, 0.11)


static func _need_hunger(ci: CanvasItem) -> void:
	# drumstick
	var rot := -0.6
	var prev := U.xf_push(ci, Vector2.ZERO, rot, Vector2.ONE * 0.98)
	U.capsule(ci, Vector2(-0.05, 0.0), Vector2(0.78, 0.0), 0.12, Color("F4E6CF"))
	U.circ(ci, Vector2(0.84, -0.12), 0.13, Color("F4E6CF"))
	U.circ(ci, Vector2(0.84, 0.12), 0.13, Color("F4E6CF"))
	U.ellipse(ci, Vector2(-0.38, 0.0), 0.56, 0.5, Palette.shade(Color("D9783A"), 0.3))
	U.ellipse(ci, Vector2(-0.4, -0.03), 0.55, 0.48, Color("E98B45"))
	_hl(ci, Vector2(-0.5, -0.24), 0.28, 0.1, 0.4)
	U.xf_load(ci, prev)


static func _need_fun(ci: CanvasItem) -> void:
	# balloon
	U.pline(ci, PackedVector2Array([Vector2(0, 0.62), Vector2(0.12, 0.78), Vector2(-0.1, 0.9), Vector2(0.06, 1.0)]), Palette.STEEL_DARK, 0.06)
	U.poly(ci, PackedVector2Array([Vector2(0, 0.5), Vector2(-0.13, 0.7), Vector2(0.13, 0.7)]), Color("C93759"))
	U.ellipse(ci, Vector2(0.03, -0.26), 0.62, 0.72, Color("C93759"))
	U.ellipse(ci, Vector2.ZERO + Vector2(0, -0.3), 0.6, 0.7, Color("FF5C8A"))
	_hl(ci, Vector2(-0.24, -0.55), 0.14, 0.24, 0.55)


static func _need_hygiene(ci: CanvasItem) -> void:
	# bubbles
	U.circ(ci, Vector2(-0.18, 0.2), 0.58, Palette.TEAL_DARK)
	U.circ(ci, Vector2(-0.2, 0.18), 0.56, Palette.TEAL)
	U.circ(ci, Vector2(0.5, -0.35), 0.38, Palette.TEAL_DARK)
	U.circ(ci, Vector2(0.49, -0.37), 0.36, Palette.TEAL_LIGHT)
	U.circ(ci, Vector2(-0.35, -0.58), 0.22, Palette.TEAL_LIGHT)
	_hl(ci, Vector2(-0.38, 0.0), 0.16, 0.26, 0.6)
	_hl(ci, Vector2(0.38, -0.5), 0.1, 0.14, 0.7)
	U.star(ci, Vector2(0.62, 0.42), 0.2, Color.WHITE, 0.0, 0.4)


# ---- utilities ----------------------------------------------------------------------------------
static func _power(ci: CanvasItem) -> void:
	var b := _bolt()
	U.poly_xf(ci, b, Vector2(0.05, 0.06), 0.0, Vector2(0.95, 0.98), Palette.SUN_DEEP)
	U.poly_xf(ci, b, Vector2.ZERO, 0.0, Vector2(0.95, 0.98), Palette.SUN)
	_hl(ci, Vector2(0.28, -0.7), 0.1, 0.16, 0.5)


static func _water(ci: CanvasItem) -> void:
	var d := _drop()
	U.poly_xf(ci, d, Vector2(0.04, 0.05), 0.0, Vector2.ONE, Palette.SEA_DEEP)
	U.poly(ci, d, Color("3AA0F0"))
	U.poly_xf(ci, d, Vector2(0.0, 0.3), 0.0, Vector2(0.7, 0.55), Color("2F86E0"))
	_hl(ci, Vector2(-0.34, 0.1), 0.1, 0.24, 0.6)


static func _wrench(ci: CanvasItem) -> void:
	var prev := U.xf_push(ci, Vector2.ZERO, -PI * 0.25, Vector2.ONE)
	U.capsule(ci, Vector2(-0.2, 0.0), Vector2(0.78, 0.0), 0.17, Palette.shade(Palette.STEEL, 0.25))
	U.capsule(ci, Vector2(-0.2, -0.03), Vector2(0.78, -0.03), 0.14, Palette.STEEL)
	U.arc(ci, Vector2(-0.58, 0.0), 0.3, PI + 0.55, PI + TAU - 0.55, Palette.shade(Palette.STEEL, 0.25), 0.36, 14)
	U.arc(ci, Vector2(-0.58, -0.02), 0.3, PI + 0.55, PI + TAU - 0.55, Palette.STEEL, 0.32, 14)
	U.circ(ci, Vector2(0.76, 0.0), 0.06, Palette.NAVY)
	U.xf_load(ci, prev)


static func _mop(ci: CanvasItem) -> void:
	var prev := U.xf_push(ci, Vector2.ZERO, PI * 0.2, Vector2.ONE)
	U.capsule(ci, Vector2(0.0, -0.95), Vector2(0.0, 0.2), 0.08, Palette.WOOD)
	# head
	U.poly(ci, PackedVector2Array([Vector2(-0.3, 0.2), Vector2(0.3, 0.2), Vector2(0.55, 0.95), Vector2(-0.55, 0.95)]), Palette.shade(Palette.TEAL, 0.2))
	for i in range(5):
		var x := -0.45 + float(i) * 0.225
		U.capsule(ci, Vector2(x * 0.7, 0.25), Vector2(x, 0.92), 0.09, Palette.TEAL_LIGHT if i % 2 == 0 else Color.WHITE)
	U.capsule(ci, Vector2(-0.3, 0.18), Vector2(0.3, 0.18), 0.08, Palette.STEEL)
	U.xf_load(ci, prev)


static func _clock(ci: CanvasItem, t: float) -> void:
	U.circ(ci, Vector2(0.03, 0.05), 0.96, Color(0.12, 0.18, 0.32, 0.2))
	U.circ(ci, Vector2.ZERO, 0.95, Palette.NAVY)
	U.circ(ci, Vector2.ZERO, 0.78, Palette.CREAM)
	for i in range(4):
		var a := float(i) * PI * 0.5
		U.line(ci, Vector2(cos(a), sin(a)) * 0.6, Vector2(cos(a), sin(a)) * 0.7, Palette.NAVY, 0.09)
	var ma := t * 1.2 - PI * 0.5
	U.line(ci, Vector2.ZERO, Vector2(cos(ma), sin(ma)) * 0.58, Palette.CORAL, 0.1)
	var ha := t * 0.1 + 0.9
	U.line(ci, Vector2.ZERO, Vector2(cos(ha), sin(ha)) * 0.38, Palette.NAVY, 0.14)
	U.circ(ci, Vector2.ZERO, 0.09, Palette.NAVY)


# ---- UI glyphs (cream with navy shadow so they read on both light and dark) --------------------
static func _glyph_pause(ci: CanvasItem) -> void:
	for pass_i in range(2):
		var off := Vector2(0.04, 0.08) if pass_i == 0 else Vector2.ZERO
		var c := Color(0.17, 0.23, 0.33, 0.9) if pass_i == 0 else Palette.CREAM
		U.capsule(ci, Vector2(-0.38, -0.55) + off, Vector2(-0.38, 0.55) + off, 0.2, c)
		U.capsule(ci, Vector2(0.38, -0.55) + off, Vector2(0.38, 0.55) + off, 0.2, c)


static func _tri(ci: CanvasItem, x0: float, w: float, h: float, c: Color, off: Vector2) -> void:
	var p := PackedVector2Array([Vector2(x0, -h) + off, Vector2(x0 + w, 0.0) + off, Vector2(x0, h) + off])
	U.poly(ci, p, c)
	U.pline(ci, PackedVector2Array([p[0], p[1], p[2], p[0]]), c, 0.16)


static func _glyph_play(ci: CanvasItem) -> void:
	_tri(ci, -0.4, 0.95, 0.62, Color(0.17, 0.23, 0.33, 0.9), Vector2(0.04, 0.08))
	_tri(ci, -0.4, 0.95, 0.62, Palette.CREAM, Vector2.ZERO)


static func _glyph_fast(ci: CanvasItem, n: int) -> void:
	var step := 0.56 if n == 2 else 0.44
	var w := 0.62 if n == 2 else 0.5
	var x0 := -0.5 - (float(n - 2) * 0.12) if n == 2 else -0.7
	for pass_i in range(2):
		var off := Vector2(0.04, 0.08) if pass_i == 0 else Vector2.ZERO
		var c := Color(0.17, 0.23, 0.33, 0.9) if pass_i == 0 else Palette.CREAM
		for i in range(n):
			_tri(ci, x0 + float(i) * step, w, 0.5, c, off)


static func _lock(ci: CanvasItem) -> void:
	U.arc(ci, Vector2(0, -0.2), 0.4, PI, TAU, Palette.STEEL_DARK, 0.2, 14)
	U.line(ci, Vector2(-0.4, -0.2), Vector2(-0.4, 0.05), Palette.STEEL_DARK, 0.2)
	U.line(ci, Vector2(0.4, -0.2), Vector2(0.4, 0.05), Palette.STEEL_DARK, 0.2)
	U.rbox(ci, Rect2(-0.68, -0.02, 1.36, 1.0), 0.2, Palette.SUN_DEEP)
	U.rbox(ci, Rect2(-0.68, -0.05, 1.36, 0.9), 0.2, Palette.SUN)
	U.circ(ci, Vector2(0, 0.35), 0.15, Palette.INK)
	U.poly(ci, PackedVector2Array([Vector2(-0.07, 0.4), Vector2(0.07, 0.4), Vector2(0.1, 0.7), Vector2(-0.1, 0.7)]), Palette.INK)


static func _warning(ci: CanvasItem) -> void:
	var tri := PackedVector2Array()
	var pts := [Vector2(0, -0.92), Vector2(0.98, 0.75), Vector2(-0.98, 0.75)]
	for i in range(3):
		tri.append(pts[i])
	var rounded := U.chaikin(U.chaikin(tri, true), true)
	U.poly_xf(ci, rounded, Vector2(0.03, 0.06), 0.0, Vector2.ONE, Palette.SUN_DEEP)
	U.poly(ci, rounded, Palette.SUN)
	U.capsule(ci, Vector2(0, -0.35), Vector2(0, 0.2), 0.09, Palette.INK)
	U.circ(ci, Vector2(0, 0.48), 0.11, Palette.INK)


static func _guest(ci: CanvasItem) -> void:
	U.capsule(ci, Vector2(0, -0.1), Vector2(0, 0.55), 0.5, Palette.shade(Palette.CORAL, 0.3))
	U.capsule(ci, Vector2(0, -0.12), Vector2(0, 0.52), 0.46, Palette.CORAL_LIGHT)
	U.circ(ci, Vector2(-0.16, 0.05), 0.07, Palette.INK)
	U.circ(ci, Vector2(0.16, 0.05), 0.07, Palette.INK)
	_hl(ci, Vector2(-0.22, -0.3), 0.12, 0.2, 0.4)
	U.ellipse(ci, Vector2(-0.2, 0.98), 0.17, 0.1, Palette.CORAL_DARK)
	U.ellipse(ci, Vector2(0.2, 0.98), 0.17, 0.1, Palette.CORAL_DARK)


static func _staff(ci: CanvasItem) -> void:
	U.capsule(ci, Vector2(0, -0.05), Vector2(0, 0.55), 0.5, Palette.NAVY_DARK)
	U.capsule(ci, Vector2(0, -0.07), Vector2(0, 0.52), 0.46, Palette.NAVY_LIGHT)
	U.circ(ci, Vector2(-0.16, 0.1), 0.07, Color.WHITE)
	U.circ(ci, Vector2(0.16, 0.1), 0.07, Color.WHITE)
	# yellow hard hat
	U.poly(ci, PackedVector2Array([Vector2(-0.52, -0.2), Vector2(-0.4, -0.62), Vector2(0, -0.8), Vector2(0.4, -0.62), Vector2(0.52, -0.2)]), Palette.SUN_DEEP)
	U.poly(ci, PackedVector2Array([Vector2(-0.46, -0.24), Vector2(-0.36, -0.6), Vector2(0, -0.74), Vector2(0.36, -0.6), Vector2(0.46, -0.24)]), Palette.SUN)
	U.rbox(ci, Rect2(-0.62, -0.26, 1.24, 0.12), 0.05, Palette.SUN_DEEP)
	U.ellipse(ci, Vector2(-0.2, 0.98), 0.17, 0.1, Palette.NAVY_DARK)
	U.ellipse(ci, Vector2(0.2, 0.98), 0.17, 0.1, Palette.NAVY_DARK)


static func _event(ci: CanvasItem) -> void:
	# megaphone
	var cone := PackedVector2Array([Vector2(-0.7, -0.22), Vector2(0.12, -0.7), Vector2(0.12, 0.7), Vector2(-0.7, 0.22)])
	U.poly_xf(ci, cone, Vector2(0.03, 0.05), 0.0, Vector2.ONE, Palette.CORAL_DARK)
	U.poly(ci, cone, Palette.CORAL)
	U.rbox(ci, Rect2(-0.88, -0.28, 0.32, 0.56), 0.1, Palette.NAVY)
	U.rbox(ci, Rect2(0.05, -0.76, 0.2, 1.52), 0.1, Palette.CORAL_DARK)
	U.capsule(ci, Vector2(-0.45, 0.25), Vector2(-0.4, 0.8), 0.13, Palette.NAVY)
	U.arc(ci, Vector2(0.18, 0), 0.5, -0.7, 0.7, Palette.SUN, 0.1, 8)
	U.arc(ci, Vector2(0.18, 0), 0.78, -0.6, 0.6, Palette.SUN, 0.1, 8)


# ================================================================================================
# Room icons: white glyph on a coloured round badge
# ================================================================================================
static func draw_room_icon(ci: CanvasItem, room_id: StringName, center: Vector2, size: float) -> void:
	var s := size * 0.5
	var bc := room_badge_color(room_id)
	U.xf(ci, center, 0.0, Vector2(s, s))
	U.circ(ci, Vector2(0.03, 0.07), 1.0, Color(0.1, 0.15, 0.3, 0.25))
	U.circ(ci, Vector2.ZERO, 1.0, Palette.shade(bc, 0.3))
	U.circ(ci, Vector2(0.0, -0.05), 0.94, bc)
	U.circ(ci, Vector2(-0.3, -0.45), 0.34, Color(1, 1, 1, 0.16))
	var g := Palette.CREAM if room_id != &"medbay" else Palette.CORAL
	if room_id == &"medbay":
		U.circ(ci, Vector2(0.0, -0.05), 0.94, Palette.CREAM)
	match room_id:
		&"cabin":
			U.rbox(ci, Rect2(-0.62, 0.0, 1.24, 0.3), 0.08, g)
			U.rbox(ci, Rect2(-0.62, -0.5, 0.16, 0.9), 0.06, g)
			U.rbox(ci, Rect2(-0.36, -0.22, 0.4, 0.2), 0.1, g)
			U.rbox(ci, Rect2(0.05, -0.12, 0.57, 0.14), 0.07, g)
			U.rbox(ci, Rect2(0.5, 0.3, 0.12, 0.2), 0.03, g)
		&"buffet":
			U.arc(ci, Vector2(0, 0.2), 0.55, PI, TAU, g, 0.2, 14)
			U.rbox(ci, Rect2(-0.68, 0.18, 1.36, 0.16), 0.06, g)
			U.circ(ci, Vector2(0, -0.45), 0.1, g)
			U.rbox(ci, Rect2(-0.5, 0.42, 1.0, 0.1), 0.05, g)
		&"toilets":
			U.rbox(ci, Rect2(-0.5, -0.62, 0.38, 0.6), 0.08, g)
			U.poly(ci, PackedVector2Array([Vector2(-0.5, -0.02), Vector2(0.62, -0.02), Vector2(0.5, 0.35), Vector2(0.2, 0.5), Vector2(-0.18, 0.5), Vector2(-0.18, 0.2), Vector2(-0.5, 0.2)]), g)
			U.rbox(ci, Rect2(-0.2, 0.5, 0.42, 0.18), 0.05, g)
		&"bar":
			U.poly(ci, PackedVector2Array([Vector2(-0.62, -0.5), Vector2(0.62, -0.5), Vector2(0.0, 0.2)]), g)
			U.line(ci, Vector2(0, 0.15), Vector2(0, 0.6), g, 0.14)
			U.line(ci, Vector2(-0.32, 0.64), Vector2(0.32, 0.64), g, 0.14)
			U.line(ci, Vector2(0.18, -0.15), Vector2(0.5, -0.75), g, 0.08)
			U.circ(ci, Vector2(0.52, -0.15), 0.1, Palette.SUN)
		&"pool":
			for i in range(3):
				var y := -0.35 + float(i) * 0.38
				var pts := PackedVector2Array()
				for k in range(13):
					var x := -0.65 + 1.3 * float(k) / 12.0
					pts.append(Vector2(x, y + sin(float(k) / 12.0 * TAU * 1.5) * 0.1))
				U.pline(ci, pts, g, 0.13)
		&"deck_chairs":
			U.line(ci, Vector2(-0.6, 0.35), Vector2(-0.45, -0.35), g, 0.16)
			U.line(ci, Vector2(-0.6, 0.35), Vector2(0.3, 0.35), g, 0.16)
			U.line(ci, Vector2(0.3, 0.35), Vector2(0.62, 0.0), g, 0.14)
			U.line(ci, Vector2(-0.35, 0.35), Vector2(-0.35, 0.68), g, 0.1)
			U.line(ci, Vector2(0.3, 0.35), Vector2(0.4, 0.68), g, 0.1)
			U.circ(ci, Vector2(0.3, -0.45), 0.17, g)
		&"cinema":
			U.rbox(ci, Rect2(-0.62, -0.1, 1.24, 0.75), 0.08, g)
			U.poly(ci, PackedVector2Array([Vector2(-0.64, -0.2), Vector2(0.55, -0.62), Vector2(0.62, -0.38), Vector2(-0.58, 0.02)]), g)
			for i in range(3):
				var x := -0.42 + float(i) * 0.38
				U.poly(ci, PackedVector2Array([Vector2(x, -0.1), Vector2(x + 0.14, -0.4), Vector2(x + 0.26, -0.44), Vector2(x + 0.12, -0.1)]), bc)
		&"gym":
			U.line(ci, Vector2(-0.6, 0), Vector2(0.6, 0), g, 0.14)
			U.rbox(ci, Rect2(-0.72, -0.4, 0.2, 0.8), 0.07, g)
			U.rbox(ci, Rect2(-0.46, -0.3, 0.16, 0.6), 0.06, g)
			U.rbox(ci, Rect2(0.52, -0.4, 0.2, 0.8), 0.07, g)
			U.rbox(ci, Rect2(0.3, -0.3, 0.16, 0.6), 0.06, g)
		&"arcade":
			U.circ(ci, Vector2(-0.1, -0.42), 0.22, g)
			U.line(ci, Vector2(-0.1, -0.3), Vector2(-0.1, 0.15), g, 0.14)
			U.rbox(ci, Rect2(-0.62, 0.1, 1.24, 0.5), 0.15, g)
			U.circ(ci, Vector2(0.28, 0.35), 0.09, bc)
			U.circ(ci, Vector2(0.48, 0.35), 0.09, bc)
		&"restaurant":
			U.line(ci, Vector2(-0.32, -0.6), Vector2(-0.32, 0.65), g, 0.14)
			for dx in [-0.5, -0.32, -0.14]:
				U.line(ci, Vector2(dx, -0.62), Vector2(dx, -0.2), g, 0.07)
			U.poly(ci, PackedVector2Array([Vector2(0.32, -0.62), Vector2(0.52, -0.5), Vector2(0.52, 0.0), Vector2(0.32, 0.0)]), g)
			U.line(ci, Vector2(0.4, -0.1), Vector2(0.4, 0.65), g, 0.14)
		&"medbay":
			U.rbox(ci, Rect2(-0.18, -0.6, 0.36, 1.2), 0.08, g)
			U.rbox(ci, Rect2(-0.6, -0.18, 1.2, 0.36), 0.08, g)
		&"sauna":
			for i in range(3):
				var x := -0.38 + float(i) * 0.38
				var pts := PackedVector2Array()
				for k in range(9):
					var y := 0.1 - 0.8 * float(k) / 8.0
					pts.append(Vector2(x + sin(float(k) / 8.0 * TAU * 1.2 + float(i)) * 0.1, y))
				U.pline(ci, pts, g, 0.12)
			U.rbox(ci, Rect2(-0.62, 0.3, 1.24, 0.2), 0.08, g)
		&"ice_rink":
			U.poly(ci, PackedVector2Array([Vector2(-0.3, -0.62), Vector2(0.05, -0.62), Vector2(0.08, 0.1), Vector2(0.6, 0.25), Vector2(0.6, 0.45), Vector2(-0.5, 0.45), Vector2(-0.5, 0.1)]), g)
			U.line(ci, Vector2(-0.6, 0.62), Vector2(0.68, 0.62), g, 0.1)
		&"casino":
			var prev := U.xf_push(ci, Vector2.ZERO, 0.25, Vector2.ONE)
			U.rbox(ci, Rect2(-0.55, -0.55, 1.1, 1.1), 0.2, g)
			for p in [Vector2(-0.28, -0.28), Vector2(0.28, -0.28), Vector2(0, 0), Vector2(-0.28, 0.28), Vector2(0.28, 0.28)]:
				U.circ(ci, p, 0.11, bc)
			U.xf_load(ci, prev)
		&"stairs":
			U.poly(ci, PackedVector2Array([Vector2(-0.65, 0.55), Vector2(-0.65, 0.2), Vector2(-0.25, 0.2), Vector2(-0.25, -0.15), Vector2(0.15, -0.15), Vector2(0.15, -0.5), Vector2(0.6, -0.5), Vector2(0.6, 0.55)]), g)
		&"elevator":
			U.rbox_outline(ci, Rect2(-0.6, -0.65, 1.2, 1.3), 0.12, g, 0.12)
			U.poly(ci, PackedVector2Array([Vector2(-0.3, -0.05), Vector2(0.0, -0.4), Vector2(0.3, -0.05)]), g)
			U.poly(ci, PackedVector2Array([Vector2(-0.3, 0.1), Vector2(0.0, 0.45), Vector2(0.3, 0.1)]), g)
		&"generator":
			U.poly(ci, _bolt(), g)
		&"water_tank":
			var d := _drop()
			U.poly_xf(ci, d, Vector2(0, 0.05), 0.0, Vector2(0.75, 0.78), g)
		_:
			U.circ(ci, Vector2.ZERO, 0.4, g)
	U.xf_end(ci)
