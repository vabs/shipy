class_name SeaBackground
extends Node2D
## Screen-space animated sea + sky backdrop (SPEC §6). Self-animating; put it on a back CanvasLayer.
##
## API
##   set_destination(id: StringName)        # &"med" | &"arctic" | &"underworld"
##   set_horizon_y(y: float)                # screen y of the horizon (-1 = auto 0.42*height)
##   set_waterline_y(y: float)              # screen y where the hull meets the water (-1 = auto horizon+110)
##   set_motion_scale(s: float)             # 0 = frozen scroll, 1 = sailing (everything drifts LEFT)
##   make_foreground() -> Node2D            # front wave layer node (add AFTER the ship / on a higher layer)
##   bind_camera(cam: Camera2D, waterline_local_y: float)   # derive horizon/waterline from the camera each frame
##   static attach_to(host: Node, back_layer := -10, front_layer := 4) -> SeaBackground
##   var foreground: Node2D                 # set by make_foreground()/attach_to()
##   var horizon_gap: float                 # (0.14) horizon sits waterline - gap*screen_h above when bound to a camera
##   get_horizon_y() / get_waterline_y()    # current effective screen values
## The front wave's crest sits ~6 px above the waterline (+-8 px wave) so it overlaps the hull bottom.

const U := preload("res://src/render/art/art_util.gd")

const STEP: float = 32.0
const TILE: float = 2400.0
const SCN_SPEED: float = 8.0
const SS: float = 1.55   # scenery scale
const FAR_SPEED: float = 3.0
const CLOUD_SPEED: float = 7.0
const WAVE_SPEED: Array[float] = [14.0, 26.0, 44.0, 70.0]

var foreground: Node2D = null
var dest: StringName = &"med"
var horizon_gap: float = 0.14

var _pal: Dictionary = Palette.dest(&"med")
var _horizon_y: float = -1.0
var _waterline_y: float = -1.0
var _motion: float = 1.0
var _mt: float = 0.0     # motion time (scroll clock)
var _anim: float = 0.0   # real time (twinkles / pulses)
var _size: Vector2 = Vector2(1920, 1080)
var _cam: Camera2D = null
var _cam_local_y: float = 40.0

# wave buffers
var _wn: int = 0
var _wp: PackedVector2Array = PackedVector2Array()
var _wi: PackedInt32Array = PackedInt32Array()
var _tp: PackedVector2Array = PackedVector2Array()
var _wcols: Array[PackedColorArray] = []
var _wcols_dirty: bool = true
var _skirt_cols: PackedColorArray = PackedColorArray()
# aurora buffers
var _an: int = 0
var _ap: PackedVector2Array = PackedVector2Array()
var _ai: PackedInt32Array = PackedInt32Array()
var _ac: PackedColorArray = PackedColorArray()

# scenery
var _ridge: PackedVector2Array = PackedVector2Array()
var _ridge_caps: Array[PackedVector2Array] = []
var _ridge2: PackedVector2Array = PackedVector2Array()
var _objs: Array[Obj] = []
var _strip_len: float = 3100.0
var _clouds: Array[Vector4] = []
var _sparkles: PackedFloat32Array = PackedFloat32Array()
var _parts_back: PackedFloat32Array = PackedFloat32Array()
var _parts_front: PackedFloat32Array = PackedFloat32Array()
var _gulls: Array[Vector4] = []
var _floats: Array[Vector3] = []
var _wisps: Array[Vector4] = []
var _aurora: Array[Vector4] = []
var _foam: PackedFloat32Array = PackedFloat32Array()
var _sun_x: float = 0.76
var _ray_poly: PackedVector2Array = PackedVector2Array()
var _leaf_poly: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(0.35, -0.24), Vector2(0.75, -0.2), Vector2(1.0, 0.14), Vector2(0.68, 0.0), Vector2(0.35, -0.05)])
var _tri_poly: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(1, -0.5), Vector2(1, 0.5)])


class Obj:
	var kind: int = 0
	var x: float = 0.0
	var half_w: float = 100.0
	var h: float = 80.0
	var seed_v: int = 0
	var poly: PackedVector2Array = PackedVector2Array()
	var hi: PackedVector2Array = PackedVector2Array()
	var rock: PackedVector2Array = PackedVector2Array()
	var facets: Array[PackedVector2Array] = []
	var houses: Array[Vector4] = []
	var roofs: PackedInt32Array = PackedInt32Array()
	var trees: Array[Vector3] = []
	var lamps: Array[Vector3] = []


class SeaForeground extends Node2D:
	var sea: SeaBackground

	func _draw() -> void:
		if sea != null:
			sea._draw_front(self)


# ================================================================================================
# public API
# ================================================================================================
func set_destination(id: StringName) -> void:
	dest = id if (id == &"arctic" or id == &"underworld") else &"med"
	_pal = Palette.dest(dest)
	_rebuild()
	queue_redraw()


func set_horizon_y(y: float) -> void:
	_horizon_y = y


func set_waterline_y(y: float) -> void:
	_waterline_y = y


func set_motion_scale(s: float) -> void:
	_motion = maxf(0.0, s)


func get_horizon_y() -> float:
	return _horizon_y if _horizon_y >= 0.0 else _size.y * 0.42


func get_waterline_y() -> float:
	if _waterline_y >= 0.0:
		return maxf(_waterline_y, get_horizon_y() + 40.0)
	return get_horizon_y() + 110.0


func bind_camera(cam: Camera2D, waterline_local_y: float) -> void:
	_cam = cam
	_cam_local_y = waterline_local_y


func make_foreground() -> Node2D:
	if foreground != null and is_instance_valid(foreground):
		return foreground
	var f := SeaForeground.new()
	f.name = "SeaForeground"
	f.sea = self
	foreground = f
	return f


static func attach_to(host: Node, back_layer: int = -10, front_layer: int = 4) -> SeaBackground:
	var sea := SeaBackground.new()
	sea.name = "SeaBackground"
	var back := CanvasLayer.new()
	back.name = "SeaBackLayer"
	back.layer = back_layer
	back.add_child(sea)
	host.add_child(back)
	var front := CanvasLayer.new()
	front.name = "SeaFrontLayer"
	front.layer = front_layer
	front.add_child(sea.make_foreground())
	host.add_child(front)
	return sea


# ================================================================================================
# lifecycle
# ================================================================================================
func _ready() -> void:
	_pal = Palette.dest(dest)
	_rebuild()


func _process(dt: float) -> void:
	_anim += dt
	_mt += dt * _motion
	_size = get_viewport_rect().size
	if _cam != null and is_instance_valid(_cam) and _cam.is_inside_tree():
		var sc: Vector2 = _cam.global_position + _cam.offset
		var z: float = _cam.zoom.y
		var wy: float = (_cam_local_y - sc.y) * z + _size.y * 0.5
		_horizon_y = clampf(wy - horizon_gap * _size.y, _size.y * 0.16, _size.y * 0.6)
		_waterline_y = maxf(wy, _horizon_y + 50.0)
	queue_redraw()
	if foreground != null and is_instance_valid(foreground):
		foreground.queue_redraw()


func _c(key: String) -> Color:
	return _pal.get(key, Color.MAGENTA)


