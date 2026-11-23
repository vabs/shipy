class_name MapCanvas
extends Control
## The sea chart behind the map screen: animated ocean, compass rose, a dotted voyage route that links the three
## destination nodes, and a little cruise ship that sails to the selected (unlocked) destination.
##   setup(dest_ids)            builds one DestNode per destination
##   set_insets(top, bottom)    px covered by the screen's top / bottom bars; nodes are laid out in the free band
##   set_ship_dest(dest, animated)
##   signal dest_chosen(dest_id)

const U := preload("res://src/render/art/art_util.gd")

signal dest_chosen(dest_id: StringName)

var nodes: Array[DestNode] = []
var dest_ids: Array[StringName] = []
var _inset_top: float = 96.0
var _inset_bottom: float = 520.0
var _t: float = 0.0
var _route: PackedVector2Array = PackedVector2Array()
var _route_len: PackedFloat32Array = PackedFloat32Array()
var _docks: Array[float] = []
var _ship_d: float = 0.0
var _ship_tw: Tween
var _marker: _Marker
var _compass_c: Vector2 = Vector2.ZERO
var _compass_r: float = 50.0


class _Marker extends Control:
	var canvas: MapCanvas

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if canvas == null or canvas._route.size() < 2:
			return
		var p: Vector2 = canvas._point_at(canvas._ship_d)
		var q: Vector2 = canvas._point_at(canvas._ship_d + 6.0)
		var dirx: float = q.x - p.x
		if absf(dirx) < 0.01:
			dirx = 1.0
		var k: float = canvas._node_k()
		# a soft ring so it reads on the route
		MapArt.draw_ship(self, p + Vector2(0, -4.0 * k), dirx, canvas._t, 1.15 * k)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func setup(ids: Array[StringName]) -> void:
	dest_ids = ids
	for id in ids:
		var n := DestNode.new(id)
		n.chosen.connect(func(d: StringName) -> void: dest_chosen.emit(d))
		add_child(n)
		nodes.append(n)
	_marker = _Marker.new()
	_marker.canvas = self
	add_child(_marker)
	_layout()


func node_for(dest: StringName) -> DestNode:
	for n in nodes:
		if n.dest == dest:
			return n
	return null


func set_insets(top: float, bottom: float) -> void:
	_inset_top = top
	_inset_bottom = bottom
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _node_k() -> float:
	var free_h: float = size.y - _inset_top - _inset_bottom
	return clampf(minf((free_h - 70.0) / 330.0, size.x / 1320.0), 0.55, 1.1)


func _layout() -> void:
	if nodes.is_empty():
		return
	var k: float = _node_k()
	var nsz := Vector2(400.0, 330.0) * k
	var free := Rect2(0.0, _inset_top, size.x, size.y - _inset_top - _inset_bottom)
	var mid_y: float = free.position.y + free.size.y * 0.5
	var rng_y: float = maxf(free.size.y - nsz.y, 0.0) * 0.5
	var fx: Array[float] = [0.185, 0.5, 0.815]
	var fy: Array[float] = [0.55, -0.45, 0.55]
	for i in range(nodes.size()):
		var n: DestNode = nodes[i]
		var cx: float = free.position.x + free.size.x * fx[mini(i, 2)]
		var cy: float = mid_y + rng_y * fy[mini(i, 2)]
		n.size = nsz
		n.position = Vector2(cx - nsz.x * 0.5, cy - nsz.y * 0.5)
		n.pivot_offset = nsz * 0.5
	_compass_r = 44.0 * k
	_compass_c = Vector2(46.0 * k + 30.0, free.end.y - 56.0 * k)
	_build_route()
	queue_redraw()


