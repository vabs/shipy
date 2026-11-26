class_name AutoBuilder
extends RefCounted
## Builds a sensible ship for a level within its budget: cabins for everyone near the gangway, stairs
## linking every deck, food / toilets / fun scaled to the guest count, medbay when unlocked, top-deck
## pool and chairs, generators and tanks when power or water run short, and a small crew.
## Used by tests, the `--autobuild` dev flag and balance runs. The result is always a valid layout
## (every deck with rooms is connected to the gangway deck).
##
## opts (all optional):
##   budget_frac: float  fraction of the budget to spend (default 1.0)
##   style: &"sensible" | &"poor"   "poor" scatters rooms far apart and skimps on facilities
##   crew: bool          hire crew (default true)
##   budget: int         override the port budget before building (e.g. 99999 to measure a plan's cost)
##   upgrades: bool      spend leftovers on tier upgrades (default true)
##   new_roles: bool     hire the specialist crew (warden, chef, medic, entertainer) when sensible (default true)
## Levels with staff fatigue also get one crew quarters (unlocked from level 7).

const FUN_BASE: Array[StringName] = [&"bar", &"cinema", &"gym", &"arcade", &"casino", &"ice_rink", &"pool"]
## One food / toilet / fun room per this many guests (a planned, not luxurious, ship).
const GUESTS_PER_BUFFET: float = 40.0
const GUESTS_PER_TOILET: float = 40.0
const GUESTS_PER_FUN: float = 32.0
## Crew is deliberately small: one janitor per this many guests, one mechanic from MECHANIC_FROM guests.
const GUESTS_PER_JANITOR: float = 36.0
const MECHANIC_FROM: int = 14
const SECOND_MECHANIC_FROM: int = 48
## Specialist crew is hired from this many guests on (one each, after the janitors / mechanics, if the crew has
## room and the money is left over). The warden is hired whenever the destination has ghosts.
const CHEF_FROM: int = 30
const MEDIC_FROM: int = 30
const ENTERTAINER_FROM: int = 36
## Money that must stay unspent after a specialist hire (keeps upgrades / mid-voyage hires possible).
const SPECIALIST_MONEY_MARGIN: int = 150


## Creates a PortState for the level and fills it.
static func build(level: LevelDef, campaign_index: int = -1, opts: Dictionary = {}) -> PortState:
	var port := PortState.new(level, campaign_index)
	apply(port, opts)
	return port


