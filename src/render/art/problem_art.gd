class_name ProblemArt
extends RefCounted
## Problem sprites living on the ship (not UI icons).
##
## API
##   ProblemArt.draw_mess(ci, floor_pos: Vector2, variant: int, clean_progress: float, t: float, colorblind := false)
##       floor_pos = point on the corridor floor (use SimConst.to_px(x, deck) -> feet level). ~28x10 px puddle.
##       variant 0..3 (spilled soda / teal slush / food splat / ice-cream), clean_progress 0..1 shrinks it and
##       adds soap bubbles; t = animation seconds.
##   ProblemArt.draw_ghost(ci, pos: Vector2, t: float, alpha: float, facing: int, colorblind := false)
##       pos = centre-bottom of the ghost (it floats ~6 px above it); ~22x30 px, translucent.

const U := preload("res://src/render/art/art_util.gd")

const _MESS_COL: Array[Color] = [Color("8B5E3C"), Color("3AA0C8"), Color("E98B45"), Color("FF9EB5")]


static func draw_mess(ci: CanvasItem, floor_pos: Vector2, variant: int, clean_progress: float, t: float, colorblind: bool = false) -> void:
	var v := posmod(variant, 4)
	var k := clampf(1.0 - clean_progress * 0.85, 0.12, 1.0)
	var base: Color = _MESS_COL[v]
	if colorblind:
		# every spill reads as the same "blue puddle" as the badge icon (Palette.problem_color(&"mess", true))
		base = Palette.problem_color(&"mess", true).lerp(Color("56B4E9"), float(v % 2) * 0.35)
	var shade := Palette.shade(base, 0.35)
	var hi := Palette.tint(base, 0.5)
	var p := floor_pos + Vector2(0.0, -3.0)
	var shimmer := 0.5 + 0.5 * sin(t * 2.4 + float(v))
	# drop shadow / wet ring
	U.ellipse(ci, p + Vector2(0.0, 1.2), 15.0 * k, 4.8 * k, Color(0.1, 0.15, 0.3, 0.18))
	match v:
		0:  # soda puddle with an ice cube
			U.ellipse(ci, p, 13.0 * k, 4.0 * k, shade)
			U.ellipse(ci, p + Vector2(-1.5, -0.4), 11.5 * k, 3.3 * k, base)
			U.ellipse(ci, p + Vector2(6.0 * k, 0.0), 5.5 * k, 2.4 * k, base)
			U.ellipse(ci, p + Vector2(-5.0 * k, -1.2), 4.0 * k, 1.0 * k, Color(1, 1, 1, 0.3 + 0.2 * shimmer))
			U.rr(ci, Rect2(p + Vector2(-3.0, -5.0) * k, Vector2(6.0, 5.0) * k), 1.6 * k, Color(0.85, 0.96, 1.0, 0.85))
			U.circ(ci, p + Vector2(10.0 * k, -3.0 * k), 1.6 * k, base)
			U.circ(ci, p + Vector2(-11.0 * k, -2.0 * k), 1.2 * k, base)
		1:  # teal slush with bubbles
			U.ellipse(ci, p, 13.5 * k, 4.2 * k, shade)
			U.ellipse(ci, p + Vector2(0.0, -0.5), 12.0 * k, 3.4 * k, base)
			for i in range(4):
				var bx := (-8.0 + float(i) * 5.5) * k
				var br := (1.5 + float(i % 2)) * k
				var up := fmod(t * 0.5 + float(i) * 0.27, 1.0)
				U.circ(ci, p + Vector2(bx, -1.0 - up * 3.0 * k), br, Color(0.9, 0.98, 1.0, 0.85 * (1.0 - up)))
			U.ellipse(ci, p + Vector2(-4.0 * k, -1.2), 4.0 * k, 1.0 * k, Color(1, 1, 1, 0.35))
		2:  # food splat with chunks
			U.ellipse(ci, p, 12.0 * k, 4.0 * k, shade)
			U.ellipse(ci, p + Vector2(0.0, -0.4), 10.5 * k, 3.2 * k, base)
			var chunks: Array[Color] = [Palette.CORAL, Palette.SUN, Palette.MINT_DARK, Palette.CREAM]
			for i in range(4):
				U.rr(ci, Rect2(p + Vector2(-8.0 + float(i) * 4.4, -3.2 - float(i % 2)) * k, Vector2(3.4, 2.6) * k), 1.0, chunks[i])
			U.circ(ci, p + Vector2(11.0 * k, -2.5 * k), 1.5 * k, base)
		3:  # melted ice cream
			U.ellipse(ci, p, 12.5 * k, 4.2 * k, Palette.shade(base, 0.2))
			U.ellipse(ci, p + Vector2(0.0, -0.4), 11.0 * k, 3.4 * k, base)
			U.poly(ci, PackedVector2Array([p + Vector2(7.0, -2.0) * k, p + Vector2(14.0, -3.0) * k, p + Vector2(11.0, 0.5) * k]), Palette.WOOD_LIGHT)
			U.circ(ci, p + Vector2(-3.0 * k, -3.0 * k), 3.0 * k, Palette.CREAM)
			U.circ(ci, p + Vector2(-3.0 * k, -5.2 * k), 1.2 * k, Palette.CORAL)
	U.ellipse(ci, p + Vector2(-5.0 * k, -1.4), 3.5 * k, 0.8 * k, hi)
	# stink lines (when not being cleaned much)
	if clean_progress < 0.3:
		for i in range(2):
			var s := fmod(t * 0.6 + float(i) * 0.5, 1.0)
			var x := p.x + (-4.0 + float(i) * 9.0)
			var pts := PackedVector2Array()
			for j in range(5):
				var f := float(j) / 4.0
				pts.append(Vector2(x + sin(f * 6.0 + t * 3.0) * 1.6, p.y - 5.0 - s * 6.0 - f * 6.0))
			U.pline(ci, pts, Color(0.55, 0.65, 0.35, 0.65 * (1.0 - s)), 1.1)
	# soap bubbles while cleaning
	if clean_progress > 0.01:
		for i in range(5):
			var s2 := fmod(t * 0.9 + float(i) * 0.21, 1.0)
			var bx2 := p.x + (-9.0 + float(i) * 4.5)
			U.circ(ci, Vector2(bx2, p.y - 2.0 - s2 * 11.0), 1.6 + float(i % 3) * 0.8, Color(0.85, 0.97, 1.0, 0.85 * (1.0 - s2)))
			U.circ(ci, Vector2(bx2 - 0.5, p.y - 2.5 - s2 * 11.0), 0.5, Color(1, 1, 1, 0.9 * (1.0 - s2)))


