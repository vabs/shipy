class_name ShipGrid
extends RefCounted
## Placement rules, utilities, connectivity validation and the walk graph for a ShipLayout.
## Port-phase mutations should go through PortState, which wraps this class.

var layout: ShipLayout
var hull: HullDef
var level: LevelDef
## Campaign index used for room/tier unlocks (defaults to the level's index).
var campaign_index: int = 99
var destination: StringName = &""
## Port budget. place/sell/upgrade charge and refund it when `enforce_money` is set.
var money: int = 1 << 30
var enforce_money: bool = true
var enforce_unlock: bool = true
var enforce_utilities: bool = true
var _graph: WalkGraph = null


func _init(l: ShipLayout, lvl: LevelDef = null, budget: int = -1) -> void:
	layout = l
	hull = l.hull
	level = lvl
	if lvl != null:
		campaign_index = lvl.campaign_index
		destination = lvl.destination
	if budget >= 0:
		money = budget


# ---------------------------------------------------------------------------------------------
# Graph
# ---------------------------------------------------------------------------------------------
var graph: WalkGraph:
	get:
		if _graph == null:
			rebuild_graph()
		return _graph


func rebuild_graph() -> void:
	_graph = WalkGraph.new()
	_graph.build(layout)


func invalidate_graph() -> void:
	_graph = null


func door_node(room: PlacedRoom) -> int:
	return graph.node(room.deck, int(room.door_x()))


# ---------------------------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------------------------
func power_used(ignore_uid: int = -1) -> int:
	var n: int = 0
	for r in layout.rooms:
		if r.uid != ignore_uid and r.def.power > 0:
			n += r.def.power
	return n


func power_capacity(ignore_uid: int = -1) -> int:
	var n: int = hull.power
	for r in layout.rooms:
		if r.uid != ignore_uid and r.def.power < 0:
			n -= r.def.power
	return n


func water_used(ignore_uid: int = -1) -> int:
	var n: int = 0
	for r in layout.rooms:
		if r.uid != ignore_uid and r.def.water > 0:
			n += r.def.water
	return n


func water_capacity(ignore_uid: int = -1) -> int:
	var n: int = hull.water
	for r in layout.rooms:
		if r.uid != ignore_uid and r.def.water < 0:
			n -= r.def.water
	return n


func utilities() -> Dictionary:
	return {
		"power_used": power_used(), "power_cap": power_capacity(),
		"water_used": water_used(), "water_cap": water_capacity(),
	}


# ---------------------------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------------------------
func _res(ok: bool, reason: String = "") -> Dictionary:
	return {"ok": ok, "reason": reason}


## The room (other than `ignore_uid`) that a candidate placement would overlap, or null.
func overlap_with(def: RoomDef, deck: int, x: int, ignore_uid: int = -1) -> PlacedRoom:
	var d0: int = 0 if def.is_elevator() else deck
	var tall: int = def.decks_tall(hull.decks)
	for r in layout.rooms:
		if r.uid == ignore_uid:
			continue
		var r0: int = r.first_deck()
		var rt: int = r.decks_tall(hull.decks)
		if d0 < r0 + rt and r0 < d0 + tall and x < r.x + r.def.width and r.x < x + def.width:
			return r
	return null


## "" if the room can be built in this level, else a short reason ("Unlocks at level 3").
func room_lock_reason(def_id: StringName) -> String:
	var def: RoomDef = ContentStore.room(def_id)
	if def == null:
		return "Unknown room"
	if def.destination_lock != &"" and def.destination_lock != destination:
		return "Not available here"
	if def.unlock_level > campaign_index:
		return "Unlocks at level %d" % def.unlock_level
	return ""


func can_place(def_id: StringName, deck: int, x: int, ignore_uid: int = -1) -> Dictionary:
	return _check_place(def_id, deck, x, ignore_uid, enforce_money, enforce_unlock, enforce_utilities, money)