static func apply(port: PortState, opts: Dictionary = {}) -> void:
	var grid: ShipGrid = port.grid
	var level: LevelDef = port.level
	var hull: HullDef = port.hull
	if opts.has("budget"):
		port.budget = int(opts["budget"])
	var poor: bool = StringName(opts.get("style", &"sensible")) == &"poor"
	var frac: float = float(opts.get("budget_frac", 1.0))
	var hire_crew: bool = bool(opts.get("crew", true))
	var n_guests: int = level.total_guests()
	var top: int = hull.decks - 1
	var gw: int = hull.gangway_deck
	var sx: int = hull.width / 2 - 1
	var dest: DestinationDef = ContentStore.destination(level.destination)
	var avail: Dictionary = {}
	for r in ContentStore.rooms_available(grid.campaign_index, level.destination):
		avail[r.id] = r
	var budget: int = int(float(port.budget) * frac)
	var spent: int = 0
	var original_money: int = port.budget
	## Money that must stay untouched (budget_frac < 1).
	var floor_money: int = original_money - budget

	# --- crew plan (reserved first so the ship is never left without any) -----------------
	var janitors: int = 1 + int(float(n_guests) / GUESTS_PER_JANITOR)
	var mechanics: int = 0
	if n_guests >= MECHANIC_FROM:
		mechanics = 1
	if n_guests >= SECOND_MECHANIC_FROM:
		mechanics = 2
	if level.tutorial:
		mechanics = 0  # the tutorial teaches the player to repair rooms themselves
	if poor:
		janitors = 1
		mechanics = 1 if n_guests >= MECHANIC_FROM else 0
	var crew_room: int = hull.max_staff - port.staff_total()
	janitors = mini(janitors, maxi(crew_room, 0))
	mechanics = mini(mechanics, maxi(crew_room - janitors, 0))
	var janitor_def: StaffDef = ContentStore.staff_role(&"janitor")
	var mechanic_def: StaffDef = ContentStore.staff_role(&"mechanic")
	var reserve: int = 0
	if hire_crew:
		reserve = janitor_def.wage + (mechanic_def.wage if mechanics > 0 else 0)

	# --- plan ------------------------------------------------------------------------------
	var plan: Array[StringName] = []
	var existing: Dictionary = {}
	for pr in grid.layout.rooms:
		existing[pr.def.id] = int(existing.get(pr.def.id, 0)) + 1
	var beds_have: int = 0
	for pr in grid.layout.rooms:
		if pr.def.id == &"cabin":
			beds_have += pr.capacity()
	var cabin_def: RoomDef = ContentStore.room(&"cabin")
	# Excursion guests give their beds back at a port stop, so cabins are sized for the most people aboard at once.
	var cabins_needed: int = maxi(int(ceil(float(level.peak_guests() - beds_have) / float(cabin_def.capacity))), 0)
	# Couples and families want one cabin together: a spare cabin per three groups keeps them from splitting up.
	var group_info: Dictionary = GuestGroup.summary(level)
	if int(group_info["groups"]) > 0:
		cabins_needed += int(ceil(float(group_info["groups"]) / 3.0))

	# Stairs: one per adjacent deck pair that is not already linked.
	var stair_cost: int = _stairs_needed(grid, hull) * int(ContentStore.room(&"stairs").cost)
	var avail_budget: int = budget - reserve - stair_cost

	var tally: Dictionary = {}  # id -> planned count
	# Planning state shared with _try_add (cost so far, utilities used, limit).
	var st: Dictionary = {
		"cost": 0, "power": grid.power_used(), "water": grid.water_used(), "limit": avail_budget,
	}
	var try_add: Callable = func(id: StringName) -> bool:
		return _try_add(grid, avail, tally, plan, st, id)

	# Core: cabins, one buffet, one toilet block, one fun room.
	for i in cabins_needed:
		try_add.call(&"cabin")
	try_add.call(&"buffet")
	try_add.call(&"toilets")
	var fun_picks: Array[StringName] = _pick_fun_rooms(level, avail, dest, n_guests, poor)
	var fun_i: int = 0
	if fun_i < fun_picks.size():
		if try_add.call(fun_picks[fun_i]):
			pass
		fun_i += 1
	# Extras, in priority order.
	var want_buffets: int = maxi(int(ceil(float(n_guests) / GUESTS_PER_BUFFET)), 1)
	var want_toilets: int = maxi(int(ceil(float(n_guests) / GUESTS_PER_TOILET)), 1)
	var want_fun: int = 1 + int(ceil(float(n_guests) / GUESTS_PER_FUN)) + (1 if n_guests >= 44 else 0)
	if poor:
		want_buffets = 1
		want_toilets = 1
		want_fun = 2
	var extras: Array[StringName] = []
	# Kids on the manifest: a kids' club (one per ~8 kids) before the grown-ups' extras.
	if avail.has(&"kids_club") and int(group_info["kids"]) > 0 and not poor:
		for i in int(ceil(float(group_info["kids"]) / 8.0)):
			extras.append(&"kids_club")
	if fun_i < fun_picks.size():
		extras.append(fun_picks[fun_i])
		fun_i += 1
	if want_toilets >= 2:
		extras.append(&"toilets")
	if want_buffets >= 2 and not (avail.has(&"restaurant") and n_guests >= 30 and not poor):
		extras.append(&"buffet")
	if avail.has(&"medbay") and n_guests >= 14 and not poor:
		extras.append(&"medbay")
	if avail.has(&"crew_quarters") and level.staff_fatigue and hire_crew and not poor:
		extras.append(&"crew_quarters")
	if avail.has(&"restaurant") and n_guests >= 30 and want_buffets >= 2 and not poor:
		extras.append(&"restaurant")
		want_buffets -= 1
	while fun_i < mini(want_fun, fun_picks.size()):
		extras.append(fun_picks[fun_i])
		fun_i += 1
	for i in range(3, want_toilets + 1):
		extras.append(&"toilets")
	for i in range(3, want_buffets + 1):
		extras.append(&"buffet")
	for id in extras:
		try_add.call(id)

	# --- place ----------------------------------------------------------------------------
	_ensure_connected(grid, hull, sx)
	# Generators / tanks first so utilities allow everything else.
	for id in [&"generator", &"water_tank"]:
		for i in int(tally.get(id, 0)):
			_place_far(grid, id)
	var hub_deck: int = mini(gw + 1, hull.decks - 2)
	if hub_deck < 0:
		hub_deck = gw
	var g: WalkGraph = grid.graph
	var gangway_node: int = g.node(gw, 0)
	var hub_node: int = g.node(hub_deck, sx)
	# Elevator on big ships when available (rooms are placed around it afterwards).
	if avail.has(&"elevator") and hull.decks >= 6 and not poor and grid.money - floor_money - 400 > reserve:
		for col in [sx + 2, sx - 2, sx + 3, sx + 4]:
			if grid.place(&"elevator", 0, col) != null:
				break
	var interior_decks: Array[int] = []
	for d in range(0, top):
		interior_decks.append(d)
	var order: Array[StringName] = []
	for id in [&"cabin", &"toilets", &"buffet", &"restaurant", &"medbay", &"crew_quarters"]:
		for i in int(tally.get(id, 0)):
			order.append(id)
	for id in plan:
		if not order.has(id) or tally.get(id, 0) == 0:
			pass
	# Fun rooms in plan order.
	var fun_ids: Array[StringName] = []
	for id in plan:
		var def: RoomDef = ContentStore.room(id)
		if def.category == &"fun" or id == &"sauna" or id == &"deck_chairs":
			fun_ids.append(id)
	for id in fun_ids:
		order.append(id)
	var cold_top: bool = dest != null and dest.top_deck_satisfaction_drain > 0.0
	for id in order:
		var def: RoomDef = ContentStore.room(id)
		var anchor: int = hub_node
		var decks: Array[int] = interior_decks
		if id == &"cabin":
			# Cabins cluster around the stairs on the gangway deck and the deck below, so rest trips
			# are short and the guests' walk to services stays compact.
			anchor = g.node(gw, sx)
			if not poor and _place_near(grid, id, [gw, 0] as Array[int], anchor) != null:
				continue
		if def.placement == &"top_deck":
			decks = [top]
			anchor = g.node(top, sx)
		if poor:
			_place_scattered(grid, id, decks, anchor)
		else:
			_place_near(grid, id, decks, anchor)
	# Any top-deck rooms planned (pool, chairs) live in fun_ids already via placement.
	if not cold_top and not poor and level.tutorial and avail.has(&"deck_chairs") \
			and grid.money - floor_money >= reserve + 150 + 100 and int(tally.get(&"deck_chairs", 0)) == 0:
		_place_near(grid, &"deck_chairs", [top], g.node(top, sx))

	# --- crew ----------------------------------------------------------------------------
	if hire_crew:
		for i in janitors:
			port.hire(&"janitor")
		for i in mechanics:
			port.hire(&"mechanic")
		if bool(opts.get("new_roles", true)) and not poor:
			_hire_specialists(port, dest, n_guests, floor_money)
	# --- upgrades with leftovers ----------------------------------------------------------
	if not poor and bool(opts.get("upgrades", true)):
		var spare: int = port.budget - floor_money
		var prio: Array[StringName] = [&"buffet", &"toilets", &"bar", &"cinema", &"restaurant"]
		for id in prio:
			for pr in grid.layout.rooms_of(id):
				if grid.can_upgrade(pr.uid)["ok"] and grid.upgrade_cost(pr.uid) <= spare - 100:
					var c: int = grid.upgrade_cost(pr.uid)
					if grid.upgrade(pr.uid):
						spare -= c
	# --- final safety: connectivity -------------------------------------------------------
	_ensure_connected(grid, hull, sx)
	port.changed.emit()