static func draw_ghost(ci: CanvasItem, pos: Vector2, t: float, alpha: float, facing: int, colorblind: bool = false) -> void:
	var old := U.alpha
	U.alpha = old * clampf(alpha, 0.0, 1.0)
	var f := 1.0 if facing >= 0 else -1.0
	var bob := sin(t * 2.6) * 3.0
	var c := pos + Vector2(0.0, -17.0 + bob)
	# glow
	if colorblind:
		var gc: Color = Palette.problem_color(&"ghost", true)
		U.circ(ci, c, 21.0, Color(gc.r, gc.g, gc.b, 0.2))
		U.circ(ci, c, 14.5, Color(gc.r, gc.g, gc.b, 0.22))
	else:
		U.circ(ci, c, 20.0, Color(0.8, 0.9, 1.0, 0.1))
		U.circ(ci, c, 14.0, Color(0.85, 0.8, 1.0, 0.1))
	# cool shadow glow: a faint indigo halo that lifts the ghost off light walls (barely visible on dark ones)
	U.circ(ci, c + Vector2(0.0, 2.0), 25.0, Color(0.33, 0.3, 0.62, 0.09))
	U.circ(ci, c + Vector2(0.0, 2.0), 18.5, Color(0.33, 0.3, 0.62, 0.11))
	# trailing wisps
	for i in range(3):
		var k := fmod(t * 0.7 + float(i) / 3.0, 1.0)
		U.circ(ci, c + Vector2(-f * (8.0 + k * 14.0), 6.0 + sin(k * 8.0 + float(i)) * 3.0), 3.0 * (1.0 - k) + 0.5, Color(0.85, 0.85, 1.0, 0.45 * (1.0 - k)))
	# body: dome + straight sides + scalloped (wobbling) hem, built from cheap primitives.
	# pass 0 is a soft cool-lilac outline + drop shadow (so the white sheet pops on cream walls), pass 1 the sheet.
	var sheet := Color(0.985, 0.98, 1.0, 0.97)
	var sh_col := Color(0.44, 0.4, 0.72, 0.75)
	for pass_i in range(2):
		var off := Vector2(0.6, 1.3) if pass_i == 0 else Vector2.ZERO
		var g: float = 1.5 if pass_i == 0 else 0.0   # the outline pass is grown by ~1.5 px on every side
		var cc := sh_col if pass_i == 0 else sheet
		U.ellipse(ci, c + off + Vector2(0.0, -2.0), 10.5 + g, 12.0 + g, cc)
		U.rect(ci, Rect2(c + off + Vector2(-10.5 - g, -2.0), Vector2(21.0 + 2.0 * g, 13.0 + g)), cc)
		for i in range(4):
			var bx := -7.9 + float(i) * 5.3
			U.circ(ci, c + off + Vector2(bx, 11.0 + 1.6 * sin(float(i) * 2.2 + t * 5.0)), 2.9 + g, cc)
	# soft belly shade
	U.ellipse(ci, c + Vector2(0.0, 7.0), 8.5, 4.0, Color(0.8, 0.78, 1.0, 0.45))
	# arms (little stubs)
	U.ellipse(ci, c + Vector2(-11.0 * f, 2.0 + sin(t * 4.0) * 1.5), 3.2, 2.2, Color(0.97, 0.96, 1.0, 0.92))
	U.ellipse(ci, c + Vector2(11.0 * f, 1.0 - sin(t * 4.0) * 1.5), 3.2, 2.2, Color(0.97, 0.96, 1.0, 0.92))
	# face
	U.ellipse(ci, c + Vector2(-3.4 + f * 1.4, -4.0), 1.8, 2.6, Palette.INK)
	U.ellipse(ci, c + Vector2(3.4 + f * 1.4, -4.0), 1.8, 2.6, Palette.INK)
	U.ellipse(ci, c + Vector2(f * 1.4, 2.0), 2.0, 2.6, Palette.INK)
	U.circ(ci, c + Vector2(-6.2 + f * 0.8, -0.2), 1.6, Color(1.0, 0.6, 0.75, 0.55))
	U.circ(ci, c + Vector2(6.2 + f * 0.8, -0.2), 1.6, Color(1.0, 0.6, 0.75, 0.55))
	U.ellipse(ci, c + Vector2(-3.2, -9.0), 3.0, 1.2, Color(1, 1, 1, 0.8))
	U.alpha = old
