class_name FxArt
extends RefCounted
## One-shot particle-ish effects. t01 = normalised effect age 0..1 (the caller owns the timing and frees
## the effect after t01 >= 1).
##
## API
##   FxArt.draw_puff(ci, pos, t01)                    # white dust/cleaning puff
##   FxArt.draw_sparkle(ci, pos, t01, color)          # 4-point twinkle (repair done)
##   FxArt.draw_spark(ci, pos, t01)                   # electric spark burst (breakdown)
##   FxArt.draw_float_text(ci, pos, text, color, t01, font := null)   # "+$9" rising text
##   FxArt.draw_hearts(ci, pos, t01) / draw_stars(ci, pos, t01)       # happy-use particles
##   FxArt.draw_coin_pop(ci, pos, t01)                # coin hop
##   FxArt.draw_pop_ring(ci, pos, t01, color, r := 20) # badge "pop": expanding ring + flung dots (spill cleaned / fixed)
##   FxArt.draw_star_burst(ci, pos, t01, color)        # 7 little stars flung out with a bit of gravity

const U := preload("res://src/render/art/art_util.gd")


static func draw_puff(ci: CanvasItem, pos: Vector2, t01: float) -> void:
	var k := clampf(t01, 0.0, 1.0)
	var a := 1.0 - k
	for i in range(6):
		var ang := float(i) * TAU / 6.0 + 0.4
		var d := 4.0 + k * 13.0
		var p := pos + Vector2(cos(ang) * d, sin(ang) * d * 0.6 - k * 5.0)
		var r := (3.0 + float(i % 3)) * (0.5 + k * 1.3)
		U.circ(ci, p + Vector2(0.8, 1.0), r, Color(0.6, 0.7, 0.9, 0.3 * a))
		U.circ(ci, p, r, Color(1, 1, 1, 0.85 * a))
	U.circ(ci, pos + Vector2(0.0, -k * 4.0), 5.0 * (0.6 + k), Color(1, 1, 1, 0.6 * a))


static func draw_sparkle(ci: CanvasItem, pos: Vector2, t01: float, color: Color) -> void:
	var k := clampf(t01, 0.0, 1.0)
	var s := sin(k * PI)
	var r := 3.0 + 9.0 * s
	var c := Color(color.r, color.g, color.b, 0.95 * s)
	# four-point star
	var p := PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(r * 0.25, -r * 0.25), pos + Vector2(r, 0), pos + Vector2(r * 0.25, r * 0.25), pos + Vector2(0, r), pos + Vector2(-r * 0.25, r * 0.25), pos + Vector2(-r, 0), pos + Vector2(-r * 0.25, -r * 0.25)])
	U.poly(ci, p, c)
	U.circ(ci, pos, r * 0.3, Color(1, 1, 1, s))
	for i in range(3):
		var ang := float(i) * TAU / 3.0 + k * 2.0
		var d := r * (1.2 + k)
		U.circ(ci, pos + Vector2(cos(ang), sin(ang)) * d, 1.2 * (1.0 - k) + 0.3, Color(c.r, c.g, c.b, 0.8 * (1.0 - k)))


static func draw_spark(ci: CanvasItem, pos: Vector2, t01: float) -> void:
	var k := clampf(t01, 0.0, 1.0)
	var a := 1.0 - k
	U.circ(ci, pos, 8.0 * (1.0 - k) + 2.0, Color(1.0, 0.9, 0.4, 0.35 * a))
	for i in range(6):
		var ang := float(i) * TAU / 6.0 + U.hash01(i * 7) * 1.5
		var d1 := 3.0 + k * 14.0
		var p0 := pos + Vector2(cos(ang), sin(ang)) * d1
		var mid := pos + Vector2(cos(ang + 0.5), sin(ang + 0.5)) * (d1 + 4.0)
		var p1 := pos + Vector2(cos(ang - 0.2), sin(ang - 0.2)) * (d1 + 8.0)
		U.pline(ci, PackedVector2Array([p0, mid, p1]), Color(1.0, 0.85, 0.25, a), 1.8)
	U.circ(ci, pos, 2.2 * a + 0.4, Color(1, 1, 0.9, a))


