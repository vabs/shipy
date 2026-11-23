extends SceneTree
## Headless unit tests for the simulation. Run:
##   godot --headless --path . --script res://tests/run_tests.gd
## Prints ALL TESTS PASSED (exit 0) or the failures (exit 1).

var _passed: int = 0
var _failed: int = 0
var _section_name: String = ""
var _failures: PackedStringArray = []
# Signal capture helpers (lambdas cannot mutate captured locals).
var _sig: Dictionary = {}


func _init() -> void:
	var t0: int = Time.get_ticks_msec()
	ContentStore.reload()
	var suites: Array[Callable] = [
		_t_content, _t_grid_placement, _t_grid_economy, _t_validation, _t_pathing, _t_elevator,
		_t_port, _t_guest_basics, _t_queue_patience, _t_slots_and_interp, _t_satisfaction,
		_t_messes, _t_breakdowns, _t_staff, _t_sickness, _t_ghosts, _t_economy, _t_events,
		_t_stars, _t_mutiny, _t_determinism, _t_autobuilder, _t_autoplayer, _t_pick_and_api,
		_t_human_player, _t_pressure, _t_no_stuck, _t_performance,
	]
	for s in suites:
		s.call()
	print("")
	print("%d checks passed, %d failed (%.1f s)" % [_passed, _failed, float(Time.get_ticks_msec() - t0) / 1000.0])
	if _failed == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		quit(1)


# ---------------------------------------------------------------------------------------------
# Tiny harness
# ---------------------------------------------------------------------------------------------
func _section(name: String) -> void:
	_section_name = name
	print("== ", name)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append("[%s] %s" % [_section_name, msg])
		print("  FAIL: ", msg)


func _eq(a: Variant, b: Variant, msg: String) -> void:
	_check(a == b, "%s (got %s, expected %s)" % [msg, str(a), str(b)])


func _near(a: float, b: float, tol: float, msg: String) -> void:
	_check(absf(a - b) <= tol, "%s (got %.3f, expected %.3f +-%.3f)" % [msg, a, b, tol])


## Level copy with no automatic waves/events, so tests control everything.
func _blank_level(level_id: StringName) -> LevelDef:
	var lvl: LevelDef = ContentStore.level(level_id).duplicate(true)
	lvl.waves = []
	lvl.scheduled_events = []
	lvl.random_event_interval = 0.0
	lvl.preset_rooms = []
	lvl.preset_staff = {}
	lvl.duration = 600.0
	return lvl


## rooms: Array of [room_id, deck, x]
func _world(level_id: StringName, rooms: Array, staff: Dictionary = {}, seed_value: int = 1, lvl: LevelDef = null) -> SimWorld:
	if lvl == null:
		lvl = _blank_level(level_id)
	var hull: HullDef = ContentStore.hull(lvl.hull)
	var layout := ShipLayout.new(hull)
	var grid := ShipGrid.new(layout, lvl)
	for r in rooms:
		grid.place_free(StringName(r[0]), int(r[1]), int(r[2]))
	return SimWorld.new(lvl, layout, staff, seed_value, 1000)


func _advance(w: SimWorld, seconds: float) -> void:
	var n: int = int(round(seconds / SimConst.TICK))
	for i in n:
		w.tick(SimConst.TICK)


func _grid_for(level_id: StringName, budget: int = 100000) -> ShipGrid:
	var lvl: LevelDef = ContentStore.level(level_id)
	var layout := ShipLayout.new(ContentStore.hull(lvl.hull))
	return ShipGrid.new(layout, lvl, budget)


func _spawn(w: SimWorld, archetype: StringName = &"holidaymaker") -> Guest:
	return w.guest_sim.spawn_guest(w, archetype)


# ---------------------------------------------------------------------------------------------
# Content
# ---------------------------------------------------------------------------------------------
func _t_content() -> void:
	_section("content")
	_eq(ContentStore.all_rooms().size(), 18, "18 rooms")
	_eq(ContentStore.all_archetypes().size(), 4, "4 archetypes")
	_eq(ContentStore.all_staff_roles().size(), 2, "2 staff roles")
	_eq(ContentStore.all_events().size(), 9, "9 events")
	_eq(ContentStore.all_destinations().size(), 3, "3 destinations")
	_eq(ContentStore.all_hulls().size(), 3, "3 hulls")
	_eq(ContentStore.campaign().size(), 18, "18 levels")
	for id in ["cabin", "buffet", "toilets", "bar", "pool", "deck_chairs", "cinema", "gym", "arcade",
			"restaurant", "medbay", "sauna", "ice_rink", "casino", "stairs", "elevator", "generator", "water_tank"]:
		_check(ContentStore.room(StringName(id)) != null, "room %s exists" % id)
	var camp: Array[LevelDef] = ContentStore.campaign()
	for i in camp.size():
		_eq(camp[i].campaign_index, i + 1, "campaign order %d" % (i + 1))
		_eq(camp[i].star_goals.size(), 3, "%s has 3 goals" % camp[i].id)
		_eq(String(camp[i].star_goals[0].get("type", "")), "rating", "%s goal 1 is rating" % camp[i].id)
		_check(camp[i].display_name != "" and camp[i].blurb != "", "%s has name and blurb" % camp[i].id)
		_check(camp[i].total_guests() > 0, "%s has guests" % camp[i].id)
		_check(ContentStore.hull(camp[i].hull) != null, "%s hull exists" % camp[i].id)
	for dest in [&"med", &"arctic", &"underworld"]:
		var lv: Array[LevelDef] = ContentStore.levels_for(dest)
		_eq(lv.size(), 6, "6 levels in %s" % dest)
		for i in lv.size():
			_eq(lv[i].index, i + 1, "%s sorted" % dest)
	var med1: LevelDef = ContentStore.level(&"med_1")
	_check(med1.tutorial and not med1.mutiny_enabled, "med_1 is the tutorial without mutiny")
	_eq(med1.hull, &"small", "med_1 small hull")
	_check(not med1.preset_rooms.is_empty(), "med_1 has preset rooms")
	_check(ContentStore.level(&"arctic_1").mutiny_enabled, "arctic_1 has mutiny")
	_eq(ContentStore.hull(&"large").width, 40, "large hull width")
	_eq(ContentStore.hull(&"medium").max_staff, 6, "medium max staff")
	var buffet: RoomDef = ContentStore.room(&"buffet")
	_eq(buffet.satisfies.get(&"hunger"), 85.0, "buffet hunger 85")
	_eq(buffet.tier_bonus.size(), 2, "buffet has 2 tiers")
	_eq(buffet.capacity_at(1), 6, "buffet tier II cap 6 (4 + 2)")
	_near(buffet.service_time_at(2), 8.0 / 1.25, 0.001, "tier III speed")
	_eq(ContentStore.room(&"cabin").capacity, 4, "cabin sleeps 4")
	_eq(ContentStore.room(&"cabin").capacity_at(2), 8, "cabin tier III sleeps 8")
	_eq(ContentStore.room(&"generator").power, -8, "generator supplies 8")
	_near(ContentStore.staff_role(&"janitor").work_time, 3.5, 0.001, "janitor work time 3.5 s")
	_near(ContentStore.staff_role(&"mechanic").work_time, 7.0, 0.001, "mechanic work time 7 s")
	_check(ContentStore.room(&"cabin").satisfies.has(&"hygiene"), "cabins give a small hygiene top-up")
	_eq(ContentStore.room(&"casino").destination_lock, &"underworld", "casino is Underworld only")
	_check(ContentStore.room(&"ice_rink").is_available(7, &"arctic") and not ContentStore.room(&"ice_rink").is_available(7, &"med"), "ice rink Arctic only")
	_check(ContentStore.room(&"cinema").is_available(2, &"med") and not ContentStore.room(&"cinema").is_available(1, &"med"), "cinema unlocks at 2")
	_eq(ContentStore.level(&"arctic_1").campaign_index, 7, "arctic_1 is level 7")
	_eq(ContentStore.destination(&"underworld").ghost_interval, Vector2(25, 40), "ghost interval")
	_eq(ContentStore.archetype(&"gamer").prop, &"headphones", "gamer prop")
	# ContentDB autoload script works headless.
	var db: Node = load("res://src/core/content_db.gd").new()
	db.load_all()
	_check(db.level(&"med_3") != null and db.levels_for(&"arctic").size() == 6 and db.campaign().size() == 18, "ContentDB wrapper works headless")
	db.free()


# ---------------------------------------------------------------------------------------------
# Grid placement
# ---------------------------------------------------------------------------------------------
func _t_grid_placement() -> void:
	_section("grid placement")
	var g: ShipGrid = _grid_for(&"underworld_1")  # medium hull, everything unlocked
	_eq(g.can_place(&"cabin", 1, 0)["ok"], true, "cabin fits")
	var cabin: PlacedRoom = g.place(&"cabin", 1, 0)
	_check(cabin != null, "cabin placed")
	var r: Dictionary = g.can_place(&"cabin", 1, 1)
	_check(not r["ok"] and r["reason"] == "Overlaps Cabin", "overlap reason: %s" % r["reason"])
	_eq(g.can_place(&"cabin", 1, 2)["ok"], true, "adjacent cabin ok")
	_eq(g.can_place(&"cabin", 1, 31)["reason"], "Out of bounds", "out of bounds right")
	_eq(g.can_place(&"cabin", 1, -1)["reason"], "Out of bounds", "out of bounds left")
	_eq(g.can_place(&"cabin", 9, 0)["reason"], "Out of bounds", "out of bounds deck")
	_eq(g.can_place(&"pool", 1, 4)["reason"], "Top deck only", "pool needs top deck")
	_eq(g.can_place(&"pool", 4, 4)["ok"], true, "pool on top deck")
	_eq(g.can_place(&"cabin", 4, 4)["reason"], "Not on the top deck", "interior not on top")
	_eq(g.can_place(&"stairs", 4, 4)["reason"], "Needs 2 free decks", "stairs on top deck")
	_eq(g.can_place(&"stairs", 3, 4)["ok"], true, "stairs into top deck ok")
	_eq(g.can_place(&"stairs", 0, 0)["reason"], "Needs 2 free decks", "stairs blocked on the upper deck")
	_eq(g.can_place(&"stairs", 1, 0)["reason"], "Overlaps Cabin", "stairs overlap lower cell")
	g.place(&"cabin", 2, 10)
	_eq(g.can_place(&"stairs", 1, 10)["reason"], "Needs 2 free decks", "stairs blocked on upper deck")
	_eq(g.can_place(&"elevator", 0, 10)["reason"], "Overlaps Cabin", "elevator column blocked")
	_eq(g.can_place(&"elevator", 0, 20)["ok"], true, "elevator column free")
	var el: PlacedRoom = g.place(&"elevator", 0, 20)
	_check(el != null and el.deck == 0, "elevator placed at deck 0")
	_check(el.occupies(3, 20, 5) and el.occupies(0, 20, 5) and not el.occupies(3, 21, 5), "elevator occupies column on every deck")
	_eq(g.can_place(&"bar", 3, 19)["reason"], "Overlaps Elevator", "bar overlaps elevator")
	# Unlocks
	var g1: ShipGrid = _grid_for(&"med_1")
	_eq(g1.can_place(&"cinema", 1, 0)["reason"], "Unlocks at level 2", "cinema locked at level 1")
	_eq(g1.can_place(&"generator", 1, 0)["reason"], "Unlocks at level 3", "generator locked at level 1")
	_eq(g1.can_place(&"ice_rink", 1, 0)["reason"], "Unlocks at level 7", "ice rink locked")
	var g2: ShipGrid = _grid_for(&"arctic_1")
	_eq(g2.can_place(&"sauna", 1, 0)["reason"], "Not available here", "sauna only in the Mediterranean")
	_eq(g2.can_place(&"ice_rink", 1, 0)["ok"], true, "ice rink available in Arctic")
	# Utilities: small hull has 16 power.
	var g3: ShipGrid = _grid_for(&"med_3")
	var placed: int = 0
	for i in 6:
		if g3.place(&"bar", 1, i * 3) != null:
			placed += 1
	_eq(placed, 6, "6 bars fit (12 power)")
	_eq(g3.can_place(&"bar", 2, 0)["ok"], true, "7th bar fits (14 power)")
	g3.place(&"bar", 2, 0)
	g3.place(&"bar", 2, 3)
	_eq(g3.can_place(&"bar", 2, 6)["reason"], "Not enough power", "power exhausted")
	var gen: PlacedRoom = g3.place(&"generator", 2, 12)
	_check(gen != null, "generator placed")
	_eq(g3.power_capacity(), 24, "generator adds 8 power")
	_eq(g3.can_place(&"bar", 2, 6)["ok"], true, "bar fits after generator")
	var uses_water: ShipGrid = _grid_for(&"med_3")
	for i in 8:
		uses_water.place(&"cabin", 1, i * 2)
	for i in 8:
		uses_water.place(&"cabin", 2, i * 2)
	_eq(uses_water.can_place(&"toilets", 0, 0)["reason"], "Not enough water", "water exhausted")


