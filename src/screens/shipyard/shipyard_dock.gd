class_name ShipyardDock
extends Node2D
## The shipyard pier behind the Shipyard screen's hero ship: a wooden pier with bollards and barrels, a coral harbour crane
## swinging a perk crate over the stern, and a welder's sparks on the hull. Pure decoration, drawn in code.
##   setup(ship_left, ship_right, waterline_y, scale)   screen-space px; call again when the layout changes

const U := preload("res://src/render/art/art_util.gd")
const WOOD_TOP: Color = Color("D9A066")
const WOOD_FRONT: Color = Color("A56A3A")

var _left: float = 300.0
var _right: float = 1000.0
var _wl: float = 440.0
var _k: float = 0.55
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _sparks: Array[Dictionary] = []
var _spark_cd: float = 0.0


func _init() -> void:
	_rng.seed = 2468


func setup(ship_left: float, ship_right: float, waterline_y: float, ship_scale: float) -> void:
	_left = ship_left
	_right = ship_right
	_wl = waterline_y
	_k = ship_scale
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_spark_cd -= delta
	if _spark_cd <= 0.0:
		_spark_cd = _rng.randf_range(0.7, 1.6)
		var origin := Vector2(_left + (_right - _left) * 0.16, _wl - 34.0 * _k * 2.0)
		for i in range(9):
			var a: float = _rng.randf_range(-PI * 0.95, -PI * 0.05)
			_sparks.append({"p": origin, "v": Vector2(cos(a), sin(a)) * _rng.randf_range(60.0, 180.0), "age": 0.0, "life": _rng.randf_range(0.3, 0.7)})
	for s in _sparks:
		s["age"] = float(s["age"]) + delta
		s["v"] = (s["v"] as Vector2) + Vector2(0, 520.0) * delta
		s["p"] = (s["p"] as Vector2) + (s["v"] as Vector2) * delta
	_sparks = _sparks.filter(func(s: Dictionary) -> bool: return float(s["age"]) < float(s["life"]))
	queue_redraw()


func _draw() -> void:
	_draw_pier()
	_draw_crane()
	_draw_sparks()


func _draw_pier() -> void:
	var x1: float = _left + 40.0
	var top: float = _wl - 8.0
	# shadow on the water and the pier body
	U.rect(self, Rect2(-40.0, top + 40.0, x1 + 40.0, 12.0), Color(0.05, 0.1, 0.25, 0.18))
	U.rect(self, Rect2(-40.0, top, x1 + 40.0, 14.0), WOOD_TOP)
	U.rect(self, Rect2(-40.0, top + 14.0, x1 + 40.0, 40.0), WOOD_FRONT)
	var px: float = -30.0
	while px < x1:
		U.line(self, Vector2(px, top + 14.0), Vector2(px, top + 54.0), Color(0.3, 0.17, 0.08, 0.5), 3.0)
		px += 46.0
	var seam: float = -10.0
	while seam < x1:
		U.line(self, Vector2(seam, top + 1.0), Vector2(seam, top + 13.0), Color(0.55, 0.33, 0.15, 0.6), 2.0)
		seam += 34.0
	# bollards
	for bx in [x1 - 30.0, 180.0, 330.0 - 40.0]:
		if bx < 40.0 or bx > x1 - 8.0:
			continue
		U.rr(self, Rect2(bx - 9.0, top - 22.0, 18.0, 24.0), 6.0, Palette.NAVY)
		U.rr(self, Rect2(bx - 12.0, top - 28.0, 24.0, 10.0), 5.0, Palette.NAVY_LIGHT)
	# barrels
	for i in range(2):
		var bx2: float = 54.0 + float(i) * 52.0
		var by: float = top - 4.0
		U.rr(self, Rect2(bx2 - 18.0, by - 40.0, 36.0, 42.0), 10.0, Palette.CORAL_DARK)
		U.rr(self, Rect2(bx2 - 18.0, by - 36.0, 36.0, 34.0), 9.0, Palette.CORAL)
		U.rect(self, Rect2(bx2 - 18.0, by - 28.0, 36.0, 4.0), Palette.CORAL_DARK)
		U.rect(self, Rect2(bx2 - 18.0, by - 12.0, 36.0, 4.0), Palette.CORAL_DARK)


