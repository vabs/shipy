class_name PortOverlay
extends Node2D
## Everything PortPhase draws ON the ship (lives in ShipView's "overlay" layer, so it shares the
## ship's bob and uses ship-local pixels): valid-cell hints, the placement ghost, the carried room's
## origin, disconnected-deck warnings, the guest path hint and little feedback effects. Also draws the
## "buildable space" grid on every EMPTY cell (empty cells are drawn as a quiet corridor by ShipArt, so this
## is what tells the player where rooms can go). The grid is cached and only redrawn when the layout changes.

const U := preload("res://src/render/art/art_util.gd")

var port: PortState
## Screen px per ship px (camera zoom). Used to keep small labels readable.
var zoom: float = 1.0

var hints: Array[Rect2] = []
var ghost_on: bool = false
var ghost_room_id: StringName = &""
var ghost_tier: int = 1
var ghost_rect: Rect2 = Rect2()        # where the ghost wants to be (snapped) or the free rect at the cursor
var ghost_valid: bool = false
var ghost_floating: bool = false       # true = not over a deck, follow the cursor freely
var origin_rect: Rect2 = Rect2()       # carried room's original spot (size 0 = none)
var bad_decks: Array[int] = []
var flash_decks: Array[int] = []
var flash_time: float = 0.0
var hover_lock_rect: Rect2 = Rect2()   # locked room under the cursor
var path_points: PackedVector2Array = PackedVector2Array()

## Buildable-space grid on empty cells (cheap to turn off for screenshots of the bare ship).
var show_grid: bool = true

var _grid_node: _GridNode
var _grid_sig: int = -1
var _grid_alpha: float = 0.0
var _t: float = 0.0
var _ghost_pos: Vector2 = Vector2.ZERO
var _ghost_alpha: float = 0.0
var _ghost_shake: float = 0.0
var _fx: Array[Dictionary] = []
var _was_valid: bool = true
var _baker: ArtBake
## Dev metric: microseconds the last _draw() took.
var draw_usec: int = 0


class _GridNode extends Node2D:
	var ov: PortOverlay
	func _draw() -> void:
		ov._draw_grid(self)


func _ready() -> void:
	z_index = 10
	_grid_node = _GridNode.new()
	_grid_node.name = "BuildGrid"
	_grid_node.ov = self
	_grid_node.z_index = -1
	add_child(_grid_node)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_baker = ArtBake.new()
	_baker.name = "GhostBaker"
	add_child(_baker)


func _process(delta: float) -> void:
	_t += delta
	_update_grid(delta)
	flash_time = maxf(0.0, flash_time - delta)
	_ghost_shake = maxf(0.0, _ghost_shake - delta * 4.0)
	var i: int = _fx.size() - 1
	while i >= 0:
		if _t - float(_fx[i]["t0"]) > float(_fx[i]["dur"]):
			_fx.remove_at(i)
		i -= 1
	# ghost glide
	if ghost_on:
		_ghost_alpha = minf(_ghost_alpha + delta * 10.0, 1.0)
		if ghost_floating or _ghost_alpha < 0.2 or _ghost_pos.distance_to(ghost_rect.position) > 400.0:
			_ghost_pos = ghost_rect.position
		else:
			_ghost_pos = _ghost_pos.lerp(ghost_rect.position, 1.0 - exp(-delta * 26.0))
		if _was_valid and not ghost_valid and not ghost_floating:
			_ghost_shake = 1.0
		_was_valid = ghost_valid
	else:
		_ghost_alpha = maxf(_ghost_alpha - delta * 8.0, 0.0)
	if ghost_on or _ghost_alpha > 0.0 or not hints.is_empty() or not bad_decks.is_empty() or not _fx.is_empty() \
			or flash_time > 0.0 or origin_rect.size.x > 0.0 or hover_lock_rect.size.x > 0.0 or path_points.size() > 1:
		queue_redraw()


# ------------------------------------------------------------------------------------------------
# effects
# ------------------------------------------------------------------------------------------------
func fx_text(pos: Vector2, text: String, color: Color, scale_f: float = 1.4) -> void:
	_fx.append({"kind": &"text", "pos": pos, "t0": _t, "dur": 1.15, "text": text, "color": color, "s": scale_f})


