class_name PerkArt
extends RefCounted
## Flat vector icons for the Shipyard perks (and the few new UI glyphs v2 needs), drawn in code in the same toy style
## as IconArt: a unit-space glyph (radius 1 = size / 2) on a coloured round badge.
##
##   PerkArt.draw_badge(ci, id, center, size, t := 0.0)   glyph on a coloured badge (perk cards)
##   PerkArt.draw_glyph(ci, id, center, size, color, accent := ...)   bare glyph in one colour (buttons, pills)
##   PerkArt.badge_color(id) -> Color        PerkArt.IDS
## ids: budget crew tickets service maintenance (perks)   anchor report heatmap (UI glyphs)

const U := preload("res://src/render/art/art_util.gd")

const IDS: Array[StringName] = [&"budget", &"crew", &"tickets", &"service", &"maintenance", &"anchor", &"report", &"heatmap"]

const _BADGE: Dictionary = {
	&"budget": Color("4DB583"), &"crew": Color("3AA0C8"), &"tickets": Color("E8505B"),
	&"service": Color("8A72BD"), &"maintenance": Color("F2A93B"), &"anchor": Color("2A7FA6"),
	&"report": Color("3AA0C8"), &"heatmap": Color("E8505B"),
}

static var _cache: Dictionary = {}


static func badge_color(id: StringName) -> Color:
	return _BADGE.get(id, Palette.TEAL)


## Glyph on a round coloured badge with a soft shadow and a highlight. `t` animates a few details.
static func draw_badge(ci: CanvasItem, id: StringName, center: Vector2, size: float, t: float = 0.0) -> void:
	var s: float = size * 0.5
	var bc: Color = badge_color(id)
	U.xf(ci, center, 0.0, Vector2(s, s))
	U.circ(ci, Vector2(0.03, 0.08), 1.0, Color(0.1, 0.15, 0.3, 0.25))
	U.circ(ci, Vector2.ZERO, 1.0, Palette.shade(bc, 0.3))
	U.circ(ci, Vector2(0.0, -0.05), 0.94, bc)
	U.circ(ci, Vector2(0.0, -0.05), 0.78, Palette.tint(bc, 0.12))
	U.circ(ci, Vector2(-0.32, -0.5), 0.3, Color(1, 1, 1, 0.16))
	_glyph(ci, id, Palette.CREAM, bc, t)
	U.xf_end(ci)


## Bare glyph, `color` for the main shape and `accent` for the small details.
static func draw_glyph(ci: CanvasItem, id: StringName, center: Vector2, size: float, color: Color, accent: Color = Palette.SUN) -> void:
	var s: float = size * 0.5
	U.xf(ci, center, 0.0, Vector2(s, s))
	_glyph(ci, id, color, accent, 0.0)
	U.xf_end(ci)


static func _glyph(ci: CanvasItem, id: StringName, g: Color, a: Color, t: float) -> void:
	match id:
		&"budget": _budget(ci, g, a, t)
		&"crew": _crew(ci, g, a)
		&"tickets": _tickets(ci, g, a)
		&"service": _service(ci, g, a, t)
		&"maintenance": _maintenance(ci, g, a, t)
		&"anchor": _anchor(ci, g)
		&"report": _report(ci, g, a)
		&"heatmap": _heatmap(ci, g)
		_: U.circ(ci, Vector2.ZERO, 0.4, g)


# ---- shapes ------------------------------------------------------------------------------------
static func _gear(teeth: int, r_out: float, r_in: float) -> PackedVector2Array:
	var key := "pgear%d_%d_%d" % [teeth, int(r_out * 100.0), int(r_in * 100.0)]
	if _cache.has(key):
		return _cache[key]
	var p := PackedVector2Array()
	var step: float = TAU / float(teeth)
	for i in range(teeth):
		var an: float = float(i) * step
		p.append(Vector2(cos(an - step * 0.24), sin(an - step * 0.24)) * r_in)
		p.append(Vector2(cos(an - step * 0.14), sin(an - step * 0.14)) * r_out)
		p.append(Vector2(cos(an + step * 0.14), sin(an + step * 0.14)) * r_out)
		p.append(Vector2(cos(an + step * 0.24), sin(an + step * 0.24)) * r_in)
	_cache[key] = p
	return p