func _draw_crane() -> void:
	var base_x: float = _left - 110.0
	var base_y: float = _wl - 8.0
	var top_y: float = maxf(_wl - 310.0, 120.0)
	var w: float = 44.0
	var red: Color = Palette.CORAL
	var red_dark: Color = Palette.CORAL_DARK
	# tower: two tapered legs, cross braces
	for side in [-1.0, 1.0]:
		var bx: float = base_x + side * w * 0.62
		var tx: float = base_x + side * w * 0.36
		U.poly(self, PackedVector2Array([Vector2(bx - 6.0, base_y), Vector2(bx + 6.0, base_y), Vector2(tx + 4.0, top_y + 40.0), Vector2(tx - 4.0, top_y + 40.0)]), red)
	var n: int = 7
	for i in range(n):
		var f0: float = float(i) / float(n)
		var f1: float = float(i + 1) / float(n)
		var y0: float = lerpf(base_y, top_y + 40.0, f0)
		var y1: float = lerpf(base_y, top_y + 40.0, f1)
		var hw0: float = lerpf(w * 0.62, w * 0.36, f0)
		var hw1: float = lerpf(w * 0.62, w * 0.36, f1)
		U.line(self, Vector2(base_x - hw0, y0), Vector2(base_x + hw1, y1), Color.WHITE, 3.0)
		U.line(self, Vector2(base_x + hw0, y0), Vector2(base_x - hw1, y1), Color.WHITE, 3.0)
		U.line(self, Vector2(base_x - hw1, y1), Vector2(base_x + hw1, y1), red_dark, 3.0)
	U.rr(self, Rect2(base_x - w * 0.8, base_y - 14.0, w * 1.6, 18.0), 6.0, Palette.NAVY)
	# slewing cab
	U.rr(self, Rect2(base_x - 36.0, top_y + 6.0, 72.0, 46.0), 12.0, red_dark)
	U.rr(self, Rect2(base_x - 36.0, top_y + 4.0, 72.0, 44.0), 12.0, red)
	U.rr(self, Rect2(base_x + 2.0, top_y + 12.0, 26.0, 20.0), 6.0, Palette.GLASS)
	U.rect(self, Rect2(base_x + 6.0, top_y + 14.0, 6.0, 16.0), Color(1, 1, 1, 0.4))
	# jib (long arm to the right) and counter-jib with its weight
	var jib_y: float = top_y + 4.0
	var jib_end: float = base_x + (_left + (_right - _left) * 0.62 - base_x)
	U.poly(self, PackedVector2Array([Vector2(base_x - 100.0, jib_y), Vector2(jib_end, jib_y), Vector2(jib_end, jib_y + 8.0), Vector2(base_x - 100.0, jib_y + 8.0)]), red_dark)
	var seg: float = 34.0
	var jx: float = base_x - 96.0
	var up: bool = true
	while jx < jib_end - seg:
		var y_from: float = jib_y if up else jib_y - 30.0
		var y_to: float = jib_y - 30.0 if up else jib_y
		U.line(self, Vector2(jx, y_from), Vector2(jx + seg, y_to), Color.WHITE, 2.5)
		jx += seg
		up = not up
	U.line(self, Vector2(base_x - 100.0, jib_y - 30.0), Vector2(jib_end, jib_y - 30.0), red, 4.0)
	U.line(self, Vector2(base_x - 100.0, jib_y - 30.0), Vector2(base_x - 100.0, jib_y + 8.0), red, 4.0)
	U.rr(self, Rect2(base_x - 112.0, jib_y + 2.0, 42.0, 40.0), 6.0, Palette.STEEL_DARK)
	U.rr(self, Rect2(base_x - 112.0, jib_y, 42.0, 38.0), 6.0, Palette.STEEL)
	U.line(self, Vector2(base_x, top_y - 38.0), Vector2(base_x - 100.0, jib_y - 30.0), Color(1, 1, 1, 0.7), 2.0)
	U.line(self, Vector2(base_x, top_y - 38.0), Vector2(jib_end, jib_y - 30.0), Color(1, 1, 1, 0.7), 2.0)
	U.line(self, Vector2(base_x, top_y - 38.0), Vector2(base_x, jib_y - 30.0), red, 5.0)
	U.circ(self, Vector2(base_x, top_y - 40.0), 7.0, Palette.SUN)
	var blink: float = 0.5 + 0.5 * sin(_t * 4.0)
	U.circ(self, Vector2(base_x, top_y - 40.0), 12.0, Color(1.0, 0.8, 0.3, 0.25 * blink))
	# trolley, cable, hook and the swinging perk crate
	var span: float = jib_end - (base_x + 60.0)
	var trolley_x: float = base_x + 60.0 + span * (0.74 + 0.04 * sin(_t * 0.5))
	var sway: float = sin(_t * 1.3) * 0.07
	var drop: float = 130.0 + sin(_t * 0.9) * 8.0
	U.rr(self, Rect2(trolley_x - 14.0, jib_y + 6.0, 28.0, 14.0), 4.0, Palette.NAVY)
	var hook := Vector2(trolley_x + sin(sway) * drop, jib_y + 20.0 + cos(sway) * drop)
	U.line(self, Vector2(trolley_x, jib_y + 20.0), hook, Palette.NAVY, 2.5)
	U.circ(self, hook + Vector2(0, 4.0), 6.0, Palette.STEEL_DARK)
	var crate_c: Vector2 = hook + Vector2(0, 40.0)
	var prev := Transform2D.IDENTITY
	draw_set_transform(crate_c, -sway * 1.2, Vector2.ONE)
	U.rr(self, Rect2(-30.0, -26.0, 60.0, 56.0), 8.0, Palette.WOOD_DARK)
	U.rr(self, Rect2(-30.0, -28.0, 60.0, 54.0), 8.0, Palette.WOOD_LIGHT)
	U.rect(self, Rect2(-30.0, -4.0, 60.0, 8.0), Palette.CORAL)
	U.rect(self, Rect2(-4.0, -28.0, 8.0, 54.0), Palette.CORAL)
	U.line(self, Vector2(-30.0, -28.0), Vector2(30.0, 26.0), Color(0.45, 0.25, 0.1, 0.35), 3.0)
	U.star(self, Vector2(0.0, -1.0), 15.0, Palette.SUN_DEEP, 0.0, 0.5)
	U.star(self, Vector2(0.0, -2.0), 12.0, Palette.SUN, 0.0, 0.5)
	draw_set_transform_matrix(prev)
	U.line(self, hook + Vector2(0, 6.0), crate_c + Vector2(-26.0, -24.0).rotated(-sway * 1.2), Palette.NAVY, 2.0)
	U.line(self, hook + Vector2(0, 6.0), crate_c + Vector2(26.0, -24.0).rotated(-sway * 1.2), Palette.NAVY, 2.0)


func _draw_sparks() -> void:
	var origin := Vector2(_left + (_right - _left) * 0.16, _wl - 34.0 * _k * 2.0)
	var glow: float = 0.55 + 0.45 * sin(_t * 17.0) * sin(_t * 5.3)
	if _spark_cd > 0.9 or glow > 0.0:
		U.circ(self, origin, 13.0 + 4.0 * glow, Color(1.0, 0.9, 0.5, 0.25))
		U.circ(self, origin, 5.0 + 2.0 * glow, Color(1.0, 0.98, 0.85, 0.8))
	for s in _sparks:
		var f: float = float(s["age"]) / float(s["life"])
		var p: Vector2 = s["p"]
		var v: Vector2 = s["v"]
		U.line(self, p, p - v.normalized() * 8.0 * (1.0 - f), Color(1.0, 0.85 - 0.3 * f, 0.4, 1.0 - f), 2.5)
