class_name ShipLayout
extends RefCounted
## Hull + list of PlacedRoom. Pure data and duplicable; ShipGrid enforces the placement rules.

var hull: HullDef
var rooms: Array[PlacedRoom] = []
var next_uid: int = 1


func _init(h: HullDef = null) -> void:
	hull = h


func top_deck() -> int:
	return hull.decks - 1


func add_room(def: RoomDef, deck: int, x: int, tier: int = 0, locked: bool = false) -> PlacedRoom:
	var r := PlacedRoom.new()
	r.uid = next_uid
	next_uid += 1
	r.def = def
	r.deck = 0 if def.id == &"elevator" else deck
	r.x = x
	r.tier = tier
	r.locked = locked
	rooms.append(r)
	return r


func remove_room(uid: int) -> bool:
	for i in rooms.size():
		if rooms[i].uid == uid:
			rooms.remove_at(i)
			return true
	return false


func get_room(uid: int) -> PlacedRoom:
	for r in rooms:
		if r.uid == uid:
			return r
	return null


## Room occupying cell (deck, cell), or null.
func room_at(deck: int, cell: int) -> PlacedRoom:
	var decks: int = hull.decks
	for r in rooms:
		if r.occupies(deck, cell, decks):
			return r
	return null


func rooms_of(room_id: StringName) -> Array[PlacedRoom]:
	var out: Array[PlacedRoom] = []
	for r in rooms:
		if r.def.id == room_id:
			out.append(r)
	return out


func count_of(room_id: StringName) -> int:
	var n: int = 0
	for r in rooms:
		if r.def.id == room_id:
			n += 1
	return n


func rooms_on_deck(deck: int) -> Array[PlacedRoom]:
	var out: Array[PlacedRoom] = []
	for r in rooms:
		if r.first_deck() <= deck and deck < r.first_deck() + r.decks_tall(hull.decks):
			out.append(r)
	return out


func duplicate() -> ShipLayout:
	var l := ShipLayout.new(hull)
	l.next_uid = next_uid
	for r in rooms:
		l.rooms.append(r.copy())
	return l


## Cheap signature of everything that affects walking (stairs/elevators).
func transport_signature() -> String:
	var parts: PackedStringArray = []
	for r in rooms:
		if r.is_transport():
			parts.append("%s@%d,%d" % [r.def.id, r.first_deck(), r.x])
	parts.sort()
	return ",".join(parts)
