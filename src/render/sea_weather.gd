class_name SeaWeather
extends RefCounted
## Storm art for SeaBackground (docs/SPEC.md §13.7): sky gloom + a dark cloud bank, slanted rain (two depths), splashes on the water,
## jagged lightning bolts and the white flash. Stateless drawing helpers; the sea owns the clocks and the lightning schedule.
## Everything scales with `storm` (0..1 = SimWorld.weather_intensity), so the storm rolls in and out smoothly. Cute, not grim:
## round soft clouds, chunky rain streaks, a flash that is brief and never pure white.

const U := preload("res://src/render/art/art_util.gd")

## Per-destination storm look: overlay (sky gloom), cloud / cloud shade, rain streak colour, bolt colour.
const LOOKS: Dictionary = {
	&"med": {"gloom": Color(0.20, 0.25, 0.36), "cloud": Color(0.43, 0.48, 0.60), "shade": Color(0.28, 0.33, 0.45),
			"rain": Color(0.86, 0.93, 1.0), "bolt": Color(1.0, 0.97, 0.78), "tint": Color(0.66, 0.72, 0.84)},
	&"arctic": {"gloom": Color(0.30, 0.33, 0.46), "cloud": Color(0.62, 0.65, 0.80), "shade": Color(0.44, 0.47, 0.64),
			"rain": Color(0.95, 0.97, 1.0), "bolt": Color(0.9, 0.96, 1.0), "tint": Color(0.76, 0.80, 0.92)},
	&"underworld": {"gloom": Color(0.09, 0.03, 0.17), "cloud": Color(0.40, 0.20, 0.50), "shade": Color(0.23, 0.09, 0.32),
			"rain": Color(0.84, 0.74, 1.0), "bolt": Color(0.78, 1.0, 0.86), "tint": Color(0.82, 0.74, 0.92)},
}

const RAIN_BACK: int = 150
const RAIN_FRONT: int = 46
const CLOUDS: int = 9


static func look(dest: StringName) -> Dictionary:
	return LOOKS.get(dest, LOOKS[&"med"])


## Colour the whole sea node is multiplied with: 1 in calm weather, the destination's gloomy tint at full storm.
static func tint(dest: StringName, storm: float) -> Color:
	return Color.WHITE.lerp(look(dest)["tint"], clampf(storm, 0.0, 1.0))


## Grey-blue gloom over the sky and the far scenery, then a bank of big dark clouds scrolling past (`scroll` = the sea's clock).
static func draw_sky(ci: CanvasItem, w: float, hy: float, storm: float, dest: StringName, anim: float, scroll: float) -> void:
	if storm <= 0.001:
		return
	var lk: Dictionary = look(dest)
	var g: Color = lk["gloom"]
	U.vgrad(ci, Rect2(0, -4, w, hy + 14.0), Color(g.r, g.g, g.b, 0.78 * storm), Color(g.r, g.g, g.b, 0.42 * storm))
	var c: Color = lk["cloud"]
	var sh: Color = lk["shade"]
	var span: float = w + 700.0
	for i in CLOUDS:
		var k: float = float(i)
		var sx: float = U.hash01(i * 31 + 7)
		var sy: float = U.hash01(i * 17 + 3)
		var sz: float = 2.3 + 1.9 * U.hash01(i * 13 + 5)
		var speed: float = 16.0 + 14.0 * U.hash01(i * 19 + 11)
		var x: float = fposmod(sx * span - scroll * speed - anim * 6.0, span) - 350.0
		var y: float = lerpf(18.0, maxf(hy * 0.62, 90.0), sy) + sin(anim * 0.35 + k) * 3.0
		var cc: Color = Color(c.r, c.g, c.b, minf(storm * 1.25, 1.0))
		var ss: Color = Color(sh.r, sh.g, sh.b, minf(storm * 1.25, 1.0))
		_cloud(ci, x, y, sz, cc, ss)
	# a heavy low band right above the horizon so the sea meets the storm
	U.vgrad(ci, Rect2(0, hy - 90.0, w, 92.0), Color(g.r, g.g, g.b, 0.0), Color(g.r, g.g, g.b, 0.5 * storm))


static func _cloud(ci: CanvasItem, x: float, y: float, s: float, c: Color, shade: Color) -> void:
	var cw: float = 120.0 * s
	var ch: float = 34.0 * s * 0.95
	U.rr(ci, Rect2(x - cw * 0.5, y + ch * 0.2 + 4.0 * s, cw, ch * 0.5), ch * 0.25, shade)
	U.rr(ci, Rect2(x - cw * 0.5, y, cw, ch * 0.66), ch * 0.33, c)
	U.circ(ci, Vector2(x - cw * 0.22, y + ch * 0.02), ch * 0.6, c)
	U.circ(ci, Vector2(x + cw * 0.04, y - ch * 0.3), ch * 0.8, c)
	U.circ(ci, Vector2(x + cw * 0.3, y + ch * 0.06), ch * 0.5, c)
	U.circ(ci, Vector2(x + cw * 0.04, y - ch * 0.05), ch * 0.7, Color(shade.r, shade.g, shade.b, shade.a * 0.35))


