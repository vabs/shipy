class_name ShipArt
extends RefCounted
## Ship structure art in ship-local px (x right, bow on the right; deck d floor at y = -d*76; hull below y=0).
## Works for any width (24/32/40 cells) and deck count (4/5/6).
##
## API
##   ShipArt.WATERLINE_Y = 40.0       ship-local y where the water surface meets the hull
##   ShipArt.HULL_H = 66.0
##   ShipArt.ship_bounds(width_cells, decks) -> Rect2   local bounds incl. hull + superstructure + gangway
##   ShipArt.draw_superstructure(ci, width_cells, decks, t, dest := &"med")   # behind everything: bridge, funnel, smoke, mast, flag
##   ShipArt.draw_hull(ci, width_cells, decks, gangway_deck)                  # navy hull, coral stripe, portholes
##   ShipArt.draw_deck_cells(ci, width_cells, decks)                          # walls/windows/corridor for ALL cells + end walls + top deck floor
##   ShipArt.draw_railings(ci, width_cells, decks)                            # top-deck railings
##   ShipArt.draw_gangway(ci, width_cells, decks, gangway_deck)               # boarding door + platform at x=0

const U := preload("res://src/render/art/art_util.gd")

const WATERLINE_Y: float = 46.0
const HULL_H: float = 76.0
const DECK_H: float = 76.0
const CELL_W: float = 40.0

static var _hull_cache: Dictionary = {}


static func ship_bounds(width_cells: int, decks: int) -> Rect2:
	var w := float(width_cells) * CELL_W
	var top := -(float(decks) * DECK_H + 118.0)
	return Rect2(-70.0, top, w + 70.0 + 44.0, -top + HULL_H)


# =================================================================================================
# HULL
# =================================================================================================
static func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, n: int, out: PackedVector2Array) -> void:
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var u := 1.0 - t
		out.append(u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3)


static func hull_outline(w: float) -> PackedVector2Array:
	var key := int(w)
	if _hull_cache.has(key):
		return _hull_cache[key]
	var p := PackedVector2Array()
	# top edge (sheer line rising a little at stern and a lot at the bow)
	p.append(Vector2(-16.0, -9.0))
	p.append(Vector2(-9.0, -3.0))
	p.append(Vector2(4.0, 0.0))
	p.append(Vector2(w - 6.0, 0.0))
	p.append(Vector2(w + 8.0, -2.0))
	p.append(Vector2(w + 22.0, -9.0))
	p.append(Vector2(w + 32.0, -22.0))
	# bow stem curving down & back to the keel
	_bezier(Vector2(w + 32.0, -22.0), Vector2(w + 40.0, 14.0), Vector2(w + 16.0, 62.0), Vector2(w - 36.0, HULL_H), 14, p)
	# bottom
	p.append(Vector2(30.0, HULL_H))
	# stern
	_bezier(Vector2(30.0, HULL_H), Vector2(-6.0, 70.0), Vector2(-24.0, 34.0), Vector2(-16.0, -9.0), 12, p)
	_hull_cache[key] = p
	return p


static func _clip_rect(poly: PackedVector2Array, r: Rect2) -> Array[PackedVector2Array]:
	var rp := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var res: Array[PackedVector2Array] = []
	for q in Geometry2D.intersect_polygons(poly, rp):
		res.append(q)
	return res


