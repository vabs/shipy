class_name WalkGraph
extends RefCounted
## Walk graph over (deck, cell) points of a hull. One node per cell; horizontal edges cost
## 1/GUEST_SPEED s, stairs 1.6 s per deck, elevators 1.0 s + 0.5 s per deck (docs/SPEC.md §5).
## Shortest paths are Dijkstra distance maps cached per source node (a custom array-based graph is
## much faster than AStar2D with a custom cost callback for the thousands of queries a voyage makes);
## routes are cached per (from, to) pair.

const UNREACHABLE: float = 1.0e9

var width: int = 0
var decks: int = 0
var count: int = 0
var elevator_cols: Dictionary = {}
var _adj: Array[PackedInt32Array] = []
var _adj_cost: Array[PackedFloat32Array] = []
var _dist: Dictionary = {}
var _pred: Dictionary = {}
var _route_cache: Dictionary = {}
var _hk: PackedFloat32Array = PackedFloat32Array()
var _hn: PackedInt32Array = PackedInt32Array()


func build(layout: ShipLayout) -> void:
	width = layout.hull.width
	decks = layout.hull.decks
	count = width * decks
	elevator_cols = {}
	_dist = {}
	_pred = {}
	_route_cache = {}
	_adj = []
	_adj_cost = []
	for i in count:
		_adj.append(PackedInt32Array())
		_adj_cost.append(PackedFloat32Array())
	var hcost: float = 1.0 / SimConst.GUEST_SPEED
	for d in decks:
		for c in range(width - 1):
			_link(node(d, c), node(d, c + 1), hcost)
	for r in layout.rooms:
		if r.is_stairs():
			var a: int = node(r.deck, r.x)
			var b: int = node(r.deck + 1, r.x)
			if r.deck + 1 < decks:
				_link(a, b, SimConst.STAIRS_TIME_PER_DECK)
		elif r.is_elevator():
			elevator_cols[r.x] = true
			for d1 in decks:
				for d2 in range(d1 + 1, decks):
					var cost: float = SimConst.ELEVATOR_WAIT + SimConst.ELEVATOR_TIME_PER_DECK * float(d2 - d1)
					_link(node(d1, r.x), node(d2, r.x), cost)


func _link(a: int, b: int, cost: float) -> void:
	_adj[a].append(b)
	_adj_cost[a].append(cost)
	_adj[b].append(a)
	_adj_cost[b].append(cost)


func node(deck: int, cell: int) -> int:
	return clampi(deck, 0, decks - 1) * width + clampi(cell, 0, width - 1)


func node_deck(n: int) -> int:
	return n / width


func node_cell(n: int) -> int:
	return n % width


## Seconds to walk from node a to node b (UNREACHABLE if no path).
func cost(a: int, b: int) -> float:
	if a == b:
		return 0.0
	var dist: PackedFloat32Array = _dist_from(a)
	return dist[b]


func reachable(a: int, b: int) -> bool:
	return cost(a, b) < UNREACHABLE * 0.5


func cost_cells(deck_a: int, x_a: float, deck_b: int, x_b: float) -> float:
	return cost(node(deck_a, int(x_a)), node(deck_b, int(x_b)))


func _dist_from(src: int) -> PackedFloat32Array:
	if _dist.has(src):
		return _dist[src]
	_dijkstra(src)
	return _dist[src]


func _hpush(key: float, n: int) -> void:
	var i: int = _hk.size()
	_hk.append(key)
	_hn.append(n)
	while i > 0:
		var p: int = (i - 1) >> 1
		if _hk[p] <= _hk[i]:
			break
		var tk: float = _hk[p]
		_hk[p] = _hk[i]
		_hk[i] = tk
		var tn: int = _hn[p]
		_hn[p] = _hn[i]
		_hn[i] = tn
		i = p


