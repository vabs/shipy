class_name TutorialTargets
extends RefCounted
## Screen-space rectangles of things the tutorial points at. Everything is recomputed every frame by the caller,
## so the spotlight follows the ship's bob, the camera pan/zoom and moving guests / crew.
##
## Port mode converts ship-local px through PortPhase.local_to_screen, voyage mode through VoyageInput.local_to_screen.

const SPOT_PREFS: Dictionary = {
	&"cabin": [Vector2i(1, 4), Vector2i(1, 6), Vector2i(1, 8)],
	&"buffet": [Vector2i(1, 6), Vector2i(1, 4), Vector2i(1, 12)],
	&"bar": [Vector2i(2, 8), Vector2i(2, 4), Vector2i(2, 12)],
}

var screen: Node = null
var port_ui: PortPhase = null
var voyage: bool = false
var _spot_cache: Dictionary = {}
var _spot_version: int = -1
var version: int = 0


func bump() -> void:
	version += 1


# ---- generic ----------------------------------------------------------------------------------
static func ctrl(c: Control) -> Rect2:
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return Rect2()
	return c.get_global_rect()


static func union(rects: Array) -> Rect2:
	var out := Rect2()
	var first: bool = true
	for r: Rect2 in rects:
		if r.size.x <= 0.0:
			continue
		out = r if first else out.merge(r)
		first = false
	return out


func to_screen(p: Vector2) -> Vector2:
	if voyage:
		var inp: VoyageInput = screen.input
		return inp.local_to_screen(p)
	return port_ui.local_to_screen(p)


func local_rect(r: Rect2) -> Rect2:
	var a: Vector2 = to_screen(r.position)
	var b: Vector2 = to_screen(Vector2(r.end.x, r.position.y))
	var c: Vector2 = to_screen(r.end)
	var d: Vector2 = to_screen(Vector2(r.position.x, r.end.y))
	var tl := Vector2(minf(minf(a.x, b.x), minf(c.x, d.x)), minf(minf(a.y, b.y), minf(c.y, d.y)))
	var br := Vector2(maxf(maxf(a.x, b.x), maxf(c.x, d.x)), maxf(maxf(a.y, b.y), maxf(c.y, d.y)))
	return Rect2(tl, br - tl)


func zoom() -> float:
	var cam: ShipCamera = screen.cam
	return cam.zoom.x if cam != null else 1.0


# ---- port -------------------------------------------------------------------------------------
func placed_rect(r: PlacedRoom) -> Rect2:
	var port: PortState = screen.port
	return local_rect(SimConst.room_rect(r.first_deck(), r.x, r.def.width, r.decks_tall(port.hull.decks)))


## First placed room of this type (preset rooms count), screen rect or empty.
func placed_rect_of(room_id: StringName) -> Rect2:
	var port: PortState = screen.port
	for r in port.layout.rooms:
		if r.def.id == room_id:
			return placed_rect(r)
	return Rect2()


## Good spot for a new room: {deck, x} (valid per can_place) or {} when nothing fits.
func spot_cell(room_id: StringName) -> Dictionary:
	if _spot_version != version:
		_spot_cache.clear()
		_spot_version = version
	if _spot_cache.has(room_id):
		return _spot_cache[room_id]
	var port: PortState = screen.port
	var found: Dictionary = {}
	var prefs: Array = SPOT_PREFS.get(room_id, [])
	for p: Vector2i in prefs:
		if bool(port.can_place(room_id, p.x, p.y)["ok"]):
			found = {"deck": p.x, "x": p.y}
			break
	if found.is_empty():
		var def: RoomDef = ContentStore.room(room_id)
		var reach: Array[int] = port.grid.graph.reachable_decks(port.hull.gangway_deck)
		var decks: Array[int] = []
		for d in reach:
			if d < port.hull.decks - 1:
				decks.append(d)
		decks.sort()
		for d in decks:
			for x in range(0, port.hull.width - def.width + 1):
				if bool(port.can_place(room_id, d, x)["ok"]):
					found = {"deck": d, "x": x}
					break
			if not found.is_empty():
				break
	_spot_cache[room_id] = found
	return found


func spot_rect(room_id: StringName) -> Rect2:
	var c: Dictionary = spot_cell(room_id)
	if c.is_empty():
		return Rect2()
	var port: PortState = screen.port
	var def: RoomDef = ContentStore.room(room_id)
	return local_rect(SimConst.room_rect(int(c["deck"]), int(c["x"]), def.width, def.decks_tall(port.hull.decks)))


# ---- voyage -----------------------------------------------------------------------------------
func mess_rect(id: int) -> Rect2:
	var rend: VoyageRenderer = screen.renderer
	var lp: Vector2 = rend.local_pos_of(&"mess", id)
	if lp == Vector2.INF:
		return Rect2()
	var z: float = zoom()
	var c: Vector2 = to_screen(lp + Vector2(0, 12))   # local_pos_of() is the splat's icon, the puddle sits on the floor
	var half := Vector2(32.0 * z, 24.0 * z)
	return Rect2(c - half, half * 2.0)


func room_rt_rect(uid: int) -> Rect2:
	var rend: VoyageRenderer = screen.renderer
	var r: Rect2 = rend.room_rect(uid)
	if r.size.x <= 0.0:
		return Rect2()
	return local_rect(r)


func staff_rect(id: int) -> Rect2:
	var rend: VoyageRenderer = screen.renderer
	var lp: Vector2 = rend.local_pos_of(&"staff", id)
	if lp == Vector2.INF:
		return Rect2()
	var c: Vector2 = to_screen(lp)
	var z: float = zoom()
	var half := Vector2(20.0 * z, 26.0 * z)
	return Rect2(c - half, half * 2.0)


func roster_card_rect(id: int) -> Rect2:
	var hud: VoyageHud = screen.hud
	if hud == null:
		return Rect2()
	var cards: Variant = hud.get("_cards")
	if cards is Dictionary and (cards as Dictionary).has(id):
		return ctrl((cards as Dictionary)[id] as Control)
	return Rect2()
