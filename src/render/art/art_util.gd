class_name ArtUtil
extends RefCounted
## Low-level drawing helpers shared by every art class. All art code draws THROUGH these wrappers so that
## a global alpha multiplier (`ArtUtil.alpha`, used for ghost previews / fades) and a base transform
## (`ArtUtil.base_xf`, used to scale whole rooms into UI cards) apply to everything.
##
## PERFORMANCE: in this engine build draw_circle / draw_colored_polygon / draw_style_box / draw_arc cost
## 15-20 us each (CPU-side tessellation) while draw_rect / draw_line / draw_mesh / draw_primitive cost
## ~0.3 us. Everything here therefore draws through cached unit meshes (circles, rounded rects, stars,
## polygons) placed with a transform, or through draw_rect/draw_line/draw_primitive.
##
## Public statics (all take the CanvasItem `ci` currently inside _draw):
##   rect / rr (rounded rect) / rr_border / rr_outline / rr_ex (per-corner radii) / rr_shadow / circ / ring /
##   ellipse / poly / poly_xf / polyc / line / pline / arc / vgrad / hgrad / star / text / shadow / dashed_ring /
##   capsule / rbox / rbox_outline
##   xf(ci, pos, rot, scale) + xf_end(ci)  -> local transform (composes with base_xf); xf_push / xf_load nest
##   begin_scaled(ci, offset, scale) / end_scaled(ci) -> draw a whole logical-space scene scaled
##   font() / font_bold() -> Fredoka (or default) fonts
##   hash01(n) -> deterministic float 0..1, mixc(a,b,t), pulse(t, hz)

static var alpha: float = 1.0
static var base_xf: Transform2D = Transform2D.IDENTITY
## Current local transform (base_xf composed with the last xf()).
static var cur_xf: Transform2D = Transform2D.IDENTITY

## Bake support: pass_mode 0 = draw everything, 1 = static parts only, 2 = dynamic parts only. Art code
## brackets its animated / state-dependent parts with dyn_begin() ... dyn_end(); while `skip` is true every
## primitive below returns immediately.
static var pass_mode: int = 0
static var skip: bool = false

static var _circles: Dictionary = {}
static var _rr_meshes: Dictionary = {}
static var _rr_outlines: Dictionary = {}
static var _poly_meshes: Dictionary = {}
static var _star_meshes: Dictionary = {}
static var _star_cache: Dictionary = {}
static var _pc3: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
static var _pc4: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
static var _no_uv: PackedVector2Array = PackedVector2Array()
static var _font: Font = null
static var _font_bold: Font = null
static var _font_tried: bool = false

const TAU_F: float = TAU
const _CACHE_LIMIT: int = 20000


# ---- fonts --------------------------------------------------------------------------------------
static func _load_fonts() -> void:
	if _font_tried:
		return
	_font_tried = true
	var path := "res://assets/fonts/Fredoka.ttf"
	if ResourceLoader.exists(path):
		var base: Font = load(path)
		if base != null:
			var fv := FontVariation.new()
			fv.base_font = base
			fv.variation_opentype = {2003265652: 500.0}
			_font = fv
			var fb := FontVariation.new()
			fb.base_font = base
			fb.variation_opentype = {2003265652: 650.0}
			_font_bold = fb
	if _font == null:
		_font = ThemeDB.fallback_font
		_font_bold = ThemeDB.fallback_font


static func font() -> Font:
	_load_fonts()
	return _font


static func font_bold() -> Font:
	_load_fonts()
	return _font_bold


# ---- state --------------------------------------------------------------------------------------
static func col(c: Color) -> Color:
	if alpha >= 0.999:
		return c
	return Color(c.r, c.g, c.b, c.a * alpha)


static func hash01(n: int) -> float:
	var x: int = (n * 73856093) ^ (n * 19349663 + 83492791)
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(absi(x) % 10007) / 10007.0


static func mixc(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))


## 0..1 smooth pulse at `hz` cycles per second.
static func pulse(t: float, hz: float = 1.0) -> float:
	return 0.5 + 0.5 * sin(t * TAU * hz)