static func draw_float_text(ci: CanvasItem, pos: Vector2, text: String, color: Color, t01: float, font: Font = null) -> void:
	var k := clampf(t01, 0.0, 1.0)
	var rise := U.smooth(k) * 30.0
	var a := 1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4
	var pop := U.ease_out_back(clampf(k / 0.18, 0.0, 1.0))
	var sz := int(round(18.0 * (0.6 + 0.4 * pop)))
	var f := font if font != null else U.font_bold()
	var p := pos + Vector2(0.0, -rise)
	var wdt := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var o := Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, a * 0.9)
	ci.draw_string_outline(f, p + Vector2(-wdt * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, U.col(o))
	ci.draw_string(f, p + Vector2(-wdt * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, U.col(Color(color.r, color.g, color.b, a)))


static func draw_hearts(ci: CanvasItem, pos: Vector2, t01: float) -> void:
	var k := clampf(t01, 0.0, 1.0)
	for i in range(3):
		var off := float(i) - 1.0
		var kk := clampf(k * 1.2 - float(i) * 0.1, 0.0, 1.0)
		var p := pos + Vector2(off * 8.0 + sin(kk * 5.0 + float(i)) * 2.0, -kk * 22.0)
		var s := 3.0 + 2.0 * sin(kk * PI)
		IconArt.draw_icon(ci, &"heart", p, s * 2.0)


static func draw_stars(ci: CanvasItem, pos: Vector2, t01: float) -> void:
	var k := clampf(t01, 0.0, 1.0)
	for i in range(4):
		var ang := float(i) * TAU / 4.0 + 0.6
		var d := 4.0 + k * 16.0
		var p := pos + Vector2(cos(ang) * d, sin(ang) * d * 0.8 - k * 6.0)
		U.star(ci, p, 3.4 * (1.0 - k * 0.6), Color(Palette.SUN.r, Palette.SUN.g, Palette.SUN.b, 1.0 - k), k * 4.0)


static func draw_coin_pop(ci: CanvasItem, pos: Vector2, t01: float) -> void:
	var k := clampf(t01, 0.0, 1.0)
	var y := -sin(k * PI) * 16.0
	var squash := absf(cos(k * TAU * 1.5))
	var old := U.alpha
	U.alpha = old * (1.0 if k < 0.7 else (1.0 - (k - 0.7) / 0.3))
	IconArt.draw_icon(ci, &"coin", pos + Vector2(0.0, y), 12.0 * (0.7 + 0.3 * squash))
	U.alpha = old


static func draw_pop_ring(ci: CanvasItem, pos: Vector2, t01: float, color: Color, r: float = 20.0) -> void:
	var k := clampf(t01, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var a := 1.0 - k
	var dark := Palette.shade(color, 0.55)
	# quick bright flash disc, then a dark-edged expanding ring (reads on pale walls) and flung dots
	U.circ(ci, pos, r * (0.45 + 0.7 * e), Color(1, 1, 1, 0.7 * a * a))
	var rr := r * (0.55 + 1.0 * e)
	var w := 3.6 * (1.0 - k * 0.6) + 0.8
	ci.draw_arc(pos, rr, 0.0, TAU, 32, U.col(Color(dark.r, dark.g, dark.b, 0.55 * a)), w + 2.4, true)
	ci.draw_arc(pos, rr, 0.0, TAU, 32, U.col(Color(color.r, color.g, color.b, 1.0 * minf(1.0, a * 1.6))), w, true)
	for i in range(8):
		var ang := float(i) * TAU / 8.0 + 0.3
		var d := r * (0.8 + 1.6 * e)
		var pp := pos + Vector2(cos(ang), sin(ang)) * d
		var dr := 3.0 * (1.0 - k) + 0.6
		U.circ(ci, pp, dr + 1.0, Color(dark.r, dark.g, dark.b, 0.5 * a))
		U.circ(ci, pp, dr, Color(color.r, color.g, color.b, 1.0 * a))


static func draw_star_burst(ci: CanvasItem, pos: Vector2, t01: float, color: Color) -> void:
	var k := clampf(t01, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 2.2)
	var edge := Color(Palette.NAVY.r, Palette.NAVY.g, Palette.NAVY.b, 0.55 * (1.0 - k * k))
	for i in range(7):
		var ang := -PI * 0.5 + (float(i) - 3.0) * 0.5 + U.hash01(i * 13) * 0.2
		var sp := 24.0 + U.hash01(i * 5 + 1) * 14.0
		var p := pos + Vector2(cos(ang) * sp * e, sin(ang) * sp * e + 26.0 * k * k)
		var sr := 5.0 * (1.0 - k * 0.5)
		var rot := k * 5.0 + float(i)
		U.star(ci, p, sr + 1.4, edge, rot)
		U.star(ci, p, sr, Color(color.r, color.g, color.b, 1.0 - k * k), rot)