func fx_place(rect: Rect2) -> void:
	var base_y: float = rect.end.y - 4.0
	var n: int = maxi(3, int(rect.size.x / 34.0))
	for i in n:
		var px: float = rect.position.x + rect.size.x * (float(i) + 0.5) / float(n)
		_fx.append({"kind": &"puff", "pos": Vector2(px, base_y), "t0": _t + float(i % 2) * 0.04, "dur": 0.55})
	for i in 4:
		var a: float = float(i) * 1.7 + rect.position.x
		_fx.append({"kind": &"sparkle", "pos": rect.get_center() + Vector2(cos(a), sin(a) * 0.7) * rect.size.x * 0.35, "t0": _t + 0.05 * float(i), "dur": 0.6, "color": Palette.SUN})


func fx_poof(rect: Rect2) -> void:
	var c: Vector2 = rect.get_center()
	for i in 5:
		var a: float = float(i) * TAU / 5.0
		_fx.append({"kind": &"puff", "pos": c + Vector2(cos(a) * rect.size.x * 0.28, sin(a) * rect.size.y * 0.25), "t0": _t + 0.02 * float(i), "dur": 0.6})


func fx_upgrade(rect: Rect2) -> void:
	var c: Vector2 = rect.get_center()
	_fx.append({"kind": &"stars", "pos": c, "t0": _t, "dur": 0.8})
	for i in 5:
		var a: float = float(i) * 1.3
		_fx.append({"kind": &"sparkle", "pos": c + Vector2(cos(a), sin(a) * 0.6) * rect.size.x * 0.4, "t0": _t + 0.06 * float(i), "dur": 0.7, "color": Palette.GOLD})


func fx_coin(pos: Vector2) -> void:
	_fx.append({"kind": &"coin", "pos": pos, "t0": _t, "dur": 0.8})


func clear_fx() -> void:
	_fx.clear()


# ------------------------------------------------------------------------------------------------
# buildable-space grid
# ------------------------------------------------------------------------------------------------
func _layout_sig() -> int:
	var h: int = port.layout.rooms.size()
	for r in port.layout.rooms:
		h = (h * 31 + r.uid * 7 + r.x * 3 + r.first_deck() * 11 + r.def.width * 5) % 1000003
	return h


func _update_grid(delta: float) -> void:
	if port == null or _grid_node == null:
		return
	var sig: int = _layout_sig()
	if sig != _grid_sig:
		_grid_sig = sig
		_grid_node.queue_redraw()
	# calm while idle, brighter while the player is placing / moving a room
	var want: float = 0.0
	if show_grid:
		want = 1.0 if (ghost_on or not hints.is_empty()) else 0.62
	_grid_alpha = move_toward(_grid_alpha, want, delta * 3.0)
	_grid_node.modulate.a = _grid_alpha
	_grid_node.visible = _grid_alpha > 0.01


## One quiet "L" bracket set per empty cell + a faint cool wash per run of empty cells.
func _draw_grid(ci: CanvasItem) -> void:
	var hull: HullDef = port.hull
	var w: int = hull.width
	var cw: float = SimConst.CELL_W
	var dh: float = SimConst.DECK_H
	var edge := Color(0.16, 0.5, 0.74, 0.62)
	var wash := Color(0.5, 0.82, 1.0, 0.15)
	for d in hull.decks:
		var occ: PackedByteArray = PackedByteArray()
		occ.resize(w)
		for r in port.layout.rooms:
			if r.first_deck() <= d and d < r.first_deck() + r.decks_tall(hull.decks):
				for c in range(maxi(r.x, 0), mini(r.x + r.def.width, w)):
					occ[c] = 1
		var top_deck: bool = d == hull.decks - 1
		var y0: float = -float(d + 1) * dh
		var c: int = 0
		while c < w:
			if occ[c] != 0:
				c += 1
				continue
			var c1: int = c
			while c1 < w and occ[c1] == 0:
				c1 += 1
			# run [c, c1)
			var rx0: float = float(c) * cw
			var rx1: float = float(c1) * cw
			var top_off: float = 36.0 if top_deck else 9.0
			var inner := Rect2(rx0 + 2.0, y0 + top_off, rx1 - rx0 - 4.0, dh - top_off - 13.0)
			U.rr(ci, inner, 6.0, wash)
			for k in range(c, c1):
				var cell := Rect2(float(k) * cw + 3.5, inner.position.y + 1.5, cw - 7.0, inner.size.y - 3.0)
				var ln: float = 6.0
				for corner in 4:
					var px: float = cell.position.x if corner % 2 == 0 else cell.end.x
					var py: float = cell.position.y if corner < 2 else cell.end.y
					var sx: float = 1.0 if corner % 2 == 0 else -1.0
					var sy: float = 1.0 if corner < 2 else -1.0
					ci.draw_line(Vector2(px, py), Vector2(px + sx * ln, py), edge, 1.8, true)
					ci.draw_line(Vector2(px, py), Vector2(px, py + sy * ln), edge, 1.8, true)
				# tiny "+" = room can go here (skipped when the wall has a porthole / picture in the middle)
				var cd: int = ShipArt.cell_detail(k, d) if not top_deck else 0
				if cd == 1 or cd == 5:
					continue
				var cc: Vector2 = cell.get_center()
				var pc := Color(edge.r, edge.g, edge.b, 0.45)
				ci.draw_line(cc + Vector2(-3.5, 0.0), cc + Vector2(3.5, 0.0), pc, 1.6, true)
				ci.draw_line(cc + Vector2(0.0, -3.5), cc + Vector2(0.0, 3.5), pc, 1.6, true)
			c = c1