static func set_pass(mode: int) -> void:
	pass_mode = mode
	skip = mode == 2


static func dyn_begin() -> void:
	skip = pass_mode == 1


static func dyn_end() -> void:
	skip = pass_mode == 2


## Set the local transform (replaces any previous local transform; composes with base_xf).
static func xf(ci: CanvasItem, pos: Vector2, rot: float = 0.0, scl: Vector2 = Vector2.ONE) -> void:
	cur_xf = base_xf * Transform2D(rot, scl, 0.0, pos)
	ci.draw_set_transform_matrix(cur_xf)


## Set the local transform from a full Transform2D (composed with base_xf).
static func xf_raw(ci: CanvasItem, t: Transform2D) -> void:
	cur_xf = base_xf * t
	ci.draw_set_transform_matrix(cur_xf)


## Nest a further transform inside the current one; returns the previous transform for xf_load().
static func xf_push(ci: CanvasItem, pos: Vector2, rot: float = 0.0, scl: Vector2 = Vector2.ONE) -> Transform2D:
	var prev := cur_xf
	cur_xf = cur_xf * Transform2D(rot, scl, 0.0, pos)
	ci.draw_set_transform_matrix(cur_xf)
	return prev


static func xf_load(ci: CanvasItem, saved: Transform2D) -> void:
	cur_xf = saved
	ci.draw_set_transform_matrix(cur_xf)


static func xf_end(ci: CanvasItem) -> void:
	cur_xf = base_xf
	ci.draw_set_transform_matrix(base_xf)


## Draw a logical-space scene scaled: everything drawn between begin_scaled and end_scaled is mapped by
## offset + scale. Used by catalog cards / portraits.
static func begin_scaled(ci: CanvasItem, offset: Vector2, scl: float) -> void:
	base_xf = Transform2D(0.0, Vector2(scl, scl), 0.0, offset)
	cur_xf = base_xf
	ci.draw_set_transform_matrix(base_xf)


static func end_scaled(ci: CanvasItem) -> void:
	base_xf = Transform2D.IDENTITY
	cur_xf = base_xf
	ci.draw_set_transform_matrix(base_xf)


