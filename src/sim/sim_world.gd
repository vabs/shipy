class_name SimWorld
extends RefCounted
## Owns everything during a voyage. Pure RefCounted logic: no nodes, rendering, input or audio.
## See docs/SPEC.md §5 for the contract; extra public members are documented inline.

signal guest_boarded(guest_id: int)
signal guest_stormed_off(guest_id: int)
signal guest_patience_out(guest_id: int, room_uid: int)
signal guest_slipped(guest_id: int)
signal guest_got_sick(guest_id: int)
signal guest_cured(guest_id: int)
signal room_used(room_uid: int, guest_id: int, spend: int)
signal room_broken(room_uid: int)
signal room_repaired(room_uid: int)
signal mess_spawned(mess_id: int)
signal mess_cleaned(mess_id: int)
signal ghost_spawned(ghost_id: int)
signal ghost_banished(ghost_id: int)
signal event_started(event_id: StringName)
signal event_ended(event_id: StringName)
signal wave_started(wave_index: int, count: int)
signal money_changed(money: int, delta: int, reason: StringName)
signal mutiny_warning(seconds_left: float)
signal mutiny_cleared()
signal voyage_ended(result: Dictionary)

var level: LevelDef
var destination: DestinationDef
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var time: float = 0.0
var duration: float = 180.0
var finished: bool = false
## Final result dictionary once finished (same dict as emitted by voyage_ended).
var result: Dictionary = {}
var tick_count: int = 0

var guests: Array[Guest] = []
var rooms: Array[RoomRuntime] = []
var staff: Array[StaffMember] = []
var messes: Array[Mess] = []
var ghosts: Array[Ghost] = []
var grid: ShipGrid

# Subsystems (public so UI/tests can inspect them).
var economy: Economy
var events: EventDirector
var director: LevelDirector
var guest_sim: GuestSim
var room_sim: RoomSim
var problems: ProblemSim
var staff_sim: StaffSim
var transit: Transit

## Counters for balancing / results.
var metrics: Dictionary = {
	"messes": 0, "cleaned": 0, "breakdowns": 0, "repairs": 0, "sick": 0, "ghosts": 0,
	"banished": 0, "slips": 0, "storm_offs": 0, "patience_outs": 0, "queue_joins": 0,
	"queue_sum": 0, "queue_ticks": 0, "peak_queue": 0, "events": 0, "ghost_hits": 0,
	"player_clicks": 0, "player_repair_s": 0.0, "problem_sum": 0, "problem_samples": 0, "problem_peak": 0, "mess_spread": 0,
}

var money: int:
	get:
		return economy.money

## Seconds of the mutiny countdown remaining (30 when not in danger).
var mutiny_time_left: float:
	get:
		return director.mutiny_time_left

var mutiny_active: bool:
	get:
		return director.mutiny_active

var _room_counts: Dictionary = {}


func _init(lvl: LevelDef, layout: ShipLayout, staff_counts: Dictionary, seed_value: int, money_start: int) -> void:
	level = lvl
	duration = lvl.duration
	destination = ContentStore.destination(lvl.destination)
	rng.seed = seed_value
	grid = ShipGrid.new(layout, lvl)
	grid.enforce_money = false
	grid.enforce_unlock = false
	grid.enforce_utilities = false
	grid.rebuild_graph()
	economy = Economy.new(money_start)
	events = EventDirector.new()
	director = LevelDirector.new()
	guest_sim = GuestSim.new()
	room_sim = RoomSim.new()
	problems = ProblemSim.new()
	staff_sim = StaffSim.new()
	transit = Transit.new()
	room_sim.setup(self)
	rooms = room_sim.rooms
	for r in rooms:
		_room_counts[r.def.id] = int(_room_counts.get(r.def.id, 0)) + 1
		economy.upkeep_per_minute += r.def.upkeep
	events.setup(self)
	guest_sim.setup(self)
	problems.setup(self)
	staff_sim.setup(self, staff_counts)
	director.setup(self)
	var wages: int = 0
	for role in staff_counts:
		var sd: StaffDef = ContentStore.staff_role(StringName(role))
		if sd != null:
			wages += sd.wage * int(staff_counts[role])
	# Informational: wages were paid in port out of the budget (not part of voyage profit).
	economy.ledger[&"wages"] = wages


## Advances the simulation by `dt` seconds (always SimConst.TICK in practice).
func tick(dt: float) -> void:
	if finished:
		return
	tick_count += 1
	for g in guests:
		g.prev_x = g.x
		g.prev_deck_f = g.deck_f
	for s in staff:
		s.snapshot()
	for gh in ghosts:
		gh.prev_x = gh.x
		gh.prev_deck_f = gh.deck_f
	time += dt
	director.tick(self, dt)
	events.tick(self, dt)
	room_sim.tick(self, dt)
	guest_sim.tick(self, dt)
	problems.tick(self, dt)
	staff_sim.tick(self, dt)
	transit.tick()
	var charged: int = economy.tick_upkeep(dt)
	if charged > 0:
		money_changed.emit(economy.money, -charged, &"upkeep")
	if tick_count % 5 == 0:
		var q: int = room_sim.total_queue()
		metrics["queue_sum"] += q
		metrics["queue_ticks"] += 1
		if q > int(metrics["peak_queue"]):
			metrics["peak_queue"] = q
	if tick_count % 10 == 0:
		var open: int = messes.size() + ghosts.size() + room_sim.broken_total()
		metrics["problem_sum"] += open
		metrics["problem_samples"] += 1
		if open > int(metrics["problem_peak"]):
			metrics["problem_peak"] = open
	director.post_tick(self, dt)


# ---------------------------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------------------------
func rating() -> float:
	return director.rating()