# ================================================================================================
# scene construction (deterministic per destination)
# ================================================================================================
func _rebuild() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(dest)) + 7
	_wcols_dirty = true
	_objs.clear()
	_clouds.clear()
	_gulls.clear()
	_floats.clear()
	_wisps.clear()
	_aurora.clear()
	_ridge_caps.clear()
	_ridge = PackedVector2Array()
	_ridge2 = PackedVector2Array()
	match String(dest):
		"arctic":
			_sun_x = 0.64
			_build_ridge_peaks(rng)
			_build_icebergs(rng)
			for i in range(3):
				_aurora.append(Vector4(0.22 + 0.11 * float(i), rng.randf() * 6.0, 0.8 + 0.3 * float(i), float(i)))
		"underworld":
			_sun_x = 0.27
			_build_ridge_jagged(rng)
			_build_spires(rng)
			for i in range(6):
				_wisps.append(Vector4(rng.randf(), rng.randf(), rng.randf() * 6.0, rng.randf_range(0.7, 1.3)))
		_:
			_sun_x = 0.76
			_build_ridge_hills(rng)
			_build_islands(rng)
			for i in range(5):
				_gulls.append(Vector4(rng.randf(), rng.randf_range(0.18, 0.7), rng.randf_range(18.0, 42.0), rng.randf() * 6.0))
	# clouds
	var nc: int = 9 if dest == &"med" else 7
	for i in range(nc):
		_clouds.append(Vector4(rng.randf(), rng.randf(), rng.randf_range(0.7, 1.5), rng.randf_range(0.6, 1.4)))
	# floaters (sailboats / ice chunks / lantern buoys) sitting between wave layers
	for i in range(4):
		_floats.append(Vector3(rng.randf(), rng.randf(), rng.randf() * 6.0))
	# sparkles (xf, yf, phase, rate)
	_sparkles = PackedFloat32Array()
	for i in range(46):
		_sparkles.append_array(PackedFloat32Array([rng.randf(), rng.randf(), rng.randf() * 6.28, rng.randf_range(1.2, 3.0)]))
	_foam = PackedFloat32Array()
	for i in range(18):
		_foam.append_array(PackedFloat32Array([rng.randf(), rng.randf_range(0.6, 1.4), rng.randf() * 6.28]))
	# ambient particles: xf, yf, vx, vy, r, phase
	_parts_back = PackedFloat32Array()
	_parts_front = PackedFloat32Array()
	match String(dest):
		"arctic":
			for i in range(90):
				_parts_back.append_array(PackedFloat32Array([rng.randf(), rng.randf(), rng.randf_range(8.0, 22.0), rng.randf_range(18.0, 46.0), rng.randf_range(1.2, 2.8), rng.randf() * 6.28]))
			for i in range(14):
				_parts_front.append_array(PackedFloat32Array([rng.randf(), rng.randf(), rng.randf_range(14.0, 34.0), rng.randf_range(50.0, 90.0), rng.randf_range(3.0, 5.2), rng.randf() * 6.28]))
		"underworld":
			for i in range(70):
				_parts_back.append_array(PackedFloat32Array([rng.randf(), rng.randf(), rng.randf_range(4.0, 14.0), rng.randf_range(14.0, 34.0), rng.randf_range(1.2, 2.6), rng.randf() * 6.28]))
			for i in range(10):
				_parts_front.append_array(PackedFloat32Array([rng.randf(), rng.randf(), rng.randf_range(8.0, 20.0), rng.randf_range(30.0, 60.0), rng.randf_range(3.0, 4.6), rng.randf() * 6.28]))
		_:
			for i in range(26):
				_parts_back.append_array(PackedFloat32Array([rng.randf(), rng.randf(), rng.randf_range(4.0, 12.0), rng.randf_range(-6.0, 6.0), rng.randf_range(1.0, 1.8), rng.randf() * 6.28]))
	# sun rays
	_ray_poly = PackedVector2Array([Vector2(0, -3), Vector2(360, -22), Vector2(360, 22), Vector2(0, 3)])


func _build_ridge_hills(rng: RandomNumberGenerator) -> void:
	var n: int = int(TILE / 40.0)
	_ridge = PackedVector2Array()
	var ph1 := rng.randf() * 6.28
	var ph2 := rng.randf() * 6.28
	for i in range(n + 1):
		var x: float = float(i) * 40.0
		var a: float = x / TILE * TAU
		var y: float = -(26.0 + 14.0 * sin(a * 3.0 + ph1) + 9.0 * sin(a * 7.0 + ph2) + 5.0 * sin(a * 13.0))
		_ridge.append(Vector2(x, y))
	_ridge.append(Vector2(TILE, 10.0))
	_ridge.append(Vector2(0.0, 10.0))


func _build_ridge_peaks(rng: RandomNumberGenerator) -> void:
	_ridge = PackedVector2Array()
	_ridge_caps.clear()
	var peaks: int = 11
	var sp: float = TILE / float(peaks)
	_ridge.append(Vector2(0.0, 10.0))
	_ridge.append(Vector2(0.0, -16.0))
	for i in range(peaks):
		var px: float = (float(i) + 0.5) * sp + rng.randf_range(-sp * 0.18, sp * 0.18)
		var ph: float = rng.randf_range(44.0, 104.0)
		_ridge.append(Vector2(px - sp * 0.5 + sp * 0.06, -rng.randf_range(12.0, 24.0)))
		_ridge.append(Vector2(px - ph * 0.1, -ph * 0.9))
		_ridge.append(Vector2(px, -ph))
		_ridge.append(Vector2(px + ph * 0.12, -ph * 0.82))
		var cap := PackedVector2Array([
			Vector2(px - ph * 0.34, -ph * 0.66), Vector2(px - ph * 0.1, -ph * 0.9), Vector2(px, -ph),
			Vector2(px + ph * 0.12, -ph * 0.82), Vector2(px + ph * 0.3, -ph * 0.62),
			Vector2(px + ph * 0.16, -ph * 0.7), Vector2(px + ph * 0.02, -ph * 0.6), Vector2(px - ph * 0.12, -ph * 0.7)])
		_ridge_caps.append(cap)
	_ridge.append(Vector2(TILE, -16.0))
	_ridge.append(Vector2(TILE, 10.0))


func _build_ridge_jagged(rng: RandomNumberGenerator) -> void:
	_ridge = PackedVector2Array()
	_ridge.append(Vector2(0.0, 10.0))
	var x: float = 0.0
	var first: bool = true
	while x < TILE - 30.0:
		var hh: float = -rng.randf_range(20.0, 78.0)
		if first:
			hh = -30.0
			first = false
		_ridge.append(Vector2(x, hh))
		x += rng.randf_range(18.0, 44.0)
	_ridge.append(Vector2(TILE, -30.0))
	_ridge.append(Vector2(TILE, 10.0))
	# second, nearer, darker jagged ridge
	_ridge2 = PackedVector2Array()
	_ridge2.append(Vector2(0.0, 10.0))
	x = 0.0
	first = true
	while x < TILE - 40.0:
		var hh2: float = -rng.randf_range(14.0, 52.0)
		if first:
			hh2 = -24.0
			first = false
		_ridge2.append(Vector2(x, hh2))
		x += rng.randf_range(26.0, 70.0)
	_ridge2.append(Vector2(TILE, -24.0))
	_ridge2.append(Vector2(TILE, 10.0))