## Hires the specialist crew the level can use, one of each, while the crew has room and the money lasts.
static func _hire_specialists(port: PortState, dest: DestinationDef, n_guests: int, floor_money: int) -> void:
	var wants: Array[StringName] = []
	if dest != null and dest.ghost_interval.y > 0.0:
		wants.append(&"warden")
	if n_guests >= CHEF_FROM and (port.layout.count_of(&"buffet") + port.layout.count_of(&"restaurant")) > 0:
		wants.append(&"chef")
	if n_guests >= MEDIC_FROM:
		wants.append(&"medic")
	if n_guests >= ENTERTAINER_FROM:
		wants.append(&"entertainer")
	for role in wants:
		var def: StaffDef = ContentStore.staff_role(role)
		if def == null or port.budget - floor_money < def.wage + SPECIALIST_MONEY_MARGIN:
			continue
		port.hire(role)


## Adds `id` to the plan if it (plus any generators/tanks it forces) fits the budget.
static func _try_add(grid: ShipGrid, avail: Dictionary, tally: Dictionary, plan: Array[StringName], st: Dictionary, id: StringName) -> bool:
	if not avail.has(id):
		return false
	var def: RoomDef = avail[id]
	var np: int = int(st["power"]) + maxi(def.power, 0)
	var nw: int = int(st["water"]) + maxi(def.water, 0)
	var gens_have: int = int(tally.get(&"generator", 0))
	var tanks_have: int = int(tally.get(&"water_tank", 0))
	var extra_gen: int = maxi(int(ceil(float(np - (grid.power_capacity() + 8 * gens_have)) / 8.0)), 0)
	var extra_tank: int = maxi(int(ceil(float(nw - (grid.water_capacity() + 8 * tanks_have)) / 8.0)), 0)
	var add_cost: int = def.cost
	if extra_gen > 0:
		if not avail.has(&"generator"):
			return false
		add_cost += extra_gen * int(ContentStore.room(&"generator").cost)
	if extra_tank > 0:
		if not avail.has(&"water_tank"):
			return false
		add_cost += extra_tank * int(ContentStore.room(&"water_tank").cost)
	if int(st["cost"]) + add_cost > int(st["limit"]):
		return false
	st["cost"] = int(st["cost"]) + add_cost
	st["power"] = np
	st["water"] = nw
	tally[id] = int(tally.get(id, 0)) + 1
	if extra_gen > 0:
		tally[&"generator"] = gens_have + extra_gen
	if extra_tank > 0:
		tally[&"water_tank"] = tanks_have + extra_tank
	plan.append(id)
	return true


