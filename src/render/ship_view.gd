class_name ShipView
extends Node2D
## Renders a ship from plain data (used by the port/build phase AND the voyage).
##
## API
##   set_hull(width_cells: int, decks: int, gangway_deck: int, destination: StringName)
##   set_rooms(rooms: Array)    # each {uid:int, room_id:StringName, deck:int, x:int, width:int, tier:int, decks_tall:int}
##                              # (stairs decks_tall 2; elevator occupies all decks)
##   set_room_state(uid: int, state: Dictionary)   # RoomArt state keys (+ car_deck_f for elevators); merged over previous
##   clear_room_state(uid: int)
##   var bob_enabled: bool = true     # whole ship bobs +-3 px / tilts +-0.5 deg at ~0.22 Hz
##   var anim_speed: float = 1.0      # 0 freezes room/superstructure animation (pause), 1 normal, 2/3 faster
##   var weather: float = 0.0         # 0..1 storm (SimWorld.weather_intensity): the bob grows x3 and the tilt x4 at 1, a little quicker
##   get_layer(name: StringName) -> Node2D   # "rooms_back" (mine) "entities" "rooms_front" (mine) "overlay" "fx"
##       -> children of these inherit the bob; use SimConst.to_px() ship-local coordinates.
##   mouse_local() -> Vector2         # mouse position in ship-local coordinates (same as layer.get_local_mouse_position())
##   cell_at_local(p: Vector2) -> Vector2i   # (x, deck) or (-1, -1)
##   ship_rect() -> Rect2             # local bounds incl. hull + superstructure (+ gangway)
##   room_rect(uid: int) -> Rect2     # local rect of a placed room (empty Rect2 if unknown)
##   waterline_local_y() -> float     # ShipArt.WATERLINE_Y
##   set_visible_margin(px)           # extra margin when culling redraws to the camera view
## Notes: keep the ShipView at the world origin when using ShipCamera. Put UI/Camera-independent stuff elsewhere.

const U := preload("res://src/render/art/art_util.gd")
const DECK_H: float = 76.0
const CELL_W: float = 40.0

var bob_enabled: bool = true
var anim_speed: float = 1.0
var weather: float = 0.0:
	set(v):
		if absf(v - weather) > 0.004:
			weather = v
			if _sway != null:
				_apply_tint()
var width_cells: int = 24
var decks: int = 4
var gangway_deck: int = 1
var destination: StringName = &"med"

var _sway: Node2D
var _baker: ArtBake
var _super_node: _SuperNode
var _structure: _StructNode
var _hull_node: _HullNode
var _layers: Dictionary = {}
var _rooms: Dictionary = {}       # uid -> _RoomNode (back)
var _fronts: Dictionary = {}      # uid -> _RoomNode (front)
var _room_data: Dictionary = {}   # uid -> room Dictionary
var _anim_t: float = 0.0
var _bob_t: float = 0.0
var _bob_ph: float = 0.0
var _frame: int = 0
var _vis_margin: float = 80.0


# ---- inner draw nodes ---------------------------------------------------------------------------
class _SuperNode extends Node2D:
	var view: ShipView
	func _draw() -> void:
		ShipArt.draw_superstructure(self, view.width_cells, view.decks, view._anim_t, view.destination)


class _HullNode extends Node2D:
	var view: ShipView
	func _draw() -> void:
		pass


## Hull + deck cells + gangway + railings: static, so baked once into a mipmapped texture.
class _StructNode extends Node2D:
	var view: ShipView

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		var b := view._struct_bounds()
		var key := view._struct_key()
		var tex := ArtBake.get_tex(key)
		if tex != null:
			draw_texture_rect(tex, b, false)
			return
		view._draw_struct_vector(self, Vector2.ZERO)
		var v := view
		view._baker.request(key, b.size, 2.0, func(ci: CanvasItem) -> void: v._draw_struct_vector(ci, -b.position))


class _RoomNode extends Node2D:
	var view: ShipView
	var room_id: StringName = &""
	var rect: Rect2 = Rect2()
	var tier: int = 1
	var state: Dictionary = {}
	var front: bool = false
	var dirty: bool = true

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		var broken: bool = state.get("broken", false)
		if front and not ShipView._has_static_front(room_id):
			state["pass"] = 2
			RoomArt.draw_room_front(self, room_id, rect, tier, state)
			state["pass"] = 0
			return
		var key := "room|%s|%d|%d|%d|%d|%d" % [room_id, tier, int(rect.size.x), int(rect.size.y), 1 if broken else 0, 1 if front else 0]
		var tex := ArtBake.get_tex(key)
		if tex == null:
			# vector fallback until the static layer is baked
			state["pass"] = 0
			if front:
				RoomArt.draw_room_front(self, room_id, rect, tier, state)
			else:
				RoomArt.draw_room(self, room_id, rect, tier, state)
			var rid := room_id
			var tr := tier
			var sz := rect.size
			var fr := front
			view._baker.request(key, sz, 3.0, func(ci: CanvasItem) -> void:
				U.begin_scaled(ci, Vector2.ZERO, 1.0)
				var r0 := Rect2(Vector2.ZERO, sz)
				var st0 := {"pass": 1, "broken": broken, "t": 0.0}
				if fr:
					RoomArt.draw_room_front(ci, rid, r0, tr, st0)
				else:
					RoomArt.draw_room(ci, rid, r0, tr, st0)
				U.end_scaled(ci))
			return
		draw_texture_rect(tex, rect, false)
		state["pass"] = 2
		if front:
			RoomArt.draw_room_front(self, room_id, rect, tier, state)
		else:
			RoomArt.draw_room(self, room_id, rect, tier, state)
		state["pass"] = 0