# ---- mesh cache ---------------------------------------------------------------------------------
static func _make_mesh(verts: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Cached meshes are referenced by RETAINED canvas commands, so they must never be freed: the caches only
## grow (keys are quantized so they stay bounded in practice). Above the cap new shapes are not cached.
static func _full(d: Dictionary) -> bool:
	return d.size() > _CACHE_LIMIT


static func _circle_mesh(seg: int) -> ArrayMesh:
	var m: ArrayMesh = _circles.get(seg)
	if m != null:
		return m
	var v := PackedVector2Array()
	var idx := PackedInt32Array()
	v.append(Vector2.ZERO)
	for i in range(seg):
		var a := TAU * float(i) / float(seg)
		v.append(Vector2(cos(a), sin(a)))
	for i in range(seg):
		idx.append(0)
		idx.append(1 + i)
		idx.append(1 + (i + 1) % seg)
	m = _make_mesh(v, idx)
	_circles[seg] = m
	return m


static func _seg_for(r: float) -> int:
	var er := r * cur_xf.x.length()
	if er < 2.0:
		return 10
	if er < 6.0:
		return 18
	if er < 16.0:
		return 26
	if er < 60.0:
		return 40
	return 56


static func _arc_pts(out: PackedVector2Array, c: Vector2, r: float, a0: float, a1: float, seg: int) -> void:
	for i in range(seg + 1):
		var a := lerpf(a0, a1, float(i) / float(seg))
		out.append(c + Vector2(cos(a), sin(a)) * r)


static func _rr_loop(w: float, h: float, tl: float, tr: float, br: float, bl: float, seg: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	_arc_pts(p, Vector2(tl, tl), tl, PI, PI * 1.5, seg)
	_arc_pts(p, Vector2(w - tr, tr), tr, PI * 1.5, TAU, seg)
	_arc_pts(p, Vector2(w - br, h - br), br, 0.0, PI * 0.5, seg)
	_arc_pts(p, Vector2(bl, h - bl), bl, PI * 0.5, PI, seg)
	return p


## Cached rounded-rect mesh with origin at the top-left corner. Sizes are quantized (0.25 px, or 1/64 for
## tiny unit-space shapes) so the cache stays small.
static func _rr_mesh(w: float, h: float, tl: float, tr: float, br: float, bl: float, seg: int) -> ArrayMesh:
	var small := maxf(w, h) < 8.0
	var q := 64.0 if small else 4.0
	var kw := int(roundf(w * q))
	var kh := int(roundf(h * q))
	var k0 := clampi(int(roundf(tl * q)), 0, 255)
	var k1 := clampi(int(roundf(tr * q)), 0, 255)
	var k2 := clampi(int(roundf(br * q)), 0, 255)
	var k3 := clampi(int(roundf(bl * q)), 0, 255)
	var key: int = kw | (kh << 16) | (k0 << 32) | (k1 << 40) | (k2 << 48) | (k3 << 56)
	var dk: int = (seg << 1) | (1 if small else 0)
	var d: Dictionary = _rr_meshes.get(dk, {})
	if d.is_empty():
		_rr_meshes[dk] = d
	var m: ArrayMesh = d.get(key)
	if m != null:
		return m
	var qw := float(kw) / q
	var qh := float(kh) / q
	var loop := _rr_loop(qw, qh, float(k0) / q, float(k1) / q, float(k2) / q, float(k3) / q, seg)
	var v := PackedVector2Array()
	v.append(Vector2(qw * 0.5, qh * 0.5))
	v.append_array(loop)
	var idx := PackedInt32Array()
	var n := loop.size()
	for i in range(n):
		idx.append(0)
		idx.append(1 + i)
		idx.append(1 + (i + 1) % n)
	m = _make_mesh(v, idx)
	d[key] = m
	return m


static func _rr_seg(rad: float) -> int:
	var er := rad * cur_xf.x.length()
	return clampi(int(ceil(er * 0.5)) + 3, 3, 9)


static func _rr_outline_mesh(w: float, h: float, rad: float, bw: float, seg: int) -> ArrayMesh:
	var small := maxf(w, h) < 8.0
	var q := 64.0 if small else 4.0
	var kw := int(roundf(w * q))
	var kh := int(roundf(h * q))
	var kr := clampi(int(roundf(rad * q)), 0, 1023)
	var kb := clampi(int(roundf(bw * q)), 1, 1023)
	var key: int = kw | (kh << 16) | (kr << 32) | (kb << 42)
	var dk: int = (seg << 1) | (1 if small else 0)
	var d: Dictionary = _rr_outlines.get(dk, {})
	if d.is_empty():
		_rr_outlines[dk] = d
	var m: ArrayMesh = d.get(key)
	if m != null:
		return m
	var qw := float(kw) / q
	var qh := float(kh) / q
	var r0 := float(kr) / q
	var b := float(kb) / q
	var outer := _rr_loop(qw, qh, r0, r0, r0, r0, seg)
	var r1 := maxf(r0 - b, 0.0)
	var inner_loop := _rr_loop(qw - 2.0 * b, qh - 2.0 * b, r1, r1, r1, r1, seg)
	var v := PackedVector2Array()
	v.append_array(outer)
	for p in inner_loop:
		v.append(p + Vector2(b, b))
	var n := outer.size()
	var idx := PackedInt32Array()
	for i in range(n):
		var j := (i + 1) % n
		idx.append(i)
		idx.append(j)
		idx.append(n + i)
		idx.append(n + i)
		idx.append(j)
		idx.append(n + j)
	m = _make_mesh(v, idx)
	d[key] = m
	return m


static func _poly_mesh(pts: PackedVector2Array) -> ArrayMesh:
	var key := hash(pts)
	var m: ArrayMesh = _poly_meshes.get(key)
	if m != null:
		return m
	if _full(_poly_meshes):
		return null
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		# degenerate / self-intersecting: fall back to a fan around the first point
		for i in range(1, pts.size() - 1):
			idx.append(0)
			idx.append(i)
			idx.append(i + 1)
	m = _make_mesh(pts, idx)
	_poly_meshes[key] = m
	return m


static func _star_mesh(inner: float, points: int) -> ArrayMesh:
	var key := int(inner * 100.0) * 100 + points
	var m: ArrayMesh = _star_meshes.get(key)
	if m != null:
		return m
	var p := star_pts(inner, points)
	m = _make_mesh(p, Geometry2D.triangulate_polygon(p))
	_star_meshes[key] = m
	return m


# ---- primitives ---------------------------------------------------------------------------------
static func rect(ci: CanvasItem, r: Rect2, c: Color) -> void:
	if skip:
		return
	ci.draw_rect(r, col(c))


static func rr(ci: CanvasItem, r: Rect2, radius: float, c: Color) -> void:
	if skip:
		return
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	if rad * cur_xf.x.length() < 0.6:
		ci.draw_rect(r, col(c))
		return
	var m := _rr_mesh(r.size.x, r.size.y, rad, rad, rad, rad, _rr_seg(rad))
	ci.draw_mesh(m, null, Transform2D(0.0, Vector2.ONE, 0.0, r.position), col(c))


## Per-corner radii (top-left, top-right, bottom-right, bottom-left).
static func rr_ex(ci: CanvasItem, r: Rect2, tl: float, tr: float, br: float, bl: float, c: Color) -> void:
	if skip:
		return
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var mx := minf(r.size.x, r.size.y) * 0.5
	tl = minf(tl, mx)
	tr = minf(tr, mx)
	br = minf(br, mx)
	bl = minf(bl, mx)
	var big := maxf(maxf(tl, tr), maxf(br, bl))
	if big * cur_xf.x.length() < 0.6:
		ci.draw_rect(r, col(c))
		return
	var m := _rr_mesh(r.size.x, r.size.y, tl, tr, br, bl, _rr_seg(big))
	ci.draw_mesh(m, null, Transform2D(0.0, Vector2.ONE, 0.0, r.position), col(c))


## Outline only (no fill); the border is drawn INSIDE the rect.
static func rr_outline(ci: CanvasItem, r: Rect2, radius: float, border: Color, bw: float) -> void:
	if skip:
		return
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var m := _rr_outline_mesh(r.size.x, r.size.y, rad, bw, _rr_seg(rad))
	ci.draw_mesh(m, null, Transform2D(0.0, Vector2.ONE, 0.0, r.position), col(border))


static func rr_border(ci: CanvasItem, r: Rect2, radius: float, fill: Color, border: Color, bw: float) -> void:
	if fill.a > 0.001:
		rr(ci, r, radius, fill)
	rr_outline(ci, r, radius, border, bw)


## Rounded rect with a soft drop shadow (a few stacked translucent layers).
static func rr_shadow(ci: CanvasItem, r: Rect2, radius: float, c: Color, shadow_c: Color, shadow_size: float, off: Vector2) -> void:
	for i in range(3):
		var g := shadow_size * (1.0 - float(i) / 3.0)
		rr(ci, Rect2(r.position - Vector2(g, g) + off, r.size + Vector2(g, g) * 2.0), radius + g, Color(shadow_c.r, shadow_c.g, shadow_c.b, shadow_c.a / 3.0))
	rr(ci, r, radius, c)


static func circ(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	if skip:
		return
	if r <= 0.0:
		return
	ci.draw_mesh(_circle_mesh(_seg_for(r)), null, Transform2D(Vector2(r, 0.0), Vector2(0.0, r), c), col(color))


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, color: Color) -> void:
	if skip:
		return
	if rx <= 0.0 or ry <= 0.0:
		return
	ci.draw_mesh(_circle_mesh(_seg_for(maxf(rx, ry))), null, Transform2D(Vector2(rx, 0.0), Vector2(0.0, ry), c), col(color))


## Antialiased line feathering is 1 LOCAL unit wide, so only use it when the local transform is ~1:1
## (in unit-space icons MSAA does the smoothing and feathering would show as a halo).
static func _aa() -> bool:
	return cur_xf.x.length() < 3.0


static func ring(ci: CanvasItem, c: Vector2, r: float, color: Color, w: float = 1.5) -> void:
	arc(ci, c, r, 0.0, TAU, color, w, 24)


static func line(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, w: float = 1.5) -> void:
	if skip:
		return
	ci.draw_line(a, b, col(color), w, _aa())


## Polyline as separate segments (cheap); thick lines get round joints.
static func pline(ci: CanvasItem, pts: PackedVector2Array, color: Color, w: float = 1.5) -> void:
	if skip:
		return
	var n := pts.size()
	if n < 2:
		return
	var cc := col(color)
	var aa := _aa()
	for i in range(n - 1):
		ci.draw_line(pts[i], pts[i + 1], cc, w, aa)
	if w > 2.2:
		var m := _circle_mesh(_seg_for(w * 0.5))
		var hw := w * 0.5
		for i in range(1, n - 1):
			ci.draw_mesh(m, null, Transform2D(Vector2(hw, 0.0), Vector2(0.0, hw), pts[i]), cc)


static func arc(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, color: Color, w: float = 1.5, n: int = 16) -> void:
	if skip:
		return
	var cc := col(color)
	var aa := _aa()
	var prev := c + Vector2(cos(a0), sin(a0)) * r
	var m: ArrayMesh = null
	var hw := w * 0.5
	if w > 2.2:
		m = _circle_mesh(_seg_for(hw))
	for i in range(1, n + 1):
		var a := lerpf(a0, a1, float(i) / float(n))
		var p := c + Vector2(cos(a), sin(a)) * r
		ci.draw_line(prev, p, cc, w, aa)
		if m != null and i < n:
			ci.draw_mesh(m, null, Transform2D(Vector2(hw, 0.0), Vector2(0.0, hw), p), cc)
		prev = p


static func poly(ci: CanvasItem, pts: PackedVector2Array, color: Color) -> void:
	if skip:
		return
	var n := pts.size()
	if n < 3:
		return
	var cc := col(color)
	if n == 3:
		_pc3[0] = cc
		_pc3[1] = cc
		_pc3[2] = cc
		ci.draw_primitive(pts, _pc3, _no_uv)
	elif n == 4:
		_pc4[0] = cc
		_pc4[1] = cc
		_pc4[2] = cc
		_pc4[3] = cc
		ci.draw_primitive(pts, _pc4, _no_uv)
	else:
		var m := _poly_mesh(pts)
		if m != null:
			ci.draw_mesh(m, null, Transform2D.IDENTITY, cc)
		else:
			ci.draw_colored_polygon(pts, cc)


## Polygon drawn in local space of a transform (cached mesh; ideal for static shapes like hearts/stars).
static func poly_xf(ci: CanvasItem, pts: PackedVector2Array, pos: Vector2, rot: float, scl: Vector2, color: Color) -> void:
	if skip:
		return
	if pts.size() < 3:
		return
	var m := _poly_mesh(pts)
	if m != null:
		ci.draw_mesh(m, null, Transform2D(rot, scl, 0.0, pos), col(color))


static func polyc(ci: CanvasItem, pts: PackedVector2Array, colors: PackedColorArray) -> void:
	if skip:
		return
	if pts.size() == 4 and colors.size() == 4:
		for i in range(4):
			_pc4[i] = col(colors[i])
		ci.draw_primitive(pts, _pc4, _no_uv)
	else:
		var cc := PackedColorArray()
		for c in colors:
			cc.append(col(c))
		ci.draw_polygon(pts, cc)


static func vgrad(ci: CanvasItem, r: Rect2, top: Color, bottom: Color) -> void:
	if skip:
		return
	var c1 := col(top)
	var c2 := col(bottom)
	_pc4[0] = c1
	_pc4[1] = c1
	_pc4[2] = c2
	_pc4[3] = c2
	ci.draw_primitive(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), _pc4, _no_uv)


static func hgrad(ci: CanvasItem, r: Rect2, left: Color, right: Color) -> void:
	if skip:
		return
	var c1 := col(left)
	var c2 := col(right)
	_pc4[0] = c1
	_pc4[1] = c2
	_pc4[2] = c2
	_pc4[3] = c1
	ci.draw_primitive(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), _pc4, _no_uv)


