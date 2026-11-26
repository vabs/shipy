class_name RefitState
extends PortState
## The "Quick refit" at a mid-voyage port stop (docs/SPEC.md §13.8): a PortState that edits the LIVE ship of a running SimWorld, so
## PortPhase (build bar, ghost preview, popover, crew panel) can be reused as it is. Place + upgrade only (no sell, no move), paid
## from the voyage money at 1.0x, crew hired at the normal wage. Every rule lives in SimWorld (`can_add_room`, `add_room`,
## `upgrade_room`, `hire_staff_mid_voyage`); this class only translates.
##
## `grid` IS the sim's grid while the refit lasts, with its enforce flags switched on and `grid.money` mirroring the voyage
## money, so the build bar's affordability and the popover's upgrade check use the refit rules too. `close()` restores them.

var world: SimWorld = null
var stop_name: String = ""
var _flags: Array[bool] = []


func _init(w: SimWorld) -> void:
	super(w.level, w.level.campaign_index)
	world = w
	stop_name = w.port_stop.stop_name
	layout = w.grid.layout
	grid = w.grid
	hull = w.grid.hull
	preset_staff = {}
	_flags = [grid.enforce_money, grid.enforce_unlock, grid.enforce_utilities]
	grid.enforce_money = true
	grid.enforce_unlock = true
	grid.enforce_utilities = true
	world.money_changed.connect(_on_money)
	sync()


## Gives the grid back to the sim exactly as it was.
func close() -> void:
	if world == null:
		return
	if world.money_changed.is_connected(_on_money):
		world.money_changed.disconnect(_on_money)
	grid.enforce_money = _flags[0]
	grid.enforce_unlock = _flags[1]
	grid.enforce_utilities = _flags[2]
	grid.money = 1 << 30
	world = null


func is_refit() -> bool:
	return true


func _on_money(_m: int, _d: int, _r: StringName) -> void:
	sync()


## Mirrors the voyage money into `budget` and the crew into `hired`; tells the UI.
func sync() -> void:
	if world == null:
		return
	grid.money = world.money
	var counts: Dictionary = {}
	for s in world.staff:
		counts[s.role] = int(counts.get(s.role, 0)) + 1
	hired = counts
	changed.emit()


# --- rooms -------------------------------------------------------------------------------------
func can_place(room_id: StringName, deck: int, x: int, _ignore_uid: int = -1) -> Dictionary:
	return world.can_add_room(room_id, deck, x)


func place(room_id: StringName, deck: int, x: int) -> PlacedRoom:
	var uid: int = world.add_room(room_id, deck, x)
	if uid < 0:
		return null
	sync()
	return layout.get_room(uid)


func move(_uid: int, _deck: int, _x: int) -> bool:
	return false


func sell(_uid: int) -> int:
	return -1


func upgrade(uid: int) -> bool:
	var ok: bool = world.upgrade_room(uid)
	if ok:
		sync()
	return ok


# --- crew --------------------------------------------------------------------------------------
func staff_total() -> int:
	return world.staff.size()


func staff_counts() -> Dictionary:
	return hired.duplicate()


func can_hire(role: StringName) -> Dictionary:
	var def: StaffDef = ContentStore.staff_role(role)
	if def == null:
		return {"ok": false, "reason": "Unknown role"}
	if not def.is_available(level.campaign_index, level.destination):
		if def.destination_lock != &"" and def.destination_lock != level.destination:
			return {"ok": false, "reason": "%s only" % _destination_name(def.destination_lock)}
		return {"ok": false, "reason": "Unlocks at level %d" % def.unlock_level}
	if world.staff.size() >= hull.max_staff:
		return {"ok": false, "reason": "Crew is full"}
	if world.mid_voyage_hire_cost(role) > world.money:
		return {"ok": false, "reason": "Not enough money"}
	return {"ok": true, "reason": ""}


func hire(role: StringName) -> bool:
	if not bool(can_hire(role)["ok"]):
		return false
	var ok: bool = world.hire_staff_mid_voyage(role)
	if ok:
		sync()
	return ok


func fire(_role: StringName) -> bool:
	return false


# --- info --------------------------------------------------------------------------------------
func validate() -> Dictionary:
	return {"errors": [], "warnings": []}