static func draw_hull(ci: CanvasItem, width_cells: int, decks: int, gangway_deck: int) -> void:
	var w := float(width_cells) * CELL_W
	var h := hull_outline(w)
	# soft shadow under/behind
	U.poly_xf(ci, h, Vector2(2.0, 4.0), 0.0, Vector2.ONE, Color(0.05, 0.1, 0.25, 0.25))
	U.poly(ci, h, Palette.NAVY)
	# submerged section darker
	for q in _clip_rect(h, Rect2(-40.0, 42.0, w + 120.0, 50.0)):
		U.poly(ci, q, Palette.NAVY_DARK)
	# soft upper highlight band
	for q in _clip_rect(h, Rect2(-40.0, 6.0, w + 120.0, 5.0)):
		U.poly(ci, q, Palette.NAVY_LIGHT)
	# white gunwale trim following the sheer line
	var trim := PackedVector2Array()
	var edge := PackedVector2Array([Vector2(-16.0, -9.0), Vector2(-9.0, -3.0), Vector2(4.0, 0.0), Vector2(w - 6.0, 0.0), Vector2(w + 8.0, -2.0), Vector2(w + 22.0, -9.0), Vector2(w + 32.0, -22.0)])
	for v in edge:
		trim.append(v)
	for i in range(edge.size() - 1, -1, -1):
		trim.append(edge[i] + Vector2(0.0, 7.0 if i < edge.size() - 1 else 9.0))
	for q in Geometry2D.intersect_polygons(trim, h):
		U.poly(ci, q, Palette.HULL_WHITE)
		U.poly_xf(ci, q, Vector2(0.0, 1.0), 0.0, Vector2.ONE, Color(0.1, 0.15, 0.3, 0.0))
	# coral waterline stripe
	for q in _clip_rect(h, Rect2(-40.0, 30.0, w + 120.0, 9.0)):
		U.poly(ci, q, Palette.CORAL)
	for q in _clip_rect(h, Rect2(-40.0, 30.0, w + 120.0, 2.0)):
		U.poly(ci, q, Palette.CORAL_LIGHT)
	for q in _clip_rect(h, Rect2(-40.0, 37.0, w + 120.0, 2.0)):
		U.poly(ci, q, Palette.CORAL_DARK)
	# portholes
	var count := int((w - 40.0) / 44.0)
	for i in range(count + 1):
		var px := 28.0 + float(i) * (w - 56.0) / float(maxi(count, 1))
		var pc := Vector2(px, 17.5)
		U.circ(ci, pc + Vector2(0.0, 0.8), 6.4, Color(0.05, 0.1, 0.25, 0.4))
		U.circ(ci, pc, 6.2, Palette.HULL_WHITE)
		U.circ(ci, pc, 4.6, Palette.TEAL_DARK)
		U.circ(ci, pc + Vector2(0.0, 0.6), 4.0, Palette.TEAL_LIGHT)
		U.circ(ci, pc + Vector2(-1.2, -1.2), 1.5, Color(1, 1, 1, 0.8))
	# bow detail: anchor hawse hole
	U.circ(ci, Vector2(w + 12.0, 8.0), 2.8, Palette.NAVY_DARK)
	# stern rudder hint / propeller wash is under water; add rub rail line
	U.pline(ci, PackedVector2Array([Vector2(8.0, 41.0), Vector2(w - 30.0, 41.0)]), Color(1, 1, 1, 0.07), 1.0)


# =================================================================================================
# DECK CELLS (structure)
# =================================================================================================
static func draw_deck_cells(ci: CanvasItem, width_cells: int, decks: int) -> void:
	var w := float(width_cells) * CELL_W
	# interior decks 0 .. decks-2
	for d in range(decks - 1):
		var y0 := -float(d + 1) * DECK_H
		for c in range(width_cells):
			_cell(ci, Rect2(float(c) * CELL_W, y0, CELL_W, DECK_H), c, d)
	# top deck: open air floor
	var td := decks - 1
	var ty0 := -float(td + 1) * DECK_H
	var fy := ty0 + DECK_H - 11.0
	U.rect(ci, Rect2(0.0, fy, w, 7.0), Color("E3B987"))
	U.rect(ci, Rect2(0.0, fy + 7.0, w, 4.0), Color("B98F63"))
	U.rect(ci, Rect2(0.0, fy, w, 1.2), Color(1, 1, 1, 0.3))
	for i in range(1, int(w / 20.0)):
		U.rect(ci, Rect2(float(i) * 20.0 - 0.5, fy, 1.0, 7.0), Color(0.55, 0.38, 0.2, 0.25))
	# end walls (interior decks)
	for d in range(decks - 1):
		var y0 := -float(d + 1) * DECK_H
		U.rr(ci, Rect2(-6.0, y0, 7.0, DECK_H + 1.0), 2.0, Palette.HULL_WHITE)
		U.rect(ci, Rect2(-6.0, y0, 2.0, DECK_H + 1.0), Color(1, 1, 1, 0.35))
		U.rr(ci, Rect2(w - 1.0, y0, 7.0, DECK_H + 1.0), 2.0, Palette.HULL_WHITE)
		U.rect(ci, Rect2(w + 4.0, y0, 2.0, DECK_H + 1.0), Color(0.1, 0.15, 0.3, 0.12))
		# deck separators: navy beam sticking out slightly
		U.rr(ci, Rect2(-7.0, y0 - 1.0, 9.0, 6.0), 2.0, Palette.NAVY_LIGHT)
		U.rr(ci, Rect2(w - 2.0, y0 - 1.0, 9.0, 6.0), 2.0, Palette.NAVY_LIGHT)
	# top of the interior stack = underside of the top deck (a roof line)
	var ry := -float(decks - 1) * DECK_H
	U.rr(ci, Rect2(-9.0, ry - 1.0, w + 18.0, 5.0), 2.5, Palette.HULL_WHITE)
	U.rect(ci, Rect2(-9.0, ry + 2.0, w + 18.0, 2.0), Color(0.1, 0.15, 0.3, 0.2))
	# end posts for the top deck
	for xx in [-4.0, w + 1.0]:
		U.rr(ci, Rect2(xx - 1.0, ty0 + 30.0, 5.0, DECK_H - 41.0), 2.0, Palette.HULL_WHITE)
		U.circ(ci, Vector2(xx + 1.5, ty0 + 30.0), 3.2, Palette.HULL_WHITE)