func _dome(w: float, h: float, n: int, wob: float, bottom: float = 8.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var u: float = -1.0 + 2.0 * float(i) / float(n)
		var y: float = -h * pow(maxf(0.0, 1.0 - u * u), 0.6)
		y *= 1.0 + wob * sin(u * 7.0 + float(i) * 0.7) * 0.5
		pts.append(Vector2(u * w * 0.5, y))
	pts.append(Vector2(w * 0.5, bottom))
	pts.append(Vector2(-w * 0.5, bottom))
	return pts


func _spread_x(i: int, n: int, rng: RandomNumberGenerator) -> float:
	return (float(i) + 0.5 + rng.randf_range(-0.22, 0.22)) * _strip_len / float(n)


func _build_islands(rng: RandomNumberGenerator) -> void:
	var kinds: Array[int] = [0, 1, 0, 2, 1]
	for i in range(kinds.size()):
		var o := Obj.new()
		o.kind = kinds[i]
		o.x = _spread_x(i, kinds.size(), rng)
		match o.kind:
			0:
				var w: float = rng.randf_range(250.0, 340.0) * SS
				var h: float = rng.randf_range(62.0, 92.0) * SS
				o.half_w = w * 0.5
				o.h = h
				o.poly = _dome(w, h, 28, 0.12)
				var hi := _dome(w * 0.82, h * 0.93, 24, 0.1)
				for k in range(hi.size()):
					hi[k] = hi[k] + Vector2(-w * 0.05, 0.0)
				o.hi = hi
				var rk := PackedVector2Array()
				for k in range(29):
					var u: float = -1.0 + 2.0 * float(k) / 28.0
					var y: float = -minf(h * pow(maxf(0.0, 1.0 - u * u), 0.6), h * 0.26 * (1.0 + 0.2 * sin(u * 8.0)))
					rk.append(Vector2(u * w * 0.5, y))
				rk.append(Vector2(w * 0.5, 8.0))
				rk.append(Vector2(-w * 0.5, 8.0))
				o.rock = rk
				var cnt: int = rng.randi_range(12, 18)
				for k in range(cnt):
					var u2: float = rng.randf_range(-0.66, 0.66)
					var prof: float = h * pow(1.0 - u2 * u2, 0.6)
					var hw: float = rng.randf_range(10.0, 17.0) * SS
					o.houses.append(Vector4(u2 * w * 0.5, -prof * rng.randf_range(0.5, 0.97), hw, hw * rng.randf_range(0.75, 1.0)))
					o.roofs.append(rng.randi_range(0, 3))
				# sort: highest (most negative y) first so lower houses overlap
				var idx: Array = range(o.houses.size())
				idx.sort_custom(func(a: int, b: int) -> bool: return o.houses[a].y < o.houses[b].y)
				var hs: Array[Vector4] = []
				var rf := PackedInt32Array()
				for id in idx:
					hs.append(o.houses[id])
					rf.append(o.roofs[id])
				o.houses = hs
				o.roofs = rf
				for k in range(rng.randi_range(2, 4)):
					var u3: float = rng.randf_range(-0.85, 0.85)
					o.trees.append(Vector3(u3 * w * 0.5, -h * pow(1.0 - u3 * u3, 0.6) * 0.8, rng.randf_range(0.8, 1.2) * SS))
			1:
				var w1: float = rng.randf_range(110.0, 160.0) * SS
				var h1: float = rng.randf_range(26.0, 40.0) * SS
				o.half_w = w1 * 0.5
				o.h = h1
				o.poly = _dome(w1, h1, 18, 0.15)
				var hi1 := _dome(w1 * 0.8, h1 * 0.9, 16, 0.1)
				for k in range(hi1.size()):
					hi1[k] = hi1[k] + Vector2(-w1 * 0.05, 0.0)
				o.hi = hi1
				for k in range(rng.randi_range(2, 3)):
					var u4: float = rng.randf_range(-0.55, 0.55)
					o.trees.append(Vector3(u4 * w1 * 0.5, -h1 * pow(1.0 - u4 * u4, 0.6) * 0.8, rng.randf_range(0.9, 1.3) * SS))
			_:
				var w2: float = 120.0 * SS
				var h2: float = 34.0 * SS
				o.half_w = w2 * 0.6
				o.h = 90.0 * SS
				o.poly = _dome(w2, h2, 18, 0.12)
				var hi2 := _dome(w2 * 0.8, h2 * 0.9, 16, 0.1)
				for k in range(hi2.size()):
					hi2[k] = hi2[k] + Vector2(-w2 * 0.05, 0.0)
				o.hi = hi2
				o.lamps.append(Vector3(10.0 * SS, -h2 * 0.66, SS))
		_objs.append(o)


func _build_icebergs(rng: RandomNumberGenerator) -> void:
	var kinds: Array[int] = [0, 1, 0, 1, 1]
	for i in range(kinds.size()):
		var o := Obj.new()
		o.kind = kinds[i]
		o.x = _spread_x(i, kinds.size(), rng)
		var big: bool = o.kind == 0
		var w: float = (rng.randf_range(210.0, 290.0) if big else rng.randf_range(90.0, 140.0)) * 1.45
		var h: float = (rng.randf_range(78.0, 112.0) if big else rng.randf_range(32.0, 52.0)) * 1.45
		o.half_w = w * 0.5
		o.h = h
		var j := func(a: float) -> float: return a + rng.randf_range(-0.04, 0.04)
		var pk1: float = j.call(-0.2)
		var pk2: float = j.call(0.14)
		o.poly = PackedVector2Array([
			Vector2(-0.5 * w, 10), Vector2(-0.5 * w, 0), Vector2(-0.4 * w, -0.34 * h), Vector2(pk1 * w - 0.1 * w, -0.5 * h),
			Vector2(pk1 * w, -0.98 * h), Vector2(pk1 * w + 0.1 * w, -0.62 * h), Vector2(0.0, -0.66 * h),
			Vector2(pk2 * w, -h), Vector2(pk2 * w + 0.12 * w, -0.52 * h), Vector2(0.32 * w, -0.46 * h),
			Vector2(0.43 * w, -0.2 * h), Vector2(0.5 * w, 0), Vector2(0.5 * w, 10)])
		# shadow facet (right side of each peak)
		o.facets.append(PackedVector2Array([
			Vector2(pk2 * w, -h), Vector2(pk2 * w + 0.12 * w, -0.52 * h), Vector2(0.32 * w, -0.46 * h),
			Vector2(0.43 * w, -0.2 * h), Vector2(0.5 * w, 0), Vector2(0.5 * w, 10), Vector2(pk2 * w + 0.02 * w, 10), Vector2(pk2 * w + 0.01 * w, -0.45 * h)]))
		o.facets.append(PackedVector2Array([
			Vector2(pk1 * w, -0.98 * h), Vector2(pk1 * w + 0.1 * w, -0.62 * h), Vector2(0.0, -0.66 * h),
			Vector2(pk2 * w - 0.06 * w, -0.4 * h), Vector2(pk1 * w + 0.03 * w, -0.35 * h)]))
		# lower-left blue-ish facet
		o.facets.append(PackedVector2Array([
			Vector2(-0.5 * w, 0), Vector2(-0.4 * w, -0.34 * h), Vector2(pk1 * w - 0.1 * w, -0.5 * h),
			Vector2(pk1 * w - 0.12 * w, -0.2 * h), Vector2(pk1 * w - 0.16 * w, 10), Vector2(-0.5 * w, 10)]))
		_objs.append(o)


func _build_spires(rng: RandomNumberGenerator) -> void:
	var n: int = 5
	for i in range(n):
		var o := Obj.new()
		o.kind = 0 if i % 2 == 0 else 1
		o.x = _spread_x(i, n, rng)
		var total_w: float = (rng.randf_range(150.0, 230.0) if o.kind == 0 else rng.randf_range(80.0, 120.0)) * 1.5
		o.half_w = total_w * 0.5
		var spires: int = rng.randi_range(3, 5) if o.kind == 0 else rng.randi_range(2, 3)
		var maxh: float = 0.0
		for k in range(spires):
			var cx: float = (float(k) / float(maxi(spires - 1, 1)) - 0.5) * total_w * 0.7
			var bw: float = rng.randf_range(34.0, 64.0) * 1.5
			var hh: float = (rng.randf_range(44.0, 112.0) if o.kind == 0 else rng.randf_range(30.0, 64.0)) * 1.5
			if k == spires / 2:
				hh *= 1.25
			maxh = maxf(maxh, hh)
			var apex: float = cx + rng.randf_range(-bw * 0.2, bw * 0.2)
			var body := PackedVector2Array([
				Vector2(cx - bw * 0.5, 10), Vector2(cx - bw * 0.5, 0), Vector2(cx - bw * 0.28, -hh * 0.5),
				Vector2(apex - bw * 0.05, -hh), Vector2(apex + bw * 0.06, -hh * 0.86), Vector2(cx + bw * 0.24, -hh * 0.42),
				Vector2(cx + bw * 0.5, 0), Vector2(cx + bw * 0.5, 10)])
			var lit := PackedVector2Array([
				Vector2(cx - bw * 0.5, 10), Vector2(cx - bw * 0.5, 0), Vector2(cx - bw * 0.28, -hh * 0.5),
				Vector2(apex - bw * 0.05, -hh), Vector2(apex + bw * 0.01, -hh * 0.5), Vector2(cx - bw * 0.02, 10)])
			o.facets.append(body)
			o.facets.append(lit)
		o.h = maxh
		if o.kind == 0 or rng.randf() < 0.7:
			o.lamps.append(Vector3(total_w * 0.5 * rng.randf_range(0.5, 0.95) * (1.0 if rng.randf() < 0.5 else -1.0), -rng.randf_range(24.0, 46.0) * 1.5, rng.randf_range(1.2, 1.7)))
		_objs.append(o)


# ================================================================================================
# drawing: background
# ================================================================================================
func _draw() -> void:
	var w: float = _size.x
	var h: float = _size.y
	var hy: float = get_horizon_y()
	var wy: float = get_waterline_y()
	var d: float = wy - hy
	_ensure_buffers()
	_draw_sky(hy, w)
	_draw_sun(hy, w)
	if dest == &"arctic":
		_draw_aurora(hy, w)
	_draw_clouds(hy, w)
	_draw_ridges(hy, w)
	_draw_objects(hy, w)
	_draw_sea_base(hy, w, h)
	# far wave layer
	_wave(self, 0, hy + maxf(d * 0.1, 6.0), 3.0, 150.0, 0.7, h, d * 0.3)
	_draw_floaters(hy, d)
	_wave(self, 1, hy + d * 0.44, 5.0, 240.0, 2.1, h, d * 0.36)
	_wave(self, 2, hy + d * 0.8, 7.0, 340.0, 4.0, h, d * 0.2 + 30.0)
	_draw_reflection(hy, wy, w)
	_draw_sparkles(hy, w, h)
	match String(dest):
		"med":
			_draw_gulls(hy, w)
		"arctic":
			_draw_snow(self, _parts_back, w, h, 0.8)
		"underworld":
			_draw_wisps(hy, d, w)
			_draw_embers(self, _parts_back, w, h, 0.8)


func _ensure_buffers() -> void:
	var n: int = int(ceil(_size.x / STEP)) + 3
	if n != _wn:
		_wn = n
		_wp.resize(n * 2)
		_tp.resize(n)
		_wi = _grid_indices(n, 2)
		_wcols_dirty = true
	if _wcols_dirty:
		_wcols_dirty = false
		_wcols.clear()
		var sb: Color = _c("sea_bottom")
		var tops: Array[Color] = [_c("wave_far"), _c("wave_mid"), _c("wave_near"), _c("wave_front")]
		for li in range(4):
			var top: Color = tops[li]
			var bot: Color = top.lerp(sb, 0.28 + 0.1 * float(li))
			if li == 3:
				top = top.lerp(_c("wave_mid"), 0.45)
				top.a = 0.92
				bot = _c("wave_front").lerp(sb, 0.5)
				bot.a = 0.97
			var arr := PackedColorArray()
			arr.resize(n * 2)
			for i in range(n):
				arr[i * 2] = top
				arr[i * 2 + 1] = bot
			_wcols.append(arr)
		_skirt_cols.resize(n * 2)
		var fcol: Color = _c("foam")
		for i in range(n):
			_skirt_cols[i * 2] = Color(fcol.r, fcol.g, fcol.b, 0.34)
			_skirt_cols[i * 2 + 1] = Color(fcol.r, fcol.g, fcol.b, 0.0)
	var an: int = int(ceil(_size.x / 40.0)) + 2
	if an != _an:
		_an = an
		_ap.resize(an * 3)
		_ac.resize(an * 3)
		_ai = _grid_indices(an, 3)


## Quad strip indices for `cols` columns x `rows` rows (vertex = col*rows+row).
func _grid_indices(cols: int, rows: int) -> PackedInt32Array:
	var idx := PackedInt32Array()
	for c in range(cols - 1):
		for r in range(rows - 1):
			var a: int = c * rows + r
			var b: int = a + 1
			var cc: int = a + rows
			var dd: int = cc + 1
			idx.append_array(PackedInt32Array([a, b, cc, b, dd, cc]))
	return idx


func _draw_sky(hy: float, w: float) -> void:
	var top: Color = _c("sky_top")
	var mid: Color = _c("sky_mid")
	var bot: Color = _c("sky_bottom")
	var ym: float = hy * 0.55
	U.vgrad(self, Rect2(0, -4, w, ym + 4), top, mid)
	U.vgrad(self, Rect2(0, ym - 1, w, hy - ym + 4), mid, bot)


func _draw_sun(hy: float, w: float) -> void:
	var sun: Color = _c("sun")
	var glow: Color = _c("sun_glow")
	var p := Vector2(w * _sun_x, maxf(hy * 0.48, 190.0))
	match String(dest):
		"med":
			var c0: Color = Palette.alpha(glow, 0.2)
			var c1: Color = Palette.alpha(glow, 0.0)
			for i in range(12):
				var a: float = _anim * 0.04 + float(i) * TAU / 12.0
				var dir := Vector2(cos(a), sin(a))
				var nrm := Vector2(-dir.y, dir.x)
				var tip: Vector2 = p + dir * 520.0
				U.polyc(self, PackedVector2Array([p + nrm * 5.0, tip + nrm * 34.0, tip - nrm * 34.0, p - nrm * 5.0]), PackedColorArray([c0, c1, c1, c0]))
			U.circ(self, p, 150.0, Palette.alpha(glow, 0.1))
			U.circ(self, p, 104.0, Palette.alpha(glow, 0.16))
			U.circ(self, p, 72.0, Palette.alpha(glow, 0.3))
			U.circ(self, p, 48.0, sun)
			U.circ(self, p + Vector2(-8, -8), 34.0, Palette.tint(sun, 0.5))
		"arctic":
			p.y = maxf(hy - 175.0, 170.0)
			U.circ(self, p, 130.0, Palette.alpha(glow, 0.14))
			U.circ(self, p, 84.0, Palette.alpha(glow, 0.25))
			U.ring(self, p, 96.0, Palette.alpha(Color.WHITE, 0.3), 3.0)
			U.ring(self, p, 110.0, Palette.alpha(Color.WHITE, 0.14), 2.0)
			U.circ(self, p, 34.0, sun)
		_:
			p.y = maxf(hy * 0.46, 180.0)
			U.circ(self, p, 190.0, Palette.alpha(glow, 0.1))
			U.circ(self, p, 130.0, Palette.alpha(glow, 0.16))
			U.circ(self, p, 92.0, Palette.alpha(glow, 0.26))
			U.circ(self, p, 66.0, sun)
			var cr: Color = Palette.alpha(Color("D9A3D0"), 0.55)
			U.circ(self, p + Vector2(-20, -14), 13.0, cr)
			U.circ(self, p + Vector2(18, 10), 9.0, cr)
			U.circ(self, p + Vector2(-8, 26), 6.0, cr)
			U.circ(self, p + Vector2(22, -26), 5.0, cr)


func _draw_aurora(hy: float, w: float) -> void:
	var cols: Array[Color] = [_c("aurora1"), _c("aurora2"), _c("aurora3")]
	var n: int = _an
	for ri in range(_aurora.size()):
		var rb: Vector4 = _aurora[ri]
		var c: Color = cols[ri % 3]
		var by: float = 110.0 + (hy - 110.0) * rb.x
		var t: float = _mt * 0.22 * rb.z
		for i in range(n):
			var x: float = float(i) * 40.0 - 20.0
			var yc: float = by + sin(x * 0.0042 + rb.y + t) * 46.0 + sin(x * 0.011 - rb.y * 1.7 - t * 1.6) * 16.0
			var len_up: float = 120.0 + 46.0 * sin(x * 0.007 + t * 0.8 + rb.y)
			var shimmer: float = 0.6 + 0.4 * sin(float(i) * 0.9 + _anim * 1.3 + rb.y * 3.0)
			var a: float = 0.8 * shimmer * (0.8 + 0.2 * sin(_anim * 0.4 + rb.y))
			var b: int = i * 3
			_ap[b] = Vector2(x, yc - len_up)
			_ap[b + 1] = Vector2(x, yc)
			_ap[b + 2] = Vector2(x, yc + 26.0)
			_ac[b] = Color(c.r, c.g, c.b, 0.0)
			_ac[b + 1] = Color(c.r, c.g, c.b, a)
			_ac[b + 2] = Color(c.r, c.g, c.b, 0.0)
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _ai, _ap, _ac)