# ------------------------------------------------------------------------------------------------
# drawing
# ------------------------------------------------------------------------------------------------
func _draw() -> void:
	if port == null:
		return
	var t0: int = Time.get_ticks_usec()
	_draw_impl()
	draw_usec = Time.get_ticks_usec() - t0


func _draw_impl() -> void:
	_draw_deck_tags()
	_draw_hints()
	_draw_bad_decks()
	_draw_flash()
	if origin_rect.size.x > 0.0:
		_draw_origin()
	if path_points.size() > 1:
		_draw_path()
	if hover_lock_rect.size.x > 0.0:
		var c := Vector2(hover_lock_rect.end.x - 18.0, hover_lock_rect.position.y + 22.0)
		U.circ(self, c + Vector2(0, 2), 17.0, Color(0, 0, 0, 0.2))
		U.circ(self, c, 17.0, Palette.NAVY_LIGHT)
		IconArt.draw_icon(self, &"lock", c, 24.0)
	if _ghost_alpha > 0.01 and ghost_room_id != &"":
		_draw_ghost()
	_draw_fx()


## Little deck numbers on the bow side so "Deck 3 is not connected" can be matched to the ship.
## The gangway deck (where guests board) is yellow.
func _draw_deck_tags() -> void:
	var hull: HullDef = port.hull
	var strong: bool = ghost_on or flash_time > 0.0 or not bad_decks.is_empty()
	var a: float = 0.95 if strong else 0.6
	var xc: float = float(hull.width) * SimConst.CELL_W + 24.0
	for d in hull.decks:
		var c := Vector2(xc, -float(d) * SimConst.DECK_H - SimConst.DECK_H * 0.5 + 4.0)
		var is_gw: bool = d == hull.gangway_deck
		var is_top: bool = d == hull.decks - 1
		var base: Color = Palette.SUN if is_gw else Palette.NAVY_LIGHT
		var txt_col: Color = Palette.INK if is_gw else Palette.CREAM
		var bad: bool = bad_decks.has(d)
		if bad:
			base = Palette.CORAL
			txt_col = Color.WHITE
		base.a = a
		txt_col.a = a
		if is_top:
			var r := Rect2(c.x - 18.0, c.y - 11.0, 36.0, 22.0)
			U.rr(self, Rect2(r.position + Vector2(0, 2), r.size), 11.0, Color(0, 0, 0, 0.18 * a))
			U.rr(self, r, 11.0, base)
			_ctext("TOP", Vector2(c.x, c.y + 5.0), 14, txt_col)
		else:
			U.circ(self, c + Vector2(0, 2), 12.0, Color(0, 0, 0, 0.18 * a))
			U.circ(self, c, 12.0, base)
			_ctext(str(d + 1), Vector2(c.x, c.y + 5.5), 16, txt_col)


## Bold text centred on pos.x (baseline at pos.y).
func _ctext(text: String, pos: Vector2, size_px: int, color: Color) -> void:
	var w: float = U.font_bold().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	U.text(self, text, Vector2(pos.x - w * 0.5, pos.y), size_px, color)


func _draw_hints() -> void:
	if hints.is_empty():
		return
	var pulse: float = 0.5 + 0.5 * sin(_t * 3.2)
	for r in hints:
		var rr := r.grow(-3.0)
		U.rr(self, rr, 8.0, Color(Palette.MINT.r, Palette.MINT.g, Palette.MINT.b, 0.12 + 0.06 * pulse))
		U.rr_outline(self, rr, 8.0, Color(Palette.MINT_DARK.r, Palette.MINT_DARK.g, Palette.MINT_DARK.b, 0.55 + 0.25 * pulse), 2.5)
		U.rr(self, Rect2(rr.position.x + 6.0, rr.end.y - 9.0, rr.size.x - 12.0, 4.0), 2.0, Color(0.55, 0.95, 0.7, 0.55 + 0.25 * pulse))