func _t_grid_economy() -> void:
	_section("grid money, sell, move, upgrade")
	var g: ShipGrid = _grid_for(&"arctic_1", 1000)
	var c: PlacedRoom = g.place(&"cabin", 1, 0)
	_eq(g.money, 880, "cabin costs 120")
	var refund: int = g.sell(c.uid)
	_eq(refund, 90, "sell refunds 75%")
	_eq(g.money, 970, "money after sell")
	var b: PlacedRoom = g.place(&"buffet", 1, 0)
	_eq(g.money, 670, "buffet costs 300")
	_eq(g.can_upgrade(b.uid)["ok"], true, "arctic can upgrade buffet")
	_eq(g.upgrade_cost(b.uid), 180, "tier II costs 60%")
	_check(g.upgrade(b.uid), "upgrade ok")
	_eq(b.tier, 1, "tier is 1")
	_eq(g.money, 490, "money after upgrade")
	_eq(g.sell(b.uid), int(floor(480.0 * 0.75)), "sell refunds cost plus upgrades")
	_eq(g.can_place(&"pool", 4, 0)["ok"], true, "pool affordable")
	g.money = 100
	_eq(g.can_place(&"buffet", 1, 0)["reason"], "Not enough money", "not enough money")
	g.money = 1000
	# Move is free, locked rooms can't move or be sold.
	var m: PlacedRoom = g.place(&"cabin", 1, 0)
	var before: int = g.money
	_check(g.move(m.uid, 2, 6), "move ok")
	_eq(g.money, before, "move is free")
	_check(m.deck == 2 and m.x == 6, "room moved")
	var lock: PlacedRoom = g.place_free(&"toilets", 1, 10, true)
	_check(not g.move(lock.uid, 1, 12), "locked room can't move")
	_eq(g.sell(lock.uid), -1, "locked room can't be sold")
	_eq(g.can_sell(lock.uid)["reason"], "Locked", "locked reason")
	_check(g.can_upgrade(lock.uid)["ok"], "locked rooms can still be upgraded")
	# Tier unlocks: tier II at level 4, III at level 10.
	var g_med: ShipGrid = _grid_for(&"med_3")
	var cab: PlacedRoom = g_med.place(&"cabin", 1, 0)
	_eq(g_med.can_upgrade(cab.uid)["reason"], "Unlocks at level 4", "tier II locked at level 3")
	var g_a4: ShipGrid = _grid_for(&"arctic_4")
	var bar: PlacedRoom = g_a4.place(&"bar", 1, 0)
	_check(g_a4.upgrade(bar.uid), "tier II at level 10")
	_eq(g_a4.can_upgrade(bar.uid)["ok"], true, "tier III available at level 10")
	_check(g_a4.upgrade(bar.uid), "tier III ok")
	_eq(g_a4.can_upgrade(bar.uid)["reason"], "Fully upgraded", "no tier IV")
	_eq(bar.capacity(), 4 + 2 + 2, "bar tier III capacity")
	# Generator can't be sold while power is needed.
	var gu: ShipGrid = _grid_for(&"arctic_1")
	var gen: PlacedRoom = gu.place(&"generator", 1, 0)
	for i in 7:
		gu.place(&"arcade", 2, i * 3)  # 7 x 4 = 28 power > the hull's 26: only fits with the generator
	_eq(gu.can_sell(gen.uid)["ok"], false, "can't sell a generator that is needed")


# ---------------------------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------------------------
func _t_validation() -> void:
	_section("validation")
	var g: ShipGrid = _grid_for(&"med_2")
	g.place(&"cabin", 1, 0)
	g.place(&"buffet", 2, 0)
	var v: Dictionary = g.validate_for_voyage()
	_eq(v["errors"].size(), 1, "unconnected upper deck is an error")
	_check(String(v["errors"][0]).contains("Deck 3"), "error names the deck: %s" % v["errors"][0])
	g.place(&"stairs", 1, 10)
	v = g.validate_for_voyage()
	_eq(v["errors"].size(), 0, "stairs connect the decks")
	_check(v["warnings"].size() >= 3, "warnings: beds, toilets, fun")
	var warn_text: String = " ".join(v["warnings"])
	_check(warn_text.contains("beds") and warn_text.contains("toilets") and warn_text.contains("fun"), "warning texts")
	g.place(&"pool", 3, 0)
	v = g.validate_for_voyage()
	_eq(v["errors"].size(), 1, "top deck needs a link")
	g.place(&"stairs", 2, 11)
	v = g.validate_for_voyage()
	_eq(v["errors"].size(), 0, "all decks connected")
	v = g.validate_for_voyage(14, 0)
	_check(" ".join(v["warnings"]).contains("No crew"), "no crew warning")
	# Elevator connects every deck by itself.
	var ge: ShipGrid = _grid_for(&"arctic_1")
	ge.place(&"elevator", 0, 4)
	ge.place(&"cabin", 4 - 1, 10) if false else null
	ge.place(&"bar", 1, 10)
	ge.place(&"cinema", 3, 10)
	ge.place(&"deck_chairs", 4, 10)
	_eq(ge.validate_for_voyage()["errors"].size(), 0, "elevator connects all decks")
	# Tutorial presets are connected.
	var port := PortState.new(ContentStore.level(&"med_1"))
	_eq(port.validate()["errors"].size(), 0, "tutorial presets valid")


# ---------------------------------------------------------------------------------------------
# Pathing
# ---------------------------------------------------------------------------------------------
func _t_pathing() -> void:
	_section("pathfinding")
	var g: ShipGrid = _grid_for(&"med_2")
	g.place_free(&"stairs", 0, 10)
	g.place_free(&"stairs", 1, 11)
	var gr: WalkGraph = g.graph
	var a: int = gr.node(0, 2)
	var b: int = gr.node(1, 5)
	_check(gr.reachable(a, b), "reachable via stairs")
	var route: Array = gr.route(a, b)
	var modes: Array = []
	for wp in route:
		modes.append(wp["mode"])
	_check(modes.has(&"stairs"), "route uses stairs")
	_near(gr.cost(a, b), 8.0 / 2.2 + 1.6 + 5.0 / 2.2, 0.3, "stairs cost = walk + 1.6 s")
	var top: int = gr.node(3, 3)
	_check(gr.reachable(a, top) == false, "top deck unreachable without stairs")
	g.place_free(&"stairs", 2, 12)
	gr = g.graph
	_check(gr.reachable(gr.node(0, 0), gr.node(3, 0)), "top deck reachable once stairs added")
	var r2: Array = gr.route(gr.node(0, 0), gr.node(3, 20))
	var n_stairs: int = 0
	for wp in r2:
		if wp["mode"] == &"stairs":
			n_stairs += 1
	_eq(n_stairs, 3, "three flights to reach the top deck")
	# Walker follows the route and arrives.
	var wk := Walker.new()
	wk.set_position(0, 1.5)
	_check(wk.plan_route(g, 3, 20.5), "walker plans a route")
	var tr := Transit.new()
	var steps: int = 0
	var cost: float = gr.cost(gr.node(0, 1), gr.node(3, 20))
	while not wk.step_route(0.1, 2.2, tr, &"walk") and steps < 2000:
		steps += 1
	_near(wk.x, 20.5, 0.01, "walker arrives at x")
	_eq(wk.deck, 3, "walker arrives on deck 3")
	_near(float(steps) * 0.1, cost, 1.5, "travel time close to path cost")
	# Cache returns the same route object.
	_check(gr.route(gr.node(0, 0), gr.node(3, 20)) == r2, "route cache")
	# Layout changes rebuild the graph.
	g.sell(g.layout.room_at(2, 12).uid)
	_check(not g.graph.reachable(g.graph.node(0, 0), g.graph.node(3, 0)), "selling stairs disconnects")


func _t_elevator() -> void:
	_section("elevator")
	var g: ShipGrid = _grid_for(&"arctic_1")
	g.place_free(&"elevator", 0, 10)
	var gr: WalkGraph = g.graph
	var a: int = gr.node(0, 10)
	var b: int = gr.node(4, 10)
	_near(gr.cost(a, b), 1.0 + 0.5 * 4.0, 0.01, "elevator cost 1.0 + 0.5 per deck")
	var route: Array = gr.route(gr.node(0, 3), gr.node(4, 3))
	var m: Array = []
	for wp in route:
		m.append(wp["mode"])
	_check(m.has(&"elevator") and not m.has(&"stairs"), "route uses the elevator")
	# Six walkers wanting to ride: at most 4 ride at once.
	var tr := Transit.new()
	var walkers: Array[Walker] = []
	for i in 6:
		var w := Walker.new()
		w.set_position(0, 10.5)
		w.plan_route(g, 4, 10.5)
		walkers.append(w)
	var max_riding: int = 0
	var done: Array[bool] = [false, false, false, false, false, false]
	for step in 400:
		for i in 6:
			if not done[i]:
				done[i] = walkers[i].step_route(0.1, 2.2, tr, &"walk")
		tr.tick()
		var riding: int = 0
		for w in walkers:
			if w.travel_mode == Walker.T_RIDE:
				riding += 1
		max_riding = maxi(max_riding, riding)
		_check(riding <= SimConst.ELEVATOR_CAPACITY, "elevator never carries more than 4")
		if not done.has(false):
			break
	_eq(max_riding, 4, "elevator reaches capacity 4")
	_check(not done.has(false), "all six eventually arrive")
	for w in walkers:
		_eq(w.deck, 4, "arrived on the top deck")
	_eq(tr.riders_in(10), 0, "elevator empties")


# ---------------------------------------------------------------------------------------------
# Port state
# ---------------------------------------------------------------------------------------------
func _t_port() -> void:
	_section("port state")
	var lvl: LevelDef = ContentStore.level(&"arctic_2")
	var port := PortState.new(lvl)
	_eq(port.budget, lvl.budget, "budget starts at level budget")
	var r: PlacedRoom = port.place(&"cabin", 1, 0)
	_check(r != null, "port place")
	_eq(port.budget, lvl.budget - 120, "budget charged")
	_check(port.hire(&"janitor"), "hire janitor")
	_eq(port.budget, lvl.budget - 120 - 40, "wage charged")
	_check(port.hire(&"mechanic"), "hire mechanic")
	_eq(port.staff_total(), 2, "2 staff")
	_check(port.fire(&"janitor"), "fire janitor")
	_eq(port.budget, lvl.budget - 120 - 60, "wage refunded on fire")
	_check(not port.fire(&"janitor"), "can't fire what isn't hired")
	for i in 5:
		port.hire(&"janitor")
	_eq(port.staff_total(), 6, "max staff by hull (medium = 6)")
	_check(not port.hire(&"janitor"), "crew full")
	var m: Dictionary = port.manifest()
	_eq(m["guests"], lvl.total_guests(), "manifest guests")
	var sum: int = 0
	for k in m["by_archetype"]:
		sum += int(m["by_archetype"][k])
	_eq(sum, lvl.total_guests(), "manifest archetypes sum to guests")
	_eq(m["cabins_needed"], int(ceil(float(lvl.total_guests()) / 4.0)), "cabins needed")
	# Tutorial presets are locked and free.
	var tut := PortState.new(ContentStore.level(&"med_1"))
	_eq(tut.budget, ContentStore.level(&"med_1").budget, "tutorial presets cost nothing")
	var locked_count: int = 0
	for pr in tut.layout.rooms:
		if pr.locked:
			locked_count += 1
	_check(locked_count >= 2, "tutorial has locked presets")
	_eq(tut.sell(tut.layout.rooms[0].uid), -1, "locked preset can't be sold")
	# Catalog lists availability and lock reasons.
	var cat: Array[Dictionary] = port.catalog()
	var arc_ids: Array = []
	for e in cat:
		arc_ids.append(e["def"].id)
		if e["def"].id == &"ice_rink":
			_check(e["available"], "ice rink available in arctic_2")
		if e["def"].id == &"casino":
			_check(false, "casino must not be listed in the Arctic")
		if e["def"].id == &"sauna":
			_check(false, "sauna must not be listed in the Arctic")
	_check(arc_ids.has(&"ice_rink") and arc_ids.has(&"cabin") and not arc_ids.has(&"casino"), "catalog filters by destination")
	var tut_cat: Array[Dictionary] = tut.catalog()
	for e in tut_cat:
		if e["def"].id == &"cinema":
			_eq(e["reason"], "Unlocks at level 2", "locked rooms carry their reason")
			_check(not e["available"], "cinema locked in the tutorial")
		if e["def"].id == &"cabin":
			_check(e["available"], "cabin available in the tutorial")
	# create_world works.
	var w: SimWorld = port.create_world(5)
	_eq(w.staff.size(), port.staff_total(), "world has the hired crew")


# ---------------------------------------------------------------------------------------------
# Guests
# ---------------------------------------------------------------------------------------------
func _small_ship() -> Array:
	return [
		[&"stairs", 0, 10], [&"stairs", 1, 11], [&"stairs", 2, 10],
		[&"cabin", 1, 0], [&"cabin", 1, 2], [&"toilets", 1, 4], [&"buffet", 2, 2],
		[&"bar", 2, 8], [&"pool", 3, 2], [&"deck_chairs", 3, 12],
	]


