class_name MenuLogo
extends Control
## Hand-built title logo: chunky "Cruise Ship" lettering (per-letter bounce, outline, lip shadow), a coral
## "MANAGER" ribbon with an anchor medallion and a ship's wheel, and rolling waves underneath.
##   intro_t: seconds since the intro began (drives the letters dropping in). Min size 840x340.

const U := preload("res://src/render/art/art_util.gd")
const LINE1: String = "Cruise Ship"
const LINE2: String = "MANAGER"
const NAVY_D: Color = Color("1F2A40")

var intro_t: float = 0.0
var _t: float = 0.0
var _font: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(840, 340)
	_font = UITheme.font_bold()


func _process(delta: float) -> void:
	_t += delta
	intro_t += delta
	queue_redraw()


func _letter_xs(text: String, px: int, x0: float) -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	for i in range(text.length()):
		xs.append(x0 + _font.get_string_size(text.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	return xs


func _draw() -> void:
	var px1: int = 136
	var w1: float = _font.get_string_size(LINE1, HORIZONTAL_ALIGNMENT_LEFT, -1, px1).x
	var x0: float = (size.x - w1) * 0.5
	var base_y: float = 156.0
	var xs := _letter_xs(LINE1, px1, x0)
	var n: int = LINE1.length()
	var ys := PackedFloat32Array()
	var al := PackedFloat32Array()
	for i in range(n):
		var p: float = clampf((intro_t - 0.06 * float(i)) / 0.6, 0.0, 1.0)
		var drop: float = (1.0 - U.ease_out_back(p)) * -170.0 if p < 1.0 else 0.0
		var bounce: float = sin(_t * 2.6 + float(i) * 0.65) * 4.5 * clampf(intro_t - 1.0, 0.0, 1.0)
		ys.append(base_y + drop + bounce)
		al.append(minf(p * 2.0, 1.0))
	# --- soft ground shadow
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# pass 1: outlines (with lip offset)
	for i in range(n):
		var ch: String = LINE1[i]
		if ch == " ":
			continue
		var pos := Vector2(xs[i], ys[i])
		_font_outline(ch, pos + Vector2(0, 14), px1, 26, Color(0.06, 0.09, 0.18, 0.32 * al[i]))
		_font_outline(ch, pos + Vector2(0, 10), px1, 24, Color(NAVY_D.r, NAVY_D.g, NAVY_D.b, al[i]))
		_font_outline(ch, pos, px1, 24, Color(NAVY_D.r, NAVY_D.g, NAVY_D.b, al[i]))
	# pass 2: lip + fill
	for i in range(n):
		var ch2: String = LINE1[i]
		if ch2 == " ":
			continue
		var pos2 := Vector2(xs[i], ys[i])
		var fill: Color = Color("FFF8EC") if i < 6 else Palette.SUN
		var lip: Color = Color("E3C7A0") if i < 6 else Palette.SUN_DEEP
		draw_string(_font, pos2 + Vector2(0, 10), ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, px1, Color(lip.r, lip.g, lip.b, al[i]))
		draw_string(_font, pos2, ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, px1, Color(fill.r, fill.g, fill.b, al[i]))
		# glossy highlight on the upper edge
		draw_string(_font, pos2 + Vector2(0, -3), ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, px1, Color(1, 1, 1, 0.16 * al[i]))
	# --- ribbon
	var rib_p: float = clampf((intro_t - 0.75) / 0.5, 0.0, 1.0)
	if rib_p > 0.0:
		_draw_ribbon(rib_p)
	# --- waves
	var wave_p: float = clampf((intro_t - 1.0) / 0.5, 0.0, 1.0)
	_draw_waves(wave_p)


func _font_outline(ch: String, pos: Vector2, px: int, outline: int, c: Color) -> void:
	draw_string_outline(_font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, outline, c)


func _draw_ribbon(p: float) -> void:
	var px2: int = 58
	var tw: float = 0.0
	var track: float = 9.0
	for i in range(LINE2.length()):
		tw += _font.get_string_size(LINE2[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px2).x + track
	tw -= track
	var rw: float = tw + 150.0
	var rh: float = 76.0
	var cx: float = size.x * 0.5
	var ry: float = 214.0 + (1.0 - U.ease_out_back(p)) * 60.0
	var rx: float = cx - rw * 0.5
	var sc: float = U.ease_out_back(p)
	draw_set_transform(Vector2(cx, ry + rh * 0.5), 0.0, Vector2(sc, sc))
	var o := Vector2(-cx, -(ry + rh * 0.5))
	# tails (darker folds)
	var coral_d: Color = Palette.CORAL_DARK
	var tail_l := PackedVector2Array([Vector2(rx - 6, ry + 14) + o, Vector2(rx - 52, ry + 14) + o, Vector2(rx - 34, ry + rh * 0.5 + 14) + o, Vector2(rx - 52, ry + rh + 14) + o, Vector2(rx - 6, ry + rh + 14) + o])
	var tail_r := PackedVector2Array([Vector2(rx + rw + 6, ry + 14) + o, Vector2(rx + rw + 52, ry + 14) + o, Vector2(rx + rw + 34, ry + rh * 0.5 + 14) + o, Vector2(rx + rw + 52, ry + rh + 14) + o, Vector2(rx + rw + 6, ry + rh + 14) + o])
	U.poly(self, tail_l, Color(coral_d.r * 0.85, coral_d.g * 0.85, coral_d.b * 0.85, 1.0))
	U.poly(self, tail_r, Color(coral_d.r * 0.85, coral_d.g * 0.85, coral_d.b * 0.85, 1.0))
	# shadow + body
	U.rr(self, Rect2(rx - 2 + o.x, ry + 10 + o.y, rw + 4, rh + 6), 16, Color(0.06, 0.09, 0.18, 0.3))
	U.rr(self, Rect2(rx - 4 + o.x, ry - 4 + o.y, rw + 8, rh + 8), 18, NAVY_D)
	U.rr(self, Rect2(rx + o.x, ry + 6 + o.y, rw, rh), 15, coral_d)
	U.rr(self, Rect2(rx + o.x, ry + o.y, rw, rh), 15, Palette.CORAL)
	U.rr(self, Rect2(rx + 8 + o.x, ry + 6 + o.y, rw - 16, 12), 6, Color(1, 1, 1, 0.22))
	# stitching
	for i in range(14):
		var sx: float = rx + 24.0 + float(i) * (rw - 48.0) / 13.0
		U.rr(self, Rect2(sx + o.x, ry + rh - 11 + o.y, 9, 3), 1.5, Color(1, 1, 1, 0.45))
	# letters
	var lx: float = cx - tw * 0.5
	for i in range(LINE2.length()):
		var ch: String = LINE2[i]
		var cw: float = _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px2).x
		var pos := Vector2(lx + o.x, ry + rh * 0.5 + 21.0 + o.y + sin(_t * 3.0 + float(i) * 0.8) * 1.8)
		_font_outline(ch, pos + Vector2(0, 3), px2, 11, Color(0.45, 0.12, 0.18, 0.9))
		draw_string(_font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px2, Color.WHITE)
		lx += cw + track
	# medallions
	_anchor_medal(Vector2(rx - 6 + o.x, ry + rh * 0.5 + o.y), 44.0)
	_wheel_medal(Vector2(rx + rw + 6 + o.x, ry + rh * 0.5 + o.y), 44.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _anchor_medal(c: Vector2, r: float) -> void:
	U.circ(self, c + Vector2(0, 6), r + 6, Color(0.06, 0.09, 0.18, 0.3))
	U.circ(self, c, r + 5, NAVY_D)
	U.circ(self, c, r, Palette.SUN_DEEP)
	U.circ(self, c + Vector2(0, -2), r - 3, Palette.SUN)
	U.circ(self, c, r - 11, Color("FFF3CE"))
	var sw: float = sin(_t * 1.6) * 0.14
	var k: float = r - 12.0
	var col: Color = NAVY_D
	var tilt := Transform2D(sw, Vector2.ONE, 0.0, c)
	var pt := func(v: Vector2) -> Vector2: return tilt * v
	U.arc(self, pt.call(Vector2(0, -0.62 * k)), 0.2 * k, 0.0, TAU, col, 0.13 * k + 1.5, 16)
	U.line(self, pt.call(Vector2(0, -0.42 * k)), pt.call(Vector2(0, 0.72 * k)), col, 0.17 * k + 1.0)
	U.line(self, pt.call(Vector2(-0.36 * k, -0.2 * k)), pt.call(Vector2(0.36 * k, -0.2 * k)), col, 0.15 * k + 1.0)
	var pts := PackedVector2Array()
	for i in range(0, 13):
		var a: float = lerpf(0.18, PI - 0.18, float(i) / 12.0)
		pts.append(pt.call(Vector2(cos(a) * 0.66 * k, 0.12 * k + sin(a) * 0.62 * k)))
	U.pline(self, pts, col, 0.17 * k + 1.0)
	U.circ(self, pt.call(Vector2(-0.66 * k * cos(0.18), 0.12 * k + sin(0.18) * 0.62 * k)) , 0.11 * k + 1.0, col)
	U.circ(self, pt.call(Vector2(0.66 * k * cos(0.18), 0.12 * k + sin(0.18) * 0.62 * k)), 0.11 * k + 1.0, col)


func _wheel_medal(c: Vector2, r: float) -> void:
	U.circ(self, c + Vector2(0, 6), r + 6, Color(0.06, 0.09, 0.18, 0.3))
	U.circ(self, c, r + 5, NAVY_D)
	U.circ(self, c, r, Palette.TEAL_DARK)
	U.circ(self, c + Vector2(0, -2), r - 3, Palette.TEAL)
	var rot: float = _t * 0.5
	var wr: float = r - 11.0
	for i in range(8):
		var a: float = rot + float(i) * TAU / 8.0
		var d := Vector2(cos(a), sin(a))
		U.line(self, c + d * 5.0, c + d * (wr + 4.0), Color("FFF3CE"), 4.0)
		U.circ(self, c + d * (wr + 4.0), 3.6, Color("FFF3CE"))
	U.arc(self, c, wr * 0.78, 0.0, TAU, Color("FFF3CE"), 4.5, 24)
	U.circ(self, c, 7.0, Palette.SUN)


func _draw_waves(p: float) -> void:
	if p <= 0.0:
		return
	var y0: float = 318.0
	var w: float = size.x
	for k in range(3):
		var pts := PackedVector2Array()
		var amp: float = 7.0 - float(k) * 1.5
		var x: float = 120.0 + float(k) * 34.0
		var x_end: float = w - 120.0 - float(k) * 34.0
		var steps: int = 40
		for i in range(steps + 1):
			var xx: float = lerpf(x, x_end, float(i) / float(steps))
			pts.append(Vector2(xx, y0 + float(k) * 10.0 + sin(xx * 0.03 + _t * (1.8 + float(k) * 0.3) + float(k)) * amp))
		var col: Color = Palette.TEAL_LIGHT if k != 1 else Color("EAF9FF")
		U.pline(self, pts, Color(col.r, col.g, col.b, 0.85 * p), 5.0 - float(k))