func _draw_bad_decks() -> void:
	if bad_decks.is_empty():
		return
	var pulse: float = 0.5 + 0.5 * sin(_t * 4.0)
	for d in bad_decks:
		var xs: Array[float] = []
		var xe: Array[float] = []
		for r in port.layout.rooms_on_deck(d):
			var rect: Rect2 = SimConst.room_rect(r.first_deck(), r.x, r.def.width, r.decks_tall(port.hull.decks))
			if r.is_transport():
				continue
			U.rr(self, rect, 6.0, Color(0.95, 0.22, 0.28, 0.20 + 0.10 * pulse))
			U.rr_outline(self, rect.grow(-1.5), 6.0, Color(1.0, 0.35, 0.35, 0.55 + 0.25 * pulse), 2.5)
			xs.append(rect.position.x)
			xe.append(rect.end.x)
		if xs.is_empty():
			continue
		var x0: float = xs.min()
		var x1: float = xe.max()
		var cx: float = (x0 + x1) * 0.5
		var cy: float = -float(d) * SimConst.DECK_H - 26.0
		var k: float = clampf(1.0 / maxf(zoom, 0.3), 1.0, 1.7)
		var c := Vector2(cx, cy)
		var bob: float = sin(_t * 5.0) * 3.0
		# little sign: warning icon + text
		var label := "No way up here" if d > port.hull.gangway_deck else "No way down here"
		var fs: int = int(round(17.0 * k))
		var wdt: float = U.font_bold().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pw: float = wdt + 52.0 * k
		var ph: float = 36.0 * k
		var pr := Rect2(c.x - pw * 0.5, c.y - ph * 0.5 + bob, pw, ph)
		U.rr(self, Rect2(pr.position + Vector2(0, 3), pr.size), ph * 0.5, Color(0, 0, 0, 0.22))
		U.rr(self, pr, ph * 0.5, Palette.CORAL)
		U.rr_outline(self, pr, ph * 0.5, Palette.CORAL_DARK, 2.0)
		IconArt.draw_icon(self, &"warning", pr.position + Vector2(ph * 0.5 + 2.0, ph * 0.5 - 1.0), ph * 0.72, _t)
		U.text(self, label, Vector2(pr.position.x + ph + 2.0 * k, pr.position.y + ph * 0.5 + float(fs) * 0.35), fs, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1.0)


