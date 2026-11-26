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
## A crew member's energy fell below the tired threshold / they woke up fully rested (fatigue levels only).
signal staff_tired(staff_id: int)
signal staff_rested(staff_id: int)
## A VIP came aboard / gave their verdict (kind: critic | celebrity | inspector, grade: great | ok | bad). Each fires once per VIP.
signal vip_boarded(guest_id: int, kind: StringName)
signal vip_verdict(guest_id: int, kind: StringName, grade: StringName)
## A guest turned seasick in a storm (docs/SPEC.md §13.7). Curing fires `guest_cured` as for any sick guest.
signal guest_got_seasick(guest_id: int)
## Mid-voyage port stop (docs/SPEC.md §13.8): the ship starts docking at `name` / the excursion guests are ashore and the sim holds still for
## the Quick refit (see `refit_manual`) / the player cast off and the boarding wave comes aboard.
signal port_stop_started(name: String)
signal port_stop_ready()
signal port_stop_ended()
## A room was built / upgraded in the Quick refit.
signal room_added(room_uid: int)
signal room_upgraded(room_uid: int)
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
## 0..1: how stormy it is right now (eases in and out over SimConst.STORM_EASE at both ends of a storm event). Renderers scale the
## sky, rain, waves and the ship's roll with it.
var weather_intensity: float = 0.0
## True when something outside the sim (the level screen) casts off at a port stop. False (default): the sim casts off by itself as
## soon as the excursion is over, so headless runs never wait for a player.
var refit_manual: bool = false

var guests: Array[Guest] = []
var rooms: Array[RoomRuntime] = []
var staff: Array[StaffMember] = []
var messes: Array[Mess] = []
var ghosts: Array[Ghost] = []
var grid: ShipGrid
## Couples and families that boarded so far (Guest.group_id is the 1-based index here).
var groups: Array[GuestGroup] = []

# Subsystems (public so UI/tests can inspect them).
var economy: Economy
var events: EventDirector
var director: LevelDirector
var guest_sim: GuestSim
var room_sim: RoomSim
var problems: ProblemSim
var staff_sim: StaffSim
var transit: Transit
## VIP guests: boarding, review rules, verdicts (docs/SPEC.md §13.5).
var vip_sim: VipSim
## Records the voyage for the results report / heatmap (SPEC §13.2). Read-only on the sim.
var telemetry: VoyageTelemetry
## The mid-voyage port stop of this level (docs/SPEC.md §13.8); `port_stop.configured` is false for levels without one.
var port_stop: PortStop

## Company perks applied to this voyage (Perks dictionary, see apply_perks) and the numbers they change.
var perks: Dictionary = {}
## Ticket price per boarding guest (level price x Marketing perk).
var ticket_price: int = 0