# ---- setup --------------------------------------------------------------------------------------
func _init() -> void:
	_baker = ArtBake.new()
	_baker.name = "Baker"
	add_child(_baker)
	_sway = Node2D.new()
	_sway.name = "Sway"
	add_child(_sway)
	_super_node = _SuperNode.new()
	_super_node.view = self
	_sway.add_child(_super_node)
	_hull_node = _HullNode.new()
	_hull_node.view = self
	_sway.add_child(_hull_node)
	_structure = _StructNode.new()
	_structure.view = self
	_sway.add_child(_structure)
	for n in ["rooms_back", "entities", "rooms_front", "overlay", "fx"]:
		var l := Node2D.new()
		l.name = n
		_sway.add_child(l)
		_layers[StringName(n)] = l


func _ready() -> void:
	set_process(true)
	_baker.baked.connect(_on_baked)


func _on_baked(_key: String) -> void:
	_structure.queue_redraw()
	for uid in _rooms.keys():
		(_rooms[uid] as _RoomNode).dirty = true


func _struct_key() -> String:
	return "ship_%d_%d_%d" % [width_cells, decks, gangway_deck]


func _struct_bounds() -> Rect2:
	var w := float(width_cells) * CELL_W
	return Rect2(-90.0, -(float(decks) * DECK_H + 8.0), w + 150.0, float(decks) * DECK_H + 8.0 + ShipArt.HULL_H + 4.0)


func _draw_struct_vector(ci: CanvasItem, offset: Vector2) -> void:
	U.begin_scaled(ci, offset, 1.0)
	ShipArt.draw_hull(ci, width_cells, decks, gangway_deck)
	ShipArt.draw_deck_cells(ci, width_cells, decks)
	ShipArt.draw_gangway(ci, width_cells, decks, gangway_deck)
	ShipArt.draw_railings(ci, width_cells, decks)
	U.end_scaled(ci)


func set_hull(p_width_cells: int, p_decks: int, p_gangway_deck: int, p_destination: StringName = &"med") -> void:
	width_cells = p_width_cells
	decks = p_decks
	gangway_deck = p_gangway_deck
	destination = p_destination
	_hull_node.queue_redraw()
	_structure.queue_redraw()
	_super_node.queue_redraw()
	_apply_tint()


func set_destination(p_destination: StringName) -> void:
	destination = p_destination
	_super_node.queue_redraw()
	_apply_tint()


## Subtle destination lighting on the whole ship (cool in the arctic, dusky in the underworld).
func _apply_tint() -> void:
	var c := Color(1, 1, 1)
	match destination:
		&"arctic": c = Color(0.95, 0.98, 1.0)
		&"underworld": c = Color(0.9, 0.86, 1.0)
	# storm light: the whole ship goes a little dim and blue
	_sway.modulate = c * Color(1, 1, 1).lerp(Color(0.78, 0.83, 0.95), clampf(weather, 0.0, 1.0))


func set_rooms(rooms: Array) -> void:
	var seen: Dictionary = {}
	for r in rooms:
		var uid: int = int(r["uid"])
		seen[uid] = true
		var rd: Dictionary = r
		var deck: int = int(rd["deck"])
		var x: int = int(rd["x"])
		var wc: int = int(rd.get("width", RoomArt.default_width(rd["room_id"])))
		var tall: int = int(rd.get("decks_tall", 1))
		var rid: StringName = rd["room_id"]
		if rid == &"elevator":
			tall = decks
			deck = 0
		var rect := Rect2(Vector2(float(x) * CELL_W, -float(deck + tall) * DECK_H), Vector2(float(wc) * CELL_W, float(tall) * DECK_H))
		var node: _RoomNode = _rooms.get(uid)
		var fnode: _RoomNode = _fronts.get(uid)
		if node == null:
			node = _RoomNode.new()
			node.view = self
			(_layers[&"rooms_back"] as Node2D).add_child(node)
			_rooms[uid] = node
			node.state = {}
		node.room_id = rid
		node.rect = rect
		node.tier = int(rd.get("tier", 1))
		node.dirty = true
		var needs_front := _has_front(rid)
		if needs_front and fnode == null:
			fnode = _RoomNode.new()
			fnode.view = self
			fnode.front = true
			(_layers[&"rooms_front"] as Node2D).add_child(fnode)
			_fronts[uid] = fnode
		if fnode != null:
			fnode.room_id = rid
			fnode.rect = rect
			fnode.tier = node.tier
			fnode.state = node.state
			fnode.dirty = true
		_room_data[uid] = rd
	# remove rooms that disappeared
	for uid in _rooms.keys():
		if not seen.has(uid):
			(_rooms[uid] as Node).queue_free()
			_rooms.erase(uid)
			if _fronts.has(uid):
				(_fronts[uid] as Node).queue_free()
				_fronts.erase(uid)
			_room_data.erase(uid)