## The placement rules with explicit switches (the port uses the grid's own flags; a mid-voyage refit forces all three on with
## the voyage money as `funds`).
func _check_place(def_id: StringName, deck: int, x: int, ignore_uid: int, use_money: bool, use_unlock: bool, use_utilities: bool, funds: int) -> Dictionary:
	var def: RoomDef = ContentStore.room(def_id)
	if def == null:
		return _res(false, "Unknown room")
	var moving: bool = ignore_uid >= 0
	if use_unlock and not def.is_available(campaign_index, destination):
		if def.unlock_level > campaign_index:
			return _res(false, "Unlocks at level %d" % def.unlock_level)
		return _res(false, "Not available here")
	if use_money and not moving and def.cost > funds:
		return _res(false, "Not enough money")
	var top: int = hull.decks - 1
	if x < 0 or x + def.width > hull.width or deck < 0 or deck > top:
		return _res(false, "Out of bounds")
	match def.placement:
		&"top_deck":
			if deck != top:
				return _res(false, "Top deck only")
		&"interior":
			if deck == top:
				return _res(false, "Not on the top deck")
		_:
			pass
	if def.is_stairs() and deck + 1 > top:
		return _res(false, "Needs 2 free decks")
	var hit: PlacedRoom = overlap_with(def, deck, x, ignore_uid)
	if hit != null:
		if def.is_stairs() and not hit.occupies(deck, x, hull.decks):
			return _res(false, "Needs 2 free decks")
		return _res(false, "Overlaps %s" % hit.def.display_name)
	if use_utilities and not moving:
		if def.power > 0 and power_used() + def.power > power_capacity():
			return _res(false, "Not enough power")
		if def.water > 0 and water_used() + def.water > water_capacity():
			return _res(false, "Not enough water")
	return _res(true)


## Quick refit at a port stop (docs/SPEC.md §13.8): can_place with the voyage money (`funds`), unlocks and utilities always enforced, plus
## connectivity: the new room must be reachable from the gangway deck (stairs just need one of their two decks to be; an elevator
## connects everything by itself). Nothing may overlap, as always.
func can_refit_place(def_id: StringName, deck: int, x: int, funds: int) -> Dictionary:
	var res: Dictionary = _check_place(def_id, deck, x, -1, true, true, true, funds)
	if not bool(res["ok"]):
		return res
	var def: RoomDef = ContentStore.room(def_id)
	if def.is_elevator():
		return res
	var reach: Array[int] = graph.reachable_decks(hull.gangway_deck)
	if def.is_stairs():
		if not reach.has(deck) and not reach.has(deck + 1):
			return _res(false, "Not connected")
	elif not reach.has(deck):
		return _res(false, "Not connected")
	return res


## Upgrade rules for a refit: like can_upgrade with the voyage money and the tier unlock levels always enforced.
func can_refit_upgrade(uid: int, funds: int) -> Dictionary:
	var r: PlacedRoom = layout.get_room(uid)
	if r == null:
		return _res(false, "No such room")
	var cost: int = r.def.upgrade_cost(r.tier)
	if cost < 0:
		return _res(false, "Fully upgraded" if r.def.max_tier() > 0 else "Can't be upgraded")
	if campaign_index < tier_unlock_level(r.tier + 1):
		return _res(false, "Unlocks at level %d" % tier_unlock_level(r.tier + 1))
	if cost > funds:
		return _res(false, "Not enough money")
	return _res(true)


## Places and charges. Returns the new PlacedRoom or null (see can_place for the reason).
func place(def_id: StringName, deck: int, x: int, locked: bool = false) -> PlacedRoom:
	if not can_place(def_id, deck, x)["ok"]:
		return null
	var def: RoomDef = ContentStore.room(def_id)
	if enforce_money:
		money -= def.cost
	var r: PlacedRoom = layout.add_room(def, deck, x, 0, locked)
	if def.is_transport():
		invalidate_graph()
	return r


## Adds a room without any checks or cost (level presets, tests).
func place_free(def_id: StringName, deck: int, x: int, locked: bool = false, tier: int = 0) -> PlacedRoom:
	var def: RoomDef = ContentStore.room(def_id)
	var r: PlacedRoom = layout.add_room(def, deck, x, tier, locked)
	if def.is_transport():
		invalidate_graph()
	return r


func can_move(uid: int, deck: int, x: int) -> Dictionary:
	var r: PlacedRoom = layout.get_room(uid)
	if r == null:
		return _res(false, "No such room")
	if r.locked:
		return _res(false, "Locked")
	return can_place(r.def.id, deck, x, uid)


func move(uid: int, deck: int, x: int) -> bool:
	if not can_move(uid, deck, x)["ok"]:
		return false
	var r: PlacedRoom = layout.get_room(uid)
	r.deck = 0 if r.is_elevator() else deck
	r.x = x
	if r.is_transport():
		invalidate_graph()
	return true