func _t_guest_basics() -> void:
	_section("guest basics")
	var w: SimWorld = _world(&"med_3", _small_ship())
	var g: Guest = _spawn(w)
	_eq(g.id, 1, "first guest id")
	_eq(g.state, Guest.BOARDING, "boarding at first")
	_eq(g.deck, 1, "boards at the gangway deck")
	_near(g.x, 0.5, 0.001, "boards at x=0.5")
	_check(g.cabin_uid != -1, "assigned a cabin")
	_eq(w.room_by_uid(g.cabin_uid).def.id, &"cabin", "cabin uid is a cabin")
	for i in 4:
		_check(g.nv[i] >= SimConst.INITIAL_NEED_MIN and g.nv[i] <= SimConst.INITIAL_NEED_MAX, "initial need %d in the boarding range" % i)
	_eq(g.satisfaction, 72.0, "initial satisfaction")
	_eq(w.money, 1000 + 20 * 0 + w.level.ticket_price, "ticket paid on boarding")
	# Cabin filling order: nearest cabin first, 4 beds each.
	var w2: SimWorld = _world(&"med_3", _small_ship())
	var first_cabin: int = w2.room_sim.cabins_by_distance[0].uid
	var counts: Dictionary = {}
	for i in 9:
		var gg: Guest = _spawn(w2)
		counts[gg.cabin_uid] = int(counts.get(gg.cabin_uid, 0)) + 1
	_eq(int(counts.get(first_cabin, 0)), 4, "nearest cabin filled first with 4 sleepers")
	_eq(counts.get(-1, 0), 1, "9th guest is homeless (2 cabins = 8 beds)")
	# Needs decay and states progress.
	var w3: SimWorld = _world(&"med_3", _small_ship())
	var g3: Guest = _spawn(w3)
	g3.nv[SimConst.N_HUNGER] = 30.0
	var hunger_before: float = g3.nv[SimConst.N_HUNGER]
	_advance(w3, 1.0)
	_check(g3.state == Guest.WANDER or g3.state == Guest.WALK, "guest leaves boarding")
	_advance(w3, 40.0)
	_check(g3.uses >= 1, "hungry guest used a room")
	_check(g3.nv[SimConst.N_HUNGER] > hunger_before, "hunger was restored")
	_eq(w3.metrics["patience_outs"], 0, "no patience-outs for a lone guest")
	# Decay rates: fun 1.0/s base, hygiene 0.6/s x1.25 in Med.
	var w4: SimWorld = _world(&"med_3", [[&"stairs", 0, 10], [&"stairs", 1, 11]])
	var g4: Guest = _spawn(w4)
	_advance(w4, 2.0)
	for i in 4:
		g4.nv[i] = 90.0
	_advance(w4, 20.0)
	var dm: float = w4.level.decay_mult
	_near(90.0 - g4.nv[SimConst.N_FUN], 20.0 * 1.0 * dm, 1.5, "fun decays 1.0/s")
	_near(90.0 - g4.nv[SimConst.N_HUNGER], 20.0 * 0.8 * dm, 1.5, "hunger decays 0.8/s")
	_near(90.0 - g4.nv[SimConst.N_HYGIENE], 20.0 * 0.6 * 1.25 * dm, 1.5, "hygiene decays 0.6/s x1.25 (Med)")
	_near(90.0 - g4.nv[SimConst.N_REST], 20.0 * 0.45 * dm, 1.5, "rest decays 0.45/s")
	# Archetype quirks.
	var w5: SimWorld = _world(&"med_3", [[&"stairs", 0, 10]])
	var fan: Guest = _spawn(w5, &"fitness_fan")
	var gam: Guest = _spawn(w5, &"gamer")
	_near(fan.decay[SimConst.N_HUNGER], 0.8 * 1.5 * w5.level.decay_mult, 0.001, "fitness fan hunger x1.5")
	_advance(w5, 2.0)
	for gg in [fan, gam]:
		for i in 4:
			gg.nv[i] = 90.0
	_advance(w5, 10.0)
	_near(90.0 - gam.nv[SimConst.N_FUN], 10.0 * 2.0 * w5.level.decay_mult, 1.5, "gamer fun decays x2 when no gaming room used")
	# A needy guest picks the right room (hunger -> buffet).
	var w6: SimWorld = _world(&"med_3", _small_ship())
	var g6: Guest = _spawn(w6)
	g6.nv[SimConst.N_HUNGER] = 20.0
	g6.nv[SimConst.N_FUN] = 90.0
	g6.nv[SimConst.N_HYGIENE] = 90.0
	g6.nv[SimConst.N_REST] = 90.0
	var chosen: int = -1
	for i in 200:
		w6.tick(SimConst.TICK)
		if g6.mode == Guest.WALK or g6.mode == Guest.QUEUE or g6.mode == Guest.USE:
			chosen = g6.target_uid
			break
	_check(chosen != -1 and w6.room_by_uid(chosen).def.id == &"buffet", "hungry guest heads for the buffet")
	# Medbay priority for sick guests; healthy guests ignore it.
	var w7: SimWorld = _world(&"med_3", _small_ship() + [[&"medbay", 1, 6]])
	var g7: Guest = _spawn(w7)
	for i in 4:
		g7.nv[i] = 95.0
	w7.problems.infect(w7, g7)
	var target_med: bool = false
	for i in 300:
		w7.tick(SimConst.TICK)
		if g7.mode == Guest.WALK or g7.mode == Guest.USE or g7.mode == Guest.QUEUE:
			target_med = w7.room_by_uid(g7.target_uid).def.id == &"medbay"
			break
	_check(target_med, "sick guest goes to the medbay")


func _t_queue_patience() -> void:
	_section("queues and patience")
	var w: SimWorld = _world(&"med_3", _small_ship())
	var buffet: RoomRuntime = null
	for r in w.rooms:
		if r.def.id == &"buffet":
			buffet = r
	var g: Guest = _spawn(w)
	_advance(w, 1.5)
	w.room_sim.break_room(w, buffet)
	g.mode = Guest.WALK
	g.target_uid = buffet.uid
	buffet.incoming += 1
	g.nv[SimConst.N_HUNGER] = 10.0
	g.set_position(2, buffet.door_x - 0.3)
	w.guest_sim._arrive(w, g)
	_eq(g.mode, Guest.QUEUE, "guest queues at a broken room")
	_eq(buffet.queue.size(), 1, "room has a queue")
	_eq(buffet.queue[0], g.id, "queue holds guest id")
	_check(g.queue_x <= buffet.door_x, "queue forms to the left of the door")
	var sat_before: float = g.satisfaction
	var po: Array = [0]
	w.guest_patience_out.connect(func(gid: int, ruid: int) -> void: po[0] = gid)
	_advance(w, 12.0)
	_eq(g.mode, Guest.QUEUE, "still waiting after 12 s")
	_check(g.satisfaction < sat_before, "satisfaction drains while queueing")
	_advance(w, 10.0)
	_check(g.mode != Guest.QUEUE, "patience ran out (28 s / 1.7 at a broken room)")
	_eq(buffet.queue.size(), 0, "left the queue")
	_eq(po[0], g.id, "patience-out signal fired")
	_eq(w.metrics["patience_outs"], 1, "patience out counted")
	_check(g.avoid.has(buffet.uid), "guest avoids the room for a while")
	_check(g.satisfaction < sat_before - 8.0, "-10 satisfaction on patience out")
	# Film buffs are less patient outside the cinema.
	var w2: SimWorld = _world(&"med_3", _small_ship() + [[&"cinema", 2, 14]])
	var buff2: RoomRuntime = null
	for r in w2.rooms:
		if r.def.id == &"buffet":
			buff2 = r
	w2.room_sim.break_room(w2, buff2)
	var fb: Guest = _spawn(w2, &"film_buff")
	fb.mode = Guest.WALK
	fb.target_uid = buff2.uid
	buff2.incoming += 1
	fb.set_position(2, buff2.door_x - 0.3)
	w2.guest_sim._arrive(w2, fb)
	_check(fb.patience < 28.0 * 0.6 * 1.11, "film buff patience x0.6 in non-cinema queue (%.1f)" % fb.patience)
	# Queue order: first in, first served when the room recovers.
	var w3: SimWorld = _world(&"med_3", _small_ship())
	var bf: RoomRuntime = null
	for r in w3.rooms:
		if r.def.id == &"buffet":
			bf = r
	w3.room_sim.break_room(w3, bf)
	var ids: Array[int] = []
	for i in 3:
		var gg: Guest = _spawn(w3)
		gg.mode = Guest.WALK
		gg.target_uid = bf.uid
		bf.incoming += 1
		gg.set_position(2, bf.door_x - 0.3)
		gg.nv[SimConst.N_HUNGER] = 10.0
		w3.guest_sim._arrive(w3, gg)
		ids.append(gg.id)
	_eq(bf.queue, ids, "queue is first-come first-served")
	_check(w3.guest_by_id(ids[2]).queue_x < w3.guest_by_id(ids[0]).queue_x, "later guests stand further left")
	_near(w3.guest_by_id(ids[0]).queue_x - w3.guest_by_id(ids[1]).queue_x, 0.45, 0.001, "queue spacing 0.45")
	bf.repair_progress = 0.99
	w3.room_sim.add_repair(w3, bf, 0.1)
	_check(not bf.broken, "repaired")
	_advance(w3, 0.5)
	_eq(bf.queue.size(), 0, "queue drained into the room")
	_eq(bf.users.size(), 3, "all three being served (cap 6)")
	# Queue wraps to the right at the left edge.
	var edge_room: RoomRuntime = w3.room_by_uid(w3.grid.layout.room_at(1, 0).uid)
	var spot: float = w3.room_sim.queue_spot_x(w3, edge_room, 4)
	_check(spot > edge_room.door_x, "queue wraps to the right of the door at x=0 (%.2f)" % spot)


func _t_slots_and_interp() -> void:
	_section("slots and interpolation")
	var w: SimWorld = _world(&"med_3", _small_ship())
	var guests: Array[Guest] = []
	for i in 4:
		var g: Guest = _spawn(w)
		g.nv[SimConst.N_HUNGER] = 5.0
		guests.append(g)
	var seen_slots: Dictionary = {}
	var stable: bool = true
	var prev_slot: Dictionary = {}
	for i in 400:
		w.tick(SimConst.TICK)
		for g in guests:
			if g.mode == Guest.USE and w.room_by_uid(g.target_uid).def.id == &"buffet":
				var s: int = w.slot_index_of(g.id)
				seen_slots[s] = true
				if prev_slot.has(g.id) and prev_slot[g.id] != s:
					stable = false
				prev_slot[g.id] = s
			else:
				prev_slot.erase(g.id)
				_check(w.slot_index_of(g.id) == -1 or g.mode == Guest.USE, "slot -1 when not using")
	_check(seen_slots.size() >= 2, "different guests occupy different slots")
	_check(stable, "slot is stable while using")
	# prev_x / prev_deck_f are the previous tick's values.
	var w2: SimWorld = _world(&"med_3", _small_ship())
	var g2: Guest = _spawn(w2)
	_advance(w2, 3.0)
	var px: float = g2.x
	var pdf: float = g2.deck_f
	w2.tick(SimConst.TICK)
	_near(g2.prev_x, px, 0.0001, "prev_x holds the previous tick's x")
	_near(g2.prev_deck_f, pdf, 0.0001, "prev_deck_f holds the previous tick's deck_f")
	_check(g2.facing == 1 or g2.facing == -1, "facing is -1 or 1")
	# Guests climbing report climb state and fractional deck.
	var w3: SimWorld = _world(&"med_3", [[&"stairs", 1, 5], [&"stairs", 0, 6]])
	var g3: Guest = _spawn(w3)
	g3.mode = Guest.WANDER
	g3.clear_route()
	g3.set_position(1, 5.5)
	g3.plan_route(w3.grid, 2, 5.5)
	var saw_climb: bool = false
	var saw_fraction: bool = false
	for i in 40:
		w3.tick(SimConst.TICK)
		if g3.state == &"climb":
			saw_climb = true
		if g3.deck_f > 1.05 and g3.deck_f < 1.95:
			saw_fraction = true
	_check(saw_climb and saw_fraction, "climbing state with fractional deck_f")