func _cloud(ci: CanvasItem, x: float, y: float, s: float, c: Color, shade: Color, flat: float) -> void:
	var cw: float = 120.0 * s
	var ch: float = 34.0 * s * flat
	U.rr(ci, Rect2(x - cw * 0.5, y + ch * 0.18 + 3.0 * s, cw, ch * 0.5), ch * 0.25, shade)
	U.rr(ci, Rect2(x - cw * 0.5, y, cw, ch * 0.66), ch * 0.33, c)
	U.circ(ci, Vector2(x - cw * 0.2, y + ch * 0.05), ch * 0.55, c)
	U.circ(ci, Vector2(x + cw * 0.06, y - ch * 0.22), ch * 0.72, c)
	U.circ(ci, Vector2(x + cw * 0.3, y + ch * 0.08), ch * 0.45, c)


func _draw_clouds(hy: float, w: float) -> void:
	var c: Color = _c("cloud")
	var sh: Color = _c("cloud_shade")
	var span: float = w + 520.0
	var y0: float = 120.0
	var y1: float = maxf(hy - 70.0, y0 + 60.0)
	var flat: float = 1.0 if dest == &"med" else 0.8
	for cl in _clouds:
		var x: float = fposmod(cl.x * span - _mt * CLOUD_SPEED * cl.w, span) - 260.0
		var y: float = lerpf(y0, y1, cl.y)
		_cloud(self, x, y, cl.z, c, sh, flat)