## Soft elliptical ground shadow.
static func shadow(ci: CanvasItem, pos: Vector2, rx: float, ry: float, a: float = 0.2) -> void:
	ellipse(ci, pos, rx, ry, Color(0.1, 0.15, 0.3, a))


## Cached rounded 5-point star (unit radius). inner = inner/outer ratio.
static func star_pts(inner: float = 0.5, points: int = 5) -> PackedVector2Array:
	var key := int(inner * 100.0) * 100 + points
	if _star_cache.has(key):
		return _star_cache[key]
	var raw := PackedVector2Array()
	for i in range(points * 2):
		var a := -PI * 0.5 + float(i) * PI / float(points)
		var rad := 1.0 if i % 2 == 0 else inner
		raw.append(Vector2(cos(a), sin(a)) * rad)
	var out := chaikin(chaikin(raw, true), true)
	_star_cache[key] = out
	return out


## Chaikin corner cutting -> soft rounded polygon.
static func chaikin(pts: PackedVector2Array, closed: bool = true) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in range(n):
		var a := pts[i]
		var b := pts[(i + 1) % n]
		if not closed and i == n - 1:
			break
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out


static func star(ci: CanvasItem, c: Vector2, r: float, color: Color, rot: float = 0.0, inner: float = 0.5) -> void:
	if skip:
		return
	ci.draw_mesh(_star_mesh(inner, 5), null, Transform2D(rot, Vector2(r, r), 0.0, c), col(color))