func _t_satisfaction() -> void:
	_section("satisfaction rules")
	# Isolated guest on a ship with nothing to use: needs fall, satisfaction falls.
	var w: SimWorld = _world(&"med_3", [[&"stairs", 0, 10]])
	var g: Guest = _spawn(w)
	_check(g.cabin_uid == -1, "no cabin on an empty ship")
	_advance(w, 2.0)
	for i in 4:
		g.nv[i] = 45.0
	var s0: float = g.satisfaction
	_advance(w, 10.0)
	_check(g.satisfaction < s0, "homeless guest loses satisfaction (-0.15/s)")
	_near(s0 - g.satisfaction, 10.0 * (0.15 - SimConst.SAT_OK_RATE), 0.8, "homeless drain rate")
	# Everything >= 50 -> +0.25/s with a cabin.
	var w2: SimWorld = _world(&"med_3", [[&"cabin", 1, 0]])
	var g2: Guest = _spawn(w2)
	for i in 4:
		g2.nv[i] = 100.0
	g2.satisfaction = 50.0
	_advance(w2, 10.0)
	_near(g2.satisfaction, 50.0 + 10.0 * SimConst.SAT_GOOD_RATE, 1.0, "good-rate satisfaction when all needs >= 50")
	# Low needs hurt: all needs < 15 gives -(0.6+0.6) per need per second (clamped by need decay).
	var w3: SimWorld = _world(&"med_3", [[&"stairs", 0, 10]])
	var g3: Guest = _spawn(w3)
	_advance(w3, 2.0)
	for i in 4:
		g3.nv[i] = 10.0
	g3.satisfaction = 80.0
	_advance(w3, 5.0)
	_near(g3.satisfaction, 80.0 - 5.0 * (4.0 * (SimConst.SAT_LOW_RATE + SimConst.SAT_CRIT_RATE) + 0.15), 3.0, "needs < 15 drain each")
	# A guest at satisfaction <= 5 for 8 s storms off and counts as lost.
	var w4: SimWorld = _world(&"med_3", [[&"stairs", 0, 10]])
	var g4: Guest = _spawn(w4)
	_advance(w4, 2.0)
	var so: Array = [0]
	w4.guest_stormed_off.connect(func(gid: int) -> void: so[0] = gid)
	for i in 4:
		g4.nv[i] = 0.0
	g4.satisfaction = 3.0
	_advance(w4, 6.0)
	_check(g4.mode != Guest.STORM_OFF and g4.mode != Guest.GONE, "not yet storming after 6 s")
	_advance(w4, 5.0)
	_check(g4.state == Guest.STORM_OFF or g4.state == Guest.GONE, "stormed off after ~8 s (%s)" % g4.state)
	_eq(so[0], g4.id, "stormed off signal")
	_check(g4.lost and g4.satisfaction == 0.0, "lost guest has 0 satisfaction")
	_advance(w4, 15.0)
	_eq(g4.state, Guest.GONE, "guest walks to the gangway and is gone")
	_eq(w4.stats()["lost"], 1, "stats counts the lost guest")
	_near(w4.rating(), 0.0, 0.01, "rating counts lost guests as 0")
	# Rating = mean satisfaction over boarded guests.
	var w5: SimWorld = _world(&"med_3", [[&"cabin", 1, 0]])
	var a: Guest = _spawn(w5)
	var b: Guest = _spawn(w5)
	a.satisfaction = 60.0
	b.satisfaction = 80.0
	w5.tick(SimConst.TICK)
	_near(w5.rating(), 70.0, 1.0, "rating is the mean satisfaction")
	# Arctic cold drain on the top deck.
	var w6: SimWorld = _world(&"arctic_1", [[&"stairs", 0, 10], [&"stairs", 1, 11], [&"stairs", 2, 10], [&"stairs", 3, 11], [&"cabin", 1, 0]])
	var cold: Guest = _spawn(w6)
	for i in 4:
		cold.nv[i] = 100.0
	cold.mode = Guest.WANDER
	cold.set_position(4, 5.5)
	cold.clear_route()
	cold.wander_pause = 1000.0
	cold.eval_timer = 1000.0
	var s6: float = cold.satisfaction
	_advance(w6, 10.0)
	_check(cold.satisfaction < s6 + 10.0 * SimConst.SAT_GOOD_RATE - 1.5, "cold top deck drains (0.25/s) (%.2f -> %.2f)" % [s6, cold.satisfaction])
	# A mess within 1.5 cells hurts; slips happen on mess cells.
	var w7: SimWorld = _world(&"med_3", [[&"cabin", 1, 0], [&"buffet", 1, 4]])
	var mg: Guest = _spawn(w7)
	for i in 4:
		mg.nv[i] = 100.0
	mg.mode = Guest.WANDER
	mg.set_position(1, 10.5)
	mg.wander_pause = 1000.0
	mg.eval_timer = 1000.0
	var m: Mess = w7.problems.spawn_mess(w7, w7.room_by_uid(w7.grid.layout.room_at(1, 4).uid))
	m.x = 10.5
	w7.problems.mess_cells.erase(w7.problems.cell_key(1, int(m.x)))
	m.deck = 1
	w7.problems.deck_messes[1] = [m]
	w7.problems.mess_cells[w7.problems.cell_key(1, 10)] = m.id
	mg.satisfaction = 60.0
	_advance(w7, 10.0)
	_check(mg.satisfaction < 60.0 + 10.0 * SimConst.SAT_GOOD_RATE - 3.0, "standing next to a mess drains satisfaction (%.2f)" % mg.satisfaction)
	# Slip: stepping onto a mess cell with slip chance 25% -> over many trials some slip.
	var slips: int = 0
	var trials: int = 120
	var w8: SimWorld = _world(&"med_3", [[&"cabin", 1, 0], [&"buffet", 1, 4]], {}, 11)
	var sig_slips: Array = [0]
	w8.guest_slipped.connect(func(gid: int) -> void: sig_slips[0] += 1)
	for t in trials:
		var sg: Guest = _spawn(w8)
		sg.mode = Guest.WALK
		sg.set_position(1, 3.2)
		sg.plan_route(w8.grid, 1, 8.5)
		var mm: Mess = Mess.new()
		mm.id = 1000 + t
		mm.deck = 1
		mm.x = 5.5
		w8.problems.mess_cells = {w8.problems.cell_key(1, 5): mm.id}
		for i in 40:
			w8.guest_sim._fast(w8, sg, SimConst.TICK)
			if sg.slip_timer > 0.0:
				slips += 1
				break
		w8.problems.mess_cells = {}
	_check(slips > trials * 0.12 and slips < trials * 0.40, "slip chance about 25%% (%d of %d)" % [slips, trials])
	_eq(sig_slips[0], slips, "guest_slipped signal per slip")


# ---------------------------------------------------------------------------------------------
# Problems: messes and breakdowns
# ---------------------------------------------------------------------------------------------
func _find_room(w: SimWorld, id: StringName) -> RoomRuntime:
	for r in w.rooms:
		if r.def.id == id:
			return r
	return null


func _t_messes() -> void:
	_section("messes")
	var w: SimWorld = _world(&"med_3", _small_ship())
	var buffet: RoomRuntime = _find_room(w, &"buffet")
	var sp: Array = [0]
	var cl: Array = [0]
	w.mess_spawned.connect(func(id: int) -> void: sp[0] = id)
	w.mess_cleaned.connect(func(id: int) -> void: cl[0] = id)
	var m: Mess = w.problems.spawn_mess(w, buffet)
	_check(m != null, "mess spawned")
	_eq(sp[0], m.id, "mess_spawned signal")
	_eq(m.deck, buffet.deck, "mess on the room's deck")
	_check(absf(m.x - buffet.door_x) <= 1.6, "mess near the door")
	_near(m.x - floorf(m.x), 0.5, 0.001, "mess sits on a cell centre")
	_eq(w.messes.size(), 1, "mess tracked")
	_eq(w.staff_sim.jobs.count_of(&"mess"), 1, "mess posts a job")
	w.player_click_mess(m.id)
	_near(m.clean_progress, 0.34, 0.001, "click adds 0.34")
	w.player_click_mess(m.id)
	w.player_click_mess(m.id)
	_eq(w.messes.size(), 0, "three clicks clean a mess")
	_eq(cl[0], m.id, "mess_cleaned signal")
	_eq(w.staff_sim.jobs.count_of(&"mess"), 0, "job removed when cleaned")
	# Cap of 4 per deck, distinct cells.
	var cells: Dictionary = {}
	for i in 6:
		var mm: Mess = w.problems.spawn_mess(w, buffet)
		if mm != null:
			cells[mm.x] = true
	_eq(w.messes.size(), 4, "at most 4 messes per deck")
	_eq(cells.size(), 4, "messes on distinct cells")
	# Mess chance on use (buffet 22%): over many uses roughly that many messes.
	var w2: SimWorld = _world(&"med_3", _small_ship(), {}, 3)
	var bf2: RoomRuntime = _find_room(w2, &"buffet")
	var made: int = 0
	for i in 400:
		w2.problems.try_mess(w2, bf2)
		if w2.messes.size() > 0:
			made += 1
			for m2 in w2.messes.duplicate():
				w2.problems.add_clean(w2, m2, 1.0)
	_check(made > 400 * 0.14 and made < 400 * 0.32, "buffet mess chance ~22%% (%d/400)" % made)
	# Janitor cleans on its own at 2.5 s of work.
	var w3: SimWorld = _world(&"med_3", _small_ship(), {&"janitor": 1})
	var m3: Mess = w3.problems.spawn_mess(w3, _find_room(w3, &"buffet"))
	var t_clean: float = -1.0
	for i in 600:
		w3.tick(SimConst.TICK)
		if w3.messes.is_empty():
			t_clean = w3.time
			break
	_check(t_clean > 0.0, "janitor cleans the mess (t=%.1f)" % t_clean)
	_check(t_clean > 2.5, "cleaning takes at least 2.5 s of work")
	# pool_party doubles mess chance on the top deck.
	var w4: SimWorld = _world(&"med_3", _small_ship())
	var pool: RoomRuntime = _find_room(w4, &"pool")
	_near(w4.events.mess_mult(pool), 1.0, 0.001, "no multiplier without event")
	w4.force_event(&"pool_party")
	_near(w4.events.mess_mult(pool), 2.0, 0.001, "pool party x2 mess on top deck")
	_near(w4.events.mess_mult(_find_room(w4, &"buffet")), 1.0, 0.001, "interior unaffected")


func _t_breakdowns() -> void:
	_section("breakdowns and repairs")
	var w: SimWorld = _world(&"med_3", _small_ship(), {}, 2)
	var bf: RoomRuntime = _find_room(w, &"buffet")
	var hm: float = w.level.health_mult
	_check(bf.health >= 110.0 * hm * 0.8 - 0.01 and bf.health <= 110.0 * hm * 1.2 + 0.01, "health starts at 110 x knob +-20%% (%.1f)" % bf.health)
	_eq(_find_room(w, &"cabin").health, 0.0, "cabins never break")
	_eq(_find_room(w, &"deck_chairs").health, 0.0, "deck chairs never break")
	var br: Array = [0]
	var rp: Array = [0]
	w.room_broken.connect(func(uid: int) -> void: br[0] = uid)
	w.room_repaired.connect(func(uid: int) -> void: rp[0] = uid)
	# A user is ejected (-3 sat) when the room breaks.
	var g: Guest = _spawn(w)
	_check(g != null, "spawned")
	g.nv[SimConst.N_HUNGER] = 5.0
	g.satisfaction = 70.0
	var in_use: bool = false
	for i in 400:
		w.tick(SimConst.TICK)
		if g.mode == Guest.USE and w.room_by_uid(g.target_uid).def.id == &"buffet":
			in_use = true
			break
	_check(in_use, "guest using the buffet")
	var sat_before: float = g.satisfaction
	w.room_sim.break_room(w, bf)
	_check(bf.broken, "room broke")
	_eq(br[0], bf.uid, "room_broken signal")
	_eq(bf.users.size(), 0, "users ejected")
	_check(g.mode != Guest.USE, "guest no longer using")
	_near(g.satisfaction, sat_before - 3.0, 0.01, "-3 satisfaction on ejection")
	_eq(w.staff_sim.jobs.count_of(&"repair"), 1, "repair job posted")
	# Hold repairs: 0.4 progress per second.
	w.player_hold_repair(bf.uid, 1.0)
	_near(bf.repair_progress, 0.4, 0.001, "hold repairs 0.4/s")
	w.player_hold_repair(bf.uid, 1.0)
	_check(bf.broken, "not yet repaired at 0.8")
	w.player_hold_repair(bf.uid, 0.6)
	_check(not bf.broken, "repaired after 2.5 s of holding")
	_eq(rp[0], bf.uid, "room_repaired signal")
	_check(bf.health > 90.0 * w.level.health_mult, "health reset on repair")
	_eq(w.staff_sim.jobs.count_of(&"repair"), 0, "repair job removed")
	# Natural breakdown by health running out; wear per use.
	var w2: SimWorld = _world(&"med_3", _small_ship(), {}, 4)
	var bf2: RoomRuntime = _find_room(w2, &"buffet")
	bf2.health = 5.0
	_advance(w2, 4.0)
	_check(not bf2.broken, "not broken at 1 s of health")
	_advance(w2, 2.0)
	_check(bf2.broken, "room breaks when health reaches 0")
	var w3: SimWorld = _world(&"med_3", _small_ship(), {}, 4)
	var bf3: RoomRuntime = _find_room(w3, &"buffet")
	var h0: float = bf3.health
	w3.room_sim.on_use_finished(bf3)
	_near(bf3.health, h0 - 5.0, 0.001, "wear 5 s per buffet use")
	_eq(bf3.uses, 1, "uses counted")
	# Fairness: no more than 2 broken rooms per deck.
	var w4: SimWorld = _world(&"med_3", [[&"stairs", 0, 20], [&"toilets", 1, 0], [&"toilets", 1, 3], [&"toilets", 1, 6], [&"buffet", 1, 9]], {}, 4)
	for r in w4.rooms:
		if r.is_breakable():
			r.health = 1.0
	_advance(w4, 3.0)
	_eq(w4.room_sim.broken_on_deck(1), 2, "max 2 broken rooms per deck")
	var third: RoomRuntime = null
	for r in w4.rooms:
		if r.is_breakable() and not r.broken:
			third = r
	_check(third != null and third.health > 5.0 and third.health <= 10.0, "third retries in ~10 s (%.1f)" % (third.health if third != null else -1.0))
	# Mechanic repairs after ~5 s of work.
	var w5: SimWorld = _world(&"med_3", _small_ship(), {&"mechanic": 1}, 4)
	var bf5: RoomRuntime = _find_room(w5, &"buffet")
	w5.room_sim.break_room(w5, bf5)
	var t_fix: float = -1.0
	for i in 800:
		w5.tick(SimConst.TICK)
		if not bf5.broken:
			t_fix = w5.time
			break
	_check(t_fix > 5.0 and t_fix < 40.0, "mechanic repairs the room (t=%.1f)" % t_fix)


# ---------------------------------------------------------------------------------------------
# Staff
# ---------------------------------------------------------------------------------------------
func _staff_ship() -> Array:
	return [
		[&"stairs", 0, 20], [&"stairs", 1, 21], [&"stairs", 2, 20],
		[&"toilets", 0, 4], [&"buffet", 1, 4], [&"bar", 2, 4], [&"cabin", 1, 0],
	]