func _tile(poly: PackedVector2Array, speed: float, y: float, color: Color, w: float) -> void:
	var x: float = -fposmod(_mt * speed, TILE)
	while x < w + 1.0:
		U.poly_xf(self, poly, Vector2(x, y), 0.0, Vector2.ONE, color)
		x += TILE


func _draw_ridges(hy: float, w: float) -> void:
	var far: Color = _c("far_land")
	match String(dest):
		"med":
			_tile(_ridge, FAR_SPEED, hy + 2.0, far, w)
		"arctic":
			var rc: Color = Palette.shade(far, 0.12)
			_tile(_ridge, FAR_SPEED, hy + 2.0, rc, w)
			# snow caps
			var x: float = -fposmod(_mt * FAR_SPEED, TILE)
			var cap: Color = Color("F6F8FF")
			while x < w + 1.0:
				for cp in _ridge_caps:
					U.poly_xf(self, cp, Vector2(x, hy + 2.0), 0.0, Vector2.ONE, cap)
				x += TILE
		_:
			_tile(_ridge, FAR_SPEED, hy + 2.0, far, w)
			_tile(_ridge2, FAR_SPEED * 1.6, hy + 2.0, _c("land"), w)


func _draw_objects(hy: float, w: float) -> void:
	var span: float = maxf(_strip_len, w + 900.0)
	for o in _objs:
		var sx: float = fposmod(o.x - _mt * SCN_SPEED, span) - 400.0
		if sx + o.half_w < -40.0 or sx - o.half_w > w + 40.0:
			continue
		var p := Vector2(sx, hy + 2.0)
		match String(dest):
			"med":
				_draw_med_obj(o, p)
			"arctic":
				_draw_ice_obj(o, p)
			_:
				_draw_rock_obj(o, p)