static func _dome(cx: float, base_y: float, rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in range(n + 1):
		var an: float = PI + PI * float(i) / float(n)
		p.append(Vector2(cx + cos(an) * rx, base_y + sin(an) * ry))
	return p


# ---- perk glyphs -------------------------------------------------------------------------------
static func _budget(ci: CanvasItem, g: Color, a: Color, t: float) -> void:
	# a tied money bag with a coin hopping out of it
	var bob: float = sin(t * 3.0) * 0.03
	var neck := PackedVector2Array([Vector2(-0.2, -0.42), Vector2(0.2, -0.42), Vector2(0.36, -0.1), Vector2(-0.36, -0.1)])
	U.poly(ci, neck, g)
	U.ellipse(ci, Vector2(0, 0.28), 0.58, 0.5, g)
	U.rbox(ci, Rect2(-0.26, -0.5, 0.52, 0.12), 0.05, Palette.shade(g, 0.15))
	U.rbox(ci, Rect2(-0.3, -0.36, 0.6, 0.09), 0.04, a)
	# coin on the bag: sun disc with a star
	U.circ(ci, Vector2(0, 0.3 + bob), 0.27, Palette.SUN_DEEP)
	U.circ(ci, Vector2(0, 0.28 + bob), 0.24, Palette.SUN)
	U.star(ci, Vector2(0, 0.29 + bob), 0.15, Palette.SUN_DEEP, 0.0, 0.5)
	# sparkle
	U.star(ci, Vector2(0.52, -0.5), 0.13, Palette.SUN, 0.3, 0.4)
	U.star(ci, Vector2(-0.56, -0.28), 0.09, Palette.SUN, 0.0, 0.4)


static func _crew(ci: CanvasItem, g: Color, a: Color) -> void:
	# hard hat with a ridge and a star on the front, plus a small uptick arrow
	U.poly(ci, _dome(0.0, 0.18, 0.62, 0.78), g)
	U.rbox(ci, Rect2(-0.78, 0.12, 1.56, 0.2), 0.09, g)
	U.rbox(ci, Rect2(-0.12, -0.6, 0.24, 0.74), 0.07, a)
	U.rbox(ci, Rect2(-0.82, 0.3, 1.64, 0.08), 0.04, Palette.shade(g, 0.2))
	U.star(ci, Vector2(0.0, 0.62), 0.2, a, 0.0, 0.5)


static func _tickets(ci: CanvasItem, g: Color, a: Color) -> void:
	# a ticket stub tilted a little, with notches and a star
	var prev := U.xf_push(ci, Vector2.ZERO, -0.22, Vector2.ONE)
	U.rbox(ci, Rect2(-0.78, -0.4, 1.56, 0.8), 0.1, g)
	U.circ(ci, Vector2(-0.78, 0.0), 0.15, a)
	U.circ(ci, Vector2(0.78, 0.0), 0.15, a)
	for i in range(5):
		U.rbox(ci, Rect2(0.34, -0.3 + float(i) * 0.13, 0.06, 0.07), 0.02, a)
	U.star(ci, Vector2(-0.17, 0.0), 0.3, a, 0.0, 0.5)
	U.star(ci, Vector2(-0.17, -0.02), 0.2, g, 0.0, 0.5)
	U.xf_load(ci, prev)


static func _service(ci: CanvasItem, g: Color, a: Color, t: float) -> void:
	# a service bell (cloche) with a ding
	U.poly(ci, _dome(0.0, 0.34, 0.66, 0.78), g)
	U.rbox(ci, Rect2(-0.82, 0.3, 1.64, 0.18), 0.08, g)
	U.circ(ci, Vector2(0.0, -0.5), 0.1, g)
	U.rbox(ci, Rect2(-0.1, -0.5, 0.2, 0.1), 0.04, g)
	U.arc(ci, Vector2(-0.12, 0.34), 0.5, PI + 0.5, PI + 1.2, a, 0.1, 6)
	var k: float = 0.5 + 0.5 * sin(t * 4.0)
	U.line(ci, Vector2(0.62, -0.6), Vector2(0.8, -0.78 - 0.04 * k), a, 0.09)
	U.line(ci, Vector2(0.74, -0.38), Vector2(0.96, -0.4), a, 0.09)


static func _maintenance(ci: CanvasItem, g: Color, a: Color, t: float) -> void:
	# a gear with a wrench laid across it
	var gear := _gear(8, 0.78, 0.6)
	var prev := U.xf_push(ci, Vector2(-0.12, -0.08), t * 0.5, Vector2.ONE)
	U.poly(ci, gear, g)
	U.circ(ci, Vector2.ZERO, 0.28, a)
	U.xf_load(ci, prev)
	var prev2 := U.xf_push(ci, Vector2(0.18, 0.18), PI * 0.25, Vector2.ONE)
	U.capsule(ci, Vector2(-0.1, 0.0), Vector2(0.78, 0.0), 0.12, Palette.shade(g, 0.28))
	U.capsule(ci, Vector2(-0.1, -0.02), Vector2(0.78, -0.02), 0.1, Palette.CREAM if g != Palette.CREAM else Color.WHITE)
	U.arc(ci, Vector2(-0.34, 0.0), 0.22, PI + 0.6, PI + TAU - 0.6, Palette.shade(g, 0.28), 0.28, 12)
	U.arc(ci, Vector2(-0.34, -0.02), 0.22, PI + 0.6, PI + TAU - 0.6, Palette.CREAM if g != Palette.CREAM else Color.WHITE, 0.24, 12)
	U.xf_load(ci, prev2)


# ---- UI glyphs ---------------------------------------------------------------------------------
static func _anchor(ci: CanvasItem, g: Color) -> void:
	U.ring(ci, Vector2(0, -0.66), 0.17, g, 0.13)
	U.capsule(ci, Vector2(0, -0.5), Vector2(0, 0.68), 0.075, g)
	U.capsule(ci, Vector2(-0.34, -0.26), Vector2(0.34, -0.26), 0.075, g)
	U.arc(ci, Vector2(0, 0.18), 0.62, 0.15, PI - 0.15, g, 0.15, 18)
	U.poly(ci, PackedVector2Array([Vector2(-0.8, 0.28), Vector2(-0.46, 0.2), Vector2(-0.6, 0.52)]), g)
	U.poly(ci, PackedVector2Array([Vector2(0.8, 0.28), Vector2(0.46, 0.2), Vector2(0.6, 0.52)]), g)


static func _report(ci: CanvasItem, g: Color, a: Color) -> void:
	U.rbox(ci, Rect2(-0.62, -0.72, 1.24, 1.5), 0.14, g)
	U.rbox(ci, Rect2(-0.28, -0.84, 0.56, 0.28), 0.1, Palette.shade(g, 0.22))
	var bars: Array[float] = [0.34, 0.62, 0.48]
	for i in range(3):
		var h: float = bars[i]
		U.rbox(ci, Rect2(-0.42 + float(i) * 0.3, 0.62 - h, 0.2, h), 0.05, a)
	U.line(ci, Vector2(-0.44, 0.66), Vector2(0.44, 0.66), Palette.shade(g, 0.2), 0.05)


static func _heatmap(ci: CanvasItem, g: Color) -> void:
	var cols: Array[Color] = [Color("FFE08A"), Color("FFC857"), Color("F58A3C"), Color("FFC857"), Color("F58A3C"), Color("E8505B"), Color("FFE08A"), Color("FFC857"), Color("F58A3C")]
	for r in range(3):
		for c in range(3):
			var col: Color = cols[r * 3 + c]
			U.rbox(ci, Rect2(-0.74 + float(c) * 0.52, -0.74 + float(r) * 0.52, 0.46, 0.46), 0.1, col)
	U.rbox_outline(ci, Rect2(-0.78, -0.78, 1.56, 1.56), 0.16, g, 0.06)