## Rain streaks. `front` = the bigger, brighter, faster layer drawn over the ship. Arctic gets chunky sleet dots as well.
static func draw_rain(ci: CanvasItem, w: float, h: float, storm: float, dest: StringName, anim: float, front: bool) -> void:
	if storm <= 0.02:
		return
	var rc: Color = look(dest)["rain"]
	var n: int = RAIN_FRONT if front else RAIN_BACK
	var count: int = int(ceil(float(n) * clampf(storm, 0.0, 1.0)))
	var pts := PackedVector2Array()
	var slope: float = 0.26
	for i in count:
		var sx: float = U.hash01(i * 7 + (301 if front else 11))
		var sy: float = U.hash01(i * 13 + (17 if front else 5))
		var sp: float = (1250.0 if front else 880.0) * (0.75 + 0.5 * U.hash01(i * 3 + 1))
		var ln: float = (44.0 if front else 26.0) * (0.7 + 0.6 * U.hash01(i * 5 + 2))
		var y: float = fposmod(sy * (h + 120.0) + anim * sp, h + 120.0) - 60.0
		var x: float = fposmod(sx * (w + 200.0) - y * slope * 0.0 - anim * sp * slope, w + 200.0) - 100.0
		pts.append(Vector2(x, y))
		pts.append(Vector2(x - ln * slope, y + ln))
	var width: float = 3.4 if front else 2.0
	var a: float = (0.46 if front else 0.34) * minf(storm * 1.4, 1.0)
	ci.draw_multiline(pts, Color(rc.r, rc.g, rc.b, a), width, true)
	if dest == &"arctic":
		var dots := 18 if front else 40
		for i in int(float(dots) * storm):
			var dx: float = fposmod(U.hash01(i * 23 + 9) * (w + 100.0) - anim * 260.0 + sin(anim * 1.3 + float(i)) * 18.0, w + 100.0) - 50.0
			var dy: float = fposmod(U.hash01(i * 29 + 4) * (h + 80.0) + anim * (300.0 if front else 200.0), h + 80.0) - 40.0
			U.circ(ci, Vector2(dx, dy), 4.2 if front else 2.6, Color(1, 1, 1, 0.9 * minf(storm, 1.0)))


## Little rings where the rain hits the water between the horizon-side swell and the bottom of the screen.
static func draw_splashes(ci: CanvasItem, w: float, y0: float, y1: float, storm: float, anim: float, dest: StringName) -> void:
	if storm <= 0.05:
		return
	var rc: Color = look(dest)["rain"]
	var n: int = int(34.0 * storm)
	for i in n:
		var ph: float = fposmod(anim * (0.9 + 0.5 * U.hash01(i * 7)) + U.hash01(i * 3), 1.0)
		var x: float = U.hash01(i * 11 + 2) * w
		var yf: float = U.hash01(i * 5 + 8)
		var y: float = lerpf(y0, y1, yf * yf)
		var sc: float = 0.5 + yf
		var r: float = (3.0 + 11.0 * ph) * sc
		var a: float = (1.0 - ph) * 0.55 * minf(storm * 1.3, 1.0)
		ci.draw_arc(Vector2(x, y), r, PI * 1.05, PI * 1.95, 8, Color(rc.r, rc.g, rc.b, a), 1.8 * sc, true)
		ci.draw_arc(Vector2(x, y + 1.5 * sc), r * 0.55, PI * 1.05, PI * 1.95, 6, Color(rc.r, rc.g, rc.b, a * 0.7), 1.4 * sc, true)


## A jagged bolt from the clouds towards the horizon. `pts` are screen points (SeaBackground builds them when it fires),
## `a` is the fade 0..1.
static func draw_bolt(ci: CanvasItem, pts: PackedVector2Array, branch: PackedVector2Array, a: float, dest: StringName) -> void:
	if pts.size() < 2 or a <= 0.01:
		return
	var bc: Color = look(dest)["bolt"]
	U.pline(ci, pts, Color(bc.r, bc.g, bc.b, 0.16 * a), 20.0)
	U.pline(ci, pts, Color(bc.r, bc.g, bc.b, 0.5 * a), 8.0)
	U.pline(ci, pts, Color(1, 1, 1, a), 3.2)
	if branch.size() >= 2:
		U.pline(ci, branch, Color(bc.r, bc.g, bc.b, 0.45 * a), 5.0)
		U.pline(ci, branch, Color(1, 1, 1, 0.9 * a), 2.2)


## Builds a jagged bolt polyline from (x, y0) down to y1 (deterministic from `seed_v`) plus a short side branch.
static func make_bolt(x: float, y0: float, y1: float, seed_v: int, branch_out: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cur := Vector2(x, y0)
	pts.append(cur)
	var steps: int = 9
	var branch_at: int = 3 + int(U.hash01(seed_v) * 3.0)
	for i in steps:
		var f: float = float(i + 1) / float(steps)
		var jitter: float = (U.hash01(seed_v * 7 + i * 13) - 0.5) * 86.0 * (1.0 - f * 0.4)
		cur = Vector2(x + jitter + (U.hash01(seed_v + 5) - 0.5) * 120.0 * f, lerpf(y0, y1, f))
		pts.append(cur)
		if i == branch_at:
			var br := PackedVector2Array()
			var sgn: float = 1.0 if U.hash01(seed_v + 9) > 0.5 else -1.0
			br.append(cur)
			br.append(cur + Vector2(sgn * 38.0, 34.0))
			br.append(cur + Vector2(sgn * 22.0, 70.0))
			br.append(cur + Vector2(sgn * 58.0, 104.0))
			branch_out.append(br)
	return pts


## Full-screen flash. Soft blue-white, capped well below pure white so it reads as lightning, not a glitch.
static func draw_flash(ci: CanvasItem, w: float, h: float, flash: float, dest: StringName) -> void:
	if flash <= 0.01:
		return
	var bc: Color = look(dest)["bolt"]
	var c: Color = Color(0.86, 0.9, 1.0).lerp(bc, 0.35)
	ci.draw_rect(Rect2(0, 0, w, h), Color(c.r, c.g, c.b, 0.38 * flash))