func _draw_med_obj(o: Obj, p: Vector2) -> void:
	var land: Color = _c("land")
	var dark: Color = _c("land_dark")
	var rock: Color = _c("rock")
	U.poly_xf(self, o.poly, p, 0.0, Vector2.ONE, dark)
	U.poly_xf(self, o.hi, p, 0.0, Vector2.ONE, land)
	if o.kind == 0:
		U.poly_xf(self, o.rock, p, 0.0, Vector2.ONE, rock)
		var wall: Color = _c("village_wall")
		var wall_shade := Color("E9DFCB")
		var roof_a: Color = _c("village_roof")
		var roof_b: Color = _c("village_roof2")
		for i in range(o.houses.size()):
			var hs: Vector4 = o.houses[i]
			var hp := p + Vector2(hs.x, hs.y)
			var hw: float = hs.z
			var hh: float = hs.w
			var rk: int = o.roofs[i]
			if rk == 0:
				U.circ(self, hp + Vector2(0, -hh), hw * 0.45, roof_b)
			U.rect(self, Rect2(hp.x - hw * 0.5, hp.y - hh, hw, hh), wall)
			U.rect(self, Rect2(hp.x + hw * 0.18, hp.y - hh, hw * 0.32, hh), wall_shade)
			match rk:
				1:
					U.rect(self, Rect2(hp.x - hw * 0.5 - 0.5, hp.y - hh - 2.0, hw + 1.0, 2.5), roof_a)
				2:
					U.poly(self, PackedVector2Array([hp + Vector2(-hw * 0.5 - 1.0, -hh), hp + Vector2(0, -hh - hw * 0.45), hp + Vector2(hw * 0.5 + 1.0, -hh)]), roof_a)
				3:
					U.rect(self, Rect2(hp.x - hw * 0.5 - 0.5, hp.y - hh - 2.0, hw + 1.0, 2.5), roof_b)
			U.rect(self, Rect2(hp.x - hw * 0.12, hp.y - hh * 0.62, hw * 0.24, hh * 0.3), roof_b)
		for tr in o.trees:
			_cypress(p + Vector2(tr.x, tr.y), tr.z, dark)
	elif o.kind == 1:
		for tr in o.trees:
			_palm(p + Vector2(tr.x, tr.y), tr.z)
	else:
		for lp in o.lamps:
			_lighthouse(p + Vector2(lp.x, lp.y), lp.z)


func _cypress(p: Vector2, s: float, dark: Color) -> void:
	var g: Color = Palette.shade(dark, 0.25)
	U.ellipse(self, p + Vector2(0, -8.0 * s), 3.2 * s, 9.0 * s, g)


func _palm(p: Vector2, s: float) -> void:
	var trunk: Color = Palette.WOOD_DARK
	var top := p + Vector2(3.0 * s, -20.0 * s)
	U.pline(self, PackedVector2Array([p, p + Vector2(0.5 * s, -10.0 * s), top]), trunk, 2.0 * s)
	var leaf: Color = Palette.MINT_DARK
	var ang: Array[float] = [-2.9, -2.3, -1.57, -0.85, -0.2]
	for i in range(ang.size()):
		var sway: float = sin(_anim * 1.3 + float(i)) * 0.06
		var len_s: float = (13.0 if i != 2 else 9.0) * s
		U.poly_xf(self, _leaf_poly, top, ang[i] + sway, Vector2(len_s, len_s), leaf)


func _lighthouse(p: Vector2, k: float) -> void:
	var wcol: Color = Palette.HULL_WHITE
	var stripe: Color = Palette.CORAL
	var hgt: float = 48.0 * k
	var w0: float = 6.5 * k
	var w1: float = 4.4 * k
	U.poly(self, PackedVector2Array([p + Vector2(-w0, 0), p + Vector2(-w1, -hgt), p + Vector2(w1, -hgt), p + Vector2(w0, 0)]), wcol)
	for si in range(2):
		var y0: float = (-10.0 - float(si) * 16.0) * k
		var y1: float = y0 - 8.0 * k
		var wa: float = lerpf(w0, w1, -y0 / hgt)
		var wb: float = lerpf(w0, w1, -y1 / hgt)
		U.poly(self, PackedVector2Array([p + Vector2(-wa, y0), p + Vector2(-wb, y1), p + Vector2(wb, y1), p + Vector2(wa, y0)]), stripe)
	U.rect(self, Rect2(p.x - 6.5 * k, p.y - hgt - 3.0 * k, 13.0 * k, 3.0 * k), Palette.NAVY)
	U.rr(self, Rect2(p.x - 4.0 * k, p.y - hgt - 11.0 * k, 8.0 * k, 8.0 * k), 2.0 * k, Palette.SUN)
	U.poly(self, PackedVector2Array([p + Vector2(-5.5, -hgt / k - 11.0) * k, p + Vector2(0, -hgt / k - 18.0) * k, p + Vector2(5.5, -hgt / k - 11.0) * k]), stripe)
	var lamp := p + Vector2(0, -hgt - 7.0 * k)
	var pu: float = 0.6 + 0.4 * sin(_anim * 2.2)
	U.circ(self, lamp, 18.0 * k, Palette.alpha(Palette.SUN, 0.14 * pu))
	U.circ(self, lamp, 10.0 * k, Palette.alpha(Palette.SUN, 0.22))


func _draw_ice_obj(o: Obj, p: Vector2) -> void:
	var body: Color = _c("land")
	var shade: Color = _c("land_dark")
	U.poly_xf(self, o.poly, p, 0.0, Vector2.ONE, body)
	var cols: Array[Color] = [shade, Palette.tint(shade, 0.35), Palette.alpha(Color("9EC4EA"), 0.6)]
	for i in range(o.facets.size()):
		U.poly_xf(self, o.facets[i], p, 0.0, Vector2.ONE, cols[i % cols.size()])


func _draw_rock_obj(o: Obj, p: Vector2) -> void:
	var rock: Color = _c("rock")
	var dark: Color = _c("land_dark")
	var lit: Color = Palette.tint(rock, 0.18)
	var accent: Color = _c("accent")
	for i in range(0, o.facets.size() - 1, 2):
		U.poly_xf(self, o.facets[i], p, 0.0, Vector2.ONE, rock)
		U.poly_xf(self, o.facets[i + 1], p, 0.0, Vector2.ONE, lit)
	# faint glowing cracks
	var fl: float = 0.5 + 0.5 * sin(_anim * 1.7 + o.x)
	U.pline(self, PackedVector2Array([p + Vector2(-o.half_w * 0.2, -4.0), p + Vector2(-o.half_w * 0.1, -o.h * 0.25), p + Vector2(0, -o.h * 0.18), p + Vector2(o.half_w * 0.08, -o.h * 0.42)]), Palette.alpha(accent, 0.25 + 0.25 * fl), 1.6)
	U.rect(self, Rect2(p.x - o.half_w - 6.0, p.y + 3.0, o.half_w * 2.0 + 12.0, 6.0), dark)
	for lp in o.lamps:
		_lantern_post(p + Vector2(lp.x, 0.0), -lp.y + 8.0, lp.z, o.x)


func _lantern_post(base: Vector2, height: float, s: float, seed_x: float) -> void:
	var top := base + Vector2(0, -height)
	var pole: Color = Palette.INK
	U.line(self, base, top, pole, 2.0)
	U.line(self, top, top + Vector2(7.0 * s, 0), pole, 2.0)
	var lp := top + Vector2(7.0 * s, 8.0 * s)
	U.line(self, top + Vector2(7.0 * s, 0), lp + Vector2(0, -4.0 * s), pole, 1.2)
	_lantern(lp, s, seed_x)