func _draw_flash() -> void:
	if flash_time <= 0.0 or flash_decks.is_empty():
		return
	var a: float = clampf(flash_time / 1.0, 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(_t * 9.0)
	for d in flash_decks:
		var w: float = float(port.hull.width) * SimConst.CELL_W
		var rect := Rect2(0.0, -float(d + 1) * SimConst.DECK_H, w, SimConst.DECK_H)
		U.rr_outline(self, rect.grow(-2.0), 10.0, Color(1.0, 0.3, 0.32, (0.6 + 0.4 * pulse) * a), 5.0)
		U.rr(self, rect, 10.0, Color(1.0, 0.25, 0.3, (0.12 + 0.12 * pulse) * a))


func _draw_origin() -> void:
	var r := origin_rect
	U.rr(self, r, 8.0, Color(0.96, 0.93, 0.85, 0.62))
	var per: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	var off: float = fmod(_t * 18.0, 14.0)
	for s in 4:
		var a: Vector2 = per[s]
		var b: Vector2 = per[s + 1]
		var len: float = a.distance_to(b)
		var dir: Vector2 = (b - a) / maxf(len, 0.01)
		var p: float = -off
		while p < len:
			var p0: float = maxf(p, 0.0)
			var p1: float = minf(p + 8.0, len)
			if p1 > p0:
				U.line(self, a + dir * p0, a + dir * p1, Color(Palette.NAVY.r, Palette.NAVY.g, Palette.NAVY.b, 0.55), 2.5)
			p += 14.0


func _draw_path() -> void:
	var pts := path_points
	U.pline(self, pts, Color(Palette.SUN.r, Palette.SUN.g, Palette.SUN.b, 0.28), 4.0)
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	var d: float = fmod(_t * 70.0, 22.0)
	while d < total:
		var acc: float = 0.0
		for i in range(pts.size() - 1):
			var seg: float = pts[i].distance_to(pts[i + 1])
			if d <= acc + seg:
				var p: Vector2 = pts[i].lerp(pts[i + 1], (d - acc) / maxf(seg, 0.01))
				U.circ(self, p, 4.0, Color(1.0, 0.92, 0.55, 0.9))
				break
			acc += seg
		d += 22.0
	U.circ(self, pts[0], 7.0, Color(Palette.SUN.r, Palette.SUN.g, Palette.SUN.b, 0.8))
	IconArt.draw_icon(self, &"guest", pts[0] + Vector2(0, -2), 14.0)


func _draw_ghost() -> void:
	var size_v: Vector2 = ghost_rect.size
	var pos: Vector2 = _ghost_pos
	if _ghost_shake > 0.0 and not ghost_floating:
		pos.x += sin(_t * 70.0) * 5.0 * _ghost_shake
	var rect := Rect2(pos, size_v)
	if not ghost_floating:
		# landing marker where the ghost will settle
		var col: Color = Palette.MINT if ghost_valid else Palette.CORAL
		var tgt := ghost_rect
		U.rr(self, tgt, 8.0, Color(col.r, col.g, col.b, 0.14))
		U.rr_outline(self, tgt.grow(-1.0), 8.0, Color(col.r, col.g, col.b, 0.7), 3.0)
	var old: float = U.alpha
	var st: Dictionary = {"ghost_preview": true, "invalid": (not ghost_valid) and not ghost_floating, "t": _t, "busy_ratio": 0.0, "highlight": 0}
	var back: Texture2D = _ghost_tex(false, rect.size)
	var a: float = 0.78 * _ghost_alpha
	if back != null:
		# static art comes from the shared bake cache (same textures ShipView uses); only the animated /
		# overlay parts are drawn as vectors, exactly like a placed room
		draw_texture_rect(back, rect, false, Color(1, 1, 1, a))
		U.alpha = old * _ghost_alpha
		st["pass"] = 2
		RoomArt.draw_room(self, ghost_room_id, rect, ghost_tier, st)
		if ghost_room_id != &"stairs" and ghost_room_id != &"elevator":
			if ShipView._has_static_front(ghost_room_id):
				var front: Texture2D = _ghost_tex(true, rect.size)
				if front != null:
					draw_texture_rect(front, rect, false, Color(1, 1, 1, a))
			RoomArt.draw_room_front(self, ghost_room_id, rect, ghost_tier, st)
	else:
		U.alpha = old * _ghost_alpha
		st["pass"] = 0
		RoomArt.draw_room(self, ghost_room_id, rect, ghost_tier, st)
		if ghost_room_id != &"stairs" and ghost_room_id != &"elevator":
			RoomArt.draw_room_front(self, ghost_room_id, rect, ghost_tier, st)
	U.alpha = old


## Baked static art for the ghost; requests the bake (shared cache key with ShipView) when missing.
func _ghost_tex(front: bool, size_v: Vector2) -> Texture2D:
	var key: String = "room|%s|%d|%d|%d|%d|%d" % [ghost_room_id, ghost_tier, int(size_v.x), int(size_v.y), 0, 1 if front else 0]
	var tex: Texture2D = ArtBake.get_tex(key)
	if tex == null:
		var rid: StringName = ghost_room_id
		var tr: int = ghost_tier
		var sz: Vector2 = size_v
		_baker.request(key, sz, 3.0, func(ci: CanvasItem) -> void:
			U.begin_scaled(ci, Vector2.ZERO, 1.0)
			var r0 := Rect2(Vector2.ZERO, sz)
			var st0: Dictionary = {"pass": 1, "broken": false, "t": 0.0}
			if front:
				RoomArt.draw_room_front(ci, rid, r0, tr, st0)
			else:
				RoomArt.draw_room(ci, rid, r0, tr, st0)
			U.end_scaled(ci))
	return tex


func _draw_fx() -> void:
	for f in _fx:
		var k: float = (_t - float(f["t0"])) / float(f["dur"])
		if k < 0.0:
			continue
		var pos: Vector2 = f["pos"]
		match f["kind"]:
			&"puff":
				FxArt.draw_puff(self, pos, k)
			&"sparkle":
				FxArt.draw_sparkle(self, pos, k, f["color"])
			&"stars":
				FxArt.draw_stars(self, pos, k)
			&"coin":
				FxArt.draw_coin_pop(self, pos, k)
			&"text":
				var s: float = float(f["s"])
				U.xf(self, pos, 0.0, Vector2(s, s))
				FxArt.draw_float_text(self, Vector2.ZERO, String(f["text"]), f["color"], k)
				U.xf_end(self)