## Which (sparse) detail an empty cell carries, deterministic per (cell, deck): 0 none, 1 round porthole,
## 2 plant, 3 wall lamp, 4 bench, 5 framed picture. PortOverlay uses it to keep its "+" off the centre details.
static func cell_detail(c: int, d: int) -> int:
	if U.hash01(c * 13 + d * 29 + 3) < 0.15:
		return 1
	var v := int(U.hash01(c * 31 + d * 17 + 5) * 14.0)
	return v + 2 if v <= 3 else 0


## An EMPTY deck cell: deliberately calm so that built rooms (saturated, lit, full of furniture) are the
## loudest things on the ship. Soft greige wall, quiet baseboard and runner, one tiny ceiling lamp, and only
## the odd small porthole / plant / bench. No big windows, life rings or bright carpets here.
static func _cell(ci: CanvasItem, R: Rect2, c: int, d: int) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - 11.0
	var cx := x0 + w * 0.5
	var alt := (c + d) % 2 == 1
	var wt: Color = Palette.EMPTY_WALL_TOP if not alt else Palette.EMPTY_WALL_TOP.darkened(0.025)
	var wb: Color = Palette.EMPTY_WALL_BOT if not alt else Palette.EMPTY_WALL_BOT.darkened(0.025)
	U.vgrad(ci, Rect2(x0, y0 + 5.0, w, fy - y0 - 5.0), wt, wb)
	# baseboard
	U.rect(ci, Rect2(x0, fy - 7.0, w, 7.0), Color(0.45, 0.38, 0.3, 0.1))
	U.rect(ci, Rect2(x0, fy - 8.0, w, 1.0), Color(1, 1, 1, 0.35))
	# ceiling
	U.rect(ci, Rect2(x0, y0, w, 5.0), Palette.CEILING_TRIM)
	U.rect(ci, Rect2(x0, y0 + 4.0, w, 1.0), Color(1, 1, 1, 0.12))
	U.vgrad(ci, Rect2(x0, y0 + 5.0, w, 9.0), Color(0.1, 0.15, 0.3, 0.12), Color(0.1, 0.15, 0.3, 0.0))
	# small ceiling lamp, dim
	U.rr(ci, Rect2(cx - 4.0, y0 + 5.0, 8.0, 2.2), 1.1, Color("F4EEDD"))
	U.circ(ci, Vector2(cx, y0 + 9.0), 7.0, Color(1.0, 0.95, 0.75, 0.07))
	# soft vertical panel seam
	U.rect(ci, Rect2(x0, y0 + 5.0, 1.0, R.size.y - 5.0), Palette.EMPTY_SEAM)
	# edge shading
	U.hgrad(ci, Rect2(x0, y0 + 5.0, 6.0, fy - y0 - 5.0), Color(0.1, 0.15, 0.3, 0.07), Color(0.1, 0.15, 0.3, 0.0))
	# floor + muted runner
	U.rect(ci, Rect2(x0, fy, w, 7.0), Palette.EMPTY_FLOOR_TOP)
	U.rect(ci, Rect2(x0, fy + 7.0, w, 4.0), Palette.EMPTY_FLOOR_FRONT)
	U.rect(ci, Rect2(x0, fy, w, 1.2), Color(1, 1, 1, 0.25))
	U.rect(ci, Rect2(x0, fy + 2.0, w, 3.6), Palette.EMPTY_RUNNER)
	U.rect(ci, Rect2(x0, fy + 2.0, w, 0.9), Palette.EMPTY_RUNNER_ALT)
	# sparse, quiet details
	match cell_detail(c, d):
		1:  # small round porthole
			var pc := Vector2(cx, y0 + 33.0)
			U.circ(ci, pc, 9.4, Color(0.45, 0.4, 0.34, 0.16))
			U.circ(ci, pc, 8.6, Color("E9E5DB"))
			U.circ(ci, pc, 6.6, Color("A8C9D8"))
			U.rr_ex(ci, Rect2(pc.x - 6.0, pc.y + 1.5, 12.0, 4.6), 0.0, 0.0, 4.5, 4.5, Color("8DB7CB"))
			U.circ(ci, pc + Vector2(-2.2, -2.4), 1.7, Color(1, 1, 1, 0.55))
		2:  # potted plant (muted)
			var px := x0 + 10.0 + float(c % 3) * 9.0
			U.rr_ex(ci, Rect2(px - 3.5, fy - 7.0, 7.0, 7.0), 1.0, 1.0, 3.0, 3.0, Color("C7B49C"))
			U.rect(ci, Rect2(px - 3.5, fy - 7.0, 7.0, 1.4), Color("B09C84"))
			for k in range(3):
				var a := -PI * 0.5 + (float(k) - 1.0) * 0.55
				U.capsule(ci, Vector2(px, fy - 7.0), Vector2(px + cos(a) * 8.0, fy - 7.0 + sin(a) * 10.0), 1.5, Color("7DB892") if k != 1 else Color("92CBA6"))
		3:  # wall lamp: little sconce with a warm glow
			var lx := x0 + 10.0
			U.circ(ci, Vector2(lx, y0 + 35.0), 9.0, Color(1.0, 0.92, 0.6, 0.1))
			U.rr(ci, Rect2(lx - 1.0, y0 + 36.0, 2.0, 4.0), 1.0, Color("C9B48A"))
			U.rr_ex(ci, Rect2(lx - 3.5, y0 + 30.0, 7.0, 7.0), 3.5, 3.5, 1.5, 1.5, Color("F0DCA0"))
		4:  # bench
			U.rr(ci, Rect2(x0 + 7.0, fy - 7.0, 24.0, 2.8), 1.4, Color("D6BFA0"))
			U.rect(ci, Rect2(x0 + 9.0, fy - 4.4, 2.0, 4.4), Color("B49C7C"))
			U.rect(ci, Rect2(x0 + 27.0, fy - 4.4, 2.0, 4.4), Color("B49C7C"))
		5:  # tiny framed picture
			U.rr(ci, Rect2(cx - 7.0, y0 + 24.0, 14.0, 11.0), 2.0, Color("CDBFA7"))
			U.rr(ci, Rect2(cx - 5.4, y0 + 25.6, 10.8, 7.8), 1.4, Color("E5EEF0"))
			U.rr_ex(ci, Rect2(cx - 5.4, y0 + 30.0, 10.8, 3.4), 0.0, 0.0, 1.4, 1.4, Color("B5D3DC"))