func can_sell(uid: int) -> Dictionary:
	var r: PlacedRoom = layout.get_room(uid)
	if r == null:
		return _res(false, "No such room")
	if r.locked:
		return _res(false, "Locked")
	if enforce_utilities:
		if r.def.power < 0 and power_used() > power_capacity(uid):
			return _res(false, "Power still needed")
		if r.def.water < 0 and water_used() > water_capacity(uid):
			return _res(false, "Water still needed")
	return _res(true)


func refund_for(uid: int) -> int:
	var r: PlacedRoom = layout.get_room(uid)
	if r == null:
		return 0
	return int(floor(float(r.invested()) * SimConst.SELL_REFUND))


## Sells a room; returns the refund, or -1 if it could not be sold.
func sell(uid: int) -> int:
	if not can_sell(uid)["ok"]:
		return -1
	var refund: int = refund_for(uid)
	var r: PlacedRoom = layout.get_room(uid)
	var was_transport: bool = r.def.is_transport()
	layout.remove_room(uid)
	if enforce_money:
		money += refund
	if was_transport:
		invalidate_graph()
	return refund


func tier_unlock_level(next_tier: int) -> int:
	return SimConst.TIER2_UNLOCK_LEVEL if next_tier <= 1 else SimConst.TIER3_UNLOCK_LEVEL


func upgrade_cost(uid: int) -> int:
	var r: PlacedRoom = layout.get_room(uid)
	if r == null:
		return -1
	return r.def.upgrade_cost(r.tier)


func can_upgrade(uid: int) -> Dictionary:
	var r: PlacedRoom = layout.get_room(uid)
	if r == null:
		return _res(false, "No such room")
	var cost: int = r.def.upgrade_cost(r.tier)
	if cost < 0:
		return _res(false, "Fully upgraded" if r.def.max_tier() > 0 else "Can't be upgraded")
	if enforce_unlock and campaign_index < tier_unlock_level(r.tier + 1):
		return _res(false, "Unlocks at level %d" % tier_unlock_level(r.tier + 1))
	if enforce_money and cost > money:
		return _res(false, "Not enough money")
	return _res(true)


func upgrade(uid: int) -> bool:
	if not can_upgrade(uid)["ok"]:
		return false
	var r: PlacedRoom = layout.get_room(uid)
	if enforce_money:
		money -= r.def.upgrade_cost(r.tier)
	r.tier += 1
	return true


# ---------------------------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------------------------
func deck_name(deck: int) -> String:
	return "Top deck" if deck == hull.decks - 1 else "Deck %d" % (deck + 1)


## Errors block "Set sail"; warnings do not. `guests` / `staff_total` default to the level's totals
## and 'unknown' (-1: no staff warning).
func validate_for_voyage(guests: int = -1, staff_total: int = -1) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	rebuild_graph()
	var reach: Array[int] = graph.reachable_decks(hull.gangway_deck)
	var decks_with_rooms: Dictionary = {}
	for r in layout.rooms:
		if r.is_transport():
			continue
		decks_with_rooms[r.deck] = true
	var keys: Array = decks_with_rooms.keys()
	keys.sort()
	for d in keys:
		if not reach.has(int(d)):
			errors.append("%s is not connected to the gangway deck. Add stairs or an elevator." % deck_name(int(d)))
	if guests < 0 and level != null:
		guests = level.peak_guests()
	var beds: int = 0
	for r in layout.rooms:
		if r.def.id == &"cabin":
			beds += r.capacity()
	if guests >= 0 and beds < guests:
		warnings.append("Only %d beds for %d guests. Some guests will have no cabin." % [beds, guests])
	var has_food: bool = false
	var has_toilet: bool = false
	var has_fun: bool = false
	for r in layout.rooms:
		if r.def.satisfies.has(&"hunger"):
			has_food = true
		if r.def.satisfies.has(&"hygiene") and r.def.category == &"hygiene":
			has_toilet = true
		if r.def.satisfies.has(&"fun") and r.def.category == &"fun":
			has_fun = true
	if not has_food:
		warnings.append("No food: guests will go hungry.")
	if not has_toilet:
		warnings.append("No toilets: guests will get grubby.")
	if not has_fun:
		warnings.append("Nothing fun to do: guests will get bored.")
	if staff_total == 0:
		warnings.append("No crew hired: messes and breakdowns will pile up.")
	elif level != null and level.staff_fatigue and layout.count_of(&"crew_quarters") == 0:
		warnings.append("Crew tire out on this voyage. Build crew quarters or they will nap in the corridors.")
	return {"errors": errors, "warnings": warnings}