static func _has_static_front(rid: StringName) -> bool:
	return rid in [&"bar", &"pool", &"restaurant", &"ice_rink"]


static func _has_front(rid: StringName) -> bool:
	return rid in [&"cabin", &"toilets", &"bar", &"pool", &"cinema", &"restaurant", &"sauna", &"ice_rink", &"crew_quarters"]


func set_room_state(uid: int, state: Dictionary) -> void:
	var node: _RoomNode = _rooms.get(uid)
	if node == null:
		return
	var changed := false
	for k in state.keys():
		if not node.state.has(k) or node.state[k] != state[k]:
			node.state[k] = state[k]
			changed = true
	if not changed:
		return
	node.dirty = true
	var f: _RoomNode = _fronts.get(uid)
	if f != null:
		f.state = node.state
		f.dirty = true


func clear_room_state(uid: int) -> void:
	var node: _RoomNode = _rooms.get(uid)
	if node == null:
		return
	node.state = {}
	node.dirty = true


func get_layer(layer_name: StringName) -> Node2D:
	return _layers.get(layer_name)


func set_visible_margin(px: float) -> void:
	_vis_margin = px


func mouse_local() -> Vector2:
	return _sway.get_local_mouse_position()


func cell_at_local(p: Vector2) -> Vector2i:
	var w := float(width_cells) * CELL_W
	if p.x < 0.0 or p.x >= w or p.y >= 0.0 or p.y < -float(decks) * DECK_H:
		return Vector2i(-1, -1)
	return Vector2i(int(floor(p.x / CELL_W)), int(floor(-p.y / DECK_H)))


func ship_rect() -> Rect2:
	return ShipArt.ship_bounds(width_cells, decks)


func room_rect(uid: int) -> Rect2:
	var n: _RoomNode = _rooms.get(uid)
	return n.rect if n != null else Rect2()


func waterline_local_y() -> float:
	return ShipArt.WATERLINE_Y


# ---- per-frame ----------------------------------------------------------------------------------
func _visible_local_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2(-1e6, -1e6, 2e6, 2e6)
	var vr := vp.get_visible_rect()
	var inv := _sway.get_global_transform_with_canvas().affine_inverse()
	var r := Rect2(inv * vr.position, Vector2.ZERO)
	r = r.expand(inv * Vector2(vr.end.x, vr.position.y))
	r = r.expand(inv * vr.end)
	r = r.expand(inv * Vector2(vr.position.x, vr.end.y))
	return r.grow(_vis_margin)


func _process(delta: float) -> void:
	_bob_t += delta
	_bob_ph += delta * TAU * 0.22 * (1.0 + 0.45 * weather)
	_anim_t += delta * anim_speed
	_frame += 1
	# bob + tilt about the waterline centre
	if bob_enabled:
		var ph := _bob_ph
		var dy := sin(ph) * 3.0 * (1.0 + 2.0 * weather) + sin(ph * 2.7 + 1.3) * 1.6 * weather
		var rot := sin(ph + 0.9) * deg_to_rad(0.5) * (1.0 + 3.0 * weather)
		var pivot := Vector2(float(width_cells) * CELL_W * 0.5, ShipArt.WATERLINE_Y)
		var rm := Transform2D(rot, Vector2.ZERO)
		_sway.transform = Transform2D(rot, Vector2.ONE, 0.0, pivot - rm * pivot + Vector2(0.0, dy))
	else:
		_sway.transform = Transform2D.IDENTITY
	var animating := anim_speed > 0.0
	# superstructure animation at ~30 Hz
	if animating and _frame % 2 == 0:
		_super_node.queue_redraw()
	# rooms: redraw animated ones at ~30 Hz (staggered), only when near the view; dirty ones immediately
	var vis := _visible_local_rect()
	var parity := _frame % 2
	for uid in _rooms.keys():
		var node: _RoomNode = _rooms[uid]
		var f: _RoomNode = _fronts.get(uid)
		var on_screen := node.rect.intersects(vis)
		if not on_screen:
			continue
		if node.dirty or (animating and int(uid) % 2 == parity):
			node.state["t"] = _anim_t
			node.queue_redraw()
			if f != null:
				f.state = node.state
				f.queue_redraw()
			node.dirty = false