# =================================================================================================
# RAILINGS (top deck)
# =================================================================================================
static func draw_railings(ci: CanvasItem, width_cells: int, decks: int) -> void:
	var w := float(width_cells) * CELL_W
	var td := decks - 1
	var ty0 := -float(td + 1) * DECK_H
	var fy := ty0 + DECK_H - 11.0
	var top := fy - 27.0
	# glass panels between posts (one panel per cell: a calmer fence than a post every 20 px)
	var n := int(w / 40.0)
	for i in range(n):
		var x := float(i) * 40.0
		U.rr(ci, Rect2(x + 3.0, top + 3.0, 34.0, 22.0), 4.0, Color(0.75, 0.93, 1.0, 0.15))
		U.poly(ci, PackedVector2Array([Vector2(x + 7.0, top + 24.0), Vector2(x + 16.0, top + 4.0), Vector2(x + 20.0, top + 4.0), Vector2(x + 11.0, top + 24.0)]), Color(1, 1, 1, 0.13))
		U.poly(ci, PackedVector2Array([Vector2(x + 22.0, top + 24.0), Vector2(x + 28.0, top + 10.0), Vector2(x + 30.0, top + 10.0), Vector2(x + 24.0, top + 24.0)]), Color(1, 1, 1, 0.09))
	# rails
	U.rr(ci, Rect2(-2.0, top, w + 4.0, 3.0), 1.5, Palette.HULL_WHITE)
	U.rect(ci, Rect2(-2.0, top + 2.0, w + 4.0, 1.0), Color(0.1, 0.15, 0.3, 0.18))
	U.rr(ci, Rect2(-2.0, fy - 12.0, w + 4.0, 1.8), 0.9, Palette.HULL_WHITE)
	# posts
	for i in range(n + 1):
		var x := float(i) * 40.0
		U.rr(ci, Rect2(x - 1.4, top, 3.0, fy - top), 1.4, Palette.HULL_WHITE)
		U.circ(ci, Vector2(x + 0.1, top), 2.3, Palette.HULL_WHITE)