func _lantern(p: Vector2, s: float, seed_v: float) -> void:
	var lan: Color = _c("lantern")
	var flick: float = 0.75 + 0.25 * sin(_anim * 6.0 + seed_v) * sin(_anim * 3.7 + seed_v * 0.3)
	U.circ(self, p, 24.0 * s, Palette.alpha(lan, 0.1 * flick))
	U.circ(self, p, 15.0 * s, Palette.alpha(lan, 0.2 * flick))
	U.rr(self, Rect2(p.x - 4.5 * s, p.y - 5.0 * s, 9.0 * s, 11.0 * s), 3.0 * s, lan)
	U.rr(self, Rect2(p.x - 5.5 * s, p.y - 7.0 * s, 11.0 * s, 3.0 * s), 1.5 * s, Palette.NAVY_DARK)
	U.rr(self, Rect2(p.x - 5.0 * s, p.y + 5.0 * s, 10.0 * s, 2.5 * s), 1.2 * s, Palette.NAVY_DARK)
	U.circ(self, p + Vector2(0, 0.5 * s), 2.6 * s, Palette.tint(Color("FFE9A8"), 0.4))


# ================================================================================================
# drawing: sea
# ================================================================================================
func _draw_sea_base(hy: float, w: float, h: float) -> void:
	var st: Color = _c("sea_top")
	var sb: Color = _c("sea_bottom")
	var haze: Color = st.lerp(Color.WHITE, 0.45)
	if dest == &"underworld":
		haze = _c("sky_bottom").lerp(st, 0.3)
	U.vgrad(self, Rect2(0, hy, w, 52.0), haze, st)
	U.vgrad(self, Rect2(0, hy + 45.0, w, h - hy - 45.0 + 4.0), st, sb)


## One wave layer: filled strip from a sine crest down to bottom_y, a foam crest line and little "~" ticks.
func _wave(ci: CanvasItem, li: int, base: float, amp: float, wl: float, seed_v: float, bottom_y: float, band: float = 40.0) -> void:
	var n: int = _wn
	var k: float = TAU / wl
	var shift: float = _mt * WAVE_SPEED[li]
	for i in range(n):
		var x: float = float(i) * STEP - STEP
		var ph: float = (x + shift) * k
		var y: float = base + amp * (sin(ph + seed_v) * 0.72 + sin(ph * 2.3 + seed_v * 1.7) * 0.28)
		_wp[i * 2] = Vector2(x, y)
		_wp[i * 2 + 1] = Vector2(x, bottom_y)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _wi, _wp, _wcols[li])
	if li == 3:
		# soft foam skirt right under the crest (sells the water-over-hull overlap)
		for i in range(n):
			_wp[i * 2 + 1] = _wp[i * 2] + Vector2(0.0, 22.0)
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _wi, _wp, _skirt_cols)
	if li >= 1:
		for i in range(n):
			_tp[i] = _wp[i * 2]
		var fc: Color = _c("foam")
		fc.a = [0.0, 0.34, 0.48, 0.8][li]
		ci.draw_polyline(_tp, fc, [0.0, 2.0, 2.6, 3.4][li], true)
	# decorative wave ticks that travel with the layer
	var span: float = _size.x + 80.0
	var tc: Color = _c("foam")
	tc.a = [0.3, 0.34, 0.4, 0.5][li]
	var cnt: int = [11, 9, 8, 6][li]
	for j in range(cnt):
		var xf: float = fposmod(float(j) * 0.618034 + float(li) * 0.31, 1.0)
		var yf: float = fposmod(float(j) * 0.381966 * 1.7 + float(li) * 0.17, 1.0)
		var x: float = fposmod(xf * span - shift, span) - 40.0
		var ph2: float = (x + shift) * k
		var yc: float = base + amp * (sin(ph2 + seed_v) * 0.72 + sin(ph2 * 2.3 + seed_v * 1.7) * 0.28)
		var r: float = (7.0 + 9.0 * fposmod(xf * 7.3, 1.0)) * (0.7 + 0.22 * float(li))
		var cy: float = yc + 9.0 + yf * maxf(band - 18.0, 6.0)
		ci.draw_arc(Vector2(x, cy + r * 0.55), r, PI * 1.2, PI * 1.8, 7, tc, 1.8 + 0.4 * float(li), true)


func _draw_floaters(hy: float, d: float) -> void:
	var w: float = _size.x
	var span: float = w + 300.0
	for f in _floats:
		var x: float = fposmod(f.x * span - _mt * 16.0, span) - 150.0
		var depth: float = 0.25 + 0.14 * f.y
		var y: float = hy + d * depth
		var sc: float = 1.2 + 1.4 * f.y
		var bob: float = sin(_anim * 1.4 + f.z) * 1.6
		var p := Vector2(x, y + bob)
		match String(dest):
			"med":
				U.rr(self, Rect2(p.x - 12.0 * sc, p.y - 3.0 * sc, 24.0 * sc, 6.0 * sc), 3.0 * sc, Palette.CORAL)
				U.line(self, p + Vector2(0, -3) * sc, p + Vector2(0, -26) * sc, Palette.WOOD_DARK, 1.4 * sc)
				U.poly(self, PackedVector2Array([p + Vector2(1.5, -25) * sc, p + Vector2(1.5, -5) * sc, p + Vector2(13, -5) * sc]), Color("FFFDF6"))
				U.poly(self, PackedVector2Array([p + Vector2(-1.5, -22) * sc, p + Vector2(-1.5, -5) * sc, p + Vector2(-10, -5) * sc]), Color("EFE6D6"))
			"arctic":
				U.poly(self, PackedVector2Array([p + Vector2(-16, 3) * sc, p + Vector2(-12, -5) * sc, p + Vector2(-3, -9) * sc, p + Vector2(6, -6) * sc, p + Vector2(15, 3) * sc]), _c("land"))
				U.poly(self, PackedVector2Array([p + Vector2(6, -6) * sc, p + Vector2(15, 3) * sc, p + Vector2(0, 3) * sc]), _c("land_dark"))
			_:
				var fl: float = 0.75 + 0.25 * sin(_anim * 5.0 + f.z)
				U.circ(self, p + Vector2(0, -4) * sc, 16.0 * sc, Palette.alpha(_c("lantern"), 0.14 * fl))
				U.rr(self, Rect2(p.x - 6.0 * sc, p.y - 2.0 * sc, 12.0 * sc, 5.0 * sc), 2.5 * sc, Palette.NAVY_DARK)
				U.rr(self, Rect2(p.x - 3.0 * sc, p.y - 9.0 * sc, 6.0 * sc, 8.0 * sc), 2.0 * sc, _c("lantern"))


func _draw_reflection(hy: float, wy: float, w: float) -> void:
	var sx: float = w * _sun_x
	var c: Color = _c("sun_glow")
	var d: float = wy - hy
	for i in range(8):
		var f: float = float(i) / 7.0
		var y: float = hy + 8.0 + f * (d * 0.95)
		var ww: float = (26.0 + 82.0 * f) * (0.8 + 0.2 * sin(_anim * 1.6 + float(i) * 1.3))
		var a: float = 0.4 * (1.0 - f * 0.65)
		U.rr(self, Rect2(sx - ww * 0.5 + sin(_anim * 0.8 + float(i)) * 3.0, y, ww, 3.0), 1.5, Palette.alpha(c, a))


