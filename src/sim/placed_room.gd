class_name PlacedRoom
extends RefCounted
## A room placed on a ShipLayout. Pure data. `tier` is 0-based (0 = tier I, 1 = tier II, 2 = tier III).
## Elevators have deck 0 and span the whole hull; stairs at (deck, x) also occupy (deck + 1, x).

var uid: int = 0
var def: RoomDef
var deck: int = 0
var x: int = 0
var tier: int = 0
var locked: bool = false


func width() -> int:
	return def.width


func is_stairs() -> bool:
	return def.id == &"stairs"


func is_elevator() -> bool:
	return def.id == &"elevator"


func is_transport() -> bool:
	return def.category == &"transport"


func decks_tall(hull_decks: int) -> int:
	return def.decks_tall(hull_decks)


## Lowest deck occupied.
func first_deck() -> int:
	return 0 if def.id == &"elevator" else deck


func occupies(d: int, cell: int, hull_decks: int) -> bool:
	if cell < x or cell >= x + def.width:
		return false
	var d0: int = first_deck()
	return d >= d0 and d < d0 + def.decks_tall(hull_decks)


func capacity() -> int:
	return def.capacity_at(tier)


func door_x() -> float:
	return float(x) + float(def.width) / 2.0


## Everything the player has paid for this room (base cost + upgrades).
func invested() -> int:
	var total: int = def.cost
	for t in tier:
		total += maxi(def.upgrade_cost(t), 0)
	return total


func copy() -> PlacedRoom:
	var r := PlacedRoom.new()
	r.uid = uid
	r.def = def
	r.deck = deck
	r.x = x
	r.tier = tier
	r.locked = locked
	return r