# =================================================================================================
# GANGWAY
# =================================================================================================
static func draw_gangway(ci: CanvasItem, width_cells: int, decks: int, gangway_deck: int) -> void:
	var gy := -float(gangway_deck) * DECK_H   # floor of the gangway deck
	var interior := gangway_deck < decks - 1
	# door opening in the stern end wall
	if interior:
		var door := Rect2(-6.0, gy - 11.0 - 32.0, 8.0, 32.0)
		U.rr(ci, door.grow(1.6), 3.0, Palette.CORAL_DARK)
		U.rr(ci, door, 2.0, Color("FFE9B5"))
		U.rr(ci, Rect2(door.position.x, door.position.y, 3.0, door.size.y), 1.0, Color(1, 1, 1, 0.5))
		# door leaf swung outward
		U.poly(ci, PackedVector2Array([Vector2(-6.0, gy - 11.0 - 30.0), Vector2(-26.0, gy - 11.0 - 25.0), Vector2(-26.0, gy - 11.0 + 2.0), Vector2(-6.0, gy - 11.0)]), Palette.CORAL)
		U.poly(ci, PackedVector2Array([Vector2(-6.0, gy - 11.0 - 30.0), Vector2(-26.0, gy - 11.0 - 25.0), Vector2(-26.0, gy - 11.0 - 20.0), Vector2(-6.0, gy - 11.0 - 24.0)]), Palette.CORAL_LIGHT)
	# boarding platform + folded ramp + rails
	var py := gy - 11.0 + 7.0
	U.rr(ci, Rect2(-52.0, py, 48.0, 5.0), 2.0, Palette.WOOD)
	U.rr(ci, Rect2(-52.0, py + 3.0, 48.0, 3.0), 1.5, Palette.WOOD_DARK)
	for i in range(6):
		U.rect(ci, Rect2(-50.0 + float(i) * 8.0, py, 1.0, 4.0), Color(0.3, 0.15, 0.05, 0.25))
	U.rect(ci, Rect2(-50.0, py + 6.0, 3.0, 26.0), Palette.STEEL)
	U.rect(ci, Rect2(-14.0, py + 6.0, 3.0, 18.0), Palette.STEEL)
	# bracing
	U.line(ci, Vector2(-48.0, py + 30.0), Vector2(-10.0, py + 6.0), Palette.STEEL_DARK, 1.6)
	# railings
	var rtop := py - 22.0
	U.rr(ci, Rect2(-52.0, rtop, 46.0, 2.4), 1.2, Palette.HULL_WHITE)
	U.rr(ci, Rect2(-52.0, py - 10.0, 46.0, 1.6), 0.8, Palette.HULL_WHITE)
	for xx in [-52.0, -38.0, -24.0]:
		U.rr(ci, Rect2(xx, rtop, 2.2, 22.0), 1.0, Palette.HULL_WHITE)
	# lifebuoy
	var lb := Vector2(-31.0, rtop + 9.0)
	U.circ(ci, lb, 6.8, Palette.CORAL)
	for i in range(4):
		var a := float(i) * PI * 0.5 + PI * 0.25
		U.poly(ci, PackedVector2Array([lb + Vector2(cos(a - 0.4), sin(a - 0.4)) * 4.2, lb + Vector2(cos(a - 0.4), sin(a - 0.4)) * 6.8, lb + Vector2(cos(a + 0.4), sin(a + 0.4)) * 6.8, lb + Vector2(cos(a + 0.4), sin(a + 0.4)) * 4.2]), Palette.HULL_WHITE)
	U.circ(ci, lb, 3.2, Color(0.15, 0.2, 0.35, 0.0))
	# folded gangway ramp tucked under the platform
	U.poly(ci, PackedVector2Array([Vector2(-52.0, py + 6.0), Vector2(-82.0, py + 22.0), Vector2(-79.0, py + 27.0), Vector2(-49.0, py + 11.0)]), Palette.STEEL)
	U.line(ci, Vector2(-52.0, py + 4.0), Vector2(-82.0, py + 20.0), Palette.HULL_WHITE, 1.4)