func guest_by_id(id: int) -> Guest:
	var i: int = id - 1
	if i >= 0 and i < guests.size() and guests[i].id == id:
		return guests[i]
	return null


func room_by_uid(uid: int) -> RoomRuntime:
	return room_sim.room(uid)


func staff_by_id(id: int) -> StaffMember:
	return staff_sim.staff_by_id(self, id)


func mess_by_id(id: int) -> Mess:
	for m in messes:
		if m.id == id:
			return m
	return null


func ghost_by_id(id: int) -> Ghost:
	for gh in ghosts:
		if gh.id == id:
			return gh
	return null


func has_room_type(room_id: StringName) -> bool:
	return int(_room_counts.get(room_id, 0)) > 0


## Which slot of its room a using guest occupies (stable while using); -1 if not using.
func slot_index_of(guest_id: int) -> int:
	var g: Guest = guest_by_id(guest_id)
	if g == null or g.mode != Guest.USE:
		return -1
	return g.slot


## Topmost thing near the logical point (deck, x): {kind: "mess"|"room"|"staff"|"guest"|"ghost"|"", id}.
## Priority: ghost, mess, staff, guest, room.
func pick_at(deck: int, x: float) -> Dictionary:
	for gh in ghosts:
		if gh.deck == deck and absf(gh.x - x) <= 0.9:
			return {"kind": "ghost", "id": gh.id}
	for m in messes:
		if m.deck == deck and absf(m.x - x) <= 0.8:
			return {"kind": "mess", "id": m.id}
	for s in staff:
		if int(round(s.deck_f)) == deck and absf(s.x - x) <= 0.6:
			return {"kind": "staff", "id": s.id}
	var best_g: Guest = null
	var best_d: float = 0.55
	for g in guests:
		if g.mode == Guest.GONE or g.mode == Guest.USE or int(round(g.deck_f)) != deck:
			continue
		var d: float = absf(g.x - x)
		if d <= best_d:
			best_d = d
			best_g = g
	if best_g != null:
		return {"kind": "guest", "id": best_g.id}
	var cell: int = int(floor(x))
	for r in rooms:
		if r.def.is_transport() or r.def.is_utility():
			continue
		if r.deck == deck and cell >= r.x and cell < r.x + r.width:
			return {"kind": "room", "id": r.uid}
	return {"kind": "", "id": -1}


func active_events() -> Array[Dictionary]:
	return events.active_list()


func stats() -> Dictionary:
	var on_board: int = 0
	for g in guests:
		if g.mode != Guest.GONE and g.mode != Guest.STORM_OFF:
			on_board += 1
	var broken: int = 0
	for r in rooms:
		if r.broken:
			broken += 1
	return {
		"rating": director.rating(),
		"money": economy.money,
		"guests_on_board": on_board,
		"guests_total": guests.size(),
		"lost": director.lost_count(self),
		"served": director.served,
		"problems": messes.size() + broken + ghosts.size() + problems.sick_count(self),
	}


func ledger() -> Dictionary:
	return economy.ledger.duplicate()


# ---------------------------------------------------------------------------------------------
# Money helpers (emit money_changed)
# ---------------------------------------------------------------------------------------------
func economy_earn(category: StringName, amount: int, reason: StringName) -> void:
	var d: int = economy.earn(category, amount)
	money_changed.emit(economy.money, d, reason)


func economy_spend(category: StringName, amount: int, reason: StringName) -> void:
	var d: int = economy.spend(category, amount)
	money_changed.emit(economy.money, d, reason)


# ---------------------------------------------------------------------------------------------
# Player actions
# ---------------------------------------------------------------------------------------------
func player_click_mess(mess_id: int) -> void:
	var m: Mess = mess_by_id(mess_id)
	if m == null or finished:
		return
	metrics["player_clicks"] += 1
	problems.add_clean(self, m, SimConst.PLAYER_MESS_CLICK)


## Press-and-hold on a broken room: 0.4 progress per second held.
func player_hold_repair(room_uid: int, dt: float) -> void:
	var r: RoomRuntime = room_sim.room(room_uid)
	if r == null or not r.broken or finished:
		return
	metrics["player_repair_s"] += dt
	room_sim.add_repair(self, r, SimConst.PLAYER_REPAIR_RATE * dt)


func player_banish_ghost(ghost_id: int) -> void:
	var gh: Ghost = ghost_by_id(ghost_id)
	if gh == null or finished:
		return
	metrics["player_clicks"] += 1
	problems.banish_ghost(self, gh)


## Sends crew member `staff_id` to a problem. kind: &"mess" or &"repair" (&"breakdown" accepted).
func assign_staff(staff_id: int, kind: StringName, target_id: int) -> bool:
	if finished:
		return false
	return staff_sim.player_assign(self, staff_id, kind, target_id)


## Hires a crew member mid-voyage for 1.5x wage. False if the crew is full or money is short.
func hire_staff_mid_voyage(role: StringName) -> bool:
	if finished:
		return false
	var def: StaffDef = ContentStore.staff_role(role)
	if def == null or staff.size() >= grid.hull.max_staff:
		return false
	var cost: int = int(round(float(def.wage) * SimConst.MID_VOYAGE_HIRE_MULT))
	if economy.money < cost:
		return false
	economy_spend(&"hires", cost, &"hire")
	staff_sim.add_staff(self, role)
	return true


## Cost the player would pay for a mid-voyage hire of `role`.
func mid_voyage_hire_cost(role: StringName) -> int:
	var def: StaffDef = ContentStore.staff_role(role)
	if def == null:
		return 0
	return int(round(float(def.wage) * SimConst.MID_VOYAGE_HIRE_MULT))


## Fires an event immediately (tutorial / tests / debug).
func force_event(event_id: StringName) -> void:
	events.start_event(self, event_id)