## Text with optional shadow. align: HORIZONTAL_ALIGNMENT_*; `width` -1 = no wrap/align box.
static func text(ci: CanvasItem, s: String, pos: Vector2, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, f: Font = null) -> void:
	var ft: Font = f if f != null else font_bold()
	ci.draw_string(ft, pos, s, align, width, size, col(color))


static func text_outlined(ci: CanvasItem, s: String, pos: Vector2, size: int, color: Color, outline: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, f: Font = null) -> void:
	var ft: Font = f if f != null else font_bold()
	ci.draw_string_outline(ft, pos, s, align, width, size, maxi(2, size / 5), col(outline))
	ci.draw_string(ft, pos, s, align, width, size, col(color))


static func dashed_ring(ci: CanvasItem, c: Vector2, rx: float, ry: float, color: Color, w: float, t: float, dashes: int = 14) -> void:
	if skip:
		return
	var cc := col(color)
	var aa := _aa()
	for i in range(dashes):
		var a0 := t * 0.8 + float(i) * TAU / float(dashes)
		var a1 := a0 + TAU / float(dashes) * 0.55
		var am := (a0 + a1) * 0.5
		var p0 := c + Vector2(cos(a0) * rx, sin(a0) * ry)
		var p1 := c + Vector2(cos(am) * rx, sin(am) * ry)
		var p2 := c + Vector2(cos(a1) * rx, sin(a1) * ry)
		ci.draw_line(p0, p1, cc, w, aa)
		ci.draw_line(p1, p2, cc, w, aa)


## Smooth easing helpers
static func ease_out_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var u := x - 1.0
	return 1.0 + c3 * u * u * u + c1 * u * u


static func smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Thick line with round caps (works in any transform scale).
static func capsule(ci: CanvasItem, a: Vector2, b: Vector2, r: float, color: Color) -> void:
	if skip:
		return
	var c := col(color)
	ci.draw_line(a, b, c, r * 2.0, _aa())
	var m := _circle_mesh(_seg_for(r))
	ci.draw_mesh(m, null, Transform2D(Vector2(r, 0.0), Vector2(0.0, r), a), c)
	ci.draw_mesh(m, null, Transform2D(Vector2(r, 0.0), Vector2(0.0, r), b), c)


## Rounded rect (any scale; identical to rr but the radius may be fractional in unit-space icons).
static func rbox(ci: CanvasItem, r: Rect2, rad: float, color: Color) -> void:
	rr(ci, r, rad, color)


static func rbox_outline(ci: CanvasItem, r: Rect2, rad: float, color: Color, w: float) -> void:
	rr_outline(ci, r, rad, color, w)