# =================================================================================================
# SUPERSTRUCTURE (behind the top deck)
# =================================================================================================
static func draw_superstructure(ci: CanvasItem, width_cells: int, decks: int, t: float, dest: StringName = &"med") -> void:
	var w := float(width_cells) * CELL_W
	var top := -float(decks) * DECK_H            # top edge of the top deck cells
	var base := top + DECK_H - 8.0               # down to the top deck floor (hidden behind rooms)
	var dw := clampf(w * 0.3, 150.0, 260.0)
	var dx0 := w * 0.6 - dw * 0.5
	var dx1 := dx0 + dw
	var arctic := dest == &"arctic"
	var under := dest == &"underworld"
	var glass_top := Color("6FD0EE")
	var glass_bot := Color("2D8FBF")
	if under:
		glass_top = Color("FFD98A")
		glass_bot = Color("FF9E5E")
	# ---- deckhouse lower tier --------------------------------------------------------------------
	var low_top := top - 30.0
	U.rr(ci, Rect2(dx0, low_top, dw, base - low_top), 6.0, Color("E9E3D4"))
	U.rr(ci, Rect2(dx0, low_top, dw, base - low_top), 6.0, Color(0, 0, 0, 0.0))
	U.rect(ci, Rect2(dx1 - 10.0, low_top + 6.0, 10.0, base - low_top - 6.0), Color(0.1, 0.15, 0.3, 0.08))
	# windows (visible band above the deck line + big ones behind the sundeck)
	var nwin := int(dw / 26.0)
	for i in range(nwin):
		var wx := dx0 + 12.0 + float(i) * (dw - 24.0) / float(maxi(nwin - 1, 1)) - 9.0
		var wr := Rect2(wx, low_top + 8.0, 18.0, 13.0)
		U.rr(ci, wr, 3.5, glass_top)
		U.rr_ex(ci, Rect2(wr.position.x, wr.position.y + 6.5, wr.size.x, 6.5), 0.0, 0.0, 3.5, 3.5, glass_bot)
		U.rect(ci, Rect2(wr.position.x + 3.0, wr.position.y + 1.5, 2.2, 10.0), Color(1, 1, 1, 0.4))
		var wr2 := Rect2(wx - 1.0, top + 6.0, 20.0, 22.0)
		U.rr(ci, wr2, 5.0, glass_top)
		U.rr_ex(ci, Rect2(wr2.position.x, wr2.position.y + 12.0, wr2.size.x, 10.0), 0.0, 0.0, 5.0, 5.0, glass_bot)
		U.rect(ci, Rect2(wr2.position.x + 3.0, wr2.position.y + 2.0, 2.6, 17.0), Color(1, 1, 1, 0.38))
	# roof edge
	U.rr(ci, Rect2(dx0 - 4.0, low_top - 3.0, dw + 8.0, 6.0), 3.0, Palette.NAVY_LIGHT)
	# ---- bridge (upper tier) ---------------------------------------------------------------------
	var bw := dw * 0.64
	var bx0 := dx0 + dw * 0.2
	var btop := low_top - 30.0
	U.rr(ci, Rect2(bx0, btop, bw, 30.0), 5.0, Palette.HULL_WHITE)
	U.rect(ci, Rect2(bx0 + bw - 8.0, btop + 4.0, 8.0, 26.0), Color(0.1, 0.15, 0.3, 0.07))
	var strip := Rect2(bx0 + 6.0, btop + 6.0, bw - 12.0, 15.0)
	U.rr(ci, strip, 4.0, Color("2C6E93") if not under else Color("C9733F"))
	U.rr(ci, Rect2(strip.position.x, strip.position.y, strip.size.x, 7.0), 4.0, glass_top)
	var mull := int(strip.size.x / 24.0)
	for i in range(1, mull + 1):
		U.rect(ci, Rect2(strip.position.x + float(i) * strip.size.x / float(mull + 1) - 0.6, strip.position.y, 1.4, strip.size.y), Palette.HULL_WHITE)
	U.poly(ci, PackedVector2Array([Vector2(strip.position.x + 6.0, strip.end.y - 1.0), Vector2(strip.position.x + 14.0, strip.position.y + 1.0), Vector2(strip.position.x + 20.0, strip.position.y + 1.0), Vector2(strip.position.x + 12.0, strip.end.y - 1.0)]), Color(1, 1, 1, 0.3))
	U.rr(ci, Rect2(bx0 - 5.0, btop - 4.0, bw + 10.0, 7.0), 3.5, Palette.NAVY)
	U.rect(ci, Rect2(bx0 - 3.0, btop - 3.0, bw + 6.0, 1.2), Color(1, 1, 1, 0.2))
	# snow caps in the arctic
	if arctic:
		U.rr(ci, Rect2(bx0 - 5.0, btop - 8.0, bw + 10.0, 6.0), 3.0, Color("F4FBFF"))
		U.rr(ci, Rect2(dx0 - 4.0, low_top - 7.0, dw + 8.0, 6.0), 3.0, Color("F4FBFF"))
	# ---- radar + mast -----------------------------------------------------------------------------
	var mx := bx0 + bw * 0.5
	U.rr(ci, Rect2(mx - 1.4, btop - 26.0, 2.8, 24.0), 1.2, Palette.STEEL)
	var ra := absf(cos(t * 1.6)) * 11.0 + 1.5
	U.ellipse(ci, Vector2(mx, btop - 27.0), ra, 2.4, Palette.STEEL_DARK)
	U.ellipse(ci, Vector2(mx, btop - 27.6), ra, 1.8, Palette.STEEL)
	U.circ(ci, Vector2(mx, btop - 28.0), 1.6, Palette.CORAL if sin(t * 4.0) > 0.0 else Palette.CORAL_DARK)
	U.line(ci, Vector2(mx + 6.0, btop - 4.0), Vector2(mx + 14.0, btop - 16.0), Palette.STEEL, 1.2)
	U.circ(ci, Vector2(mx + 14.0, btop - 16.5), 1.3, Palette.STEEL)
	# ---- lifeboats on the deckhouse sides ---------------------------------------------------------
	for lbx in [dx0 - 22.0, dx1 + 6.0]:
		U.rr_ex(ci, Rect2(lbx, top + 4.0, 18.0, 9.0), 4.0, 4.0, 7.0, 7.0, Palette.ORANGE)
		U.rect(ci, Rect2(lbx + 1.0, top + 7.0, 16.0, 1.6), Palette.HULL_WHITE)
		U.line(ci, Vector2(lbx + 3.0, top - 6.0), Vector2(lbx + 3.0, top + 4.0), Palette.STEEL_DARK, 1.0)
		U.line(ci, Vector2(lbx + 15.0, top - 6.0), Vector2(lbx + 15.0, top + 4.0), Palette.STEEL_DARK, 1.0)
		U.rect(ci, Rect2(lbx - 1.0, top - 8.0, 20.0, 2.4), Palette.STEEL_DARK)
	# ---- funnel -----------------------------------------------------------------------------------
	var fx := clampf(w * 0.3, 60.0, dx0 - 36.0)
	var fh := 90.0
	var fb := base
	var ftop := top - fh
	var fw0 := 54.0
	var fw1 := 44.0
	U.poly(ci, PackedVector2Array([Vector2(fx - fw0 * 0.5, fb), Vector2(fx - fw1 * 0.5, ftop), Vector2(fx + fw1 * 0.5, ftop), Vector2(fx + fw0 * 0.5, fb)]), Palette.CORAL)
	U.poly(ci, PackedVector2Array([Vector2(fx + 4.0, fb), Vector2(fx + 7.0, ftop), Vector2(fx + fw1 * 0.5, ftop), Vector2(fx + fw0 * 0.5, fb)]), Palette.CORAL_DARK)
	U.poly(ci, PackedVector2Array([Vector2(fx - fw0 * 0.5 + 3.0, fb), Vector2(fx - fw1 * 0.5 + 3.0, ftop + 4.0), Vector2(fx - fw1 * 0.5 + 8.0, ftop + 4.0), Vector2(fx - fw0 * 0.5 + 8.0, fb)]), Color(1, 1, 1, 0.22))
	# white band with a star
	var by := ftop + 34.0
	U.poly(ci, PackedVector2Array([Vector2(fx - 23.0, by + 16.0), Vector2(fx - 22.4, by), Vector2(fx + 22.4, by), Vector2(fx + 23.0, by + 16.0)]), Palette.HULL_WHITE)
	U.star(ci, Vector2(fx, by + 8.0), 6.5, Palette.CORAL)
	# navy cap + rim
	U.rr(ci, Rect2(fx - 23.0, ftop, 46.0, 14.0), 3.0, Palette.NAVY)
	U.ellipse(ci, Vector2(fx, ftop), 23.0, 4.0, Palette.NAVY_LIGHT)
	U.ellipse(ci, Vector2(fx, ftop - 0.5), 18.0, 2.6, Color("11182A"))
	# smoke (ship moves right => smoke trails left)
	var smoke := Color(0.96, 0.96, 1.0)
	if under:
		smoke = Color(0.78, 1.0, 0.88)
	for i in range(6):
		var k := fmod(t * 0.3 + float(i) / 6.0, 1.0)
		var p := Vector2(fx - 4.0 - k * 80.0 + sin(k * 6.0 + float(i)) * 3.0, ftop - 8.0 - k * 54.0)
		var r := 6.0 + k * 15.0
		var a := 0.85 * (1.0 - k) * minf(1.0, k * 8.0 + 0.3)
		U.circ(ci, p + Vector2(1.5, 2.0), r, Color(0.55, 0.6, 0.78, a * 0.5))
		U.circ(ci, p, r, Color(smoke.r, smoke.g, smoke.b, a))
		U.circ(ci, p + Vector2(-r * 0.3, -r * 0.3), r * 0.5, Color(1, 1, 1, a * 0.7))
	# ---- bow flag ---------------------------------------------------------------------------------
	var fpx := w - 8.0
	var fp_top := top - 38.0
	U.rr(ci, Rect2(fpx - 1.2, fp_top, 2.4, 40.0), 1.0, Palette.STEEL)
	U.circ(ci, Vector2(fpx, fp_top - 1.0), 2.2, Palette.GOLD)
	var fl := PackedVector2Array()
	var fl2 := PackedVector2Array()
	for i in range(7):
		var f := float(i) / 6.0
		var wave := sin(t * 5.0 - f * 4.0) * 2.4 * f
		fl.append(Vector2(fpx + 1.0 + f * 26.0, fp_top + 2.0 + wave))
		fl2.append(Vector2(fpx + 1.0 + f * 26.0, fp_top + 15.0 + wave * 1.1 - f * 3.0))
	for i in range(fl.size() - 1):
		U.poly(ci, PackedVector2Array([fl[i], fl[i + 1], fl2[i + 1], fl2[i]]), Palette.CORAL)
	var mid := fl[3].lerp(fl2[3], 0.5)
	U.star(ci, mid + Vector2(-2.0, 0.0), 3.6, Palette.HULL_WHITE, 0.0)