func _t_staff() -> void:
	_section("staff and jobs")
	var w: SimWorld = _world(&"med_3", _staff_ship(), {&"janitor": 2})
	_eq(w.staff.size(), 2, "two janitors")
	var s1: StaffMember = w.staff[0]
	_eq(s1.deck, 0, "crew spawns on deck 0")
	_near(s1.x, 1.5, 0.001, "crew spawns at x=1.5")
	_check(w.staff_sim.staff_by_id(w, s1.id) == s1 and w.staff_by_id(s1.id) == s1, "staff_by_id")
	# Nearest-first: a mess on deck 0 near the crew door is claimed before a mess on deck 2.
	var toilets: RoomRuntime = _find_room(w, &"toilets")
	var bar: RoomRuntime = _find_room(w, &"bar")
	var near_mess: Mess = w.problems.spawn_mess(w, toilets)
	var far_mess: Mess = w.problems.spawn_mess(w, bar)
	_advance(w, 1.0)
	var near_job: Job = w.staff_sim.jobs.find(&"mess", near_mess.id)
	var far_job: Job = w.staff_sim.jobs.find(&"mess", far_mess.id)
	_check(near_job != null and near_job.claimed_by != -1, "near job claimed")
	_check(far_job != null and far_job.claimed_by != -1 and far_job.claimed_by != near_job.claimed_by, "second janitor claims the other job")
	# With one janitor, the nearest job goes first.
	var w2: SimWorld = _world(&"med_3", _staff_ship(), {&"janitor": 1})
	var nm: Mess = w2.problems.spawn_mess(w2, _find_room(w2, &"toilets"))
	var fm: Mess = w2.problems.spawn_mess(w2, _find_room(w2, &"bar"))
	_advance(w2, 1.0)
	_eq(w2.staff_sim.jobs.find(&"mess", nm.id).claimed_by, w2.staff[0].id, "nearest mess claimed first")
	_eq(w2.staff_sim.jobs.find(&"mess", fm.id).claimed_by, -1, "far mess waits")
	# Ends up cleaning both.
	_advance(w2, 40.0)
	_eq(w2.messes.size(), 0, "janitor cleans both")
	_check(w2.staff[0].jobs_done >= 2, "jobs_done counted")
	# Janitors ignore breakdowns and mechanics ignore messes.
	var w3: SimWorld = _world(&"med_3", _staff_ship(), {&"janitor": 1, &"mechanic": 1})
	w3.room_sim.break_room(w3, _find_room(w3, &"toilets"))
	var mm: Mess = w3.problems.spawn_mess(w3, _find_room(w3, &"bar"))
	_advance(w3, 1.0)
	var jan: StaffMember = null
	var mech: StaffMember = null
	for s in w3.staff:
		if s.role == &"janitor":
			jan = s
		else:
			mech = s
	_eq(jan.job.kind, &"mess", "janitor takes the mess")
	_eq(mech.job.kind, &"repair", "mechanic takes the repair")
	_check(not w3.assign_staff(jan.id, &"repair", _find_room(w3, &"toilets").uid), "janitor can't be assigned a repair")
	_check(not w3.assign_staff(mech.id, &"mess", mm.id), "mechanic can't be assigned a mess")
	_check(not w3.assign_staff(999, &"mess", mm.id), "unknown staff rejected")
	_check(not w3.assign_staff(jan.id, &"mess", 9999), "unknown target rejected")
	# Player override steals a job from its holder and returns the old one to the queue.
	var w4: SimWorld = _world(&"med_3", _staff_ship(), {&"janitor": 2})
	var a_mess: Mess = w4.problems.spawn_mess(w4, _find_room(w4, &"toilets"))
	var b_mess: Mess = w4.problems.spawn_mess(w4, _find_room(w4, &"bar"))
	_advance(w4, 0.8)
	var ja: Job = w4.staff_sim.jobs.find(&"mess", a_mess.id)
	var jb: Job = w4.staff_sim.jobs.find(&"mess", b_mess.id)
	var holder_a: int = ja.claimed_by
	var holder_b: int = jb.claimed_by
	_check(holder_a != -1 and holder_b != -1 and holder_a != holder_b, "each janitor has a job")
	_check(w4.assign_staff(holder_a, &"mess", b_mess.id), "override accepted")
	_eq(jb.claimed_by, holder_a, "job stolen")
	_eq(ja.claimed_by, -1, "old job returned to the queue")
	_eq(w4.staff_by_id(holder_b).job, null, "previous holder dropped the job")
	_advance(w4, 1.0)
	_check(ja.claimed_by == holder_b, "freed janitor picks up the released job")
	_advance(w4, 40.0)
	_eq(w4.messes.size(), 0, "everything cleaned")
	# Idle staff patrol near their last job and don't wander off the ship.
	var w5: SimWorld = _world(&"med_3", _staff_ship(), {&"janitor": 1})
	_advance(w5, 30.0)
	_check(w5.staff[0].x >= 0.0 and w5.staff[0].x <= 24.0, "idle staff stay on the ship")
	_eq(w5.staff[0].state, &"idle", "idle with nothing to do")
	# Mid-voyage hire: 1.5x wage, respects max staff.
	var w6: SimWorld = _world(&"med_3", _staff_ship(), {&"janitor": 3})
	var money0: int = w6.money
	_check(w6.hire_staff_mid_voyage(&"mechanic"), "mid-voyage hire")
	_eq(w6.money, money0 - 90, "mechanic costs 1.5 x 60")
	_eq(w6.ledger()[&"hires"], 90, "ledger records hire")
	_check(not w6.hire_staff_mid_voyage(&"janitor"), "crew is full at max staff")
	var w7: SimWorld = _world(&"med_3", _staff_ship(), {})
	w7.economy.money = 20
	_check(not w7.hire_staff_mid_voyage(&"janitor"), "can't afford hire")


# ---------------------------------------------------------------------------------------------
# Sickness and ghosts
# ---------------------------------------------------------------------------------------------
func _t_sickness() -> void:
	_section("sickness")
	var w: SimWorld = _world(&"med_3", _small_ship() + [[&"medbay", 1, 6]], {}, 5)
	var gs: Array = [0]
	var cs: Array = [0]
	w.guest_got_sick.connect(func(id: int) -> void: gs[0] += 1)
	w.guest_cured.connect(func(id: int) -> void: cs[0] += 1)
	var g: Guest = _spawn(w)
	g.nv[SimConst.N_HUNGER] = 95.0
	w.problems.infect(w, g)
	_check(g.sick, "guest sick")
	_eq(g.mood, &"sick", "mood sick")
	_eq(gs[0], 1, "guest_got_sick signal")
	var cured_at: float = -1.0
	for i in 1200:
		w.tick(SimConst.TICK)
		if not g.sick:
			cured_at = w.time
			break
	_check(cured_at > 0.0 and cured_at < 60.0, "medbay cures quickly (t=%.1f)" % cured_at)
	_eq(cs[0], 1, "guest_cured signal")
	# Without a medbay the guest recovers after 75 s.
	var w2: SimWorld = _world(&"med_3", _small_ship(), {}, 5)
	var g2: Guest = _spawn(w2)
	w2.problems.infect(w2, g2)
	_advance(w2, 70.0)
	_check(g2.sick, "still sick at 70 s without a medbay")
	_advance(w2, 8.0)
	_check(not g2.sick, "recovered after ~75 s")
	# Spread: a sick guest infects neighbours within 1.2 cells.
	var w3: SimWorld = _world(&"med_3", [[&"stairs", 0, 20]], {}, 6)
	var src: Guest = _spawn(w3)
	var victims: Array[Guest] = []
	for i in 12:
		var v: Guest = _spawn(w3)
		victims.append(v)
	for gg in [src] + victims:
		gg.mode = Guest.WANDER
		gg.set_position(1, 5.0)
		gg.wander_pause = 1.0e6
		gg.eval_timer = 1.0e6
		gg.clear_route()
		for i in 4:
			gg.nv[i] = 100.0
	var spread: Array = [0]
	w3.guest_got_sick.connect(func(id: int) -> void: spread[0] += 1)
	w3.problems.infect(w3, src)
	src.sick_timer = 1000.0
	_advance(w3, 70.0)
	_check(spread[0] >= 3, "sickness spreads (%d infections incl. the source)" % spread[0])
	# Far-away guests stay healthy.
	var w4: SimWorld = _world(&"med_3", [[&"stairs", 0, 20]], {}, 6)
	var s4: Guest = _spawn(w4)
	var far: Guest = _spawn(w4)
	for gg in [s4, far]:
		gg.mode = Guest.WANDER
		gg.wander_pause = 1.0e6
		gg.eval_timer = 1.0e6
		for i in 4:
			gg.nv[i] = 100.0
	s4.set_position(1, 2.0)
	far.set_position(1, 15.0)
	w4.problems.infect(w4, s4)
	s4.sick_timer = 1000.0
	_advance(w4, 60.0)
	_check(not far.sick, "distant guests are not infected")
	# Buffet use can cause food poisoning (1.5%).
	var w5: SimWorld = _world(&"med_3", _small_ship(), {}, 9)
	var made: int = 0
	var buf: RoomRuntime = _find_room(w5, &"buffet")
	for i in 1000:
		var gg: Guest = _spawn(w5)
		gg.mode = Guest.USE
		gg.target_uid = buf.uid
		buf.users.append(gg.id)
		gg.use_rates = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		gg.use_timer = 0.0
		w5.guest_sim._finish_use(w5, gg)
		if gg.sick:
			made += 1
	_check(made >= 5 and made <= 30, "buffet food poisoning ~1.5%% (%d/1000)" % made)


func _t_ghosts() -> void:
	_section("ghosts")
	var w: SimWorld = _world(&"underworld_1", [[&"stairs", 0, 20], [&"cabin", 1, 0]], {}, 3)
	var sp: Array = [0]
	var bn: Array = [0]
	w.ghost_spawned.connect(func(id: int) -> void: sp[0] += 1)
	w.ghost_banished.connect(func(id: int) -> void: bn[0] = id)
	_advance(w, 90.0)
	_check(sp[0] >= 2 and sp[0] <= 4, "ghosts spawn every 25-40 s (%d in 90 s)" % sp[0])
	# Spawn one by hand, check drift and hit effects.
	var w2: SimWorld = _world(&"underworld_1", [[&"stairs", 0, 20], [&"cabin", 1, 0]], {}, 3)
	var g: Guest = _spawn(w2)
	g.mode = Guest.QUEUE
	var q_room: RoomRuntime = _find_room(w2, &"cabin")
	g.target_uid = q_room.uid
	g.patience = 20.0
	g.set_position(2, 10.0)
	g.queue_x = 10.0
	var gh: Ghost = w2.problems.spawn_ghost(w2)
	gh.deck = 2
	gh.deck_f = 2.0
	gh.dir = 1
	gh.x = 5.0
	gh.prev_x = 5.0
	for i in 4:
		g.nv[i] = 30.0
	var sat0: float = g.satisfaction
	_advance(w2, 10.0)
	_check(gh.x > 5.0 + 10.0, "ghost drifts at 1.2 cells/s (x=%.1f)" % gh.x)
	_check(g.satisfaction < sat0 - 2.0, "ghost pass costs 4 satisfaction (%.1f -> %.1f)" % [sat0, g.satisfaction])
	_check(g.patience < 20.0 - 10.0 - 6.0, "ghost pass takes 8 s of patience (%.1f)" % g.patience)
	# Banish.
	var gh2: Ghost = w2.problems.spawn_ghost(w2)
	w2.player_banish_ghost(gh2.id)
	_check(not w2.ghosts.has(gh2), "ghost banished")
	_eq(w2.metrics["banished"], 1, "banish counted")
	# Ghost leaves the far edge.
	var w3: SimWorld = _world(&"underworld_1", [[&"stairs", 0, 20]], {}, 3)
	var gh3: Ghost = w3.problems.spawn_ghost(w3)
	gh3.x = 30.0
	gh3.dir = 1
	_advance(w3, 10.0)
	_check(not w3.ghosts.has(gh3), "unbanished ghost leaves the far edge")
	# Non-underworld levels have no ghosts.
	var w4: SimWorld = _world(&"med_3", [[&"stairs", 0, 20]])
	_advance(w4, 120.0)
	_eq(w4.ghosts.size(), 0, "no ghosts in the Mediterranean")


# ---------------------------------------------------------------------------------------------
# Economy
# ---------------------------------------------------------------------------------------------
func _t_economy() -> void:
	_section("economy")
	var lvl: LevelDef = _blank_level(&"med_3")
	lvl.waves = [{"t": 0.0, "count": 6}]
	var w: SimWorld = _world(&"med_3", _small_ship(), {&"janitor": 1}, 1, lvl)
	var ch: Array = []
	w.money_changed.connect(func(m: int, d: int, reason: StringName) -> void: ch.append([m, d, reason]))
	_eq(w.money, 1000, "starts with the budget")
	_advance(w, 5.0)
	_eq(w.guests.size(), 6, "six guests boarded")
	_eq(w.ledger()[&"tickets"], 6 * lvl.ticket_price, "tickets paid per guest")
	_eq(w.money, 1000 + 6 * lvl.ticket_price - int(w.ledger()[&"upkeep"]), "money = start + tickets - upkeep so far")
	_advance(w, 120.0)
	var led: Dictionary = w.ledger()
	_check(led[&"spending"] > 0, "guests spend money")
	_check(led[&"upkeep"] > 0, "upkeep charged continuously")
	var upkeep_rate: float = w.economy.upkeep_per_minute
	_near(float(led[&"upkeep"]), upkeep_rate * 125.0 / 60.0, 4.0, "upkeep = rooms x rate")
	_eq(w.money, 1000 + int(led[&"tickets"]) + int(led[&"spending"]) - int(led[&"upkeep"]) - int(led[&"hires"]), "ledger balances with money")
	_eq(w.economy.profit(), w.money - 1000, "profit = end - start")
	var kinds: Dictionary = {}
	for c in ch:
		kinds[c[2]] = true
	_check(kinds.has(&"tickets") and kinds.has(&"spending") and kinds.has(&"upkeep"), "money_changed reasons (%s)" % str(kinds.keys()))
	var sum_delta: int = 0
	for c in ch:
		sum_delta += int(c[1])
	_eq(sum_delta, w.money - 1000, "money_changed deltas add up to the money change")
	_check(int(led[&"wages"]) == 40, "wages recorded informationally (janitor)")
	# Room spend per use: bar pays 9.
	var w2: SimWorld = _world(&"med_3", _small_ship())
	var bar: RoomRuntime = _find_room(w2, &"bar")
	var g: Guest = _spawn(w2)
	var m0: int = w2.money
	g.mode = Guest.USE
	g.target_uid = bar.uid
	bar.users.append(g.id)
	g.use_timer = 0.0
	w2.guest_sim._finish_use(w2, g)
	_eq(w2.money - m0, 9, "bar use pays 9")
	_eq(w2.ledger()[&"spending"], 9, "spending ledger")
	_eq(w2.stats()["served"], 1, "served counter")


