class_name PortState
extends RefCounted
## Everything the player controls in port: budget, layout, hired crew. All port-phase mutations go
## through here (UI) so that budget accounting stays in one place.

signal changed

var level: LevelDef
var hull: HullDef
var layout: ShipLayout
var grid: ShipGrid
## Crew pre-hired by the level (free, can't be fired).
var preset_staff: Dictionary = {}
## Crew hired by the player in port (wages already deducted from the budget).
var hired: Dictionary = {&"janitor": 0, &"mechanic": 0}

var budget: int:
	get:
		return grid.money
	set(v):
		grid.money = v


func _init(lvl: LevelDef, campaign_index: int = -1) -> void:
	level = lvl
	hull = ContentStore.hull(lvl.hull)
	layout = ShipLayout.new(hull)
	grid = ShipGrid.new(layout, lvl, lvl.budget)
	if campaign_index >= 0:
		grid.campaign_index = campaign_index
	for p in lvl.preset_rooms:
		grid.place_free(StringName(p.get("room", &"")), int(p.get("deck", 0)), int(p.get("x", 0)), bool(p.get("locked", false)))
	preset_staff = lvl.preset_staff.duplicate()


# --- rooms -------------------------------------------------------------------------------------
func can_place(room_id: StringName, deck: int, x: int, ignore_uid: int = -1) -> Dictionary:
	return grid.can_place(room_id, deck, x, ignore_uid)


func place(room_id: StringName, deck: int, x: int) -> PlacedRoom:
	var r: PlacedRoom = grid.place(room_id, deck, x)
	if r != null:
		changed.emit()
	return r


func move(uid: int, deck: int, x: int) -> bool:
	var ok: bool = grid.move(uid, deck, x)
	if ok:
		changed.emit()
	return ok


func sell(uid: int) -> int:
	var refund: int = grid.sell(uid)
	if refund >= 0:
		changed.emit()
	return refund


func upgrade(uid: int) -> bool:
	var ok: bool = grid.upgrade(uid)
	if ok:
		changed.emit()
	return ok


## Every room that can appear in this level's catalog (rooms locked to other destinations are
## left out): [{def: RoomDef, available: bool, reason: String}] sorted by unlock level then name.
func catalog() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in ContentStore.all_rooms():
		if def.destination_lock != &"" and def.destination_lock != level.destination:
			continue
		var reason: String = grid.room_lock_reason(def.id)
		out.append({"def": def, "available": reason == "", "reason": reason})
	return out


# --- crew --------------------------------------------------------------------------------------
func max_staff() -> int:
	return hull.max_staff


func staff_total() -> int:
	var n: int = 0
	for k in preset_staff:
		n += int(preset_staff[k])
	for k in hired:
		n += int(hired[k])
	return n


func staff_counts() -> Dictionary:
	var out: Dictionary = {}
	for k in preset_staff:
		out[StringName(k)] = int(out.get(StringName(k), 0)) + int(preset_staff[k])
	for k in hired:
		out[StringName(k)] = int(out.get(StringName(k), 0)) + int(hired[k])
	return out


func can_hire(role: StringName) -> Dictionary:
	var def: StaffDef = ContentStore.staff_role(role)
	if def == null:
		return {"ok": false, "reason": "Unknown role"}
	if staff_total() >= hull.max_staff:
		return {"ok": false, "reason": "Crew is full"}
	if def.wage > budget:
		return {"ok": false, "reason": "Not enough money"}
	return {"ok": true, "reason": ""}


func hire(role: StringName) -> bool:
	if not can_hire(role)["ok"]:
		return false
	var def: StaffDef = ContentStore.staff_role(role)
	budget -= def.wage
	hired[role] = int(hired.get(role, 0)) + 1
	changed.emit()
	return true


func fire(role: StringName) -> bool:
	if int(hired.get(role, 0)) <= 0:
		return false
	var def: StaffDef = ContentStore.staff_role(role)
	budget += def.wage
	hired[role] = int(hired[role]) - 1
	changed.emit()
	return true


# --- info --------------------------------------------------------------------------------------
## Guest manifest: {guests, by_archetype {id: count}, waves [{t,count}], beds, cabins_built,
## cabins_needed}.
func manifest() -> Dictionary:
	var total: int = level.total_guests()
	var sum_w: float = 0.0
	for k in level.archetype_weights:
		sum_w += float(level.archetype_weights[k])
	var by: Dictionary = {}
	var assigned: int = 0
	var ids: Array = level.archetype_weights.keys()
	for i in ids.size():
		var k: StringName = StringName(ids[i])
		var n: int = int(round(float(total) * float(level.archetype_weights[k]) / maxf(sum_w, 0.0001)))
		if i == ids.size() - 1:
			n = maxi(total - assigned, 0)
		assigned += n
		by[k] = n
	var beds: int = 0
	var cabins: int = 0
	for r in layout.rooms:
		if r.def.id == &"cabin":
			beds += r.capacity()
			cabins += 1
	var cabin_def: RoomDef = ContentStore.room(&"cabin")
	return {
		"guests": total,
		"by_archetype": by,
		"waves": level.waves.duplicate(true),
		"beds": beds,
		"cabins_built": cabins,
		"cabins_needed": int(ceil(float(total) / float(cabin_def.capacity))),
	}


func validate() -> Dictionary:
	return grid.validate_for_voyage(level.total_guests(), staff_total())


func utilities() -> Dictionary:
	return grid.utilities()


## Creates the voyage simulation from the current port state.
func create_world(seed_value: int = 1) -> SimWorld:
	return SimWorld.new(level, layout.duplicate(), staff_counts(), seed_value, budget)