func _build_route() -> void:
	_route = PackedVector2Array()
	_route_len = PackedFloat32Array()
	_docks.clear()
	if nodes.size() < 2:
		return
	var k: float = _node_k()
	var cs: Array[Vector2] = []
	for n in nodes:
		cs.append(n.position + n.lagoon_center() + Vector2(0, 6.0 * k))
	var reach: float = 168.0 * k
	var pts := PackedVector2Array()
	var dock_idx: Array[int] = []
	# leg i: from node i (right edge) to node i+1 (left edge)
	for i in range(cs.size() - 1):
		var a: Vector2 = cs[i] + Vector2(reach, 2.0 * k)
		var b: Vector2 = cs[i + 1] + Vector2(-reach, 2.0 * k)
		if i == 0:
			dock_idx.append(pts.size())
		var dx: float = b.x - a.x
		var c1: Vector2 = a + Vector2(dx * 0.5, (cs[i].y - cs[i + 1].y) * -0.15)
		var c2: Vector2 = b + Vector2(-dx * 0.5, (cs[i + 1].y - cs[i].y) * -0.15)
		for s in range(0, 41):
			var u: float = float(s) / 40.0
			var iu: float = 1.0 - u
			pts.append(iu * iu * iu * a + 3.0 * iu * iu * u * c1 + 3.0 * iu * u * u * c2 + u * u * u * b)
		dock_idx.append(pts.size() - 1)
		# straight hidden connector across the next island
		if i + 1 < cs.size() - 1:
			var a2: Vector2 = cs[i + 1] + Vector2(reach, 2.0 * k)
			pts.append(a2)
	_route = pts
	var acc: float = 0.0
	_route_len.append(0.0)
	for i in range(1, pts.size()):
		acc += pts[i].distance_to(pts[i - 1])
		_route_len.append(acc)
	for di in dock_idx:
		_docks.append(_route_len[di])


func _point_at(d: float) -> Vector2:
	if _route.size() < 2:
		return Vector2.ZERO
	d = clampf(d, 0.0, _route_len[_route_len.size() - 1])
	var lo: int = 0
	var hi: int = _route_len.size() - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) / 2
		if _route_len[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg: float = maxf(_route_len[hi] - _route_len[lo], 0.0001)
	return _route[lo].lerp(_route[hi], (d - _route_len[lo]) / seg)


func set_ship_dest(dest: StringName, animated: bool = true) -> void:
	var idx: int = dest_ids.find(dest)
	if idx < 0 or idx >= _docks.size():
		return
	var target: float = _docks[idx]
	if _ship_tw != null and _ship_tw.is_valid():
		_ship_tw.kill()
	if not animated:
		_ship_d = target
		_marker.queue_redraw()
		return
	_ship_tw = create_tween()
	_ship_tw.tween_method(func(v: float) -> void:
		_ship_d = v
		_marker.queue_redraw(), _ship_d, target, clampf(absf(target - _ship_d) / 520.0, 0.5, 1.6)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()
	if _marker != null:
		_marker.queue_redraw()


func _unlocked_until() -> float:
	var far: float = 0.0
	for i in range(nodes.size()):
		if nodes[i].unlocked and i < _docks.size():
			far = maxf(far, _docks[i])
	return far


func _draw() -> void:
	MapArt.draw_sea(self, Rect2(Vector2.ZERO, size), _t)
	MapArt.draw_compass(self, _compass_c, _compass_r, _t)
	var kk: float = _node_k()
	var free_bottom: float = size.y - _inset_bottom
	MapArt.draw_sailboat(self, Vector2(size.x * 0.345, free_bottom - 62.0 * kk), 1.0 * kk, _t, 0.0)
	MapArt.draw_sailboat(self, Vector2(size.x * 0.372, free_bottom - 46.0 * kk), 0.7 * kk, _t, 1.4)
	MapArt.draw_whale(self, Vector2(size.x * 0.66, free_bottom - 56.0 * kk), 1.0 * kk, _t)
	if _route.size() < 2:
		return
	var total: float = _route_len[_route_len.size() - 1]
	var open_d: float = _unlocked_until()
	var k: float = _node_k()
	var spacing: float = 26.0 * k
	var march: float = fmod(_t * 22.0, spacing)
	var d: float = march
	while d < total:
		var p: Vector2 = _point_at(d)
		var open: bool = d <= open_d + 1.0
		if open:
			U.circ(self, p + Vector2(0, 2.5), 6.4 * k, Color(0.05, 0.2, 0.4, 0.22))
			U.circ(self, p, 5.6 * k, Color(1, 1, 1, 0.95))
		else:
			U.circ(self, p, 3.8 * k, Color(1, 1, 1, 0.38))
		d += spacing