# ---------------------------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------------------------
func _event_ship() -> Array:
	return _small_ship() + [[&"cinema", 2, 14], [&"restaurant", 1, 14], [&"medbay", 1, 6]]


func _t_events() -> void:
	_section("events")
	var w: SimWorld = _world(&"med_3", _event_ship(), {}, 3)
	var started: Array = []
	var ended: Array = []
	w.event_started.connect(func(id: StringName) -> void: started.append(id))
	w.event_ended.connect(func(id: StringName) -> void: ended.append(id))
	var guests: Array[Guest] = []
	for i in 8:
		guests.append(_spawn(w))
	for g in guests:
		for i in 4:
			g.nv[i] = 95.0
	var cinema: RoomRuntime = _find_room(w, &"cinema")
	var base_appeal: float = cinema.appeal_now
	w.force_event(&"film_night")
	_eq(started, [&"film_night"], "event_started")
	_near(cinema.appeal_now, base_appeal * 2.5, 0.001, "film night: cinema appeal x2.5")
	for g in guests:
		_check(g.nv[SimConst.N_FUN] <= 45.0, "film night caps fun at 45")
		_near(g.nv[SimConst.N_HUNGER], 95.0, 0.001, "film night leaves hunger alone")
	_eq(w.active_events().size(), 1, "active_events lists it")
	_check(w.active_events()[0]["time_left"] > 55.0 and w.active_events()[0]["def"] is EventDef, "active event has def and time_left")
	_advance(w, 61.0)
	_eq(w.active_events().size(), 0, "film night expires after 60 s")
	_eq(ended, [&"film_night"], "event_ended")
	_near(cinema.appeal_now, base_appeal, 0.001, "appeal restored")
	# lunch_rush: hunger capped at 20, instant.
	for g in guests:
		g.nv[SimConst.N_HUNGER] = 90.0
	w.force_event(&"lunch_rush")
	for g in guests:
		_check(g.nv[SimConst.N_HUNGER] <= 20.0, "lunch rush caps hunger at 20")
	_eq(w.active_events().size(), 0, "lunch rush is instant")
	_check(ended.has(&"lunch_rush"), "instant events still emit event_ended")
	# Everyone goes for food: queues form at the buffet.
	_advance(w, 12.0)
	var buffet: RoomRuntime = _find_room(w, &"buffet")
	var rest: RoomRuntime = _find_room(w, &"restaurant")
	_check(buffet.users.size() + buffet.queue.size() + rest.users.size() + rest.queue.size() + buffet.incoming + rest.incoming >= 4, "lunch rush sends guests to food")
	# food_poisoning: 3 guests get sick, nearest to food first.
	var w2: SimWorld = _world(&"med_3", _event_ship(), {}, 3)
	for i in 8:
		_spawn(w2)
	_advance(w2, 2.0)
	w2.force_event(&"food_poisoning")
	_eq(w2.problems.sick_count(w2), 3, "food poisoning sickens 3 guests")
	# power_surge: 2 breakable rooms break now.
	var w3: SimWorld = _world(&"med_3", _event_ship(), {}, 3)
	w3.force_event(&"power_surge")
	var broken: int = 0
	for r in w3.rooms:
		if r.broken:
			broken += 1
	_eq(broken, 2, "power surge breaks 2 rooms")
	# captains_dinner.
	var w4: SimWorld = _world(&"med_3", _event_ship(), {}, 3)
	var rest4: RoomRuntime = _find_room(w4, &"restaurant")
	var ba: float = rest4.appeal_now
	w4.force_event(&"captains_dinner")
	_near(rest4.appeal_now, ba * 3.0, 0.001, "captain's dinner: restaurant appeal x3")
	_near(w4.events.full_room_bonus(rest4), 10.0, 0.001, "+10 satisfaction when full")
	_near(w4.events.full_room_bonus(_find_room(w4, &"buffet")), 0.0, 0.001, "no bonus elsewhere")
	for i in rest4.cap:
		var gu: Guest = _spawn(w4)
		gu.mode = Guest.USE
		gu.target_uid = rest4.uid
		rest4.users.append(gu.id)
		gu.use_timer = 0.0
	var finisher: Guest = w4.guest_by_id(rest4.users[0])
	finisher.satisfaction = 50.0
	w4.guest_sim._finish_use(w4, finisher)
	_check(finisher.satisfaction >= 50.0 + 4.0 + 10.0 - 0.01, "captain's dinner bonus applied when room is full (%.1f)" % finisher.satisfaction)
	# pool_party: top-deck rooms x1.5.
	var w5: SimWorld = _world(&"med_3", _event_ship(), {}, 3)
	var pool: RoomRuntime = _find_room(w5, &"pool")
	var pa: float = pool.appeal_now
	w5.force_event(&"pool_party")
	_near(pool.appeal_now, pa * 1.5, 0.001, "pool party: top-deck appeal x1.5")
	# heat_wave: hygiene decay x1.8 and pool x2.
	var w6: SimWorld = _world(&"med_3", _event_ship(), {}, 3)
	var pool6: RoomRuntime = _find_room(w6, &"pool")
	var pa6: float = pool6.appeal_now
	var hg: Guest = _spawn(w6)
	w6.force_event(&"heat_wave")
	_near(pool6.appeal_now, pa6 * 2.0, 0.001, "heat wave: pool appeal x2")
	_near(w6.events.hygiene_mult(), 1.8, 0.001, "heat wave hygiene x1.8")
	hg.nv[SimConst.N_HYGIENE] = 90.0
	hg.mode = Guest.WANDER
	hg.wander_pause = 1.0e6
	hg.eval_timer = 1.0e6
	_advance(w6, 10.0)
	_near(90.0 - hg.nv[SimConst.N_HYGIENE], 10.0 * 0.6 * 1.25 * 1.8 * w6.level.decay_mult, 1.8, "hygiene decays 1.8x faster in a heat wave")
	# northern_lights (Arctic): top-deck rush, fun restored on the top deck, cold suspended.
	var w7: SimWorld = _world(&"arctic_1", [[&"stairs", 0, 20], [&"stairs", 1, 21], [&"stairs", 2, 20], [&"stairs", 3, 21], [&"deck_chairs", 4, 2]], {}, 3)
	var nl: Guest = _spawn(w7)
	for i in 4:
		nl.nv[i] = 60.0
	nl.mode = Guest.WANDER
	nl.set_position(4, 10.0)
	nl.wander_pause = 1.0e6
	nl.eval_timer = 1.0e6
	nl.clear_route()
	w7.force_event(&"northern_lights")
	_check(w7.events.top_deck_rush and w7.events.cold_suspended, "northern lights: rush and no cold")
	var fun0: float = nl.nv[SimConst.N_FUN]
	var sat0: float = nl.satisfaction
	_advance(w7, 10.0)
	_check(nl.nv[SimConst.N_FUN] > fun0 - 10.0 + 10.0 * 1.0, "top-deck wanderers regain fun (1.5/s) (%.1f -> %.1f)" % [fun0, nl.nv[SimConst.N_FUN]])
	_check(nl.satisfaction >= sat0 - 0.5, "no cold drain during northern lights")
	# haunting (Underworld): 4 ghosts at once.
	var w8: SimWorld = _world(&"underworld_1", [[&"stairs", 0, 20]], {}, 3)
	var before: int = w8.ghosts.size()
	w8.force_event(&"haunting")
	_eq(w8.ghosts.size(), before + 4, "haunting spawns 4 ghosts")
	# Scheduled events fire at their time.
	var lvl9: LevelDef = _blank_level(&"med_5")
	lvl9.scheduled_events = [{"t": 10.0, "event": &"lunch_rush"}, {"t": 20.0, "event": &"film_night"}]
	var w9: SimWorld = _world(&"med_3", _event_ship(), {}, 3, lvl9)
	var fired: Array = []
	w9.event_started.connect(func(id: StringName) -> void: fired.append(id))
	var fired_at: Array = []
	for i in 250:
		var n_before: int = fired.size()
		w9.tick(SimConst.TICK)
		if fired.size() > n_before:
			fired_at.append(w9.time)
	_eq(fired.size(), 2, "two scheduled events fired")
	_check(fired[0] == &"lunch_rush" and absf(fired_at[0] - 10.0) < 0.3, "first at t=10")
	_check(fired[1] == &"film_night" and absf(fired_at[1] - 20.0) < 0.3, "second at t=20")
	# Scheduled events with nothing to act on (no cinema / restaurant / pool / food room) are skipped: no banner, no event.
	var lvl9b: LevelDef = _blank_level(&"med_5")
	lvl9b.scheduled_events = [{"t": 5.0, "event": &"film_night"}, {"t": 6.0, "event": &"captains_dinner"}, {"t": 7.0, "event": &"pool_party"},
			{"t": 8.0, "event": &"food_poisoning"}, {"t": 9.0, "event": &"lunch_rush"}]
	var w9b: SimWorld = _world(&"med_3", [[&"stairs", 0, 20], [&"cabin", 0, 2]], {}, 3, lvl9b)
	var fired9b: Array = []
	w9b.event_started.connect(func(id: StringName) -> void: fired9b.append(id))
	_advance(w9b, 15.0)
	_eq(fired9b, [&"lunch_rush"], "scheduled film night / dinner / pool party / food poisoning are skipped without their rooms")
	_eq(int(w9b.metrics["events"]), 1, "skipped scheduled events are not counted")
	var w9c: SimWorld = _world(&"med_3", _event_ship() + [[&"pool", 2, 2]], {}, 3, lvl9b)
	var fired9c: Array = []
	w9c.event_started.connect(func(id: StringName) -> void: fired9c.append(id))
	_advance(w9c, 15.0)
	_eq(fired9c, [&"film_night", &"captains_dinner", &"pool_party", &"food_poisoning", &"lunch_rush"], "with the rooms present every scheduled event fires")
	# Power surge never exceeds the per-deck broken cap, even when the random picks all land on a full deck.
	var w9d: SimWorld = _world(&"med_3", [[&"stairs", 0, 20], [&"toilets", 1, 0], [&"toilets", 1, 3], [&"toilets", 1, 6], [&"buffet", 1, 9]], {}, 4)
	w9d.force_event(&"power_surge")
	_eq(w9d.room_sim.broken_on_deck(1), 2, "surge breaks two rooms on a deck")
	w9d.force_event(&"power_surge")
	_eq(w9d.room_sim.broken_on_deck(1), 2, "a second surge cannot break a third room on the same deck")
	# Random events fire periodically, never two timed events at once.
	var lvl10: LevelDef = _blank_level(&"med_5")
	lvl10.random_event_interval = 30.0
	var w10: SimWorld = _world(&"med_3", _event_ship(), {}, 8, lvl10)
	for i in 6:
		_spawn(w10)
	var n_started: Array = [0]
	var max_concurrent: Array = [0]
	w10.event_started.connect(func(id: StringName) -> void: n_started[0] += 1)
	for i in 2400:
		w10.tick(SimConst.TICK)
		var timed: int = 0
		for a in w10.active_events():
			if (a["def"] as EventDef).duration > 0.0:
				timed += 1
		max_concurrent[0] = maxi(max_concurrent[0], timed)
	_check(n_started[0] >= 3 and n_started[0] <= 12, "random events fire (%d in 240 s at 30 s interval)" % n_started[0])
	_check(max_concurrent[0] <= 1, "never two timed events at once")
	# Destination-locked events are never picked in the wrong destination.
	var all_ok: bool = true
	for i in 200:
		var pick: StringName = w10.events._pick_random(w10)
		var d: EventDef = ContentStore.event(pick)
		if d != null and d.destination_lock != &"" and d.destination_lock != &"med":
			all_ok = false
	_check(all_ok, "random picks respect destination locks")