## Counters for balancing / results.
var metrics: Dictionary = {
	"messes": 0, "cleaned": 0, "breakdowns": 0, "repairs": 0, "sick": 0, "ghosts": 0,
	"banished": 0, "slips": 0, "storm_offs": 0, "patience_outs": 0, "queue_joins": 0,
	"queue_sum": 0, "queue_ticks": 0, "peak_queue": 0, "events": 0, "ghost_hits": 0,
	"player_clicks": 0, "player_repair_s": 0.0, "problem_sum": 0, "problem_samples": 0, "problem_peak": 0, "mess_spread": 0,
	"medic_cures": 0, "warden_banishes": 0, "rests": 0, "naps": 0,
	"vips": 0, "vip_great": 0, "vip_ok": 0, "vip_bad": 0, "inspector_issues": 0,
	"groups": 0, "groups_split": 0, "group_follows": 0, "group_storm_hits": 0, "kids": 0,
	"seasick": 0, "excursions": 0, "refit_rooms": 0, "refit_upgrades": 0,
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
## Walkers in the middle of a climb / lift ride when a refit rebuilt the walk graph: re-planned as soon as they step off (see _repath).
var _repath_later: Array[Walker] = []


func _init(lvl: LevelDef, layout: ShipLayout, staff_counts: Dictionary, seed_value: int, money_start: int) -> void:
	level = lvl
	duration = lvl.duration
	ticket_price = lvl.ticket_price
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
	vip_sim = VipSim.new()
	telemetry = VoyageTelemetry.new()
	port_stop = PortStop.new()
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
	telemetry.setup(self)
	port_stop.setup(self)
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
	if port_stop.phase == PortStop.READY:
		# Port stop: everybody is ashore, the Quick refit is open. The sim holds still until the player casts off.
		if refit_manual:
			return
		port_stop.cast_off(self)
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
	if port_stop.configured:
		port_stop.tick(self, dt)
	room_sim.tick(self, dt)
	guest_sim.tick(self, dt)
	if not vip_sim.members.is_empty():
		vip_sim.tick(self, dt)
	problems.tick(self, dt)
	staff_sim.tick(self, dt)
	transit.tick()
	if not _repath_later.is_empty():
		_replan_after_hops()
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
	telemetry.tick(self)
	director.post_tick(self, dt)


## Applies company perks (`{perk_id: level}`, see Perks) to this voyage. Call before the first tick; calling it
## again with another dictionary replaces the previous perks (nothing stacks). The budget perk is not here: it is
## folded into the port budget by PortState.perks. Perks never touch the rng, so a run without perks is unchanged.
##   tickets      -> ticket_price           service     -> guest queue patience
##   maintenance  -> room health            crew        -> StaffMember speed / work time
func apply_perks(p: Dictionary) -> void:
	perks = Perks.normalized(p)
	ticket_price = int(round(float(level.ticket_price) * Perks.ticket_mult(perks)))
	guest_sim.patience_perk_mult = Perks.patience_mult(perks)
	room_sim.set_health_perk_mult(Perks.health_mult(perks))
	staff_sim.set_crew_perk(self, Perks.crew_speed_mult(perks), Perks.crew_work_mult(perks))


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
		if g.is_aboard():
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


## Sends crew member `staff_id` somewhere. kind / target: &"mess" (janitor, mess id), &"repair" or &"breakdown" (mechanic,
## broken room uid), &"sick" (medic, guest id), &"ghost" (warden, ghost id), &"perform" (entertainer, service room uid, stays
## 20 s), &"station" (chef, food room uid), &"rest" (any crew, crew quarters uid). False for any invalid combination.
func assign_staff(staff_id: int, kind: StringName, target_id: int) -> bool:
	if finished:
		return false
	return staff_sim.player_assign(self, staff_id, kind, target_id)


## Hires a crew member mid-voyage for 1.5x wage. False if the role is unknown or not offered at this level
## (unlock level / destination), the crew is full or money is short.
func hire_staff_mid_voyage(role: StringName) -> bool:
	if finished:
		return false
	var def: StaffDef = ContentStore.staff_role(role)
	if def == null or staff.size() >= grid.hull.max_staff:
		return false
	if not def.is_available(level.campaign_index, level.destination):
		return false
	var cost: int = mid_voyage_hire_cost(role)
	if economy.money < cost:
		return false
	economy_spend(&"hires", cost, &"hire")
	if port_stop.can_refit():
		port_stop.refit_spent += cost
	staff_sim.add_staff(self, role)
	return true


## Cost the player would pay for a mid-voyage hire of `role`: 1.5x the wage at sea, the normal wage during the Quick refit at a port stop.
func mid_voyage_hire_cost(role: StringName) -> int:
	var def: StaffDef = ContentStore.staff_role(role)
	if def == null:
		return 0
	var mult: float = SimConst.REFIT_HIRE_MULT if port_stop.can_refit() else SimConst.MID_VOYAGE_HIRE_MULT
	return int(round(float(def.wage) * mult))


## Fires an event immediately (tutorial / tests / debug).
func force_event(event_id: StringName) -> void:
	events.start_event(self, event_id)


# ---------------------------------------------------------------------------------------------
# Mid-voyage port stop: Quick refit (docs/SPEC.md §13.8)
# ---------------------------------------------------------------------------------------------
## True while the Quick refit is open (the ship is alongside, the excursion is over and the player has not cast off).
func refit_open() -> bool:
	return not finished and port_stop.can_refit()


## Can `def_id` be built at (deck, x)? {ok, reason}: only during the refit, with the voyage money (1.0x cost), the level's unlocks,
## free power / water, no overlap with any room and a connection to the gangway deck (see ShipGrid.can_refit_place).
func can_add_room(def_id: StringName, deck: int, x: int) -> Dictionary:
	if not refit_open():
		return {"ok": false, "reason": "Not at a port"}
	return grid.can_refit_place(def_id, deck, x, economy.money)


## Builds `def_id` at (deck, x) in the Quick refit and returns the new room's uid (-1 if `can_add_room` says no). Rebuilds the walk
## graph for stairs / elevators and re-plans every walking guest and crew member's route.
func add_room(def_id: StringName, deck: int, x: int) -> int:
	if not bool(can_add_room(def_id, deck, x)["ok"]):
		return -1
	var def: RoomDef = ContentStore.room(def_id)
	economy_spend(&"refit", def.cost, &"refit")
	port_stop.refit_spent += def.cost
	port_stop.refit_rooms += 1
	var placed: PlacedRoom = grid.layout.add_room(def, deck, x, 0, false)
	if def.is_transport():
		grid.rebuild_graph()   # new graph = fresh distance maps and route caches
		_repath_walkers()
	var r: RoomRuntime = room_sim.add_runtime(self, placed)
	_room_counts[def.id] = int(_room_counts.get(def.id, 0)) + 1
	economy.upkeep_per_minute += def.upkeep
	guest_sim.on_room_added(self, r)
	telemetry.on_room_added(self, r)
	metrics["refit_rooms"] += 1
	room_added.emit(r.uid)
	return r.uid


## Can the room `uid` be upgraded one tier right now? {ok, reason} (during the refit, voyage money, tier unlock levels).
func can_upgrade_room(uid: int) -> Dictionary:
	if not refit_open():
		return {"ok": false, "reason": "Not at a port"}
	return grid.can_refit_upgrade(uid, economy.money)


## Upgrades the room `uid` one tier in the Quick refit (1.0x cost). False if `can_upgrade_room` says no.
func upgrade_room(uid: int) -> bool:
	if not bool(can_upgrade_room(uid)["ok"]):
		return false
	var placed: PlacedRoom = grid.layout.get_room(uid)
	var r: RoomRuntime = room_sim.room(uid)
	if placed == null or r == null:
		return false
	var cost: int = placed.def.upgrade_cost(placed.tier)
	economy_spend(&"refit", cost, &"refit")
	port_stop.refit_spent += cost
	port_stop.refit_upgrades += 1
	placed.tier += 1
	room_sim.upgrade_runtime(self, r, placed.tier)
	metrics["refit_upgrades"] += 1
	room_upgraded.emit(uid)
	return true


## "Cast off": ends the Quick refit, `port_stop.board` guests board as a wave and the voyage goes on. False when no refit is open.
func cast_off() -> bool:
	if finished:
		return false
	return port_stop.cast_off(self)


## Re-plans the route of every walking guest / crew member to the same destination on the (rebuilt) walk graph; anybody in the middle of
## a climb or an elevator ride finishes the hop first and is re-planned right after it (`_replan_after_hops`).
func _repath_walkers() -> void:
	for g in guests:
		if g.mode != Guest.GONE:
			_repath(g)
	for s in staff:
		_repath(s)


func _repath(wk: Walker) -> void:
	var n: int = wk.wp_deck.size()
	if n == 0 or not wk.has_route():
		return
	if wk.vertical_busy():
		if not _repath_later.has(wk):
			_repath_later.append(wk)
		return
	wk.plan_route(grid, wk.wp_deck[n - 1], wk.wp_x[n - 1])


## Walkers that were mid-hop at the refit: once they stand on a deck again they take the route the new graph gives them (in the order
## they were queued, so the outcome stays deterministic).
func _replan_after_hops() -> void:
	var still: Array[Walker] = []
	for wk in _repath_later:
		if not wk.has_route() or (wk is Guest and (wk as Guest).mode == Guest.GONE):
			continue
		if wk.vertical_busy():
			still.append(wk)
		else:
			_repath(wk)
	_repath_later = still