# ---------------------------------------------------------------------------------------------
static func _pick_fun_rooms(level: LevelDef, avail: Dictionary, dest: DestinationDef, n_guests: int, poor: bool) -> Array[StringName]:
	var out: Array[StringName] = []
	var counts: Dictionary = {}
	var cold_top: bool = dest != null and dest.top_deck_satisfaction_drain > 0.0
	var archs: Array[ArchetypeDef] = ContentStore.all_archetypes()
	var wsum: float = 0.0
	for a in archs:
		wsum += float(level.archetype_weights.get(a.id, 0.0))
	wsum = maxf(wsum, 0.001)
	var picks: int = 7
	for i in picks:
		var best: StringName = &""
		var best_v: float = 0.0
		for id in FUN_BASE:
			if not avail.has(id):
				continue
			var def: RoomDef = avail[id]
			if id == &"pool" and cold_top:
				continue
			if id == &"deck_chairs":
				continue  # chairs are added separately when affordable
			var aud: float = 0.0
			for a in archs:
				var wt: float = float(level.archetype_weights.get(a.id, 0.0)) / wsum
				aud += wt * (1.0 if a.likes(def) else 0.18)
			var tp: float = float(def.capacity) / maxf(def.service_time, 1.0)
			var v: float = (0.1 + aud) * tp / (1.0 + 1.3 * float(counts.get(id, 0)))
			v /= sqrt(float(def.cost) / 300.0)
			if id == &"pool" and dest != null:
				v *= dest.pool_appeal_mult
			if dest != null and id == dest.new_room:
				v *= 2.2
			if poor:
				v = -v
			if best == &"" or v > best_v:
				best_v = v
				best = id
		if best == &"":
			break
		counts[best] = int(counts.get(best, 0)) + 1
		out.append(best)
	return out