# ---------------------------------------------------------------------------------------------
# Stars and mutiny
# ---------------------------------------------------------------------------------------------
func _t_stars() -> void:
	_section("star scoring")
	var lvl: LevelDef = _blank_level(&"med_3")
	lvl.duration = 30.0
	lvl.star_goals = [
		{"type": "rating", "value": 60},
		{"type": "profit", "value": 100},
		{"type": "served", "value": 2},
	]
	var w: SimWorld = _world(&"med_3", _small_ship(), {}, 1, lvl)
	var res: Array = []
	w.voyage_ended.connect(func(r: Dictionary) -> void: res.append(r))
	for i in 3:
		_spawn(w)
	_advance(w, 29.0)
	_check(not w.finished, "not finished before the duration")
	_advance(w, 2.0)
	_check(w.finished, "finished at the duration")
	_eq(res.size(), 1, "voyage_ended emitted exactly once")
	_advance(w, 5.0)
	_eq(res.size(), 1, "no second voyage_ended")
	var r: Dictionary = res[0]
	_eq(r["goals"].size(), 3, "three goals in result")
	_eq(r["level_id"], &"med_3", "level id in result")
	_check(r.has("ledger") and r.has("guests_total") and r.has("guests_lost") and r.has("served") and r.has("mutiny") and r.has("profit") and r.has("rating") and r.has("stars"), "result has all keys")
	var met: int = 0
	for gd in r["goals"]:
		if gd["met"]:
			met += 1
	_eq(r["stars"], met, "stars = goals met")
	_check(r["goals"][0]["met"] == (r["rating"] >= 60.0), "rating goal evaluated")
	_check(r["goals"][1]["met"] == (r["profit"] >= 100), "profit goal evaluated")
	# Direct goal logic.
	var lvl2: LevelDef = _blank_level(&"med_3")
	lvl2.duration = 20.0
	lvl2.star_goals = [{"type": "rating", "value": 50}, {"type": "no_lost_guests"}, {"type": "profit", "value": 1000000}]
	var w2: SimWorld = _world(&"med_3", _small_ship(), {}, 1, lvl2)
	_spawn(w2)
	_advance(w2, 21.0)
	_eq(w2.result["stars"], 2, "rating + no_lost_guests met, impossible profit not")
	_eq(w2.result["goals"][2]["met"], false, "impossible profit goal unmet")
	# A lost guest fails no_lost_guests.
	var w3: SimWorld = _world(&"med_3", [[&"stairs", 0, 20]], {}, 1, lvl2)
	var g3: Guest = _spawn(w3)
	_advance(w3, 1.0)
	for i in 4:
		g3.nv[i] = 0.0
	g3.satisfaction = 2.0
	_advance(w3, 19.0)
	_eq(w3.result["goals"][1]["met"], false, "no_lost_guests fails when a guest storms off")
	_eq(w3.result["guests_lost"], 1, "guests_lost counted")
	# Waves: guests spawn spread over 4 s per wave; wave_started fires.
	var lvl4: LevelDef = _blank_level(&"med_3")
	lvl4.waves = [{"t": 5.0, "count": 8}, {"t": 20.0, "count": 4}]
	var w4: SimWorld = _world(&"med_3", _small_ship(), {}, 1, lvl4)
	var waves: Array = []
	w4.wave_started.connect(func(i: int, c: int) -> void: waves.append([i, c]))
	_advance(w4, 4.0)
	_eq(w4.guests.size(), 0, "nobody before the first wave")
	_advance(w4, 2.0)
	_check(w4.guests.size() >= 1 and w4.guests.size() < 8, "first wave trickles in over 4 s")
	_advance(w4, 4.0)
	_eq(w4.guests.size(), 8, "first wave complete")
	_advance(w4, 15.0)
	_eq(w4.guests.size(), 12, "second wave complete")
	_eq(waves.size(), 2, "wave_started twice")
	_check(waves[0][0] == 0 and waves[0][1] == 8, "first wave signal")
	# Archetype mix follows the weights.
	var lvl5: LevelDef = _blank_level(&"med_3")
	lvl5.waves = [{"t": 0.0, "count": 400}]
	lvl5.archetype_weights = {&"gamer": 0.75, &"film_buff": 0.25}
	var w5: SimWorld = _world(&"med_3", _small_ship(), {}, 1, lvl5)
	_advance(w5, 5.0)
	var gam: int = 0
	for g in w5.guests:
		if g.archetype.id == &"gamer":
			gam += 1
	_check(gam > 400 * 0.65 and gam < 400 * 0.85, "archetype weights respected (%d gamers of 400)" % gam)


func _t_mutiny() -> void:
	_section("mutiny")
	var lvl: LevelDef = _blank_level(&"arctic_1")
	lvl.waves = [{"t": 0.0, "count": 6}]
	var w: SimWorld = _world(&"arctic_1", [[&"stairs", 0, 20], [&"cabin", 1, 0], [&"cabin", 1, 2]], {}, 1, lvl)
	var warns: Array = []
	var cleared: Array = [0]
	var ended: Array = []
	w.mutiny_warning.connect(func(s: float) -> void: warns.append(s))
	w.mutiny_cleared.connect(func() -> void: cleared[0] += 1)
	w.voyage_ended.connect(func(r: Dictionary) -> void: ended.append(r))
	_advance(w, 6.0)
	_check(not w.mutiny_active, "no mutiny at the start")
	# Hold satisfaction at 10% for 20 s: warning, then recover: cleared.
	for i in 200:
		for g in w.guests:
			g.satisfaction = 10.0
			for k in 4:
				g.nv[k] = 100.0
		w.tick(SimConst.TICK)
	_check(w.mutiny_active, "mutiny countdown active below 20%")
	_check(warns.size() >= 15, "mutiny_warning emitted each second (%d)" % warns.size())
	_check(w.mutiny_time_left < 11.0 and w.mutiny_time_left > 9.0, "countdown ~10 s left (%.1f)" % w.mutiny_time_left)
	for g in w.guests:
		g.satisfaction = 80.0
	_advance(w, 1.0)
	_check(not w.mutiny_active and cleared[0] == 1, "mutiny_cleared when rating recovers")
	_check(not w.finished, "no mutiny yet")
	# Stay below for 30 s -> voyage ends with mutiny and 0 stars.
	for i in 330:
		for g in w.guests:
			g.satisfaction = 10.0
			for k in 4:
				g.nv[k] = 100.0
		w.tick(SimConst.TICK)
		if w.finished:
			break
	_check(w.finished, "voyage ended by mutiny")
	_eq(ended.size(), 1, "voyage_ended once")
	_check(ended[0]["mutiny"], "result flags mutiny")
	_eq(ended[0]["stars"], 0, "mutiny = 0 stars")
	_check(w.time < 70.0, "mutiny ended the voyage early (t=%.1f)" % w.time)
	# Disabled on the tutorial.
	var tl: LevelDef = _blank_level(&"med_1")
	tl.waves = [{"t": 0.0, "count": 4}]
	_check(not tl.mutiny_enabled, "tutorial has mutiny off")
	var wt: SimWorld = _world(&"med_1", [[&"stairs", 0, 20], [&"cabin", 1, 0]], {}, 1, tl)
	for i in 450:
		for g in wt.guests:
			g.satisfaction = 5.0
			for k in 4:
				g.nv[k] = 100.0
		wt.tick(SimConst.TICK)
	_check(not wt.finished and not wt.mutiny_active, "no mutiny on the tutorial level")


# ---------------------------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------------------------
func _snapshot(w: SimWorld) -> String:
	var parts: PackedStringArray = []
	for g in w.guests:
		parts.append("%d:%s:%.3f:%.3f:%.2f" % [g.id, g.state, g.x, g.deck_f, g.satisfaction])
	for r in w.rooms:
		parts.append("%d:%d:%d:%.2f" % [r.uid, r.users.size(), r.queue.size(), r.health])
	return "|".join(parts) + "|" + str(w.money)


func _t_determinism() -> void:
	_section("determinism")
	var lvl: LevelDef = ContentStore.level(&"arctic_2")
	var port := AutoBuilder.build(lvl)
	var a: Dictionary = SimRunner.run(lvl, port, 42, &"active")
	var b: Dictionary = SimRunner.run(lvl, port, 42, &"active")
	_eq(a["rating"], b["rating"], "same seed gives the same rating")
	_eq(a["profit"], b["profit"], "same seed gives the same profit")
	_eq(a["served"], b["served"], "same seed gives the same served count")
	_eq(str(a["metrics"]), str(b["metrics"]), "same seed gives identical metrics")
	var c: Dictionary = SimRunner.run(lvl, port, 43, &"active")
	_check(str(c["metrics"]) != str(a["metrics"]) or c["profit"] != a["profit"], "different seeds differ")
	# Mid-run snapshots match tick for tick.
	var w1: SimWorld = port.create_world(7)
	var w2: SimWorld = port.create_world(7)
	var same: bool = true
	for i in 1200:
		w1.tick(SimConst.TICK)
		w2.tick(SimConst.TICK)
		if i % 100 == 0 and _snapshot(w1) != _snapshot(w2):
			same = false
			break
	_check(same, "world snapshots identical tick for tick")
	# Layout duplicate does not alias.
	var l2: ShipLayout = port.layout.duplicate()
	l2.rooms[0].x = 17
	_check(port.layout.rooms[0].x != 17, "ShipLayout.duplicate is deep")


# ---------------------------------------------------------------------------------------------
# AutoBuilder / AutoPlayer
# ---------------------------------------------------------------------------------------------
func _t_autobuilder() -> void:
	_section("autobuilder")
	for lvl in ContentStore.campaign():
		var port := AutoBuilder.build(lvl)
		var v: Dictionary = port.validate()
		_eq(v["errors"].size(), 0, "%s autobuild valid (%s)" % [lvl.id, str(v["errors"])])
		_check(port.budget >= 0, "%s within budget (%d left)" % [lvl.id, port.budget])
		_check(port.staff_total() <= port.hull.max_staff, "%s crew within hull limit" % lvl.id)
		_check(port.staff_total() >= 1, "%s has crew" % lvl.id)
		var u: Dictionary = port.utilities()
		_check(u["power_used"] <= u["power_cap"] and u["water_used"] <= u["water_cap"], "%s utilities ok" % lvl.id)
		var beds: int = 0
		var has_fun: bool = false
		for r in port.layout.rooms:
			if r.def.id == &"cabin":
				beds += r.capacity()
			if r.def.category == &"fun":
				has_fun = true
			_check(r.def.is_available(lvl.campaign_index, lvl.destination), "%s only uses unlocked rooms (%s)" % [lvl.id, r.def.id])
		_check(beds >= lvl.total_guests(), "%s has enough beds (%d for %d)" % [lvl.id, beds, lvl.total_guests()])
		_check(has_fun and port.layout.count_of(&"buffet") + port.layout.count_of(&"restaurant") >= 1 and port.layout.count_of(&"toilets") >= 1, "%s has food, toilets and fun" % lvl.id)
		# Presets survive.
		for p in lvl.preset_rooms:
			var found: PlacedRoom = port.layout.room_at(int(p["deck"]), int(p["x"]))
			_check(found != null and found.def.id == StringName(p["room"]) and found.locked == bool(p["locked"]), "%s keeps preset %s" % [lvl.id, p["room"]])
	# Cabins cluster around the stairs; crew is small relative to ship size.
	for lvl2 in ContentStore.campaign():
		var port2 := AutoBuilder.build(lvl2)
		var stairs_x: float = 0.0
		var n_st: int = 0
		for r in port2.layout.rooms:
			if r.is_stairs():
				stairs_x += float(r.x)
				n_st += 1
		stairs_x /= float(maxi(n_st, 1))
		var dist_sum: float = 0.0
		var n_cab: int = 0
		for r in port2.layout.rooms:
			if r.def.id == &"cabin" and not r.locked:
				dist_sum += absf(float(r.x) - stairs_x)
				n_cab += 1
		if n_cab > 0:
			_check(dist_sum / float(n_cab) <= 9.0, "%s: cabins cluster near the stairs (mean %.1f cells)" % [lvl2.id, dist_sum / float(n_cab)])
		var crew: Dictionary = port2.staff_counts()
		_check(int(crew.get(&"janitor", 0)) <= 1 + lvl2.total_guests() / 36, "%s: small janitor crew" % lvl2.id)
		_check(int(crew.get(&"mechanic", 0)) <= 2, "%s: at most two mechanics" % lvl2.id)
	# Budget fraction is honoured.
	var lv: LevelDef = ContentStore.level(&"arctic_3")
	var half := AutoBuilder.build(lv, -1, {"budget_frac": 0.5})
	_check(half.budget >= lv.budget * 0.5 - 5, "budget_frac 0.5 leaves at least half unspent (%d)" % half.budget)
	_eq(half.validate()["errors"].size(), 0, "half-budget build is valid")
	# Sensible beats poor.
	var sens_sum: float = 0.0
	var poor_sum: float = 0.0
	for id in [&"med_4", &"arctic_2"]:
		var l: LevelDef = ContentStore.level(id)
		var sens := AutoBuilder.build(l)
		var poor := AutoBuilder.build(l, -1, {"style": &"poor"})
		_eq(poor.validate()["errors"].size(), 0, "poor build is still valid")
		for s in 2:
			sens_sum += float(SimRunner.run(l, sens, 100 + s, &"active")["rating"])
			poor_sum += float(SimRunner.run(l, poor, 100 + s, &"active")["rating"])
	_check(sens_sum > poor_sum + 4.0 * 2.0, "a planned layout beats a scattered one (%.1f vs %.1f)" % [sens_sum / 4.0, poor_sum / 4.0])


func _t_autoplayer() -> void:
	_section("autoplayer")
	var w: SimWorld = _world(&"med_3", _staff_ship(), {})
	var ap := AutoPlayer.new(w, &"active", 3)
	var m: Mess = w.problems.spawn_mess(w, _find_room(w, &"buffet"))
	var t_clean: float = -1.0
	for i in 100:
		w.tick(SimConst.TICK)
		ap.tick(SimConst.TICK)
		if w.messes.is_empty():
			t_clean = w.time
			break
	_check(t_clean >= 1.5, "active player waits a reaction delay (t=%.1f)" % t_clean)
	_check(t_clean > 0.0 and t_clean <= 4.0, "active player cleans a mess with 3 clicks (t=%.1f)" % t_clean)
	_eq(w.metrics["player_clicks"], 3, "three clicks")
	# Passive does nothing.
	var w2: SimWorld = _world(&"med_3", _staff_ship(), {})
	var pp := AutoPlayer.new(w2, &"passive", 3)
	w2.problems.spawn_mess(w2, _find_room(w2, &"buffet"))
	w2.room_sim.break_room(w2, _find_room(w2, &"toilets"))
	for i in 200:
		w2.tick(SimConst.TICK)
		pp.tick(SimConst.TICK)
	_eq(w2.messes.size(), 1, "passive leaves messes alone")
	_eq(w2.metrics["player_clicks"], 0, "no clicks")
	_check(_find_room(w2, &"toilets").broken, "passive doesn't repair")
	# Active holds repairs and banishes ghosts, rate limited to ~3 clicks/s.
	var w3: SimWorld = _world(&"underworld_1", _staff_ship(), {})
	var ap3 := AutoPlayer.new(w3, &"active", 5)
	for i in 6:
		w3.problems.spawn_ghost(w3)
	w3.room_sim.break_room(w3, _find_room(w3, &"toilets"))
	var banished_at: Array = []
	for i in 80:
		w3.tick(SimConst.TICK)
		ap3.tick(SimConst.TICK)
	_check(w3.metrics["banished"] >= 1 and w3.metrics["banished"] <= 6, "ghosts banished at a limited rate (%d)" % w3.metrics["banished"])
	_check(w3.metrics["banished"] <= 3 * 8 + 1, "click rate limit")
	for i in 120:
		w3.tick(SimConst.TICK)
		ap3.tick(SimConst.TICK)
	_check(not _find_room(w3, &"toilets").broken, "active player repaired the room")
	_check(w3.metrics["player_repair_s"] > 1.0, "repair was done by holding")