func _hpop() -> void:
	# Removes the root (caller has already read it).
	var last: int = _hk.size() - 1
	_hk[0] = _hk[last]
	_hn[0] = _hn[last]
	_hk.resize(last)
	_hn.resize(last)
	var i: int = 0
	var size: int = last
	while true:
		var l: int = i * 2 + 1
		var r: int = l + 1
		var m: int = i
		if l < size and _hk[l] < _hk[m]:
			m = l
		if r < size and _hk[r] < _hk[m]:
			m = r
		if m == i:
			break
		var tk: float = _hk[m]
		_hk[m] = _hk[i]
		_hk[i] = tk
		var tn: int = _hn[m]
		_hn[m] = _hn[i]
		_hn[i] = tn
		i = m


func _dijkstra(src: int) -> void:
	var dist := PackedFloat32Array()
	dist.resize(count)
	dist.fill(UNREACHABLE)
	var pred := PackedInt32Array()
	pred.resize(count)
	pred.fill(-1)
	_hk = PackedFloat32Array()
	_hn = PackedInt32Array()
	dist[src] = 0.0
	_hpush(0.0, src)
	while _hk.size() > 0:
		var d: float = _hk[0]
		var u: int = _hn[0]
		_hpop()
		if d > dist[u]:
			continue
		var nb: PackedInt32Array = _adj[u]
		var nc: PackedFloat32Array = _adj_cost[u]
		for k in nb.size():
			var v: int = nb[k]
			var nd: float = d + nc[k]
			if nd < dist[v]:
				dist[v] = nd
				pred[v] = u
				_hpush(nd, v)
	_dist[src] = dist
	_pred[src] = pred


## Node path from a to b inclusive (empty if unreachable).
func path_nodes(a: int, b: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if a == b:
		out.append(a)
		return out
	if not reachable(a, b):
		return out
	var pred: PackedInt32Array = _pred[a]
	var cur: int = b
	var rev: Array[int] = []
	while cur != -1 and cur != a:
		rev.append(cur)
		cur = pred[cur]
	rev.append(a)
	rev.reverse()
	for n in rev:
		out.append(n)
	return out


## Waypoint list [{deck, x, mode: &"walk"|&"stairs"|&"elevator"}] from node a to node b. Horizontal runs
## are merged into one walk waypoint at the last cell centre; a vertical hop is preceded by a walk
## waypoint to the column centre. Empty array = already there OR unreachable (check `reachable`).
## The returned array is cached and shared: duplicate before mutating.
func route(a: int, b: int) -> Array:
	var key: int = a * count + b
	if _route_cache.has(key):
		return _route_cache[key]
	var out: Array = []
	var nodes: PackedInt32Array = path_nodes(a, b)
	for i in range(1, nodes.size()):
		var pn: int = nodes[i - 1]
		var cn: int = nodes[i]
		var pd: int = pn / width
		var pc: int = pn % width
		var cd: int = cn / width
		var cc: int = cn % width
		if cd == pd:
			if out.size() > 0 and out[out.size() - 1].mode == &"walk" and out[out.size() - 1].deck == cd:
				out[out.size() - 1] = {"deck": cd, "x": float(cc) + 0.5, "mode": &"walk"}
			else:
				out.append({"deck": cd, "x": float(cc) + 0.5, "mode": &"walk"})
		else:
			var col_x: float = float(pc) + 0.5
			if out.size() == 0 or out[out.size() - 1].mode != &"walk" or absf(float(out[out.size() - 1].x) - col_x) > 0.01:
				out.append({"deck": pd, "x": col_x, "mode": &"walk"})
			var mode: StringName = &"elevator" if elevator_cols.has(pc) else &"stairs"
			out.append({"deck": cd, "x": col_x, "mode": mode})
	_route_cache[key] = out
	return out


## Decks reachable from `deck` (walking cell 0 of that deck).
func reachable_decks(from_deck: int) -> Array[int]:
	var src: int = node(from_deck, 0)
	var dist: PackedFloat32Array = _dist_from(src)
	var out: Array[int] = []
	for d in decks:
		if dist[node(d, 0)] < UNREACHABLE * 0.5 or d == from_deck:
			out.append(d)
	return out