static func _stairs_needed(grid: ShipGrid, hull: HullDef) -> int:
	var linked: Dictionary = {}
	for r in grid.layout.rooms:
		if r.is_stairs():
			linked[r.deck] = true
		elif r.is_elevator():
			return 0
	var n: int = 0
	for d in range(0, hull.decks - 1):
		if not linked.has(d):
			n += 1
	return n


## Adds stairs until every deck is reachable from the gangway deck.
static func _ensure_connected(grid: ShipGrid, hull: HullDef, sx: int) -> void:
	for attempt in hull.decks * 2:
		grid.rebuild_graph()
		var reach: Array[int] = grid.graph.reachable_decks(hull.gangway_deck)
		var missing: int = -1
		for d in hull.decks:
			if not reach.has(d):
				missing = d
				break
		if missing < 0:
			return
		# Link `missing` to its neighbour that is already reachable.
		var lower: int = missing - 1 if reach.has(missing - 1) else missing
		var upper_ok: bool = reach.has(missing + 1)
		if reach.has(missing - 1):
			lower = missing - 1
		elif upper_ok:
			lower = missing
		else:
			lower = missing - 1 if missing > 0 else missing
		var placed: bool = false
		var base: int = sx + (lower % 2)
		for off in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6]:
			var col: int = base + int(off)
			if col < 0 or col >= hull.width:
				continue
			var was: bool = grid.enforce_money
			grid.enforce_money = false
			var r: PlacedRoom = grid.place(&"stairs", lower, col)
			grid.enforce_money = was
			if r != null:
				grid.money -= int(r.def.cost)
				placed = true
				break
		if not placed:
			return


static func _place_near(grid: ShipGrid, id: StringName, decks: Array[int], anchor: int) -> PlacedRoom:
	var def: RoomDef = ContentStore.room(id)
	var g: WalkGraph = grid.graph
	var best_d: int = -1
	var best_x: int = -1
	var best_c: float = 1.0e12
	var width: int = grid.hull.width
	for d in decks:
		for x in range(0, width - def.width + 1):
			if not grid.can_place(id, d, x)["ok"]:
				continue
			var c: float = g.cost(anchor, g.node(d, x + def.width / 2)) + float(x) * 0.001
			if c < best_c:
				best_c = c
				best_d = d
				best_x = x
	if best_d < 0:
		return null
	return grid.place(id, best_d, best_x)


## "Poor" style: farthest legal spot from the anchor (rooms scattered across the ship).
static func _place_scattered(grid: ShipGrid, id: StringName, decks: Array[int], anchor: int) -> PlacedRoom:
	var def: RoomDef = ContentStore.room(id)
	var g: WalkGraph = grid.graph
	var best_d: int = -1
	var best_x: int = -1
	var best_c: float = -1.0
	var width: int = grid.hull.width
	for d in decks:
		for x in range(0, width - def.width + 1):
			if not grid.can_place(id, d, x)["ok"]:
				continue
			var c: float = g.cost(anchor, g.node(d, x + def.width / 2))
			if id == &"cabin":
				c = -c
			if c > best_c:
				best_c = c
				best_d = d
				best_x = x
	if best_d < 0:
		return null
	return grid.place(id, best_d, best_x)


## Utility buildings go to the far end of the lowest decks where they never block traffic.
static func _place_far(grid: ShipGrid, id: StringName) -> PlacedRoom:
	var def: RoomDef = ContentStore.room(id)
	var top: int = grid.hull.decks - 1
	for d in range(0, top):
		for x in range(grid.hull.width - def.width, -1, -1):
			if grid.can_place(id, d, x)["ok"]:
				return grid.place(id, d, x)
	return null