func _draw_sparkles(hy: float, w: float, h: float) -> void:
	var c: Color = _c("sparkle")
	var span: float = w + 60.0
	var y0: float = hy + 10.0
	var yr: float = (h - y0) * 0.8
	var star := U.star_pts(0.28, 4)
	for i in range(0, _sparkles.size(), 4):
		var yf: float = _sparkles[i + 1]
		var tw: float = sin(_anim * _sparkles[i + 3] + _sparkles[i + 2])
		if tw < 0.15:
			continue
		var x: float = fposmod(_sparkles[i] * span - _mt * (14.0 + 50.0 * yf), span) - 30.0
		var y: float = y0 + yf * yr
		var r: float = (3.5 + 6.5 * yf) * tw
		U.poly_xf(self, star, Vector2(x, y), 0.0, Vector2(r, r), Palette.alpha(c, 0.85 * tw))


func _draw_gulls(hy: float, w: float) -> void:
	var span: float = w + 300.0
	for g in _gulls:
		var x: float = fposmod(g.x * span + _mt * g.z * 0.5, span) - 150.0
		var y: float = 110.0 + g.y * maxf(hy - 150.0, 80.0) + sin(_anim * 0.9 + g.w) * 8.0
		var flap: float = sin(_anim * 6.5 + g.w * 3.0)
		var t: float = -flap * 5.0
		var wing := PackedVector2Array([Vector2(-11, t * 0.9 + 1) * 1.7, Vector2(-5.5, -3.0 + t * 0.35) * 1.7, Vector2(0, 0)])
		var wing2 := PackedVector2Array([Vector2(11, t * 0.9 + 1) * 1.7, Vector2(5.5, -3.0 + t * 0.35) * 1.7, Vector2(0, 0)])
		for i in range(3):
			wing[i] += Vector2(x, y)
			wing2[i] += Vector2(x, y)
		U.pline(self, wing, Palette.alpha(Palette.NAVY_LIGHT, 0.3), 5.5)
		U.pline(self, wing2, Palette.alpha(Palette.NAVY_LIGHT, 0.3), 5.5)
		U.pline(self, wing, Color.WHITE, 3.6)
		U.pline(self, wing2, Color.WHITE, 3.6)
		U.circ(self, Vector2(x, y + 0.5), 3.2, Color.WHITE)


func _draw_snow(ci: CanvasItem, parts: PackedFloat32Array, w: float, h: float, alpha: float) -> void:
	var c := Color(1, 1, 1, alpha)
	for i in range(0, parts.size(), 6):
		var x: float = fposmod(parts[i] * w - _mt * parts[i + 2] + sin(_anim * 0.9 + parts[i + 5]) * 14.0, w + 20.0) - 10.0
		var y: float = fposmod(parts[i + 1] * h + _mt * parts[i + 3], h + 20.0) - 10.0
		U.circ(ci, Vector2(x, y), parts[i + 4], c)


func _draw_embers(ci: CanvasItem, parts: PackedFloat32Array, w: float, h: float, alpha: float) -> void:
	var warm: Color = _c("lantern")
	var green: Color = _c("wisp")
	for i in range(0, parts.size(), 6):
		var x: float = fposmod(parts[i] * w - _mt * parts[i + 2] + sin(_anim * 0.7 + parts[i + 5]) * 18.0, w + 20.0) - 10.0
		var y: float = fposmod(parts[i + 1] * h - _mt * parts[i + 3], h + 20.0) - 10.0
		var fl: float = 0.55 + 0.45 * sin(_anim * 3.0 + parts[i + 5] * 3.0)
		var c: Color = green if (i / 6) % 4 == 0 else warm
		var r: float = parts[i + 4]
		U.circ(ci, Vector2(x, y), r * 2.6, Palette.alpha(c, 0.12 * fl * alpha))
		U.circ(ci, Vector2(x, y), r, Palette.alpha(c.lerp(Color.WHITE, 0.3), 0.9 * fl * alpha))


func _draw_wisps(hy: float, d: float, w: float) -> void:
	var c: Color = _c("wisp")
	var span: float = w + 300.0
	for ws in _wisps:
		var x: float = fposmod(ws.x * span - _mt * 10.0 * ws.w, span) - 150.0
		var y: float = hy - 30.0 + ws.y * (d * 1.0 + 40.0) + sin(_anim * 1.1 * ws.w + ws.z) * 12.0
		var pu: float = 0.7 + 0.3 * sin(_anim * 2.6 + ws.z)
		for ti in range(5):
			var tf: float = float(ti + 1)
			U.circ(self, Vector2(x + tf * 7.0, y + tf * 1.5 + sin(_anim * 2.0 + tf) * 2.0), 3.6 - tf * 0.55, Palette.alpha(c, 0.35 - tf * 0.05))
		U.circ(self, Vector2(x, y), 22.0, Palette.alpha(c, 0.1 * pu))
		U.circ(self, Vector2(x, y), 13.0, Palette.alpha(c, 0.2 * pu))
		U.circ(self, Vector2(x, y), 6.0, Palette.alpha(c.lerp(Color.WHITE, 0.35), 0.95))
		# little flame tip
		U.poly(self, PackedVector2Array([Vector2(x - 3.5, y - 1), Vector2(x, y - 12.0 - 2.0 * pu), Vector2(x + 3.5, y - 1)]), Palette.alpha(c, 0.7))


# ================================================================================================
# drawing: foreground (front wave over the hull)
# ================================================================================================
func _draw_front(ci: CanvasItem) -> void:
	_size = get_viewport_rect().size
	_ensure_buffers()
	var hy: float = get_horizon_y()
	var wy: float = get_waterline_y()
	var w: float = _size.x
	var h: float = _size.y
	var base: float = wy - 6.0
	_wave(ci, 3, base, 8.0, 460.0, 5.3, maxf(h + 40.0, wy + 300.0), 70.0)
	# foam highlight on the crest
	var foam: Color = _c("foam")
	var k: float = TAU / 460.0
	var shift: float = _mt * WAVE_SPEED[3]
	var span: float = w + 120.0
	for i in range(0, _foam.size(), 3):
		var x: float = fposmod(_foam[i] * span - _mt * 70.0, span) - 60.0
		var ph: float = (x + shift) * k
		# keep foam blobs riding on the crest at their own x (compensate scroll)
		var y: float = base + 8.0 * (sin(ph + 5.3) * 0.72 + sin(ph * 2.3 + 5.3 * 1.7) * 0.28)
		var r: float = 9.0 * _foam[i + 1]
		U.ellipse(ci, Vector2(x, y + 1.0), r, 2.2, Palette.alpha(foam, 0.8))
		U.ellipse(ci, Vector2(x + r * 1.5, y + 3.0), r * 0.55, 1.8, Palette.alpha(foam, 0.6))
	# a few sparkles on the front water
	var star := U.star_pts(0.28, 4)
	for i in range(0, _sparkles.size(), 4):
		if i % 8 != 0:
			continue
		var tw: float = sin(_anim * _sparkles[i + 3] * 1.3 + _sparkles[i + 2] + 1.0)
		if tw < 0.3:
			continue
		var x2: float = fposmod(_sparkles[i] * span - _mt * 66.0, span) - 60.0
		var y2: float = base + 26.0 + _sparkles[i + 1] * 90.0
		var r2: float = 5.0 * tw
		U.poly_xf(ci, star, Vector2(x2, y2), 0.0, Vector2(r2, r2), Palette.alpha(_c("sparkle"), 0.7 * tw))
	if dest == &"arctic":
		_draw_snow(ci, _parts_front, w, h, 0.9)
	elif dest == &"underworld":
		_draw_embers(ci, _parts_front, w, h, 1.0)