# ---------------------------------------------------------------------------------------------
# Misc API
# ---------------------------------------------------------------------------------------------
func _t_pick_and_api() -> void:
	_section("pick_at and stats")
	var w: SimWorld = _world(&"med_3", _small_ship(), {&"janitor": 1})
	var buffet: RoomRuntime = _find_room(w, &"buffet")
	var p: Dictionary = w.pick_at(buffet.deck, buffet.x + 1.0)
	_eq(p["kind"], "room", "pick a room")
	_eq(p["id"], buffet.uid, "pick the buffet")
	_eq(w.pick_at(2, 20.5)["kind"], "", "nothing at empty corridor")
	var m: Mess = w.problems.spawn_mess(w, buffet)
	_eq(w.pick_at(m.deck, m.x)["kind"], "mess", "pick a mess over the room")
	var gh: Ghost = w.problems.spawn_ghost(w)
	gh.deck = m.deck
	gh.x = m.x
	_eq(w.pick_at(m.deck, m.x)["kind"], "ghost", "ghost has top priority")
	w.ghosts.clear()
	var g: Guest = _spawn(w)
	_advance(w, 2.0)
	g.set_position(2, 14.5)
	g.mode = Guest.WANDER
	g.wander_pause = 1000.0
	g.eval_timer = 1000.0
	g.clear_route()
	_eq(w.pick_at(2, 14.5)["kind"], "guest", "pick a guest")
	_eq(w.pick_at(2, 14.5)["id"], g.id, "right guest")
	var s: StaffMember = w.staff[0]
	s.set_position(2, 16.5)
	_eq(w.pick_at(2, 16.5)["kind"], "staff", "pick staff")
	_check(w.guest_by_id(g.id) == g and w.room_by_uid(buffet.uid) == buffet and w.mess_by_id(m.id) == m, "id lookups")
	_check(w.guest_by_id(999) == null and w.room_by_uid(999) == null and w.mess_by_id(999) == null and w.ghost_by_id(999) == null, "missing ids give null")
	var st: Dictionary = w.stats()
	for k in ["rating", "money", "guests_on_board", "guests_total", "lost", "served", "problems"]:
		_check(st.has(k), "stats has %s" % k)
	_eq(st["guests_total"], 1, "stats guests_total")
	_eq(st["problems"], 1, "stats problems counts the mess")
	_check(w.ledger().has(&"tickets") and w.ledger().has(&"upkeep"), "ledger keys")
	# Moods.
	var mg: Guest = _spawn(w)
	mg.nv[SimConst.N_HUNGER] = 10.0
	mg.mode = Guest.WANDER
	mg.eval_timer = 1.0e6
	mg.wander_pause = 1.0e6
	w.guest_sim._slow(w, mg, 0.5)
	_check(mg.mood == &"need_hunger" or mg.mood == &"sick", "mood reflects the lowest need (%s)" % mg.mood)
	_check(mg.bubble_timer > 0.0, "bubble timer set on mood change")


func _t_human_player() -> void:
	_section("human player mode")
	# Reaction delay 3 s, clicks limited to 1.5/s, never assigns crew.
	var w: SimWorld = _world(&"med_3", _staff_ship(), {&"janitor": 1})
	var hp := AutoPlayer.new(w, &"human", 3)
	_near(hp.reaction_delay, 3.0, 0.001, "human reaction 3 s")
	_near(hp.clicks_per_second, 1.5, 0.001, "human 1.5 actions/s")
	_check(not hp.assigns_crew, "human never assigns crew")
	hp.rng.seed = 5
	var m: Mess = w.problems.spawn_mess(w, _find_room(w, &"buffet"))
	var t_first_click: float = -1.0
	for i in 300:
		w.tick(SimConst.TICK)
		hp.tick(SimConst.TICK)
		if t_first_click < 0.0 and w.metrics["player_clicks"] > 0:
			t_first_click = w.time
	_check(t_first_click >= 3.0, "human waits ~3 s before acting (t=%.1f)" % t_first_click)
	# Busy fraction about a quarter of the time over a long quiet stretch.
	var wq: SimWorld = _world(&"med_3", _staff_ship(), {})
	var hq := AutoPlayer.new(wq, &"human", 9)
	for i in 4000:
		wq.tick(SimConst.TICK)
		hq.tick(SimConst.TICK)
	var frac: float = hq.busy_time / 400.0
	_check(frac > 0.15 and frac < 0.35, "human is busy elsewhere ~25%% of the time (%.2f)" % frac)
	# Click rate never exceeds 1.5/s on a pile of messes.
	var wc: SimWorld = _world(&"med_3", _staff_ship(), {})
	var hc := AutoPlayer.new(wc, &"human", 4)
	var cells: Array = [[1, 4], [1, 5], [1, 6], [1, 7]]
	for i in 6:
		wc.problems.spawn_mess(wc, _find_room(wc, &"buffet"))
		wc.problems.spawn_mess(wc, _find_room(wc, &"bar"))
	var clicks_by_t: Dictionary = {}
	for i in 400:
		wc.tick(SimConst.TICK)
		hc.tick(SimConst.TICK)
		clicks_by_t[i] = wc.metrics["player_clicks"]
	_check(int(clicks_by_t[399]) <= 40 * 1.5 + 4, "human click rate limited (%d clicks in 40 s)" % int(clicks_by_t[399]))
	# Nearest problem first: focus starts mid-ship on the gangway deck; a mess next to it beats a far one.
	var wn: SimWorld = _world(&"med_3", _staff_ship(), {})
	var hn := AutoPlayer.new(wn, &"human", 6)
	hn._busy_left = 0.0
	var near_m: Mess = wn.problems.spawn_mess(wn, _find_room(wn, &"buffet"))
	var far_m: Mess = wn.problems.spawn_mess(wn, _find_room(wn, &"bar"))
	hn._focus_deck = float(far_m.deck)
	hn._focus_x = far_m.x
	hn._seen["m%d" % near_m.id] = -10.0
	hn._seen["m%d" % far_m.id] = -10.0
	var pick: Dictionary = hn._nearest_problem()
	_eq(pick["id"], far_m.id, "human works the problem nearest to where it last acted")
	# Humans repair too (hold), slower than the active bot but they do get there.
	var wr: SimWorld = _world(&"med_3", _staff_ship(), {})
	var hr := AutoPlayer.new(wr, &"human", 8)
	wr.room_sim.break_room(wr, _find_room(wr, &"toilets"))
	for i in 600:
		wr.tick(SimConst.TICK)
		hr.tick(SimConst.TICK)
	_check(not _find_room(wr, &"toilets").broken, "human repairs a broken room")
	_check(wr.metrics["player_repair_s"] > 1.0, "human repaired by holding")
	_eq(wr.staff.size(), 0, "no crew was involved")


func _t_pressure() -> void:
	_section("pressure: spreading messes, queue anger")
	# Neglected messes spread (once per 7 s after 12 s) but never beyond the per-deck cap.
	var w: SimWorld = _world(&"med_3", _small_ship(), {}, 7)
	w.problems.spawn_mess(w, _find_room(w, &"buffet"))
	_advance(w, 11.0)
	_eq(w.messes.size(), 1, "a fresh mess has not spread yet")
	_advance(w, 80.0)
	_check(w.messes.size() >= 2, "a neglected mess spreads (%d messes after 90 s)" % w.messes.size())
	_check(w.messes.size() <= SimConst.MAX_MESSES_PER_DECK, "spreading respects the per-deck cap")
	_check(w.metrics["mess_spread"] >= 1, "mess_spread counted")
	for m in w.messes:
		_near(m.x - floorf(m.x), 0.5, 0.001, "spread messes sit on cell centres")
	# Cleaning stops the spread.
	var w2: SimWorld = _world(&"med_3", _small_ship(), {}, 7)
	var m2: Mess = w2.problems.spawn_mess(w2, _find_room(w2, &"buffet"))
	_advance(w2, 8.0)
	w2.problems.add_clean(w2, m2, 1.0)
	_advance(w2, 60.0)
	_eq(w2.messes.size(), 0, "a cleaned mess does not come back")
	# Queueing at a broken room hurts more than queueing at a working one.
	var drains: Array = []
	for broken in [false, true]:
		var wq: SimWorld = _world(&"med_3", _small_ship(), {}, 3)
		var bf: RoomRuntime = _find_room(wq, &"buffet")
		bf.health = 1.0e6
		if broken:
			wq.room_sim.break_room(wq, bf)
		else:
			for i in bf.cap:
				var blocker: Guest = _spawn(wq)
				blocker.mode = Guest.USE
				blocker.target_uid = bf.uid
				bf.users.append(blocker.id)
				bf.take_slot(blocker.id)
				blocker.use_timer = 1.0e6
		var g: Guest = _spawn(wq)
		g.mode = Guest.WALK
		g.target_uid = bf.uid
		bf.incoming += 1
		g.set_position(2, bf.door_x - 0.3)
		for i in 4:
			g.nv[i] = 60.0
		wq.guest_sim._arrive(wq, g)
		g.satisfaction = 60.0
		g.patience = 1.0e6
		g.slow_t = 0.0
		_advance(wq, 8.0)
		drains.append(60.0 - g.satisfaction)
	_check(drains[1] > drains[0] + 1.5, "queue anger: broken room drains more (%.2f vs %.2f)" % [drains[1], drains[0]])


func _t_no_stuck() -> void:
	_section("no stuck guests or staff")
	for id in [&"arctic_3", &"underworld_5"]:
		var lvl: LevelDef = ContentStore.level(id)
		var port := AutoBuilder.build(lvl)
		var w: SimWorld = port.create_world(21)
		var ap := AutoPlayer.new(w, &"active", 21)
		var still: Dictionary = {}
		var last: Dictionary = {}
		var longest_still: float = 0.0
		var longest_queue: float = 0.0
		var longest_use: float = 0.0
		var qt: Dictionary = {}
		var ut: Dictionary = {}
		var staff_still: float = 0.0
		var staff_last: Dictionary = {}
		var staff_t: Dictionary = {}
		for i in 1800:
			w.tick(SimConst.TICK)
			ap.tick(SimConst.TICK)
			if i % 5 != 0:
				continue
			for g in w.guests:
				if g.state == Guest.GONE:
					continue
				var key: String = "%.2f|%.2f" % [g.x, g.deck_f]
				var moving_state: bool = g.state in [&"walk", &"climb", &"elevator_wait", &"elevator_ride", &"storm_off"]
				if last.get(g.id, "") == key and moving_state and g.slip_timer <= 0.0 and g.state != &"elevator_wait":
					still[g.id] = float(still.get(g.id, 0.0)) + 0.5
					longest_still = maxf(longest_still, float(still[g.id]))
				else:
					still[g.id] = 0.0
				last[g.id] = key
				if g.state == Guest.QUEUE:
					qt[g.id] = float(qt.get(g.id, 0.0)) + 0.5
					longest_queue = maxf(longest_queue, float(qt[g.id]))
				else:
					qt[g.id] = 0.0
				if g.state == Guest.USE:
					ut[g.id] = float(ut.get(g.id, 0.0)) + 0.5
					longest_use = maxf(longest_use, float(ut[g.id]))
				else:
					ut[g.id] = 0.0
			for s in w.staff:
				var skey: String = "%.2f|%.2f|%s" % [s.x, s.deck_f, s.state]
				if staff_last.get(s.id, "") == skey and s.state == &"walk":
					staff_t[s.id] = float(staff_t.get(s.id, 0.0)) + 0.5
					staff_still = maxf(staff_still, float(staff_t[s.id]))
				else:
					staff_t[s.id] = 0.0
				staff_last[s.id] = skey
		_check(longest_still < 6.0, "%s: no guest frozen while moving (longest %.1f s)" % [id, longest_still])
		_check(longest_queue < 45.0, "%s: nobody queues forever (longest %.1f s)" % [id, longest_queue])
		_check(longest_use < 20.0, "%s: no endless use (longest %.1f s)" % [id, longest_use])
		_check(staff_still < 6.0, "%s: crew never frozen while walking (%.1f s)" % [id, staff_still])
		_check(w.transit.riders_in(w.transit.riders.keys()[0] if not w.transit.riders.is_empty() else 0) <= 4, "elevator count sane")
		# Queue lengths stay sane (no black hole).
		var q_total: int = w.room_sim.total_queue()
		_check(q_total < w.guests.size(), "%s: queues are not everyone (%d)" % [id, q_total])


func _t_performance() -> void:
	_section("performance")
	var lvl: LevelDef = ContentStore.level(&"underworld_6")
	var port := AutoBuilder.build(lvl)
	var w: SimWorld = port.create_world(1)
	var t0: int = Time.get_ticks_usec()
	var n: int = 0
	while n < 3000 and not w.finished:
		w.tick(SimConst.TICK)
		n += 1
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	print("  %d ticks, %d guests: %.0f ms" % [n, w.guests.size(), ms])
	_check(ms < 2500.0, "56 guests x 3000 ticks simulate quickly (%.0f ms)" % ms)
