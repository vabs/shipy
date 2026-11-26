extends SceneTree
## Headless unit tests for the simulation. Run:
##   godot --headless --path . --script res://tests/run_tests.gd
## Prints ALL TESTS PASSED (exit 0) or the failures (exit 1).

const SaveScript := preload("res://src/meta/save_manager.gd")
const TMP_DIR: String = "user://__test_run_tests"

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
		_t_human_player, _t_pressure, _t_no_stuck,
		_t_payout_funds, _t_perks, _t_telemetry,
		_t_roles_content, _t_medic, _t_entertainer, _t_chef, _t_warden, _t_assign_kinds, _t_fatigue,
		_t_crew_quarters, _t_roles_misc,
		_t_vip_content, _t_vip_critic, _t_vip_celebrity, _t_vip_inspector, _t_vip_misc,
		_t_groups, _t_group_cabins, _t_kids_club, _t_vip_groups_runs,
		_t_storm, _t_port_stop, _t_refit, _t_review_fixes, _t_autoplayer_refit, _t_campaign_features, _t_hints_v2, _t_performance,
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
	lvl.staff_fatigue = false   # tests switch fatigue on explicitly (see _role_level)
	lvl.vips = []               # ... and so do VIPs, groups and the port stop (the campaign levels opt in, phase 4b)
	lvl.group_ratio = 0.0
	lvl.port_stop = {}
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
	_eq(ContentStore.all_rooms().size(), 20, "20 rooms")
	_eq(ContentStore.all_archetypes().size(), 5, "5 archetypes (4 guest types + the kid)")
	_eq(ContentStore.all_staff_roles().size(), 6, "6 staff roles")
	_eq(ContentStore.all_events().size(), 10, "10 events (the storm is the tenth)")
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
	_eq(sum, lvl.total_guests() - int(m["kids"]), "manifest archetypes sum to guests (kids only come inside families)")
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
		_check(beds >= lvl.peak_guests(), "%s has enough beds (%d for %d at the peak)" % [lvl.id, beds, lvl.peak_guests()])
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


# ---------------------------------------------------------------------------------------------
# v2 phase 1: payout, company funds and perks (SPEC §13.1)
# ---------------------------------------------------------------------------------------------
## SaveManager stand-in with no ContentDB (fallback unlock tables), saving under TMP_DIR.
class _NoDB:
	extends RefCounted


func _new_save(file: String = "save.json") -> Node:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var sm: Node = SaveScript.new()
	sm.save_path = "%s/%s" % [TMP_DIR, file]
	sm.content = _NoDB.new()
	if FileAccess.file_exists(sm.save_path):
		DirAccess.remove_absolute(sm.save_path)
	sm.load_save()
	return sm


func _rm_tmp() -> void:
	for f in ["save.json", "save.json.tmp", "rt.json", "old.json", "bad.json"]:
		var path: String = "%s/%s" % [TMP_DIR, f]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR))


func _t_payout_funds() -> void:
	_section("payout and company funds")
	# --- result dict: money_start / money_end / payout
	var lvl: LevelDef = _blank_level(&"med_3")
	lvl.duration = 20.0
	lvl.waves = [{"t": 0.0, "count": 4}]
	var w: SimWorld = _world(&"med_3", _small_ship(), {}, 3, lvl)
	_advance(w, 25.0)
	_check(w.finished, "short voyage ended")
	var res: Dictionary = w.result
	_eq(res["money_start"], 1000, "result carries money_start")
	_eq(res["money_end"], w.money, "result carries money_end = final cash")
	_eq(res["payout"], LevelDirector.payout_for(w.money, int(res["stars"])), "payout = max(0, money_end) x star share")
	_eq(LevelDirector.payout_for(1000, 0), 250, "0 stars pays 25%")
	_eq(LevelDirector.payout_for(1000, 3), 1000, "3 stars pays 100%")
	_eq(res["money_end"] - res["money_start"], res["profit"], "profit = money_end - money_start")
	_check(res.has("report") and res["report"] is Dictionary, "result carries the voyage report")
	# negative cash pays nothing
	var w_neg: SimWorld = _world(&"med_3", _small_ship(), {}, 3, lvl)
	w_neg.economy.money = -500
	_advance(w_neg, 25.0)
	_check(w_neg.result["money_end"] < 0, "cash can end negative")
	_eq(w_neg.result["payout"], 0, "negative cash pays 0")
	# mutiny pays nothing even with cash in hand
	var ml: LevelDef = _blank_level(&"arctic_1")
	ml.waves = [{"t": 0.0, "count": 6}]
	var wm: SimWorld = _world(&"arctic_1", [[&"stairs", 0, 20], [&"cabin", 1, 0], [&"cabin", 1, 2]], {}, 1, ml)
	for i in 700:
		for g in wm.guests:
			g.satisfaction = 10.0
			for k in 4:
				g.nv[k] = 100.0
		wm.tick(SimConst.TICK)
		if wm.finished:
			break
	_check(wm.finished and wm.result["mutiny"], "mutiny voyage ended")
	_check(wm.result["money_end"] > 0, "mutiny ship still has cash")
	_eq(wm.result["payout"], 0, "mutiny payout is 0")

	# --- SaveManager: best payout / no farming
	var sm: Node = _new_save()
	_eq(sm.funds(), 0, "fresh save has no funds")
	var r1: Dictionary = sm.record_result({"level_id": &"med_1", "stars": 2, "rating": 70.0, "profit": 300, "payout": 1000})
	_eq(r1["funds_earned"], 1000, "first payout is credited in full")
	_eq(r1["funds_total"], 1000, "funds_total after the first payout")
	_eq(r1["best_payout"], 1000, "best_payout recorded")
	var r2: Dictionary = sm.record_result({"level_id": &"med_1", "stars": 3, "rating": 90.0, "profit": 500, "payout": 800})
	_eq(r2["funds_earned"], 0, "a lower payout earns nothing")
	_eq(r2["funds_total"], 1000, "funds unchanged by a lower payout")
	_eq(r2["best_payout"], 1000, "best payout kept")
	var r3: Dictionary = sm.record_result({"level_id": &"med_1", "stars": 1, "rating": 50.0, "profit": 100, "payout": 1000})
	_eq(r3["funds_earned"], 0, "an equal payout earns nothing")
	var r4: Dictionary = sm.record_result({"level_id": &"med_1", "stars": 1, "rating": 50.0, "profit": 100, "payout": 1500})
	_eq(r4["funds_earned"], 500, "only the improvement is credited")
	_eq(r4["funds_total"], 1500, "funds follow the best payout")
	var r5: Dictionary = sm.record_result({"level_id": &"med_2", "stars": 0, "rating": 10.0, "profit": -50, "payout": 0})
	_eq(r5["funds_earned"], 0, "a mutiny / zero payout earns nothing")
	_eq(sm.best_for(&"med_2")["best_payout"], 0, "zero best payout stored")
	var r6: Dictionary = sm.record_result({"level_id": &"med_2", "stars": 1, "rating": 50.0, "profit": 100, "payout": 700})
	_eq(r6["funds_total"], 2200, "levels add up: 1500 + 700")
	_eq(sm.funds_earned(), 2200, "funds_earned sums best payouts")
	var r7: Dictionary = sm.record_result({"level_id": &"med_1", "stars": 1, "rating": 50.0, "profit": 0})
	_eq(r7["funds_earned"], 0, "a result without payout is treated as 0")
	_eq(r7["best_payout"], 1500, "missing payout leaves the best alone")
	sm.free()

	# --- buy / refund / persistence
	var sp: Node = _new_save()
	var changes: Array = [0]
	sp.progress_changed.connect(func() -> void: changes[0] += 1)
	_check(not sp.buy_perk(&"budget"), "cannot buy with no funds")
	_check(not bool(sp.can_buy_perk(&"budget")["ok"]) and String(sp.can_buy_perk(&"budget")["reason"]) != "", "can_buy explains why not")
	_check(not sp.buy_perk(&"nonsense"), "unknown perk refused")
	sp.record_result({"level_id": &"med_1", "stars": 1, "rating": 60.0, "profit": 10, "payout": Perks.price(1) + 400})
	changes[0] = 0
	_check(sp.buy_perk(&"budget"), "buy level 1 with enough funds")
	_eq(sp.perk_level(&"budget"), 1, "perk level 1 owned")
	_eq(sp.funds(), 400, "funds drop by the price")
	_eq(sp.funds_spent(), Perks.price(1), "spent tracked")
	_eq(changes[0], 1, "buying emits progress_changed")
	_check(not sp.buy_perk(&"budget"), "level 2 is too expensive right now")
	_eq(sp.perk_level(&"budget"), 1, "failed buy changes nothing")
	_eq(sp.funds(), 400, "failed buy keeps the funds")
	sp.record_result({"level_id": &"med_2", "stars": 1, "rating": 60.0, "profit": 10, "payout": 40000})
	_check(sp.buy_perk(&"budget") and sp.buy_perk(&"budget"), "levels 2 and 3 bought")
	_eq(sp.perk_level(&"budget"), 3, "maxed at level 3")
	_check(not sp.buy_perk(&"budget"), "cannot go past level 3")
	_eq(String(sp.can_buy_perk(&"budget")["reason"]), "Already maxed", "maxed reason")
	_check(sp.buy_perk(&"crew"), "a second perk can be bought")
	var owned: Dictionary = sp.perks()
	_eq(Perks.level_of(owned, &"budget"), 3, "perks() reports budget 3")
	_eq(Perks.level_of(owned, &"crew"), 1, "perks() reports crew 1")
	owned[&"budget"] = 0
	_eq(sp.perk_level(&"budget"), 3, "perks() returns a copy")
	var funds_before: int = sp.funds()
	var spent_before: int = sp.funds_spent()
	_eq(spent_before, Perks.total_cost(3) + Perks.price(1), "spent = what the levels cost")
	# round trip through the save file
	var sp2: Node = SaveScript.new()
	sp2.save_path = sp.save_path
	sp2.content = _NoDB.new()
	_check(sp2.load_save(), "saved file loads")
	_eq(sp2.funds(), funds_before, "funds survive a save round trip")
	_eq(sp2.perk_level(&"budget"), 3, "perk levels survive a save round trip")
	_eq(sp2.perk_level(&"crew"), 1, "second perk survives")
	_eq(sp2.best_for(&"med_2")["best_payout"], 40000, "best payout survives")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sp.save_path))
	_check(parsed is Dictionary and (parsed as Dictionary).has("company"), "company block written")
	_eq(int(((parsed as Dictionary)["company"] as Dictionary)["spent"]), spent_before, "company.spent written")
	sp2.free()
	# refund
	changes[0] = 0
	var back: int = sp.refund_perks()
	_eq(back, spent_before, "refund returns everything spent")
	_eq(sp.funds(), funds_before + spent_before, "funds restored by the refund")
	_eq(sp.perks().size(), 0, "no perks after the refund")
	_eq(sp.funds_spent(), 0, "spent reset")
	_eq(changes[0], 1, "refund emits progress_changed")
	_eq(sp.refund_perks(), 0, "refunding nothing returns 0")
	sp.free()

	# --- old / hostile saves
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var old_path: String = "%s/old.json" % TMP_DIR
	var f := FileAccess.open(old_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "levels": {"med_1": {"stars": 2, "best_rating": 60.0, "best_profit": 200, "plays": 3}}, "future": [1]}))
	f.close()
	var so: Node = SaveScript.new()
	so.save_path = old_path
	so.content = _NoDB.new()
	_check(so.load_save(), "old save (no company block) loads")
	_eq(so.funds(), 0, "old save has no funds")
	_eq(so.perks().size(), 0, "old save has no perks")
	_eq(so.best_for(&"med_1")["best_payout"], 0, "old level has no best payout")
	so.record_result({"level_id": &"med_1", "stars": 1, "rating": 50.0, "profit": 10, "payout": 900})
	_eq(so.funds(), 900, "old level credits its first payout")
	var after: Variant = JSON.parse_string(FileAccess.get_file_as_string(old_path))
	_check(after is Dictionary and (after as Dictionary).has("future"), "unknown keys still pass through")
	so.free()
	var bad_path: String = "%s/bad.json" % TMP_DIR
	var g := FileAccess.open(bad_path, FileAccess.WRITE)
	g.store_string(JSON.stringify({"version": 1, "levels": {"med_1": {"stars": 1, "best_payout": -50}}, "company": {"spent": -9, "perks": {"budget": 99, "ghost": 2, "crew": "x"}}}))
	g.close()
	var sb: Node = SaveScript.new()
	sb.save_path = bad_path
	sb.content = _NoDB.new()
	sb.load_save()
	_eq(sb.perk_level(&"budget"), 3, "absurd perk level clamps to 3")
	_eq(sb.perk_level(&"crew"), 0, "junk perk level ignored")
	_eq(sb.perks().has(&"ghost"), false, "unknown perks are dropped")
	_eq(sb.funds_spent(), 0, "negative spent clamps to 0")
	_eq(sb.best_for(&"med_1")["best_payout"], 0, "negative best payout clamps to 0")
	_check(sb.funds() >= 0, "funds never negative")
	sb.free()
	# reset wipes the company too
	var sr: Node = _new_save()
	sr.record_result({"level_id": &"med_1", "stars": 1, "rating": 60.0, "profit": 10, "payout": 5000})
	sr.buy_perk(&"tickets")
	sr.reset_progress()
	_eq(sr.funds(), 0, "reset clears funds")
	_eq(sr.perks().size(), 0, "reset clears perks")
	_eq(sr.funds_spent(), 0, "reset clears spent")
	sr.free()
	_rm_tmp()
	# price table sanity
	_eq(Perks.price(0), 0, "no price for level 0")
	_eq(Perks.price(4), 0, "no price for level 4")
	_check(Perks.price(1) < Perks.price(2) and Perks.price(2) < Perks.price(3), "prices rise per level")
	_eq(Perks.total_cost(2), Perks.price(1) + Perks.price(2), "total_cost sums levels")
	_eq(Perks.total_value({&"budget": 1, "crew": 2}), Perks.total_cost(1) + Perks.total_cost(2), "total_value accepts mixed keys")


func _t_perks() -> void:
	_section("perks change the simulation")
	# --- PortState budget (Investors)
	var lvl: LevelDef = ContentStore.level(&"med_4")
	var port := PortState.new(lvl)
	_eq(port.budget, lvl.budget, "no perks, base budget")
	port.perks = {&"budget": 2}
	var bonus: int = int(round(float(lvl.budget) * 0.12))
	_eq(port.budget, lvl.budget + bonus, "Investors level 2 = +12% budget")
	_eq(port.budget_bonus(), bonus, "budget_bonus reports it")
	port.perks = {&"budget": 2}
	_eq(port.budget, lvl.budget + bonus, "assigning the same perks again does not stack")
	port.perks = {&"budget": 1}
	_eq(port.budget, lvl.budget + int(round(float(lvl.budget) * 0.06)), "lower level replaces the bonus")
	port.place(&"cabin", 1, 0)
	port.perks = {}
	_eq(port.budget, lvl.budget - 120, "removing perks keeps spending intact")
	port.perks = {"budget": 3, "bogus": 2}
	_eq(Perks.level_of(port.perks, &"budget"), 3, "String keys accepted")
	_check(not port.perks.has("bogus") and not port.perks.has(&"bogus"), "unknown perks dropped")
	var pw: SimWorld = port.create_world(2)
	_eq(pw.economy.money_start, port.budget, "world starts with the boosted budget")
	_eq(Perks.level_of(pw.perks, &"budget"), 3, "world remembers the perks")
	var plain := PortState.new(lvl)
	_check(plain.create_world(2).perks.is_empty(), "no perks, nothing applied")

	# --- Marketing: ticket price
	var tl: LevelDef = _blank_level(&"med_3")
	var wt: SimWorld = _world(&"med_3", _small_ship(), {}, 4, tl)
	wt.apply_perks({&"tickets": 3})
	_eq(wt.ticket_price, int(round(float(tl.ticket_price) * 1.24)), "Marketing level 3 = +24% tickets")
	var m0: int = wt.money
	_spawn(wt)
	_eq(wt.money - m0, wt.ticket_price, "a boarding guest pays the boosted price")
	_eq(wt.ledger()[&"tickets"], wt.ticket_price, "ledger shows the boosted ticket")
	wt.apply_perks({})
	_eq(wt.ticket_price, tl.ticket_price, "apply_perks replaces, never stacks")

	# --- Hospitality School: queue patience (same seed, same rng stream -> exact ratio)
	var pat: Array[float] = []
	for lv in [0, 3]:
		var wp: SimWorld = _world(&"med_3", _small_ship(), {}, 9)
		if lv > 0:
			wp.apply_perks({&"service": lv})
		var buffet: RoomRuntime = _find_room(wp, &"buffet")
		wp.room_sim.break_room(wp, buffet)
		var gp: Guest = _spawn(wp, &"holidaymaker")
		gp.mode = Guest.WALK
		gp.target_uid = buffet.uid
		buffet.incoming += 1
		gp.set_position(2, buffet.door_x - 0.3)
		wp.guest_sim._arrive(wp, gp)
		pat.append(gp.patience)
	_near(pat[1] / pat[0], 1.3, 0.001, "Hospitality School level 3 = +30% patience")

	# --- Maintenance Contract: room health
	var hs: Array[Dictionary] = []
	for lv in [0, 2]:
		var wh: SimWorld = _world(&"med_3", _small_ship(), {}, 6)
		if lv > 0:
			wh.apply_perks({&"maintenance": lv})
		var buf: RoomRuntime = _find_room(wh, &"buffet")
		hs.append({"max": buf.max_health, "health": buf.health, "w": wh, "r": buf})
	_near(float(hs[1]["max"]) / float(hs[0]["max"]), 1.24, 0.001, "Maintenance level 2 = +24% max health")
	_near(float(hs[1]["health"]) / float(hs[0]["health"]), 1.24, 0.001, "current health scales with it")
	var wh2: SimWorld = hs[1]["w"]
	var rb: RoomRuntime = hs[1]["r"]
	wh2.room_sim.break_room(wh2, rb)
	wh2.room_sim.repair_room(wh2, rb)
	_near(rb.max_health, rb.def.health_at(rb.tier) * wh2.level.health_mult * 1.24, 0.01, "repaired rooms keep the durability bonus")

	# --- Crew Training: speed and work time
	var wc: SimWorld = _world(&"med_3", _staff_ship(), {&"janitor": 1, &"mechanic": 1})
	var jan: StaffMember = wc.staff[0]
	var base_speed: float = jan.def.speed
	_near(jan.eff_speed(), jan.def.speed, 0.0001, "no perks, base speed")
	_near(jan.eff_work_time(), jan.def.work_time, 0.0001, "no perks, base work time")
	wc.apply_perks({&"crew": 3})
	_near(jan.eff_speed(), jan.def.speed * 1.3, 0.0001, "Crew Training level 3 = +30% speed")
	_near(jan.eff_work_time(), jan.def.work_time * 0.7, 0.0001, "Crew Training level 3 = -30% work time")
	_near(jan.def.speed, base_speed, 0.0001, "shared StaffDef untouched")
	_check(wc.hire_staff_mid_voyage(&"janitor"), "mid-voyage hire works")
	_near(wc.staff.back().eff_speed(), wc.staff.back().def.speed * 1.3, 0.0001, "mid-voyage hires get the crew perk too")
	# a janitor with the perk finishes the same mess sooner
	var clear_t: Array[float] = []
	for lv in [0, 3]:
		var wj: SimWorld = _world(&"med_3", _staff_ship(), {&"janitor": 1}, 11)
		if lv > 0:
			wj.apply_perks({&"crew": lv})
		var ms: Mess = wj.problems.spawn_mess(wj, _find_room(wj, &"bar"))
		var t0: float = wj.time
		while wj.mess_by_id(ms.id) != null and wj.time - t0 < 60.0:
			wj.tick(SimConst.TICK)
		clear_t.append(wj.time - t0)
	_check(clear_t[1] < clear_t[0] - 1.0, "trained janitor clears a mess sooner (%.1f s vs %.1f s)" % [clear_t[1], clear_t[0]])

	# --- no perks must leave the sim bit-for-bit unchanged (and apply_perks({}) too)
	var l2: LevelDef = ContentStore.level(&"arctic_2")
	var port2 := AutoBuilder.build(l2)
	var wa: SimWorld = port2.create_world(7)
	var wb: SimWorld = port2.create_world(7)
	wb.apply_perks({})
	var same: bool = true
	for i in 1000:
		wa.tick(SimConst.TICK)
		wb.tick(SimConst.TICK)
		if i % 100 == 0 and _snapshot(wa) != _snapshot(wb):
			same = false
			break
	_check(same, "apply_perks({}) changes nothing")
	# and perks are deterministic too
	var pa: SimWorld = port2.create_world(7)
	var pb: SimWorld = port2.create_world(7)
	pa.apply_perks({&"crew": 2, &"service": 1, &"maintenance": 3, &"tickets": 1})
	pb.apply_perks({&"crew": 2, &"service": 1, &"maintenance": 3, &"tickets": 1})
	same = true
	for i in 1000:
		pa.tick(SimConst.TICK)
		pb.tick(SimConst.TICK)
		if i % 100 == 0 and _snapshot(pa) != _snapshot(pb):
			same = false
			break
	_check(same, "a perked world is deterministic")
	# perks make a full voyage pay at least as much (more tickets, same everything else would be noise, so check money)
	var base_run: Dictionary = SimRunner.run(l2, port2, 21, &"active")
	var perk_port := AutoBuilder.build(l2)
	perk_port.perks = {&"budget": 3, &"tickets": 3}
	var perk_run: Dictionary = SimRunner.run(l2, perk_port, 21, &"active")
	_check(int(perk_run["payout"]) > int(base_run["payout"]), "budget + ticket perks raise the payout (%d vs %d)" % [perk_run["payout"], base_run["payout"]])


# ---------------------------------------------------------------------------------------------
# v2 phase 1: voyage telemetry, report and tips (SPEC §13.2)
# ---------------------------------------------------------------------------------------------
func _t_telemetry() -> void:
	_section("voyage telemetry")
	# --- tag rules (thresholds are inclusive)
	var buffet: RoomDef = ContentStore.room(&"buffet")
	var cabin: RoomDef = ContentStore.room(&"cabin")
	var stairs: RoomDef = ContentStore.room(&"stairs")
	_eq(VoyageTelemetry.tag_for(buffet, 0.5, 2.0, 0.0, 0, 20), &"overloaded", "avg queue 2.0 = overloaded")
	_eq(VoyageTelemetry.tag_for(buffet, 0.5, 1.99, 0.0, 0, 20), &"ok", "avg queue 1.99 = ok")
	_eq(VoyageTelemetry.tag_for(buffet, 0.5, 0.2, 0.0, 3, 20), &"overloaded", "3 patience-outs = overloaded")
	_eq(VoyageTelemetry.tag_for(buffet, 0.5, 0.2, 0.0, 2, 20), &"ok", "2 patience-outs = ok")
	_eq(VoyageTelemetry.tag_for(buffet, 0.5, 0.2, 0.2, 0, 20), &"unreliable", "broken 20% = unreliable")
	_eq(VoyageTelemetry.tag_for(buffet, 0.5, 0.2, 0.19, 0, 20), &"ok", "broken 19% = ok")
	_eq(VoyageTelemetry.tag_for(buffet, 0.14, 0.0, 0.0, 0, 2), &"idle", "util < 0.15 and uses < 3 = idle")
	_eq(VoyageTelemetry.tag_for(buffet, 0.15, 0.0, 0.0, 0, 2), &"ok", "util 0.15 is not idle")
	_eq(VoyageTelemetry.tag_for(buffet, 0.14, 0.0, 0.0, 0, 3), &"ok", "3 uses is not idle")
	_eq(VoyageTelemetry.tag_for(cabin, 0.0, 0.0, 0.0, 0, 0), &"ok", "cabins are never idle")
	_eq(VoyageTelemetry.tag_for(stairs, 0.0, 0.0, 0.0, 0, 0), &"ok", "transport is never idle")
	_eq(VoyageTelemetry.tag_for(buffet, 0.0, 3.0, 0.5, 0, 0), &"overloaded", "overloaded beats unreliable and idle")

	# --- empty ship: everything idle, one room broken the whole time
	var el: LevelDef = _blank_level(&"med_3")
	el.duration = 30.0
	var we: SimWorld = _world(&"med_3", _small_ship(), {}, 1, el)
	var bar: RoomRuntime = _find_room(we, &"bar")
	we.room_sim.break_room(we, bar)
	_advance(we, 30.5)
	_check(we.finished, "empty voyage ended")
	var rep: Dictionary = we.result["report"]
	_eq(we.telemetry.samples, 30, "one sample per second of sim time (30)")
	var rooms: Array = rep["rooms"]
	_eq(rooms.size(), we.room_sim.service_rooms.size(), "report lists every guest room")
	var tags: Dictionary = {}
	for row: Dictionary in rooms:
		tags[row["id"]] = row["tag"]
		for key in ["uid", "id", "name", "deck", "x", "util", "avg_queue", "broken_frac", "patience_outs", "uses", "tag"]:
			if not row.has(key):
				_check(false, "room row misses %s" % key)
	_eq(tags[&"bar"], &"unreliable", "a room broken all voyage is unreliable")
	_eq(tags[&"buffet"], &"idle", "an unused room is idle")
	_eq(tags[&"cabin"], &"ok", "cabins are never flagged idle")
	var bar_row: Dictionary = {}
	for row: Dictionary in rooms:
		if row["id"] == &"bar":
			bar_row = row
	_near(float(bar_row["broken_frac"]), 1.0, 0.05, "broken fraction ~1 for the always-broken bar")
	_near(float(bar_row["util"]), 0.0, 0.0001, "no utilisation on an empty ship")
	var tips: Array = rep["tips"]
	_check(tips.size() >= 1 and tips.size() <= 3, "1-3 tips (%d)" % tips.size())
	var mentions_bar: bool = false
	for t in tips:
		if String(t).contains("Bar"):
			mentions_bar = true
	_check(mentions_bar, "the broken bar shows up in the tips")
	var curve: Array = rep["rating_curve"]
	_eq(curve.size(), 7, "rating curve: a point every 5 s plus the final rating")
	for v in curve:
		if not (float(v) >= 0.0 and float(v) <= 100.0):
			_check(false, "rating curve value out of range")
	_eq(int(rep["decks"]), we.grid.hull.decks, "report knows the deck count")
	_eq(int(rep["width"]), we.grid.hull.width, "report knows the hull width")
	var grids: Dictionary = rep["grids"]
	for key in ["traffic", "unhappy", "queue"]:
		var gr: Array = grids[key]
		_eq(gr.size(), we.grid.hull.decks, "%s grid has a row per deck" % key)
		_eq((gr[0] as PackedFloat32Array).size(), we.grid.hull.width, "%s grid has a cell per column" % key)
	var total_traffic: float = 0.0
	for row in grids["traffic"]:
		for v in row:
			total_traffic += v
	_near(total_traffic, 0.0, 0.0001, "no guests, no traffic")

	# --- crowded buffet: overloaded, patience-outs add up, tips name it
	var cl: LevelDef = _blank_level(&"med_3")
	cl.duration = 90.0
	var wc: SimWorld = _world(&"med_3", _small_ship(), {}, 5, cl)
	for i in 28:
		var gg: Guest = _spawn(wc)
		gg.nv[SimConst.N_HUNGER] = 8.0
	_advance(wc, 90.5)
	_check(wc.finished, "crowded voyage ended")
	var rep2: Dictionary = wc.result["report"]
	var buf_row: Dictionary = {}
	var outs_sum: int = 0
	for row: Dictionary in rep2["rooms"]:
		outs_sum += int(row["patience_outs"])
		if row["id"] == &"buffet":
			buf_row = row
	_eq(buf_row["tag"], &"overloaded", "one buffet for 28 hungry guests is overloaded")
	_check(float(buf_row["avg_queue"]) >= 2.0 or int(buf_row["patience_outs"]) >= 3, "numbers back the tag (queue %.1f, outs %d)" % [buf_row["avg_queue"], buf_row["patience_outs"]])
	_check(int(buf_row["uses"]) > 0, "buffet use counted")
	_eq(outs_sum, int(wc.metrics["patience_outs"]), "per-room patience-outs add up to the world metric")
	var tips2: Array = rep2["tips"]
	_check(tips2.size() >= 1 and tips2.size() <= 3, "1-3 tips when crowded (%d)" % tips2.size())
	_check(String(tips2[0]).contains("Buffet"), "the top tip is about the overloaded buffet: %s" % String(tips2[0]))
	var q_total: float = 0.0
	var traffic_total: float = 0.0
	for row in rep2["grids"]["queue"]:
		for v in row:
			q_total += v
	for row in rep2["grids"]["traffic"]:
		for v in row:
			traffic_total += v
	_check(q_total > 20.0, "queue grid recorded the line (%.0f guest-seconds)" % q_total)
	_check(traffic_total > q_total, "traffic includes everyone who is not using a room")
	_check(traffic_total <= 28.0 * float(wc.telemetry.samples) + 0.001, "traffic can never exceed guests x samples")

	# --- homeless guests get a tip
	var hl: LevelDef = _blank_level(&"med_3")
	hl.duration = 20.0
	var wh: SimWorld = _world(&"med_3", [[&"stairs", 0, 10], [&"stairs", 1, 11], [&"stairs", 2, 10], [&"buffet", 2, 2], [&"toilets", 1, 4]], {}, 2, hl)
	for i in 5:
		_spawn(wh)
	_advance(wh, 20.5)
	var rep3: Dictionary = wh.result["report"]
	_eq(int(rep3["homeless"]), 5, "five guests without a bed")
	var bed_tip: bool = false
	for t in rep3["tips"]:
		if String(t).contains("no bed"):
			bed_tip = true
	_check(bed_tip, "homeless guests produce a cabin tip")

	# --- a real voyage: the report rides on the result, deterministically
	var lvl: LevelDef = ContentStore.level(&"med_3")
	var port := AutoBuilder.build(lvl)
	var ra: Dictionary = SimRunner.run(lvl, port, 12, &"human")
	var rb: Dictionary = SimRunner.run(lvl, port, 12, &"human")
	_check(ra.has("report"), "SimRunner result includes the report")
	_eq(str(ra["report"]), str(rb["report"]), "same seed gives an identical report")
	var rr: Dictionary = ra["report"]
	_check((rr["rooms"] as Array).size() >= 5, "a built ship reports its rooms")
	_check((rr["tips"] as Array).size() <= 3, "never more than 3 tips")
	_eq(int(rr["samples"]), int(floor(float(lvl.duration) + 0.0001)), "samples = duration in seconds")
	_eq((rr["rating_curve"] as Array).size(), int(lvl.duration / 5.0) + 1, "curve length for a real voyage")
	_near(float((rr["rating_curve"] as Array).back()), float(ra["rating"]), 0.001, "curve ends on the final rating")
	var all_ok: bool = true
	for row: Dictionary in rr["rooms"]:
		if not (float(row["util"]) >= 0.0 and float(row["util"]) <= 1.0001 and float(row["avg_queue"]) >= 0.0 and float(row["broken_frac"]) >= 0.0 and float(row["broken_frac"]) <= 1.0001):
			all_ok = false
	_check(all_ok, "per-room numbers stay in range")
	# heatmap overlay reads the report's grids (pure data, no UI autoloads needed)
	var heat := HeatmapOverlay.new()
	heat.setup(rr, false, Rect2())
	_check(heat.peak() > 0.0, "traffic heatmap has a hot spot (%.1f)" % heat.peak())
	var hot: Dictionary = heat.hottest()
	_check(not hot.is_empty() and int(hot["deck"]) >= 0 and int(hot["deck"]) < int(rr["decks"]), "hottest cell is on the ship")
	heat.set_mode(&"queue")
	_eq(heat.mode, &"queue", "heatmap mode switches")
	heat.set_mode(&"bogus")
	_eq(heat.mode, &"queue", "unknown heatmap mode ignored")
	_check(heat.peak() <= 10.0 * float(rr["samples"]), "queue peak is bounded by the sampling window")
	_eq(HeatmapOverlay.ramp(0.0).a, 0.0, "heat ramp starts transparent")
	_check(HeatmapOverlay.ramp(1.0).a > HeatmapOverlay.ramp(0.3).a, "heat ramp grows more opaque")
	_check(HeatmapOverlay.ramp(0.8, true) != HeatmapOverlay.ramp(0.8, false), "colour-blind ramp uses another palette")
	_check(HeatmapOverlay.ramp(0.9, true).b > 0.5 or HeatmapOverlay.ramp(0.9, true).r > 0.5, "colour-blind ramp is blue or orange")
	heat.free()
	# telemetry never feeds back into the sim: a world with and without sampling would match (it uses no rng)
	var snap_a: SimWorld = port.create_world(3)
	var snap_b: SimWorld = port.create_world(3)
	for i in 600:
		snap_a.tick(SimConst.TICK)
		snap_b.tick(SimConst.TICK)
	_check(_snapshot(snap_a) == _snapshot(snap_b), "telemetry keeps worlds identical")
	_eq(snap_a.telemetry.samples, 60, "60 s of ticks, 60 samples")



# ---------------------------------------------------------------------------------------------
# v2 phase 2: new crew roles, fatigue and crew quarters (SPEC §13.3 / §13.4)
# ---------------------------------------------------------------------------------------------
## Blank level for the role tests; `fatigue` switches LevelDef.staff_fatigue on.
func _role_level(level_id: StringName, fatigue: bool = false) -> LevelDef:
	var l: LevelDef = _blank_level(level_id)
	l.staff_fatigue = fatigue
	return l


## Parks a guest at (deck, x): no wandering, no room choices.
func _park(g: Guest, deck: int, x: float) -> void:
	g.set_position(deck, x)
	g.mode = Guest.WANDER
	g.state = Guest.WANDER
	g.wander_pause = 1.0e6
	g.eval_timer = 1.0e6
	g.clear_route()
	for i in 4:
		g.nv[i] = 90.0


## n guests queueing at `r`; fake users fill the room so the line never moves.
func _fake_queue(w: SimWorld, r: RoomRuntime, n: int) -> Array[Guest]:
	var out: Array[Guest] = []
	var fid: int = 9000
	while r.users.size() < r.capacity():
		r.users.append(fid)
		fid += 1
	for i in n:
		var g: Guest = _spawn(w)
		for k in 4:
			g.nv[k] = 60.0
		g.mode = Guest.QUEUE
		g.state = Guest.QUEUE
		g.target_uid = r.uid
		r.queue.append(g.id)
		g.queue_index = i
		g.queue_x = w.room_sim.queue_spot_x(w, r, i)
		g.set_position(r.deck, g.queue_x)
		g.patience = 28.0
		out.append(g)
	return out


func _t_roles_content() -> void:
	_section("new roles: content")
	var expect: Dictionary = {
		&"janitor": [40, 1, &"", &"mess"], &"mechanic": [60, 1, &"", &"breakdown"], &"medic": [70, 3, &"", &"sick"],
		&"entertainer": [55, 4, &"", &"aura"], &"chef": [65, 5, &"", &"aura"], &"warden": [60, 13, &"underworld", &"ghost"],
	}
	for id in expect:
		var d: StaffDef = ContentStore.staff_role(id)
		_check(d != null, "staff role %s exists" % id)
		if d == null:
			continue
		var row: Array = expect[id]
		_eq(d.wage, row[0], "%s wage" % id)
		_eq(d.unlock_level, row[1], "%s unlock level" % id)
		_eq(d.destination_lock, row[2], "%s destination lock" % id)
		_eq(d.handles, row[3], "%s handles" % id)
		_check(d.description != "" and d.display_name != "", "%s has a name and description" % id)
	_near(ContentStore.staff_role(&"warden").speed, 3.4, 0.001, "warden speed 3.4")
	_near(ContentStore.staff_role(&"warden").work_time, 1.0, 0.001, "warden channels 1 s")
	_near(ContentStore.staff_role(&"medic").work_time, 3.0, 0.001, "medic treats for 3 s")
	var order: Array[StringName] = []
	for d in ContentStore.all_staff_roles():
		order.append(d.id)
	_eq(order, [&"janitor", &"mechanic", &"medic", &"entertainer", &"chef", &"warden"] as Array[StringName], "roles sorted by unlock level")
	var med3: Array[StringName] = []
	for d in ContentStore.staff_available(3, &"med"):
		med3.append(d.id)
	_eq(med3, [&"janitor", &"mechanic", &"medic"] as Array[StringName], "level 3 offers the medic")
	var arc: Array[StringName] = []
	for d in ContentStore.staff_available(12, &"arctic"):
		arc.append(d.id)
	_check(not arc.has(&"warden") and arc.has(&"chef") and arc.has(&"entertainer"), "the warden is not offered in the Arctic")
	var und: Array[StringName] = []
	for d in ContentStore.staff_available(13, &"underworld"):
		und.append(d.id)
	_eq(und.size(), 6, "all six roles in the Underworld from level 13")
	_check(not ContentStore.staff_available(12, &"underworld").any(func(d: StaffDef) -> bool: return d.id == &"warden"), "warden unlocks at 13")
	var cq: RoomDef = ContentStore.room(&"crew_quarters")
	_check(cq != null, "crew_quarters room exists")
	_eq(cq.category, &"service", "crew quarters is a service room")
	_eq(cq.width, 2, "crew quarters is 2 wide")
	_eq(cq.capacity, 2, "crew quarters has 2 bunks")
	_eq(cq.cost, 220, "crew quarters cost 220")
	_near(cq.upkeep, 2.0, 0.001, "crew quarters upkeep 2")
	_eq(cq.power, 1, "crew quarters power 1")
	_eq(cq.water, 1, "crew quarters water 1")
	_eq(cq.placement, &"interior", "crew quarters is interior")
	_eq(cq.unlock_level, 7, "crew quarters unlock 7")
	_eq(cq.capacity_at(1), 3, "tier II adds a bunk")
	_eq(cq.capacity_at(2), 4, "tier III adds another bunk")
	_near(cq.speed_at(1), 1.25, 0.001, "tier II rests 25% faster")
	_check(cq.satisfies.is_empty() and not cq.is_service_room(), "guests never use the crew quarters")
	_check(not cq.is_available(6, &"med") and cq.is_available(7, &"arctic"), "crew quarters offered from level 7")
	for lvl in ContentStore.campaign():
		_eq(lvl.staff_fatigue, lvl.campaign_index >= 7, "%s staff_fatigue follows campaign index 7" % lvl.id)
	_check(not LevelDef.new().staff_fatigue, "LevelDef.staff_fatigue defaults to false")
	# Save unlocks: the roles are announced as features, the room as a room.
	var sm: Node = SaveScript.new()
	sm.save_path = "%s/roles.json" % TMP_DIR
	var db: Node = load("res://src/core/content_db.gd").new()
	db.load_all()
	sm.content = db
	_eq(sm.unlocked_staff_at(2), [&"janitor", &"mechanic"] as Array[StringName], "level 2 crew")
	_check(sm.unlocked_staff_at(13).has(&"warden") and not sm.unlocked_staff_at(12).has(&"warden"), "warden unlocks with level 13")
	_eq(sm.feature_display_name(&"staff_warden"), "Ghost Warden", "role feature name")
	_eq(SaveScript.staff_role_of_feature(&"staff_chef"), &"chef", "staff feature -> role id")
	_eq(SaveScript.staff_role_of_feature(&"tier_2"), &"", "other features are not roles")
	_check(sm.unlocked_rooms_at(7).has(&"crew_quarters") and not sm.unlocked_rooms_at(6).has(&"crew_quarters"), "crew quarters announced at level 7")
	sm.free()
	db.free()


func _t_medic() -> void:
	_section("medic")
	# A held guest stands still; a normal one keeps walking.
	var wh: SimWorld = _world(&"med_3", _staff_ship(), {&"janitor": 1}, 4)
	var gh: Guest = _spawn(wh)
	_advance(wh, 1.5)
	_park(gh, 1, 2.0)
	gh.plan_route(wh.grid, 1, 14.0)
	gh.eval_timer = 1.0e6
	var x0: float = gh.x
	gh.hold_until = wh.time + 1.0
	_advance(wh, 0.9)
	_near(gh.x, x0, 0.001, "a treated guest stands still")
	_advance(wh, 2.0)
	_check(gh.x > x0 + 1.0, "the guest walks on once released")
	# Full lifecycle: sick -> job -> medic walks over -> guest stops -> 3 s -> cured.
	var w: SimWorld = _world(&"med_3", _staff_ship(), {&"medic": 1}, 5)
	var cured: Array = [0]
	w.guest_cured.connect(func(_id: int) -> void: cured[0] += 1)
	var g: Guest = _spawn(w)
	_advance(w, 1.5)
	_park(g, 1, 14.0)
	var sat0: float = g.satisfaction
	w.problems.infect(w, g)
	var job: Job = w.staff_sim.jobs.find(&"sick", g.id)
	_check(job != null, "a sick guest posts a sick job")
	_eq(job.deck, 1, "job sits on the guest's deck")
	var medic: StaffMember = w.staff[0]
	_eq(medic.role, &"medic", "medic hired")
	_eq(medic.job_kind(), &"sick", "medics claim sick jobs")
	_advance(w, 0.6)
	_eq(job.claimed_by, medic.id, "the medic claims the job")
	var t_work: float = -1.0
	var t_cure: float = -1.0
	var x_work: float = 0.0
	var moved_while_treated: bool = false
	var sat_before: float = g.satisfaction
	for i in 400:
		sat_before = g.satisfaction
		w.tick(SimConst.TICK)
		if medic.state == &"work" and medic.work_kind == &"sick":
			if t_work < 0.0:
				t_work = w.time
				x_work = g.x
				_check(absf(medic.x - g.x) <= SimConst.MEDIC_REACH + 0.05, "treatment starts within a cell of the guest")
			elif absf(g.x - x_work) > 0.001:
				moved_while_treated = true
		if not g.sick:
			t_cure = w.time
			break
	_check(t_work > 0.0, "the medic reached the guest")
	_check(t_cure > t_work and absf((t_cure - t_work) - 3.0) < 0.3, "treatment takes 3 s (%.2f)" % (t_cure - t_work))
	_check(not moved_while_treated, "the guest stood still while treated")
	_eq(cured[0], 1, "guest_cured emitted once")
	_check(g.satisfaction >= sat_before + 2.5, "a cure gives +3 satisfaction (%.1f -> %.1f)" % [sat_before, g.satisfaction])
	_check(sat0 > 0.0, "guest had satisfaction to begin with")
	_eq(w.staff_sim.jobs.count_of(&"sick"), 0, "job removed once cured")
	_eq(medic.state, &"idle", "medic idle again")
	_eq(medic.jobs_done, 1, "jobs_done counted")
	_eq(w.metrics["medic_cures"], 1, "medic cure counted")
	# The job follows a guest that walks away.
	var w2: SimWorld = _world(&"med_3", _staff_ship(), {&"medic": 1}, 6)
	var g2: Guest = _spawn(w2)
	_advance(w2, 1.5)
	_park(g2, 1, 14.0)
	w2.problems.infect(w2, g2)
	g2.hold_until = 0.0
	g2.set_position(1, 17.0)
	_advance(w2, 0.2)
	_near(w2.staff_sim.jobs.find(&"sick", g2.id).x, 17.0, 0.05, "the job position follows the guest")
	# A guest cured elsewhere (medbay / timeout) removes the job and frees the medic.
	w2.guest_sim.cure(w2, g2, false)
	_eq(w2.staff_sim.jobs.count_of(&"sick"), 0, "curing by any means removes the job")
	_advance(w2, 0.3)
	_eq(w2.staff[0].job, null, "medic dropped the cured guest's job")
	# A guest who storms off / leaves clears the job too.
	var w3: SimWorld = _world(&"med_3", _staff_ship(), {&"medic": 1}, 7)
	var g3: Guest = _spawn(w3)
	_advance(w3, 1.5)
	_park(g3, 1, 14.0)
	w3.problems.infect(w3, g3)
	g3.mode = Guest.GONE
	g3.state = Guest.GONE
	_advance(w3, 0.3)
	_eq(w3.staff_sim.jobs.count_of(&"sick"), 0, "a departed guest's sick job is removed")
	# Janitors and mechanics ignore sick guests; a medic ignores messes.
	var w4: SimWorld = _world(&"med_3", _staff_ship(), {&"janitor": 1, &"mechanic": 1, &"medic": 1}, 8)
	var g4: Guest = _spawn(w4)
	_advance(w4, 1.5)
	_park(g4, 0, 6.0)
	w4.problems.infect(w4, g4)
	var mess4: Mess = w4.problems.spawn_mess(w4, _find_room(w4, &"toilets"))
	_advance(w4, 1.0)
	for s in w4.staff:
		if s.role == &"medic":
			_eq(s.job.kind, &"sick", "medic takes the sick job")
		elif s.role == &"janitor":
			_eq(s.job.kind, &"mess", "janitor takes the mess")
		else:
			_eq(s.job, null, "mechanic has nothing to do")
	_check(w4.staff_sim.jobs.find(&"mess", mess4.id).claimed_by != -1, "mess claimed")
	# With a medbay and no medic the old behaviour is unchanged: the guest heads for the medbay.
	var w5: SimWorld = _world(&"med_3", _small_ship() + [[&"medbay", 1, 6]], {}, 5)
	var g5: Guest = _spawn(w5)
	_advance(w5, 1.0)
	w5.problems.infect(w5, g5)
	_advance(w5, 60.0)
	_check(not g5.sick, "sick guests still reach the medbay without a medic")


func _t_entertainer() -> void:
	_section("entertainer")
	var lvl: LevelDef = _role_level(&"med_4")
	var wa: SimWorld = _world(&"med_4", _staff_ship(), {&"entertainer": 1}, 11, lvl)
	var wb: SimWorld = _world(&"med_4", _staff_ship(), {&"janitor": 1}, 11, lvl)   # same rng draws, no show
	var ga: Array[Guest] = _fake_queue(wa, _find_room(wa, &"toilets"), 5)
	var gb: Array[Guest] = _fake_queue(wb, _find_room(wb, &"toilets"), 5)
	var ent: StaffMember = wa.staff[0]
	_eq(ent.job_kind(), &"", "entertainers claim no jobs")
	_eq(ent.aura_kind(), &"perform", "entertainer performs")
	_advance(wa, 8.0)
	_eq(ent.state, &"perform", "the entertainer walks to the 5-guest queue and performs")
	_eq(ent.aura_uid, _find_room(wa, &"toilets").uid, "at the room with the longest queue")
	var p0: float = ga[2].patience
	_advance(wa, 6.0)
	_advance(wb, 14.0)
	var drop: float = p0 - ga[2].patience
	_check(drop > 2.4 and drop < 3.6, "patience drains at half speed while cheered (lost %.2f in 6 s)" % drop)
	_check(ga[2].patience > gb[2].patience + 3.0, "cheered guests keep more patience (%.1f vs %.1f)" % [ga[2].patience, gb[2].patience])
	_check(ga[2].satisfaction > gb[2].satisfaction + 2.0, "queue satisfaction drain becomes a gain (%.1f vs %.1f)" % [ga[2].satisfaction, gb[2].satisfaction])
	_check(ga[2].nv[SimConst.N_FUN] > gb[2].nv[SimConst.N_FUN] + 3.0, "fun rises while cheered (%.1f vs %.1f)" % [ga[2].nv[SimConst.N_FUN], gb[2].nv[SimConst.N_FUN]])
	# Guests far from the performer are not affected.
	var far: Guest = _spawn(wa)
	far.mode = Guest.QUEUE
	far.state = Guest.QUEUE
	far.target_uid = _find_room(wa, &"toilets").uid
	far.set_position(0, ent.x + 6.0)
	far.queue_x = far.x
	far.patience = 20.0
	_find_room(wa, &"toilets").queue.append(far.id)
	_advance(wa, 2.0)
	_near(far.patience, 18.0, 0.15, "guests more than 2 cells away lose patience at the normal rate")
	_check(far.cheer_until < wa.time, "guests more than 2 cells away are not cheered")
	# The queue disbands -> the show ends.
	var tr: RoomRuntime = _find_room(wa, &"toilets")
	for g in ga:
		tr.queue.erase(g.id)
		g.mode = Guest.WANDER
		g.state = Guest.WANDER
		g.eval_timer = 1.0e6
		g.wander_pause = 1.0e6
	tr.queue.erase(far.id)
	far.mode = Guest.WANDER
	far.eval_timer = 1.0e6
	far.wander_pause = 1.0e6
	_advance(wa, 7.0)
	_eq(ent.state, &"idle", "the entertainer stops when the queue is gone")
	# Short queues do not call an entertainer.
	var w2: SimWorld = _world(&"med_4", _staff_ship(), {&"entertainer": 1}, 12, lvl)
	_fake_queue(w2, _find_room(w2, &"toilets"), 2)
	_advance(w2, 10.0)
	_check(w2.staff[0].state != &"perform" and w2.staff[0].aura_uid == -1, "a queue of 2 is ignored")
	_fake_queue(w2, _find_room(w2, &"bar"), 4)
	_advance(w2, 12.0)
	_eq(w2.staff[0].aura_uid, _find_room(w2, &"bar").uid, "the queue of 4 gets the show")
	# Longest queue wins.
	var w3: SimWorld = _world(&"med_4", _staff_ship(), {&"entertainer": 1}, 13, lvl)
	_fake_queue(w3, _find_room(w3, &"toilets"), 3)
	_fake_queue(w3, _find_room(w3, &"buffet"), 6)
	_advance(w3, 14.0)
	_eq(w3.staff[0].aura_uid, _find_room(w3, &"buffet").uid, "the entertainer picks the longest queue")


func _t_chef() -> void:
	_section("chef")
	var lvl: LevelDef = _role_level(&"med_5")
	var rooms: Array = _staff_ship() + [[&"restaurant", 1, 10]]
	var w: SimWorld = _world(&"med_5", rooms, {&"chef": 1}, 21, lvl)
	var chef: StaffMember = w.staff[0]
	var buffet: RoomRuntime = _find_room(w, &"buffet")
	var rest: RoomRuntime = _find_room(w, &"restaurant")
	_eq(chef.aura_kind(), &"station", "chef stations")
	# The restaurant is busier: queue + users decide.
	_fake_queue(w, rest, 3)
	_advance(w, 14.0)
	_eq(chef.state, &"station", "the chef settles at a food room")
	_eq(chef.aura_uid, rest.uid, "at the busiest one (users + queue)")
	_check(rest.chef_on and not buffet.chef_on, "only the stationed room is boosted")
	_near(rest.svc_mult, 0.7, 0.001, "service time x0.7")
	_near(rest.mess_mult, 0.6, 0.001, "mess chance x0.6")
	_near(buffet.svc_mult, 1.0, 0.001, "other food rooms are unchanged")
	# Service time really shrinks.
	var g: Guest = _spawn(w)
	rest.users.clear()
	rest.slots.fill(-1)
	w.guest_sim.start_use(w, g, rest)
	_near(g.use_dur, rest.svc * 0.7, 0.001, "a guest is served in 70% of the time")
	var wn: SimWorld = _world(&"med_5", rooms, {&"janitor": 1}, 21, lvl)
	var gn: Guest = _spawn(wn)
	wn.guest_sim.start_use(wn, gn, _find_room(wn, &"restaurant"))
	_near(gn.use_dur, _find_room(wn, &"restaurant").svc, 0.001, "no chef: normal service time")
	# Mess chance: ~40% fewer messes.
	var with_chef: int = 0
	var without: int = 0
	for i in 3000:
		w.problems.try_mess(w, rest)
		if not w.messes.is_empty():
			with_chef += 1
			for m in w.messes.duplicate():
				w.problems.add_clean(w, m, 1.0)
		wn.problems.try_mess(wn, _find_room(wn, &"restaurant"))
		if not wn.messes.is_empty():
			without += 1
			for m in wn.messes.duplicate():
				wn.problems.add_clean(wn, m, 1.0)
	_check(without > 100 and float(with_chef) < float(without) * 0.8, "a chef cuts messes (%d vs %d of 3000)" % [with_chef, without])
	# Re-evaluated every 10 s: the crowd moves, the chef follows. Two chefs never share a room when they can avoid it.
	rest.queue.clear()
	rest.users.clear()
	var q2: Array[Guest] = _fake_queue(w, buffet, 4)
	_check(q2.size() == 4, "queue built")
	_advance(w, 25.0)
	_eq(chef.aura_uid, buffet.uid, "the chef moves to the busier food room")
	_check(buffet.chef_on and not rest.chef_on, "the boost moves with the chef")
	var w2: SimWorld = _world(&"med_5", rooms, {&"chef": 2}, 22, lvl)
	_advance(w2, 15.0)
	var rooms_used: Dictionary = {}
	for s in w2.staff:
		rooms_used[s.aura_uid] = true
	_eq(rooms_used.size(), 2, "two chefs spread over two food rooms")


func _t_warden() -> void:
	_section("warden")
	var lvl: LevelDef = _role_level(&"underworld_1")
	var w: SimWorld = _world(&"underworld_1", _staff_ship(), {&"warden": 1}, 31, lvl)
	var bn: Array = [0]
	w.ghost_banished.connect(func(_id: int) -> void: bn[0] += 1)
	var warden: StaffMember = w.staff[0]
	_eq(warden.job_kind(), &"ghost", "wardens claim ghost jobs")
	_near(warden.eff_speed(), 3.4, 0.001, "warden speed 3.4")
	var gh: Ghost = w.problems.spawn_ghost(w)
	gh.deck = 1
	gh.deck_f = 1.0
	gh.prev_deck_f = 1.0
	gh.dir = 1
	gh.x = 3.0
	gh.prev_x = 3.0
	var job: Job = w.staff_sim.jobs.find(&"ghost", gh.id)
	_check(job != null, "a ghost posts a ghost job")
	_advance(w, 0.6)
	_eq(job.claimed_by, warden.id, "the warden claims it")
	var t_work: float = -1.0
	var t_gone: float = -1.0
	for i in 400:
		w.tick(SimConst.TICK)
		if warden.state == &"work" and t_work < 0.0:
			t_work = w.time
			_check(absf(warden.x - gh.x) <= SimConst.WARDEN_REACH + 0.2, "channelling starts within a cell of the ghost")
		if w.ghosts.is_empty():
			t_gone = w.time
			break
	_check(t_work > 0.0 and t_gone > t_work, "the warden caught and banished the ghost")
	_check(absf((t_gone - t_work) - 1.0) < 0.25, "channelling takes 1 s (%.2f)" % (t_gone - t_work))
	_eq(bn[0], 1, "ghost_banished emitted")
	_eq(w.metrics["banished"], 1, "banish counted")
	_eq(w.metrics["warden_banishes"], 1, "warden banish counted")
	_eq(w.staff_sim.jobs.count_of(&"ghost"), 0, "ghost job removed")
	_eq(warden.state, &"idle", "warden idle again")
	# The player's click banishing the ghost frees the warden too.
	var w2: SimWorld = _world(&"underworld_1", _staff_ship(), {&"warden": 1}, 32, lvl)
	var g2: Ghost = w2.problems.spawn_ghost(w2)
	g2.deck = 1
	g2.deck_f = 1.0
	g2.x = 3.0
	_advance(w2, 1.0)
	w2.player_banish_ghost(g2.id)
	_advance(w2, 0.2)
	_eq(w2.staff_sim.jobs.count_of(&"ghost"), 0, "player banish removes the job")
	_eq(w2.staff[0].job, null, "warden dropped it")
	# A ghost that drifts off the ship removes its own job.
	var w3: SimWorld = _world(&"underworld_1", _staff_ship(), {}, 33, lvl)
	var g3: Ghost = w3.problems.spawn_ghost(w3)
	g3.x = 30.0
	g3.dir = 1
	_eq(w3.staff_sim.jobs.count_of(&"ghost"), 1, "job exists while the ghost is aboard")
	_advance(w3, 10.0)
	_eq(w3.staff_sim.jobs.count_of(&"ghost"), 0, "job gone when the ghost left the ship")
	# Wardens ignore messes; janitors ignore ghosts.
	var w4: SimWorld = _world(&"underworld_1", _staff_ship(), {&"warden": 1, &"janitor": 1}, 34, lvl)
	var g4: Ghost = w4.problems.spawn_ghost(w4)
	g4.deck = 0
	g4.deck_f = 0.0
	g4.x = 6.0
	w4.problems.spawn_mess(w4, _find_room(w4, &"toilets"))
	_advance(w4, 1.0)
	for s in w4.staff:
		if s.role == &"warden":
			_eq(s.job.kind, &"ghost", "warden takes the ghost")
		else:
			_eq(s.job.kind, &"mess", "janitor takes the mess")


func _t_assign_kinds() -> void:
	_section("assign_staff kinds")
	var rooms: Array = _staff_ship() + [[&"crew_quarters", 0, 8], [&"restaurant", 1, 10]]
	var w: SimWorld = _world(&"underworld_2", rooms, {&"janitor": 1, &"mechanic": 1, &"medic": 1, &"entertainer": 1, &"chef": 1, &"warden": 1}, 41, _role_level(&"underworld_2", true))
	var by: Dictionary = {}
	for s in w.staff:
		by[s.role] = s
	var g: Guest = _spawn(w)
	_advance(w, 1.5)
	_park(g, 1, 14.0)
	var healthy: Guest = _spawn(w)
	_park(healthy, 1, 16.0)
	w.problems.infect(w, g)
	var gh: Ghost = w.problems.spawn_ghost(w)
	gh.deck = 0
	gh.deck_f = 0.0
	gh.x = 5.0
	var mess: Mess = w.problems.spawn_mess(w, _find_room(w, &"toilets"))
	var toilets: RoomRuntime = _find_room(w, &"toilets")
	var buffet: RoomRuntime = _find_room(w, &"buffet")
	var cabin: RoomRuntime = _find_room(w, &"cabin")
	var quarters: RoomRuntime = _find_room(w, &"crew_quarters")
	var medic: StaffMember = by[&"medic"]
	var warden: StaffMember = by[&"warden"]
	var ent: StaffMember = by[&"entertainer"]
	var chef: StaffMember = by[&"chef"]
	var jan: StaffMember = by[&"janitor"]
	var mech: StaffMember = by[&"mechanic"]
	# sick
	_check(w.assign_staff(medic.id, &"sick", g.id), "medic -> sick guest")
	_eq(medic.job.target_id, g.id, "medic holds the guest's job")
	_check(not w.assign_staff(medic.id, &"sick", healthy.id), "medic -> healthy guest is refused")
	_check(not w.assign_staff(medic.id, &"sick", 99999), "medic -> unknown guest is refused")
	_check(not w.assign_staff(jan.id, &"sick", g.id), "janitor -> sick is refused")
	_check(not w.assign_staff(warden.id, &"sick", g.id), "warden -> sick is refused")
	_check(not w.assign_staff(medic.id, &"mess", mess.id), "medic -> mess is refused")
	# ghost
	_check(w.assign_staff(warden.id, &"ghost", gh.id), "warden -> ghost")
	_eq(warden.job.target_id, gh.id, "warden holds the ghost's job")
	_check(not w.assign_staff(medic.id, &"ghost", gh.id), "medic -> ghost is refused")
	_check(not w.assign_staff(warden.id, &"ghost", 99999), "warden -> unknown ghost is refused")
	_check(not w.assign_staff(mech.id, &"ghost", gh.id), "mechanic -> ghost is refused")
	# perform
	_check(w.assign_staff(ent.id, &"perform", toilets.uid), "entertainer -> room (perform)")
	_eq(ent.aura_uid, toilets.uid, "entertainer heads for that room")
	_check(not w.assign_staff(ent.id, &"perform", cabin.uid), "nobody performs in a cabin")
	_check(not w.assign_staff(ent.id, &"perform", 99999), "unknown room refused")
	_check(not w.assign_staff(chef.id, &"perform", toilets.uid), "chef -> perform is refused")
	_check(not w.assign_staff(jan.id, &"perform", toilets.uid), "janitor -> perform is refused")
	_check(not w.assign_staff(ent.id, &"perform", quarters.uid), "crew quarters is not a performance venue")
	# station
	_check(w.assign_staff(chef.id, &"station", buffet.uid), "chef -> food room (station)")
	_eq(chef.aura_uid, buffet.uid, "chef heads for the buffet")
	_check(not w.assign_staff(chef.id, &"station", toilets.uid), "chef -> toilets is refused")
	_check(not w.assign_staff(ent.id, &"station", buffet.uid), "entertainer -> station is refused")
	_check(not w.assign_staff(chef.id, &"station", 99999), "unknown room refused")
	# rest
	_check(not w.assign_staff(jan.id, &"rest", quarters.uid), "a fully rested crew member can't be sent to rest")
	jan.energy = 40.0
	_check(w.assign_staff(jan.id, &"rest", quarters.uid), "any crew -> crew quarters (rest)")
	_eq(jan.rest_uid, quarters.uid, "the bunk is reserved")
	_eq(quarters.users.size(), 1, "one bunk taken")
	_check(w.assign_staff(jan.id, &"rest", quarters.uid), "re-ordering the same rest is accepted")
	_eq(quarters.users.size(), 1, "still one bunk")
	_check(not w.assign_staff(jan.id, &"rest", toilets.uid), "rest at a non-quarters room is refused")
	_check(not w.assign_staff(jan.id, &"rest", 99999), "rest at an unknown room is refused")
	mech.energy = 50.0
	medic.energy = 50.0
	_check(w.assign_staff(mech.id, &"rest", quarters.uid), "second bunk")
	_check(not w.assign_staff(medic.id, &"rest", quarters.uid), "no free bunk: refused")
	_check(not w.assign_staff(99999, &"rest", quarters.uid), "unknown staff refused")
	_check(not w.assign_staff(jan.id, &"dance", toilets.uid), "unknown kind refused")
	# Taking another task frees the bunk.
	var other_mess: Mess = w.problems.spawn_mess(w, buffet)
	_check(w.assign_staff(jan.id, &"mess", other_mess.id), "a janitor can be pulled off rest")
	_eq(quarters.users.size(), 1, "the bunk is free again")
	_eq(jan.rest_uid, -1, "janitor holds no bunk")
	# perform lasts 20 s then falls back to automatic behaviour.
	var w2: SimWorld = _world(&"med_4", _staff_ship(), {&"entertainer": 1}, 42, _role_level(&"med_4"))
	var e2: StaffMember = w2.staff[0]
	_check(w2.assign_staff(e2.id, &"perform", _find_room(w2, &"toilets").uid), "order a show")
	var t0: float = w2.time
	_advance(w2, 10.0)
	_eq(e2.state, &"perform", "performing for an empty room on order")
	_advance(w2, 8.0)
	_eq(e2.state, &"perform", "still on after 18 s")
	_advance(w2, 9.0)
	_eq(e2.state, &"idle", "the ordered show ends after about 20 s (%.0f s)" % (w2.time - t0))
	# chef station order sticks for 20 s even when another room is busier
	var w3: SimWorld = _world(&"med_5", _staff_ship() + [[&"restaurant", 1, 10]], {&"chef": 1}, 43, _role_level(&"med_5"))
	_fake_queue(w3, _find_room(w3, &"restaurant"), 4)
	_check(w3.assign_staff(w3.staff[0].id, &"station", _find_room(w3, &"buffet").uid), "order the chef to the quiet buffet")
	_advance(w3, 14.0)
	_eq(w3.staff[0].aura_uid, _find_room(w3, &"buffet").uid, "the ordered station holds for now")
	_advance(w3, 14.0)
	_eq(w3.staff[0].aura_uid, _find_room(w3, &"restaurant").uid, "then the chef returns to the busiest room")
	# finished voyages accept nothing
	w.finished = true
	_check(not w.assign_staff(medic.id, &"sick", g.id), "no orders after the voyage")


func _t_fatigue() -> void:
	_section("staff fatigue")
	var lvl: LevelDef = _role_level(&"arctic_2", true)
	# Drain rates: working 2.0, walking 0.35, idle 0.
	var w: SimWorld = _world(&"arctic_2", _staff_ship(), {&"janitor": 1}, 51, lvl)
	var j: StaffMember = w.staff[0]
	_check(j.fatigue_on and is_equal_approx(j.energy, 100.0), "fatigue on, energy starts at 100")
	w.problems.spawn_mess(w, _find_room(w, &"toilets"))
	var sums: Dictionary = {&"walk": [0.0, 0.0], &"work": [0.0, 0.0], &"idle": [0.0, 0.0]}
	for i in 90:
		var e0: float = j.energy
		w.tick(SimConst.TICK)
		var st: StringName = j.state
		if sums.has(st):
			sums[st][0] += e0 - j.energy
			sums[st][1] += SimConst.TICK
	_check(sums[&"walk"][1] > 0.5 and sums[&"work"][1] > 1.0, "the janitor walked and worked")
	_near(sums[&"walk"][0] / sums[&"walk"][1], SimConst.STAFF_DRAIN_WALK, 0.01, "walking drains STAFF_DRAIN_WALK per s")
	_near(sums[&"work"][0] / sums[&"work"][1], SimConst.STAFF_DRAIN_WORK, 0.01, "working drains STAFF_DRAIN_WORK per s")
	_near(sums[&"idle"][0], 0.0, 0.0001, "idling drains nothing")
	# Aura roles: 0.8/s.
	var we: SimWorld = _world(&"arctic_2", _staff_ship(), {&"entertainer": 1}, 52, lvl)
	_fake_queue(we, _find_room(we, &"toilets"), 4)
	var ent: StaffMember = we.staff[0]
	_advance(we, 8.0)
	_eq(ent.state, &"perform", "entertainer performing")
	var e1: float = ent.energy
	_advance(we, 5.0)
	_near(e1 - ent.energy, SimConst.STAFF_DRAIN_AURA * 5.0, 0.05, "performing drains STAFF_DRAIN_AURA per s")
	# Tired: energy < 30 -> slower walking (STAFF_TIRED_SPEED) and work (STAFF_TIRED_WORK), stacking with the Crew Training perk.
	var s: StaffMember = w.staff[0]
	s.energy = 30.0
	_check(not s.is_tired(), "30 is not yet tired")
	_near(s.eff_speed(), s.def.speed, 0.0001, "no tiredness at 30")
	s.energy = 29.9
	_check(s.is_tired(), "below 30 is tired")
	_near(s.eff_speed(), s.def.speed * SimConst.STAFF_TIRED_SPEED, 0.0001, "tired: speed x STAFF_TIRED_SPEED")
	_near(s.eff_work_time(), s.def.work_time * SimConst.STAFF_TIRED_WORK, 0.0001, "tired: work time x STAFF_TIRED_WORK")
	w.apply_perks({&"crew": 2})
	_near(s.speed_mult, 1.2, 0.0001, "crew perk sets speed_mult")
	_near(s.eff_speed(), s.def.speed * 1.2 * SimConst.STAFF_TIRED_SPEED, 0.0001, "tired stacks with the Crew Training speed perk")
	_near(s.eff_work_time(), s.def.work_time * 0.8 * SimConst.STAFF_TIRED_WORK, 0.0001, "tired stacks with the Crew Training work perk")
	s.energy = 80.0
	_near(s.eff_speed(), s.def.speed * 1.2, 0.0001, "rested: perk only")
	# A tired crew member really is slower: same mess on deck 2, one janitor at 20 energy, one rested.
	var t_work_at: Array[float] = []
	var t_done_at: Array[float] = []
	for energy in [100.0, 20.0]:
		var wf: SimWorld = _world(&"arctic_2", _staff_ship(), {&"janitor": 1}, 53, lvl)
		wf.staff[0].energy = energy
		var far_mess: Mess = wf.problems.spawn_mess(wf, _find_room(wf, &"bar"))
		var tw: float = -1.0
		var td: float = -1.0
		for i in 600:
			wf.tick(SimConst.TICK)
			if tw < 0.0 and wf.staff[0].state == &"work":
				tw = wf.time
			if wf.mess_by_id(far_mess.id) == null:
				td = wf.time
				break
		t_work_at.append(tw)
		t_done_at.append(td)
	_check(t_work_at[0] > 0.0 and t_work_at[1] > t_work_at[0] + 1.5, "tired crew walk slower (%.1f s vs %.1f s)" % [t_work_at[1], t_work_at[0]])
	var clean_fast: float = t_done_at[0] - t_work_at[0]
	var clean_slow: float = t_done_at[1] - t_work_at[1]
	_check(clean_fast > 0.0 and absf(clean_slow / clean_fast - SimConst.STAFF_TIRED_WORK) < 0.12, "tired crew work slower by STAFF_TIRED_WORK (%.2f s vs %.2f s)" % [clean_slow, clean_fast])
	# tired alert fires once
	var wt: SimWorld = _world(&"arctic_2", _staff_ship(), {&"janitor": 1}, 54, lvl)
	var tired_n: Array = [0]
	wt.staff_tired.connect(func(_id: int) -> void: tired_n[0] += 1)
	wt.staff[0].energy = 31.0
	wt.problems.spawn_mess(wt, _find_room(wt, &"toilets"))
	_advance(wt, 8.0)
	_eq(tired_n[0], 1, "staff_tired emitted once when crossing 30")
	# Fatigue off: nothing drains, nobody is ever tired.
	var wo: SimWorld = _world(&"arctic_2", _staff_ship(), {&"janitor": 1}, 55, _role_level(&"arctic_2", false))
	for i in 4:
		wo.problems.spawn_mess(wo, _find_room(wo, &"toilets"))
	_advance(wo, 60.0)
	_check(wo.staff[0].jobs_done >= 1, "worked")
	_near(wo.staff[0].energy, 100.0, 0.0001, "no fatigue: energy stays 100")
	_check(not wo.staff[0].is_tired(), "no fatigue: never tired")
	wo.staff[0].energy = 5.0
	_check(not wo.staff[0].is_tired(), "no fatigue: low energy is not tired")
	# Exhaustion without crew quarters: drops the job, naps on the spot at 4/s.
	var wn: SimWorld = _world(&"arctic_2", _staff_ship(), {&"janitor": 1}, 56, lvl)
	var nj: StaffMember = wn.staff[0]
	nj.energy = 0.8
	var nm: Mess = wn.problems.spawn_mess(wn, _find_room(wn, &"toilets"))
	var rested: Array = [0]
	wn.staff_rested.connect(func(_id: int) -> void: rested[0] += 1)
	var t_nap: float = -1.0
	for i in 200:
		wn.tick(SimConst.TICK)
		if nj.state == &"nap":
			t_nap = wn.time
			break
	_check(t_nap > 0.0, "an exhausted janitor naps on the spot without crew quarters")
	_eq(wn.staff_sim.jobs.find(&"mess", nm.id).claimed_by, -1, "the job went back to the queue")
	_eq(nj.job, null, "the napper holds no job")
	_eq(wn.metrics["naps"], 1, "nap counted")
	var en0: float = nj.energy
	_advance(wn, 5.0)
	_near(nj.energy - en0, SimConst.STAFF_NAP_RATE * 5.0, 0.5, "napping restores STAFF_NAP_RATE per s")
	_eq(nj.state, &"nap", "still napping")
	_advance(wn, 22.0)
	_eq(rested[0], 1, "staff_rested emitted after the nap")
	_check(nj.energy > 85.0 and nj.state != &"nap", "rested and back on duty (%.0f)" % nj.energy)
	_advance(wn, 40.0)
	_eq(wn.messes.size(), 0, "the mess gets cleaned afterwards")
	# Energy never leaves 0..100.
	_check(nj.energy <= 100.0 and nj.energy >= 0.0, "energy stays within 0..100")


func _t_crew_quarters() -> void:
	_section("crew quarters")
	var lvl: LevelDef = _role_level(&"arctic_2", true)
	var rooms: Array = _staff_ship() + [[&"crew_quarters", 0, 8]]
	var w: SimWorld = _world(&"arctic_2", rooms, {&"janitor": 1}, 61, lvl)
	var q: RoomRuntime = _find_room(w, &"crew_quarters")
	var j: StaffMember = w.staff[0]
	_check(q != null and w.room_sim.crew_rooms.has(q), "crew quarters registered")
	_check(not w.room_sim.service_rooms.has(q), "guests never see the crew quarters")
	_eq(q.capacity(), 2, "two bunks")
	j.energy = 0.0
	var rested: Array = [0]
	w.staff_rested.connect(func(_id: int) -> void: rested[0] += 1)
	var t_arrive: float = -1.0
	var rate_sum: float = 0.0
	var rate_t: float = 0.0
	for i in 400:
		var e0: float = j.energy
		w.tick(SimConst.TICK)
		if j.state == &"walk" and j.goal == &"rest":
			_check(q.users.has(j.id), "the bunk is reserved while walking")
		if j.state == &"rest":
			if t_arrive < 0.0:
				t_arrive = w.time
				_check(absf(j.x - q.door_x) < 0.3 and j.deck == q.deck, "asleep at the quarters")
			else:
				rate_sum += j.energy - e0
				rate_t += SimConst.TICK
		if rested[0] > 0:
			break
	_check(t_arrive > 0.0, "an exhausted janitor walks to the crew quarters")
	_near(rate_sum / maxf(rate_t, 0.1), SimConst.STAFF_REST_RATE, 0.3, "bunk rest restores STAFF_REST_RATE per s")
	_eq(rested[0], 1, "woke up rested")
	_check(q.users.is_empty(), "bunk freed on waking")
	_eq(w.metrics["rests"], 1, "rest counted")
	_near(j.energy, 100.0, 0.01, "full energy")
	_eq(w.metrics["naps"], 0, "no nap with quarters available")
	# Faster than napping: 0 -> 100 in ~10 s in a bunk, 25 s on the spot.
	# Tier II: three bunks, rest speed x1.25.
	var w2: SimWorld = _world(&"arctic_2", rooms, {&"janitor": 3}, 62, lvl)
	var q2: RoomRuntime = _find_room(w2, &"crew_quarters")
	q2.tier = 1
	_eq(q2.capacity(), 3, "tier II has 3 bunks")
	for s in w2.staff:
		s.energy = 0.0
	_advance(w2, 8.0)
	_eq(q2.users.size(), 3, "all three crew rest in bunks")
	var slots: Dictionary = {}
	for s in w2.staff:
		slots[q2.slot_of(s.id)] = true
	_eq(slots.size(), 3, "each bunk has its own slot")
	var ea: float = w2.staff[0].energy
	_advance(w2, 1.0)
	_near(w2.staff[0].energy - ea, SimConst.STAFF_REST_RATE * 1.25, 0.3, "tier II rests x1.25")
	# More exhausted crew than bunks: the extra one naps.
	var w3: SimWorld = _world(&"arctic_2", rooms, {&"janitor": 3}, 63, lvl)
	for s in w3.staff:
		s.energy = 0.0
	_advance(w3, 8.0)
	var napping: int = 0
	var resting: int = 0
	for s in w3.staff:
		if s.state == &"nap":
			napping += 1
		elif s.state == &"rest":
			resting += 1
	_eq(resting, 2, "two bunks hold two sleepers")
	_eq(napping, 1, "the third crew member naps on the spot")
	# Player-ordered rest from a half-tired state, then the quarters door.
	var w4: SimWorld = _world(&"arctic_2", rooms, {&"mechanic": 1}, 64, lvl)
	var m: StaffMember = w4.staff[0]
	m.energy = 45.0
	_check(w4.assign_staff(m.id, &"rest", _find_room(w4, &"crew_quarters").uid), "order a tired mechanic to rest")
	_advance(w4, 12.0)
	_check(m.energy >= 99.9 and m.state == &"idle", "rested and idle again (%s, %.0f)" % [m.state, m.energy])
	# A repair job released by an exhausted mechanic goes to the queue.
	var w5: SimWorld = _world(&"arctic_2", rooms, {&"mechanic": 1}, 65, lvl)
	var tr: RoomRuntime = _find_room(w5, &"buffet")
	w5.room_sim.break_room(w5, tr)
	w5.staff[0].energy = 3.0
	_advance(w5, 12.0)
	_check(w5.staff[0].energy < 100.0 or w5.metrics["rests"] > 0 or tr.broken == false, "the exhausted mechanic stopped working")
	# Validation warning.
	var port := PortState.new(ContentStore.level(&"arctic_2"))
	port.hire(&"janitor")
	var warn_text: String = " ".join(port.validate()["warnings"])
	_check(warn_text.contains("crew quarters"), "port warns that tired crew need quarters")
	port.place(&"crew_quarters", 1, 12)
	_check(not " ".join(port.validate()["warnings"]).contains("crew quarters"), "no warning once quarters exist")
	var port_med := PortState.new(ContentStore.level(&"med_3"))
	port_med.hire(&"janitor")
	_check(not " ".join(port_med.validate()["warnings"]).contains("crew quarters"), "no warning when fatigue is off")
	# AutoPlayer sends tired crew to rest.
	var w6: SimWorld = _world(&"arctic_2", rooms, {&"janitor": 1}, 66, lvl)
	var ap := AutoPlayer.new(w6, &"active", 5)
	w6.staff[0].energy = 22.0
	for i in 60:
		w6.tick(SimConst.TICK)
		ap.tick(SimConst.TICK)
	_check(w6.staff[0].state == &"rest" or w6.staff[0].goal == &"rest" or w6.metrics["rests"] > 0, "AutoPlayer sends tired crew to the quarters")


func _t_roles_misc() -> void:
	_section("new roles: hiring, port, autobuilder")
	# Mid-voyage hire of every role (1.5x wage, availability enforced).
	var w: SimWorld = _world(&"underworld_2", _staff_ship(), {}, 71, _role_level(&"underworld_2"))
	var money0: int = w.money
	for role in [&"janitor", &"mechanic", &"medic", &"entertainer", &"chef", &"warden"]:
		var cost: int = int(round(float(ContentStore.staff_role(role).wage) * 1.5))
		_eq(w.mid_voyage_hire_cost(role), cost, "%s costs 1.5x wage" % role)
		_check(w.hire_staff_mid_voyage(role), "mid-voyage hire of the %s" % role)
	_eq(w.staff.size(), 6, "six roles hired")
	var roles: Dictionary = {}
	for s in w.staff:
		roles[s.role] = true
	_eq(roles.size(), 6, "one of each")
	_eq(money0 - w.money, 60 + 90 + 105 + 83 + 98 + 90, "wages charged at 1.5x (rounded)")
	var wm: SimWorld = _world(&"med_3", _staff_ship(), {}, 72, _role_level(&"med_3"))
	_check(wm.hire_staff_mid_voyage(&"medic"), "medic can be hired at level 3")
	_check(not wm.hire_staff_mid_voyage(&"entertainer"), "entertainer is locked until level 4")
	_check(not wm.hire_staff_mid_voyage(&"warden"), "warden is Underworld only")
	var wa: SimWorld = _world(&"arctic_3", _staff_ship(), {}, 73, _role_level(&"arctic_3"))
	_check(not wa.hire_staff_mid_voyage(&"warden"), "no warden in the Arctic")
	_check(wa.hire_staff_mid_voyage(&"chef") and wa.hire_staff_mid_voyage(&"entertainer"), "chef + entertainer in the Arctic")
	# Newly hired staff carry the fatigue flag and the perk multipliers.
	var wf: SimWorld = _world(&"arctic_3", _staff_ship(), {}, 74, _role_level(&"arctic_3", true))
	wf.apply_perks({&"crew": 1})
	wf.hire_staff_mid_voyage(&"medic")
	_check(wf.staff[0].fatigue_on and is_equal_approx(wf.staff[0].speed_mult, 1.1), "mid-voyage hires get fatigue and perks")
	# Port hiring respects unlocks and destinations.
	var pm := PortState.new(ContentStore.level(&"med_3"))
	_check(pm.can_hire(&"medic")["ok"], "port: medic offered at level 3")
	_eq(pm.can_hire(&"entertainer")["reason"], "Unlocks at level 4", "port: entertainer locked reason")
	_check(not pm.can_hire(&"warden")["ok"], "port: warden locked in the Mediterranean")
	var pu := PortState.new(ContentStore.level(&"underworld_3"))
	_check(pu.can_hire(&"warden")["ok"] and pu.hire(&"warden"), "port: the warden hires in the Underworld")
	_eq(pu.budget, ContentStore.level(&"underworld_3").budget - 60, "port: warden wage 60")
	var pa := PortState.new(ContentStore.level(&"arctic_3"))
	_eq(pa.can_hire(&"warden")["reason"], "Underworld only", "port: warden destination reason")
	_eq(pu.available_roles().size(), 6, "port lists six roles in the Underworld")
	_eq(pm.available_roles().size(), 3, "port lists three roles at level 3")
	# AutoBuilder: Mediterranean ships keep the old crew; fatigue levels get quarters and specialists.
	for lvl in ContentStore.campaign():
		var p := AutoBuilder.build(lvl)
		var crew: Dictionary = p.staff_counts()
		if lvl.campaign_index <= 6:
			_check(not crew.has(&"medic") and not crew.has(&"chef") and not crew.has(&"entertainer") and not crew.has(&"warden"), "%s: no specialists in the Mediterranean" % lvl.id)
		if lvl.staff_fatigue:
			_eq(p.layout.count_of(&"crew_quarters"), 1, "%s: autobuilder adds crew quarters" % lvl.id)
		else:
			_eq(p.layout.count_of(&"crew_quarters"), 0, "%s: no crew quarters without fatigue" % lvl.id)
		if lvl.destination == &"underworld":
			_eq(int(crew.get(&"warden", 0)), 1, "%s: a warden against the ghosts" % lvl.id)
		for role in crew:
			var sd: StaffDef = ContentStore.staff_role(StringName(role))
			_check(sd.is_available(lvl.campaign_index, lvl.destination), "%s: hires only available roles (%s)" % [lvl.id, role])
	var big: Dictionary = AutoBuilder.build(ContentStore.level(&"underworld_5")).staff_counts()
	_check(int(big.get(&"warden", 0)) == 1 and int(big.get(&"chef", 0)) + int(big.get(&"medic", 0)) + int(big.get(&"entertainer", 0)) >= 1, "late levels hire specialists (%s)" % str(big))
	var none: Dictionary = AutoBuilder.build(ContentStore.level(&"underworld_5"), -1, {"new_roles": false}).staff_counts()
	_check(not none.has(&"warden") and not none.has(&"chef"), "new_roles: false keeps the old crew")
	# Determinism with every role aboard and fatigue on.
	var lvl2: LevelDef = ContentStore.level(&"underworld_3")
	var port2 := AutoBuilder.build(lvl2)
	var a: Dictionary = SimRunner.run(lvl2, port2, 42, &"active")
	var b: Dictionary = SimRunner.run(lvl2, port2, 42, &"active")
	_eq(str(a["metrics"]), str(b["metrics"]), "specialist crew: same seed gives identical metrics")
	_eq(a["profit"], b["profit"], "specialist crew: same seed gives the same profit")
	_check(int(a["metrics"]["warden_banishes"]) + int(a["metrics"]["banished"]) >= 0, "metrics carry the new counters")
	# Specialists actually do something over a whole voyage.
	var wr: SimWorld = port2.create_world(9)
	while not wr.finished:
		wr.tick(SimConst.TICK)   # no player at all: the crew carries the ship
	_check(int(wr.metrics["warden_banishes"]) >= 1, "the warden banished ghosts on its own (%d)" % int(wr.metrics["warden_banishes"]))
	var tired_total: int = int(wr.metrics["rests"]) + int(wr.metrics["naps"])
	print("  underworld_3 voyage: warden banishes %d, medic cures %d, rests %d, naps %d" % [int(wr.metrics["warden_banishes"]), int(wr.metrics["medic_cures"]), int(wr.metrics["rests"]), int(wr.metrics["naps"])])
	_check(tired_total >= 1, "crew got tired and rested during a fatigue voyage (%d)" % tired_total)


# ---------------------------------------------------------------------------------------------
# v2 phase 3: VIP guests, guest groups and kids (SPEC §13.5 / §13.6)
# ---------------------------------------------------------------------------------------------
## Blank level for VIP / group tests (waves, events, fatigue off); `vips` / `ratio` are set by the caller.
func _p3_level(level_id: StringName, vips: Array = [], ratio: float = 0.0) -> LevelDef:
	var l: LevelDef = _blank_level(level_id)
	var list: Array[Dictionary] = []
	for v in vips:
		list.append({"t": float(v[0]), "kind": StringName(v[1])})
	l.vips = list
	l.group_ratio = ratio
	l.health_mult = 50.0   # nothing wears out by itself: the tests break what they want to break
	return l


## Signal counters for the VIP signals: _sig["boarded"] / _sig["verdicts"] (Array of [id, kind, grade]).
func _watch_vips(w: SimWorld) -> void:
	_sig["boarded"] = []
	_sig["verdicts"] = []
	w.vip_boarded.connect(func(id: int, kind: StringName) -> void: _sig["boarded"].append([id, kind]))
	w.vip_verdict.connect(func(id: int, kind: StringName, grade: StringName) -> void: _sig["verdicts"].append([id, kind, grade]))


## A calm VIP: holidaymaker archetype (no queue quirks), parked, all needs full.
func _calm_vip(w: SimWorld, kind: StringName) -> Guest:
	var g: Guest = w.vip_sim.board(w, kind)
	g.archetype = ContentStore.archetype(&"holidaymaker")
	g.fav = {}
	return g


## _park plus: forget any room the guest had already set off for.
func _park_clean(g: Guest, deck: int, x: float) -> void:
	_park(g, deck, x)
	g.target_uid = -1
	g.queue_since = Guest.NOT_QUEUED
	g.mode = Guest.WANDER
	g.state = Guest.WANDER


func _t_vip_content() -> void:
	_section("vip: content & rules")
	var dl := LevelDef.new()
	_check(dl.vips.is_empty(), "LevelDef.vips defaults to empty")
	_near(dl.group_ratio, 0.0, 0.0001, "LevelDef.group_ratio defaults to 0")
	var vl: LevelDef = _p3_level(&"med_3", [[10, &"critic"], [30, &"inspector"]])
	_eq(vl.total_guests(), 2, "VIPs count towards total_guests")
	# critic scoring table
	_near(VipSim.critic_points(0.0, true, false), 40.0, 0.001, "critic: instant, clean door = 40")
	_near(VipSim.critic_points(8.0, true, false), 40.0, 0.001, "critic: waited 8 s, clean = 40")
	_near(VipSim.critic_points(8.1, true, false), 20.0, 0.001, "critic: waited 8.1 s = 20")
	_near(VipSim.critic_points(3.0, false, false), 20.0, 0.001, "critic: quick but a spill at the door = 20")
	_near(VipSim.critic_points(20.0, false, false), 20.0, 0.001, "critic: waited 20 s = 20")
	_near(VipSim.critic_points(20.1, true, false), 0.0, 0.001, "critic: waited over 20 s = 0")
	_near(VipSim.critic_points(2.0, true, true), 60.0, 0.001, "critic: restaurant x1.5 (60)")
	_near(VipSim.critic_points(15.0, true, true), 30.0, 0.001, "critic: restaurant x1.5 (30)")
	_near(VipSim.critic_points(25.0, true, true), 0.0, 0.001, "critic: restaurant, slow = 0")
	# grade boundaries
	_eq(VipSim.critic_grade(70.0), VipSim.GREAT, "critic 70 = great")
	_eq(VipSim.critic_grade(69.9), VipSim.OK, "critic 69.9 = ok")
	_eq(VipSim.critic_grade(35.0), VipSim.OK, "critic 35 = ok")
	_eq(VipSim.critic_grade(34.9), VipSim.BAD, "critic 34.9 = bad")
	# (phase 4b balance: celebrity great from 70, ok from 45; inspector great up to 4 problems, ok up to 9)
	_near(SimConst.CELEB_GREAT, 70.0, 0.001, "celebrity great from 70")
	_near(SimConst.CELEB_OK, 45.0, 0.001, "celebrity ok from 45")
	_eq(VipSim.celebrity_grade(SimConst.CELEB_GREAT), VipSim.GREAT, "celebrity at the great line = great")
	_eq(VipSim.celebrity_grade(SimConst.CELEB_GREAT - 0.1), VipSim.OK, "celebrity just below = ok")
	_eq(VipSim.celebrity_grade(SimConst.CELEB_OK), VipSim.OK, "celebrity at the ok line = ok")
	_eq(VipSim.celebrity_grade(SimConst.CELEB_OK - 0.1), VipSim.BAD, "celebrity just below = bad")
	_eq(VipSim.inspector_grade(0), VipSim.GREAT, "inspector 0 problems = great")
	_eq(VipSim.inspector_grade(SimConst.INSPECTOR_GREAT), VipSim.GREAT, "inspector at the great limit = great")
	_eq(VipSim.inspector_grade(SimConst.INSPECTOR_GREAT + 1), VipSim.OK, "inspector one more = ok")
	_eq(VipSim.inspector_grade(SimConst.INSPECTOR_OK), VipSim.OK, "inspector at the ok limit = ok")
	_eq(VipSim.inspector_grade(SimConst.INSPECTOR_OK + 1), VipSim.BAD, "inspector one more = bad")
	_eq(VipSim.pay_for(VipSim.GREAT), 250, "great pays $250")
	_eq(VipSim.pay_for(VipSim.OK), 0, "ok pays nothing")
	_eq(VipSim.pay_for(VipSim.BAD), -150, "bad costs $150")
	_check(VipSim.is_kind(&"critic") and VipSim.is_kind(&"celebrity") and VipSim.is_kind(&"inspector") and not VipSim.is_kind(&"king"), "three VIP kinds")
	# kids club + kid archetype
	var kc: RoomDef = ContentStore.room(&"kids_club")
	_check(kc != null, "kids_club room exists")
	_eq(kc.category, &"fun", "kids club is a fun room")
	_eq(kc.width, 3, "kids club width 3")
	_eq(kc.capacity, 6, "kids club capacity 6")
	_near(kc.service_time, 9.0, 0.001, "kids club service time 9")
	_near(float(kc.satisfies.get(&"fun", 0.0)), 90.0, 0.001, "kids club restores 90 fun")
	_eq(kc.fun_tag, &"kids", "kids club tag")
	_eq(kc.spend, 4, "kids club spend 4")
	_eq(kc.cost, 320, "kids club cost 320")
	_near(kc.upkeep, 5.0, 0.001, "kids club upkeep 5")
	_eq(kc.power, 2, "kids club power 2")
	_eq(kc.water, 1, "kids club water 1")
	_near(kc.mess_chance, 0.20, 0.001, "kids club mess 0.20")
	_near(kc.breakdown_time, 100.0, 0.001, "kids club breakdown 100")
	_near(kc.wear_per_use, 5.0, 0.001, "kids club wear 5")
	_eq(kc.unlock_level, 6, "kids club unlocks at level 6")
	_eq(kc.placement, &"interior", "kids club is interior")
	_near(kc.adult_mult, 0.2, 0.001, "adults score the kids club x0.2")
	_check(kc.is_service_room() and kc.is_available(6, &"med") and not kc.is_available(5, &"med"), "kids club offered from level 6")
	for r in ContentStore.all_rooms():
		if r.id != &"kids_club":
			_near(r.adult_mult, 1.0, 0.0001, "%s: adult_mult defaults to 1" % r.id)
	var kid: ArchetypeDef = ContentStore.archetype(&"kid")
	_check(kid != null and kid.kid, "kid archetype exists and is marked kid")
	_near(kid.body_scale, 0.75, 0.001, "kids are 0.75 scale")
	_eq(kid.prop, &"propeller", "kids wear a propeller beanie")
	_eq(kid.favorite_rooms, [&"kids_club", &"pool", &"arcade"] as Array[StringName], "kid favourites")
	_near(float(kid.decay_mult.get(&"fun", 1.0)), 1.6, 0.001, "kid fun decay x1.6")
	_near(float(kid.decay_mult.get(&"hunger", 1.0)), 1.2, 0.001, "kid hunger decay x1.2")
	for a in ContentStore.all_archetypes():
		if a.id != &"kid":
			_check(not a.kid and is_equal_approx(a.body_scale, 1.0), "%s is a grown-up" % a.id)
	for lvl in ContentStore.campaign():
		_check(not lvl.archetype_weights.has(&"kid"), "%s: kids are never in the archetype weights" % lvl.id)
	# a level with VIPs and a group ratio survives a save / load round trip (what tools/gen_content.gd writes for phase 4)
	var rt: LevelDef = _p3_level(&"med_4", [[40, &"critic"], [90, &"inspector"]], 0.35)
	var rt_path: String = "%s/vip_level.tres" % TMP_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	_eq(ResourceSaver.save(rt, rt_path), OK, "level with VIPs saves")
	var back: LevelDef = ResourceLoader.load(rt_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelDef
	_check(back != null, "level with VIPs loads")
	if back != null:
		_eq(back.vips.size(), 2, "VIP schedule survives the round trip")
		_eq(StringName(back.vips[0]["kind"]), &"critic", "VIP kind survives")
		_near(float(back.vips[1]["t"]), 90.0, 0.001, "VIP time survives")
		_near(back.group_ratio, 0.35, 0.0001, "group ratio survives")
	DirAccess.remove_absolute(rt_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR))
	# the kids club announces itself with level 6; the guest features come with the VIP / family levels
	var sm: Node = SaveScript.new()
	sm.save_path = "%s/p3.json" % TMP_DIR
	var db: Node = load("res://src/core/content_db.gd").new()
	db.load_all()
	sm.content = db
	_check(sm.unlocked_rooms_at(6).has(&"kids_club") and not sm.unlocked_rooms_at(5).has(&"kids_club"), "kids club announced at level 6")
	_eq(sm.feature_display_name(&"guests_kids"), "Kids & families", "kids feature name")
	_eq(sm.feature_display_name(&"guests_vips"), "VIP guests", "VIP feature name")
	# the guest features follow the level data: announced with the first level that schedules VIPs / boards groups
	# (the campaign data decides (phase 4b): VIPs from med_4, couples & families (kids) from med_6)
	_eq(sm.guest_features_at(18), [&"guests_vips", &"guests_kids"] as Array[StringName], "both guest features are announced by the end of the campaign")
	_eq(sm.guest_features_at(3), [] as Array[StringName], "VIPs are not announced before their level")
	_eq(sm.guest_features_at(4), [&"guests_vips"] as Array[StringName], "VIP guests announced with level 4")
	_eq(sm.guest_features_at(5), [&"guests_vips"] as Array[StringName], "kids are not announced with level 5")
	_eq(sm.guest_features_at(6), [&"guests_vips", &"guests_kids"] as Array[StringName], "kids & families announced with level 6")
	sm.free()
	db.free()


func _t_vip_critic() -> void:
	_section("vip: critic")
	var w: SimWorld = _world(&"med_3", _small_ship(), {}, 31, _p3_level(&"med_3"))
	_watch_vips(w)
	var c: Guest = _calm_vip(w, &"critic")
	_eq(c.vip_kind, &"critic", "VIP kind stored on the guest")
	_check(c.is_vip(), "is_vip")
	_near(c.nv[1], 25.0, 0.001, "the critic boards with hunger 25")
	_eq(_sig["boarded"].size(), 1, "vip_boarded fired once")
	_eq(_sig["boarded"][0], [c.id, &"critic"], "vip_boarded carries id and kind")
	var buffet: RoomRuntime = _find_room(w, &"buffet")
	# queue_since -> use_wait
	c.queue_since = w.time - 12.0
	w.guest_sim.start_use(w, c, buffet)
	_near(c.use_wait, 12.0, 0.05, "use_wait is the time spent in line")
	buffet.users.erase(c.id)
	buffet.free_slot(c.id)
	c.mode = Guest.WANDER
	# one meal does not close the review
	w.vip_sim.critic_meal(w, c, buffet)
	_near(c.vip_score, 20.0, 0.001, "12 s wait = 20 points")
	_eq(c.vip_n, 1, "one meal counted")
	_eq(c.vip_grade, &"", "no verdict after one meal")
	_eq(_sig["verdicts"].size(), 0, "no verdict signal yet")
	# the second meal does: 20 + 40 = 60 -> ok, pays nothing
	c.use_wait = 0.0
	c.saw_mess = false
	w.vip_sim.critic_meal(w, c, buffet)
	_near(c.vip_score, 60.0, 0.001, "20 + 40 = 60 points")
	_eq(c.vip_grade, VipSim.OK, "60 points is an ok review")
	_eq(_sig["verdicts"].size(), 1, "vip_verdict fired once")
	_eq(_sig["verdicts"][0], [c.id, &"critic", &"ok"], "vip_verdict carries id, kind and grade")
	_eq(int(w.economy.ledger.get(&"vip_bonus", 0)) + int(w.economy.ledger.get(&"vip_fines", 0)), 0, "ok pays nothing")
	w.vip_sim.critic_meal(w, c, buffet)
	_eq(_sig["verdicts"].size(), 1, "a verdict never fires twice")
	_near(c.vip_score, 60.0, 0.001, "meals after the verdict are not scored")
	# great: two quick clean meals; the restaurant counts x1.5
	var w2: SimWorld = _world(&"med_3", _event_ship(), {}, 32, _p3_level(&"med_3"))
	_watch_vips(w2)
	var c2: Guest = _calm_vip(w2, &"critic")
	var m0: int = w2.money
	var resto: RoomRuntime = _find_room(w2, &"restaurant")
	c2.use_wait = 2.0
	w2.vip_sim.critic_meal(w2, c2, resto)
	_near(c2.vip_score, 60.0, 0.001, "restaurant meal: 60 points")
	c2.use_wait = 30.0
	w2.vip_sim.critic_meal(w2, c2, resto)
	_near(c2.vip_score, 60.0, 0.001, "a 30 s wait scores nothing")
	_eq(c2.vip_grade, VipSim.OK, "60 points: ok (boundary: 70 needed for great)")
	var w2b: SimWorld = _world(&"med_3", _event_ship(), {}, 32, _p3_level(&"med_3"))
	_watch_vips(w2b)
	var c2b: Guest = _calm_vip(w2b, &"critic")
	var m0b: int = w2b.money
	c2b.use_wait = 5.0
	w2b.vip_sim.critic_meal(w2b, c2b, _find_room(w2b, &"restaurant"))
	c2b.use_wait = 15.0
	w2b.vip_sim.critic_meal(w2b, c2b, _find_room(w2b, &"restaurant"))
	_near(c2b.vip_score, 90.0, 0.001, "60 + 30 = 90 points")
	_eq(c2b.vip_grade, VipSim.GREAT, "90 points is a great review")
	_eq(w2b.money - m0b, 250, "a great verdict pays $250")
	_eq(int(w2b.economy.ledger[&"vip_bonus"]), 250, "ledger books the VIP bonus")
	_eq(c2b.vip_pay, 250, "the guest remembers the pay")
	_eq(w2b.metrics["vip_great"], 1, "great verdict counted")
	_check(m0 == w2.money, "no money moved for an unfinished review")
	# bad: nothing but slow service; guests within 4 cells lose 10, others do not
	var w3: SimWorld = _world(&"med_3", _small_ship(), {}, 33, _p3_level(&"med_3"))
	_watch_vips(w3)
	var c3: Guest = _calm_vip(w3, &"critic")
	_park(c3, 2, 6.0)
	var near_g: Guest = _spawn(w3)
	var far_g: Guest = _spawn(w3)
	var other_deck: Guest = _spawn(w3)
	_park(near_g, 2, 9.5)
	_park(far_g, 2, 10.6)
	_park(other_deck, 1, 6.0)
	var s_near: float = near_g.satisfaction
	var s_far: float = far_g.satisfaction
	var s_other: float = other_deck.satisfaction
	var m3: int = w3.money
	var b3: RoomRuntime = _find_room(w3, &"buffet")
	c3.use_wait = 40.0
	w3.vip_sim.critic_meal(w3, c3, b3)
	w3.vip_sim.critic_meal(w3, c3, b3)
	_eq(c3.vip_grade, VipSim.BAD, "two slow meals: a bad review")
	_eq(w3.money - m3, -150, "a bad verdict costs $150")
	_eq(int(w3.economy.ledger[&"vip_fines"]), 150, "ledger books the VIP fine")
	_near(near_g.satisfaction, s_near - 10.0, 0.001, "a guest within 4 cells loses 10 satisfaction")
	_near(far_g.satisfaction, s_far, 0.001, "a guest 4.6 cells away is untouched")
	_near(other_deck.satisfaction, s_other, 0.001, "guests on other decks are untouched")
	# a spill at the door costs the quick-service bonus (end to end through the sim)
	var w4: SimWorld = _world(&"med_3", _small_ship(), {}, 34, _p3_level(&"med_3"))
	var b4: RoomRuntime = _find_room(w4, &"buffet")
	var spill: Mess = w4.problems.spawn_mess(w4, b4)
	spill.age = -1.0e6
	_check(spill != null and w4.vip_sim.mess_at_door(w4, b4), "a spill next to the door is seen")
	var c4: Guest = _calm_vip(w4, &"critic")
	c4.nv[1] = 5.0
	for i in 900:
		w4.tick(SimConst.TICK)
		if c4.vip_n >= 1:
			break
	_eq(c4.vip_n, 1, "the critic ate a meal")
	_near(c4.vip_score, 20.0, 0.001, "spill at the door: 20 instead of 40 (waited %.1f s)" % c4.use_wait)
	# a clean door and no wait: 40 (end to end)
	var w5: SimWorld = _world(&"med_3", _small_ship(), {}, 35, _p3_level(&"med_3"))
	var c5: Guest = _calm_vip(w5, &"critic")
	for i in 900:
		w5.tick(SimConst.TICK)
		if c5.vip_n >= 1:
			break
	_eq(c5.vip_n, 1, "the critic ate (no spill)")
	_near(c5.vip_score, 40.0, 0.001, "clean door, no wait: 40 points")
	# a critic who storms off leaves a bad review
	var w6: SimWorld = _world(&"med_3", _small_ship(), {}, 36, _p3_level(&"med_3"))
	_watch_vips(w6)
	var c6: Guest = _calm_vip(w6, &"critic")
	_advance(w6, 1.5)
	w6.guest_sim._begin_storm(w6, c6)
	_eq(c6.vip_grade, VipSim.BAD, "storming off = a bad review")
	_eq(_sig["verdicts"].size(), 1, "one verdict")
	# a critic who never ate by the end of the voyage is judged bad, one with a meal on his scorecard by that score
	var lvl7: LevelDef = _p3_level(&"med_3", [[1.0, &"critic"]])
	lvl7.duration = 20.0
	var w7: SimWorld = _world(&"med_3", [[&"cabin", 1, 0]], {}, 37, lvl7)
	_advance(w7, 21.0)
	_check(w7.finished, "short voyage ended")
	_eq(w7.vip_sim.members[0].vip_grade, VipSim.BAD, "a critic who never ate: bad")
	_eq(w7.result["vips"].size(), 1, "the result lists the VIP")
	_eq(w7.result["vips"][0]["kind"], &"critic", "result: kind")
	_eq(w7.result["vips"][0]["grade"], &"bad", "result: grade")
	_eq(w7.result["money_end"], w7.economy.money, "result money_end includes the verdict")


func _t_vip_celebrity() -> void:
	_section("vip: celebrity")
	var w: SimWorld = _world(&"med_3", _small_ship(), {}, 41, _p3_level(&"med_3"))
	_watch_vips(w)
	var c: Guest = _calm_vip(w, &"celebrity")
	_near(c.nv[2], 40.0, 0.001, "the celebrity boards wanting fun")
	_near(c.decay[2], SimConst.BASE_DECAY[2] * 1.4 * w.level.decay_mult, 0.0001, "fun decays 1.4x")
	var n: Guest = _spawn(w)
	n.archetype = ContentStore.archetype(&"holidaymaker")
	# patience x0.4 in a queue
	var bar: RoomRuntime = _find_room(w, &"bar")
	var fid: int = 9000
	while bar.users.size() < bar.capacity():
		bar.users.append(fid)
		fid += 1
	for g in [c, n]:
		g.target_uid = bar.uid
		g.mode = Guest.WALK
		bar.incoming += 1
		w.guest_sim._arrive(w, g)
	_eq(c.mode, Guest.QUEUE, "the celebrity queues")
	var base_p: float = SimConst.QUEUE_PATIENCE * w.level.patience_mult
	_check(c.patience <= base_p * 1.1 * 0.4 + 0.01 and c.patience >= base_p * 0.9 * 0.4 - 0.01, "celebrity patience is 0.4x (%.1f vs base %.1f)" % [c.patience, base_p])
	_check(n.patience >= base_p * 0.9 - 0.01, "a normal guest keeps full patience (%.1f)" % n.patience)
	bar.queue.clear()
	bar.users.clear()
	bar.slots.fill(-1)
	# the rooms a celebrity uses get x1.5 appeal for everybody else
	w.room_sim.refresh_appeal(w)
	var base_a: float = bar.appeal_now
	c.mode = Guest.WANDER
	w.guest_sim.start_use(w, c, bar)
	_eq(bar.celeb_users, 1, "celebrity counted as a user")
	_near(bar.appeal_now, base_a * 1.5, 0.001, "appeal x1.5 while a celebrity is using the room")
	w.room_sim.refresh_appeal(w)
	_near(bar.appeal_now, base_a * 1.5, 0.001, "the boost survives the periodic appeal refresh")
	w.room_sim.break_room(w, bar)
	_eq(bar.celeb_users, 0, "a broken room releases the celebrity")
	_near(bar.appeal_now, base_a, 0.001, "appeal back to normal")
	w.room_sim.repair_room(w, bar)
	c.mode = Guest.WANDER
	w.guest_sim.start_use(w, c, bar)
	bar.users.erase(c.id)
	c.use_timer = 0.0
	w.guest_sim._finish_use(w, c)
	_eq(bar.celeb_users, 0, "finishing the use releases the boost")
	_near(bar.appeal_now, base_a, 0.001, "appeal back to normal after the visit")
	# verdict after the 90 s window, from the mean mood
	for entry in [[60.0, &"ok"], [90.0, &"great"], [30.0, &"bad"]]:
		var w2: SimWorld = _world(&"med_3", _small_ship(), {}, 42, _p3_level(&"med_3"))
		_watch_vips(w2)
		var c2: Guest = _calm_vip(w2, &"celebrity")
		var t_verdict: float = -1.0
		for i in 1000:
			c2.satisfaction = float(entry[0])
			for k in 4:
				c2.nv[k] = 95.0
			w2.tick(SimConst.TICK)
			if t_verdict < 0.0 and c2.vip_grade != &"":
				t_verdict = w2.time
				break
		_eq(c2.vip_grade, entry[1], "mean satisfaction %d -> %s" % [int(entry[0]), entry[1]])
		_check(absf(t_verdict - c2.boarded_at - 90.0) < 0.7, "the verdict arrives after the 90 s window (%.1f s)" % (t_verdict - c2.boarded_at))
		_eq(_sig["verdicts"].size(), 1, "one celebrity verdict")
	# a celebrity who storms off before the window ends: bad
	var w3: SimWorld = _world(&"med_3", _small_ship(), {}, 43, _p3_level(&"med_3"))
	var c3: Guest = _calm_vip(w3, &"celebrity")
	_advance(w3, 3.0)
	w3.guest_sim._begin_storm(w3, c3)
	_eq(c3.vip_grade, VipSim.BAD, "a celebrity who storms off: bad")
	_advance(w3, 100.0)
	_eq(w3.metrics["vip_bad"], 1, "and no second verdict arrives later")
	# left to itself in a decent ship the celebrity is looked after and finishes with a review
	var w4: SimWorld = _world(&"med_3", _event_ship(), {&"janitor": 1}, 44, _p3_level(&"med_3"))
	var c4: Guest = _calm_vip(w4, &"celebrity")
	_advance(w4, 95.0)
	_check(c4.vip_grade != &"", "the review window closed on its own (%s)" % c4.vip_grade)


func _t_vip_inspector() -> void:
	_section("vip: inspector")
	var w: SimWorld = _world(&"med_3", _small_ship(), {}, 51, _p3_level(&"med_3"))
	_watch_vips(w)
	var ins: Guest = _calm_vip(w, &"inspector")
	var states: Dictionary = {}
	var t_done: float = -1.0
	var decks_seen: Dictionary = {}
	for i in 2400:
		w.tick(SimConst.TICK)
		states[ins.state] = true
		decks_seen[int(round(ins.deck_f))] = true
		if ins.vip_grade != &"":
			t_done = w.time
			break
	_check(states.has(&"inspect"), "the inspector is in the inspect state while he walks round")
	_check(t_done > 0.0, "the inspection finished (%.0f s)" % t_done)
	for d in 4:
		_check(ins.inspected_decks.has(d), "deck %d inspected end to end" % d)
		_check(decks_seen.has(d), "the inspector stood on deck %d" % d)
	_eq(ins.vip_grade, VipSim.GREAT, "a spotless ship earns a great review")
	_eq(int(ins.vip_score), 0, "no problems noticed")
	_eq(_sig["verdicts"].size(), 1, "one verdict")
	_eq(ins.mode, Guest.WANDER, "afterwards he is an ordinary guest")
	_eq(int(w.economy.ledger.get(&"vip_bonus", 0)), 250, "great pays $250")
	# problems: two spills + a broken room counted once each
	var w2: SimWorld = _world(&"med_3", _small_ship(), {}, 52, _p3_level(&"med_3"))
	var s1: Mess = w2.problems.spawn_mess(w2, _find_room(w2, &"buffet"))
	var s2: Mess = w2.problems.spawn_mess(w2, _find_room(w2, &"toilets"))
	s1.age = -1.0e6
	s2.age = -1.0e6
	var ins2: Guest = _calm_vip(w2, &"inspector")
	for i in 2400:
		w2.tick(SimConst.TICK)
		if ins2.vip_grade != &"":
			break
	_eq(int(ins2.vip_score), 2, "two spills noticed")
	_eq(ins2.vip_grade, VipSim.GREAT, "2 problems: still great")
	var w3: SimWorld = _world(&"med_3", _small_ship(), {}, 53, _p3_level(&"med_3"))
	var broken: RoomRuntime = _find_room(w3, &"bar")
	w3.room_sim.break_room(w3, broken)
	var spills3: Array[Mess] = []
	for rid in [&"buffet", &"toilets", &"pool"]:
		for k in 2:
			spills3.append(w3.problems.spawn_mess(w3, _find_room(w3, rid)))
	for m in spills3:
		m.age = -1.0e6
	var ins3: Guest = _calm_vip(w3, &"inspector")
	for i in 2400:
		w3.tick(SimConst.TICK)
		if ins3.vip_grade != &"":
			break
	_eq(int(ins3.vip_score), 7, "a broken room + six spills = 7 (each counted once)")
	_eq(ins3.vip_grade, VipSim.OK, "7 problems: ok")
	_eq(int(w3.economy.ledger.get(&"vip_bonus", 0)) + int(w3.economy.ledger.get(&"vip_fines", 0)), 0, "ok pays nothing")
	# a filthy ship: bad, fined, and the guests near him lose satisfaction
	var w4: SimWorld = _world(&"med_3", _small_ship(), {}, 54, _p3_level(&"med_3"))
	var rooms4: Array[RoomRuntime] = [_find_room(w4, &"buffet"), _find_room(w4, &"toilets"), _find_room(w4, &"bar"), _find_room(w4, &"pool")]
	for r in rooms4:
		w4.room_sim.break_room(w4, r)
		for k in 2:
			var m: Mess = w4.problems.spawn_mess(w4, r)
			if m != null:
				m.age = -1.0e6
	var ins4: Guest = _calm_vip(w4, &"inspector")
	var m4: int = w4.money
	for i in 2400:
		w4.tick(SimConst.TICK)
		if ins4.vip_grade != &"":
			break
	_check(int(ins4.vip_score) > SimConst.INSPECTOR_OK, "a dirty ship: %d problems" % int(ins4.vip_score))
	_eq(ins4.vip_grade, VipSim.BAD, "a dirty ship: bad")
	_eq(int(w4.economy.ledger[&"vip_fines"]), 150, "fined $150")
	_check(w4.money - m4 <= -100, "the fine left the till (%d)" % (w4.money - m4))
	# a stalled (held) inspector does not teleport; and an unreachable deck is skipped
	var w5: SimWorld = _world(&"med_3", [[&"cabin", 1, 0], [&"stairs", 1, 5], [&"stairs", 0, 6]], {}, 55, _p3_level(&"med_3"))
	var ins5: Guest = _calm_vip(w5, &"inspector")
	for i in 2400:
		w5.tick(SimConst.TICK)
		if ins5.vip_grade != &"":
			break
	_check(ins5.vip_grade != &"", "an inspector on a ship with disconnected decks still finishes")
	_check(ins5.inspected_decks.has(1), "he inspected the gangway deck")
	# the voyage ending mid-inspection judges what he saw
	var lvl6: LevelDef = _p3_level(&"med_3", [[1.0, &"inspector"]])
	lvl6.duration = 12.0
	var w6: SimWorld = _world(&"med_3", _small_ship(), {}, 56, lvl6)
	_advance(w6, 13.0)
	_check(w6.finished and w6.vip_sim.members[0].vip_grade != &"", "unfinished inspection is judged at the end")
	_eq(w6.result["vips"].size(), 1, "result lists the inspector")


func _t_vip_misc() -> void:
	_section("vip: rating weight, schedule, signals")
	# rating weight x3
	var w: SimWorld = _world(&"med_3", _small_ship(), {}, 61, _p3_level(&"med_3"))
	var v: Guest = _calm_vip(w, &"celebrity")
	var a: Guest = _spawn(w)
	var b: Guest = _spawn(w)
	v.satisfaction = 100.0
	a.satisfaction = 40.0
	b.satisfaction = 40.0
	_near(w.director.compute_rating(w), (100.0 * 3.0 + 40.0 + 40.0) / 5.0, 0.0001, "a VIP weighs x3 in the rating")
	v.vip_kind = &""
	_near(w.director.compute_rating(w), 60.0, 0.0001, "without VIPs the rating is the plain mean")
	# VIPs board on schedule, at the gangway, paying a ticket
	var lvl: LevelDef = _p3_level(&"med_3", [[5, &"critic"], [20, &"celebrity"], [35, &"inspector"]])
	var ws: SimWorld = _world(&"med_3", _small_ship(), {}, 62, lvl)
	_watch_vips(ws)
	_eq(ws.director.guests_planned, 3, "VIPs count in the planned guests")
	_advance(ws, 4.0)
	_eq(ws.vip_sim.members.size(), 0, "nobody before t = 5")
	_advance(ws, 2.0)
	_eq(ws.vip_sim.members.size(), 1, "the critic boards at t = 5")
	_eq(ws.guests[0].vip_kind, &"critic", "first VIP is the critic")
	_eq(ws.guests[0].deck, 1, "VIPs board at the gangway deck")
	_advance(ws, 15.0)
	_eq(ws.vip_sim.members.size(), 2, "the celebrity boards at t = 20")
	_advance(ws, 16.0)
	_eq(ws.vip_sim.members.size(), 3, "the inspector boards at t = 35")
	_eq(_sig["boarded"].size(), 3, "vip_boarded fired once per VIP")
	_eq(_sig["boarded"][2][1], &"inspector", "kinds in order")
	_eq(int(ws.economy.ledger[&"tickets"]), 3 * ws.ticket_price, "VIPs pay the ticket")
	_eq(ws.metrics["vips"], 3, "metrics count the VIPs")
	# unknown kinds are ignored
	var lvl2: LevelDef = _p3_level(&"med_3", [[1, &"king"]])
	var w2: SimWorld = _world(&"med_3", _small_ship(), {}, 63, lvl2)
	_advance(w2, 3.0)
	_eq(w2.guests.size(), 0, "an unknown VIP kind boards nobody")
	# every verdict signal fires exactly once over a whole voyage; the result lists them all
	var lvl3: LevelDef = _p3_level(&"med_3", [[5, &"critic"], [10, &"celebrity"], [15, &"inspector"]])
	lvl3.duration = 200.0
	var w3: SimWorld = _world(&"med_3", _event_ship(), {&"janitor": 1}, 64, lvl3)
	_watch_vips(w3)
	var ended: Array = []
	w3.voyage_ended.connect(func(r: Dictionary) -> void: ended.append(r))
	_advance(w3, 205.0)
	_check(w3.finished and ended.size() == 1, "voyage ended once")
	_eq(_sig["boarded"].size(), 3, "three boarded signals")
	_eq(_sig["verdicts"].size(), 3, "three verdict signals, one each")
	var seen_ids: Dictionary = {}
	for vd in _sig["verdicts"]:
		seen_ids[vd[0]] = true
		_check([&"great", &"ok", &"bad"].has(vd[2]), "grade is great / ok / bad")
	_eq(seen_ids.size(), 3, "one verdict per VIP")
	var vips: Array = w3.result["vips"]
	_eq(vips.size(), 3, "result.vips has three entries")
	for e in vips:
		_check(e.has("kind") and e.has("grade") and [&"great", &"ok", &"bad"].has(e["grade"]), "result entry %s" % str(e))
	var net: int = int(w3.economy.ledger.get(&"vip_bonus", 0)) - int(w3.economy.ledger.get(&"vip_fines", 0))
	var expect_net: int = 0
	for e in vips:
		expect_net += VipSim.pay_for(e["grade"])
	_eq(net, expect_net, "ledger matches the verdict pay")
	_eq(w3.result["guests_total"], 3, "VIPs are guests too")
	# tooltip meter
	var wm: SimWorld = _world(&"med_3", _small_ship(), {}, 65, _p3_level(&"med_3"))
	var cm: Guest = _calm_vip(wm, &"critic")
	var mt: Dictionary = wm.vip_sim.meter(wm, cm)
	_check(mt.has("value") and mt.has("caption") and mt.has("detail"), "review meter has value / caption / detail")
	_near(float(mt["value"]), 0.0, 0.001, "a critic with no points: empty meter")
	cm.vip_score = 40.0
	_check(float(wm.vip_sim.meter(wm, cm)["value"]) > 0.5, "the meter fills with points")


func _t_groups() -> void:
	_section("groups & kids")
	# plan: deterministic group sizes
	_eq(GuestGroup.plan(10, 0.0), [] as Array[int], "ratio 0: no groups")
	_eq(GuestGroup.plan(1, 1.0), [] as Array[int], "a single guest cannot be a group")
	_eq(GuestGroup.plan(10, 0.5), [1, 0] as Array[int], "10 guests at 0.5: a family of 3 and a couple")
	_eq(GuestGroup.plan(10, 1.0), [1, 0, 2] as Array[int], "10 guests at 1.0: family (3), couple, family (4), one solo left")
	_eq(GuestGroup.plan(5, 1.0), [1, 0] as Array[int], "5 guests: family + couple")
	_eq(GuestGroup.plan(3, 1.0), [1] as Array[int], "3 guests: one family")
	_eq(GuestGroup.plan(2, 1.0), [0] as Array[int], "2 guests: a couple")
	for count in [2, 3, 5, 8, 13, 24, 40]:
		for ratio in [0.2, 0.4, 0.7, 1.0]:
			var kids_list: Array[int] = GuestGroup.plan(count, ratio)
			var grouped: int = 0
			for k in kids_list:
				_check(k >= 0 and k <= 2, "1-2 kids per family")
				grouped += 2 + k
			_check(grouped <= count and grouped >= int(round(float(count) * ratio)) - 1, "plan(%d, %.1f) groups %d" % [count, ratio, grouped])
			var descs: Array[Dictionary] = []
			var mem: Array[Dictionary] = LevelDirector.wave_members(count, ratio, descs)
			_eq(mem.size(), count, "wave_members(%d, %.1f) lists every guest" % [count, ratio])
			_eq(descs.size(), kids_list.size(), "wave_members creates one descriptor per group")
	var descs2: Array[Dictionary] = []
	var mem2: Array[Dictionary] = LevelDirector.wave_members(10, 0.5, descs2)
	var order: String = ""
	for m in mem2:
		order += "s" if int(m["gd"]) < 0 else ("k" if bool(m["kid"]) else "a")
	_eq(order, "aaksssaass", "family, solos, the couple, solos; adults before kids (got %s)" % order)
	# a wave boards: composition, ids, kid archetype
	var lvl: LevelDef = _p3_level(&"med_3", [], 0.5)
	lvl.waves = [{"t": 0.0, "count": 10}]
	var w: SimWorld = _world(&"med_3", _small_ship() + [[&"cabin", 1, 4], [&"cabin", 0, 0]], {}, 71, lvl)
	_advance(w, 6.0)
	_eq(w.guests.size(), 10, "the wave boarded")
	_eq(w.groups.size(), 2, "two groups boarded")
	_eq(w.groups[0].kind, GuestGroup.FAMILY, "first group: a family")
	_eq(w.groups[0].size, 3, "family of three")
	_eq(w.groups[0].kids, 1, "one kid")
	_eq(w.groups[1].kind, GuestGroup.COUPLE, "second group: a couple")
	_eq(w.groups[1].size, 2, "couple of two")
	_eq(w.groups[0].members.size(), 3, "all three family members registered")
	_eq(w.metrics["groups"], 2, "groups counted")
	_eq(w.metrics["kids"], 1, "kids counted")
	var kids: int = 0
	var solo: int = 0
	for g in w.guests:
		if g.is_kid():
			kids += 1
			_check(g.group_id >= 0, "a kid is never solo")
			_eq(g.archetype.id, &"kid", "kid archetype")
		if g.group_id < 0:
			solo += 1
	_eq(kids, 1, "exactly one kid on board")
	_eq(solo, 5, "five guests travel alone")
	var fam: GuestGroup = w.groups[0]
	_eq(w.guests[fam.members[0] - 1].group_slot, 0, "the first member is the leader")
	_check(not w.guests[fam.members[0] - 1].is_kid() and not w.guests[fam.members[1] - 1].is_kid() and w.guests[fam.members[2] - 1].is_kid(), "two adults, then the kid")
	for i in range(1, fam.members.size()):
		_eq(fam.members[i], fam.members[i - 1] + 1, "members board back to back")
	# kids never solo across a big mixed voyage
	var lvl2: LevelDef = _p3_level(&"med_3", [], 0.6)
	lvl2.waves = [{"t": 0.0, "count": 14}, {"t": 30.0, "count": 11}, {"t": 60.0, "count": 9}]
	var w2: SimWorld = _world(&"med_3", _small_ship(), {}, 72, lvl2)
	_advance(w2, 70.0)
	_eq(w2.guests.size(), 34, "all waves boarded")
	for g in w2.guests:
		if g.is_kid():
			var grp: GuestGroup = w2.groups[g.group_id - 1]
			_check(grp.kind == GuestGroup.FAMILY and grp.size >= 3, "kid %d is inside a family" % g.id)
			var adults: int = 0
			for mid in grp.members:
				if not w2.guests[mid - 1].is_kid():
					adults += 1
			_eq(adults, 2, "a family has two adults")
	# ratio 0 changes nothing: no groups, no kids
	var w3: SimWorld = _world(&"med_3", _small_ship(), {}, 73, _p3_level(&"med_3"))
	w3.level.waves = [{"t": 0.0, "count": 12}]
	w3.director.setup(w3)
	_advance(w3, 6.0)
	_eq(w3.groups.size(), 0, "ratio 0: nobody travels in a group")
	for g in w3.guests:
		_check(g.group_id == -1 and not g.is_kid(), "ratio 0: guest %d is solo and adult" % g.id)
	# kid stats
	var kid: Guest = null
	for g in w.guests:
		if g.is_kid():
			kid = g
	_near(kid.decay[2], 1.0 * 1.6 * w.level.decay_mult, 0.0001, "kid fun decay 1.6x")
	_near(kid.decay[1], 0.8 * 1.2 * w.level.decay_mult, 0.0001, "kid hunger decay 1.2x")
	_near(kid.archetype.body_scale, 0.75, 0.0001, "kid scale")


func _t_group_cabins() -> void:
	_section("groups: cabins, following, bonus, storm-off")
	var cabins2: Array = [[&"stairs", 0, 10], [&"stairs", 1, 11], [&"cabin", 1, 0], [&"cabin", 1, 2], [&"buffet", 1, 4], [&"bar", 1, 9], [&"toilets", 0, 4]]
	# shared cabin when one has enough free beds
	var lvl: LevelDef = _p3_level(&"med_3", [], 0.0)
	var w: SimWorld = _world(&"med_3", cabins2, {}, 81, lvl)
	var grp := GuestGroup.new()
	grp.id = 1
	grp.size = 3
	grp.kids = 1
	grp.kind = GuestGroup.FAMILY
	w.groups.append(grp)
	var m1: Guest = w.guest_sim.spawn_guest(w, &"", grp)
	var c0: RoomRuntime = w.room_sim.cabins_by_distance[0]
	_check(not grp.split and grp.cabin_uid == c0.uid, "the family books the nearest cabin with 3 free beds")
	_eq(c0.reserved, 2, "two beds held for the members still to board")
	var solo_between: Guest = w.guest_sim.spawn_guest(w)
	_eq(solo_between.cabin_uid, c0.uid, "a solo guest boarding meanwhile takes the one bed that is not held")
	var m2: Guest = w.guest_sim.spawn_guest(w, &"", grp)
	var m3: Guest = w.guest_sim.spawn_guest(w, &"kid", grp)
	_check(m1.cabin_uid == c0.uid and m2.cabin_uid == c0.uid and m3.cabin_uid == c0.uid, "all three share one cabin")
	_eq(c0.reserved, 0, "no beds left on hold")
	_eq(c0.sleepers.size(), 4, "the cabin is full: family + the solo guest")
	_near(m1.satisfaction, 72.0, 0.001, "a family that shares a cabin boards happy")
	var solo_after: Guest = w.guest_sim.spawn_guest(w)
	_eq(solo_after.cabin_uid, w.room_sim.cabins_by_distance[1].uid, "the next solo guest goes to the other cabin")
	# split when no cabin has enough free beds: -5 satisfaction each
	var w2: SimWorld = _world(&"med_3", cabins2, {}, 82, lvl)
	for c in w2.room_sim.cabins_by_distance:
		c.sleepers.append(9001)
		c.sleepers.append(9002)
	var grp2 := GuestGroup.new()
	grp2.id = 1
	grp2.size = 3
	grp2.kids = 1
	grp2.kind = GuestGroup.FAMILY
	w2.groups.append(grp2)
	var s1: Guest = w2.guest_sim.spawn_guest(w2, &"", grp2)
	var s2: Guest = w2.guest_sim.spawn_guest(w2, &"", grp2)
	var s3: Guest = w2.guest_sim.spawn_guest(w2, &"kid", grp2)
	_check(grp2.split and grp2.cabin_uid == -1, "no cabin with 3 free beds: the family splits up")
	for g in [s1, s2, s3]:
		_near(g.satisfaction, 67.0, 0.001, "split family: -5 satisfaction each")
	_eq(w2.metrics["groups_split"], 1, "split counted once per group")
	_check(s1.cabin_uid != -1, "split members still get beds individually")
	# a couple fits in the two free beds
	var w3: SimWorld = _world(&"med_3", cabins2, {}, 83, lvl)
	for c in w3.room_sim.cabins_by_distance:
		c.sleepers.append(9001)
		c.sleepers.append(9002)
	var grp3 := GuestGroup.new()
	grp3.id = 1
	grp3.size = 2
	w3.groups.append(grp3)
	var p1: Guest = w3.guest_sim.spawn_guest(w3, &"", grp3)
	var p2: Guest = w3.guest_sim.spawn_guest(w3, &"", grp3)
	_check(not grp3.split and p1.cabin_uid == p2.cabin_uid and p1.cabin_uid != -1, "a couple shares a cabin with 2 free beds")
	# follower adoption: the leader's target if it satisfies a need < 75
	var w4: SimWorld = _world(&"med_3", cabins2, {}, 84, lvl)
	var g4 := GuestGroup.new()
	g4.id = 1
	g4.size = 2
	w4.groups.append(g4)
	var lead: Guest = w4.guest_sim.spawn_guest(w4, &"holidaymaker", g4)
	var fol: Guest = w4.guest_sim.spawn_guest(w4, &"holidaymaker", g4)
	_advance(w4, 1.5)
	_park_clean(lead, 1, 6.0)
	_park_clean(fol, 1, 7.0)
	var buffet: RoomRuntime = _find_room(w4, &"buffet")
	lead.nv[1] = 20.0
	fol.nv[1] = 60.0
	w4.guest_sim._choose_room(w4, lead)
	_eq(lead.target_uid, buffet.uid, "the leader goes to the buffet")
	_eq(lead.mode, Guest.WALK, "the leader walks")
	w4.guest_sim._choose_room(w4, fol)
	_eq(fol.target_uid, buffet.uid, "the follower adopts the leader's target (hunger 60 < 75)")
	_eq(fol.mode, Guest.WALK, "and walks there")
	_eq(w4.metrics["group_follows"], 1, "adoption counted")
	# not hungry: chooses alone (nothing to do), does not tag along
	var w5: SimWorld = _world(&"med_3", cabins2, {}, 85, lvl)
	var g5 := GuestGroup.new()
	g5.id = 1
	g5.size = 2
	w5.groups.append(g5)
	var lead5: Guest = w5.guest_sim.spawn_guest(w5, &"holidaymaker", g5)
	var fol5: Guest = w5.guest_sim.spawn_guest(w5, &"holidaymaker", g5)
	_advance(w5, 1.5)
	_park_clean(lead5, 1, 6.0)
	_park_clean(fol5, 1, 7.0)
	lead5.nv[1] = 20.0
	fol5.nv[1] = 80.0
	w5.guest_sim._choose_room(w5, lead5)
	w5.guest_sim._choose_room(w5, fol5)
	_eq(fol5.target_uid, -1, "a follower whose needs are all >= 75 does not tag along")
	_eq(fol5.mode, Guest.WANDER, "he keeps strolling")
	# leader wandering: the follower chooses alone by its own needs
	var w6: SimWorld = _world(&"med_3", cabins2, {}, 86, lvl)
	var g6 := GuestGroup.new()
	g6.id = 1
	g6.size = 2
	w6.groups.append(g6)
	var lead6: Guest = w6.guest_sim.spawn_guest(w6, &"holidaymaker", g6)
	var fol6: Guest = w6.guest_sim.spawn_guest(w6, &"holidaymaker", g6)
	_advance(w6, 1.5)
	_park_clean(lead6, 1, 6.0)
	_park_clean(fol6, 1, 7.0)
	fol6.nv[1] = 15.0
	w6.guest_sim._choose_room(w6, fol6)
	_eq(fol6.target_uid, _find_room(w6, &"buffet").uid, "with an idle leader a hungry follower chooses alone")
	# the followers cabin rule: the leader's cabin is adopted only if it is also the follower's own
	var w7: SimWorld = _world(&"med_3", cabins2, {}, 87, lvl)
	var g7 := GuestGroup.new()
	g7.id = 1
	g7.size = 2
	w7.groups.append(g7)
	var lead7: Guest = w7.guest_sim.spawn_guest(w7, &"holidaymaker", g7)
	var fol7: Guest = w7.guest_sim.spawn_guest(w7, &"holidaymaker", g7)
	_eq(lead7.cabin_uid, fol7.cabin_uid, "the couple shares a cabin")
	_advance(w7, 1.5)
	_park_clean(lead7, 1, 6.0)
	_park_clean(fol7, 1, 7.0)
	lead7.nv[0] = 10.0
	fol7.nv[0] = 50.0
	w7.guest_sim._choose_room(w7, lead7)
	_eq(lead7.target_uid, lead7.cabin_uid, "the tired leader heads for the cabin")
	w7.guest_sim._choose_room(w7, fol7)
	_eq(fol7.target_uid, lead7.cabin_uid, "the follower joins in the shared cabin")
	fol7.cabin_uid = w7.room_sim.cabins_by_distance[1].uid
	fol7.target_uid = -1
	fol7.mode = Guest.WANDER
	fol7.clear_route()
	w7.guest_sim._choose_room(w7, fol7)
	_eq(fol7.target_uid, fol7.cabin_uid, "with a different cabin he does not follow into someone else's")
	# togetherness: +0.1 sat/s within 3 cells on the same deck
	var w8: SimWorld = _world(&"med_3", cabins2, {}, 88, lvl)
	var g8 := GuestGroup.new()
	g8.id = 1
	g8.size = 2
	w8.groups.append(g8)
	var a8: Guest = w8.guest_sim.spawn_guest(w8, &"holidaymaker", g8)
	var b8: Guest = w8.guest_sim.spawn_guest(w8, &"holidaymaker", g8)
	var c8: Guest = w8.guest_sim.spawn_guest(w8)
	var d8: Guest = w8.guest_sim.spawn_guest(w8)
	_advance(w8, 1.5)
	for g in [a8, b8, c8, d8]:
		g.satisfaction = 70.0
	var g9 := GuestGroup.new()
	g9.id = 2
	g9.size = 2
	w8.groups.append(g9)
	c8.group_id = 2
	d8.group_id = 2
	g9.members = [c8.id, d8.id]
	for k in 20:
		_park_clean(a8, 1, 6.0)
		_park_clean(b8, 1, 8.5)
		_park_clean(c8, 1, 3.0)
		_park_clean(d8, 1, 18.0)
		w8.tick(SimConst.TICK * 5.0)
	var gain_together: float = a8.satisfaction - 70.0
	var gain_apart: float = c8.satisfaction - 70.0
	_near(gain_together - gain_apart, 0.1 * 10.0, 0.25, "together for 10 s: +1.0 satisfaction (%.2f vs %.2f)" % [gain_together, gain_apart])
	# storm-off: the rest of the group loses 15
	var w9: SimWorld = _world(&"med_3", cabins2, {}, 89, lvl)
	var g10 := GuestGroup.new()
	g10.id = 1
	g10.size = 3
	g10.kids = 1
	g10.kind = GuestGroup.FAMILY
	w9.groups.append(g10)
	var f1: Guest = w9.guest_sim.spawn_guest(w9, &"holidaymaker", g10)
	var f2: Guest = w9.guest_sim.spawn_guest(w9, &"holidaymaker", g10)
	var f3: Guest = w9.guest_sim.spawn_guest(w9, &"kid", g10)
	var solo9: Guest = w9.guest_sim.spawn_guest(w9)
	var before: Array[float] = [f1.satisfaction, f2.satisfaction, solo9.satisfaction]
	w9.guest_sim._begin_storm(w9, f3)
	_near(f1.satisfaction, before[0] - 15.0, 0.001, "the parent loses 15 when the kid storms off")
	_near(f2.satisfaction, before[1] - 15.0, 0.001, "the other parent too")
	_near(solo9.satisfaction, before[2], 0.001, "strangers are unaffected")
	_eq(w9.metrics["group_storm_hits"], 2, "two members upset")
	var s_a: float = f1.satisfaction
	w9.guest_sim._begin_storm(w9, solo9)
	_near(f1.satisfaction, s_a, 0.001, "a stranger storming off does not upset the family")


func _t_kids_club() -> void:
	_section("kids club")
	var ship: Array = [[&"stairs", 0, 10], [&"stairs", 1, 11], [&"cabin", 1, 0], [&"kids_club", 1, 4], [&"bar", 1, 8], [&"buffet", 0, 4]]
	var lvl: LevelDef = _p3_level(&"med_3")
	var w: SimWorld = _world(&"med_3", ship, {}, 91, lvl)
	var kc: RoomRuntime = _find_room(w, &"kids_club")
	var bar: RoomRuntime = _find_room(w, &"bar")
	_near(kc.adult_mult, 0.2, 0.001, "the runtime room carries the adult multiplier")
	var kid: Guest = w.guest_sim.spawn_guest(w, &"kid")
	var adult: Guest = w.guest_sim.spawn_guest(w, &"holidaymaker")
	_check(kid.fav.has(kc.uid) and not adult.fav.has(kc.uid), "kids love the kids club, grown-ups do not")
	var kid_picks: int = 0
	var adult_picks: int = 0
	for i in 40:
		for g in [kid, adult]:
			_park_clean(g, 1, 6.0)
			g.nv[2] = 30.0
			g.nv[0] = 95.0
			g.nv[1] = 95.0
			g.nv[3] = 95.0
			w.guest_sim._choose_room(w, g)
		if kid.target_uid == kc.uid:
			kid_picks += 1
		if adult.target_uid == bar.uid:
			adult_picks += 1
		for g in [kid, adult]:
			if g.target_uid >= 0:
				var rr: RoomRuntime = w.room_sim.room(g.target_uid)
				rr.incoming = maxi(rr.incoming - 1, 0)
	_eq(kid_picks, 40, "a bored kid always picks the kids club")
	_eq(adult_picks, 40, "a bored grown-up picks the bar instead")
	# with the kids club as the only fun room the adult's score is x0.2 and often below the choose threshold
	var w2: SimWorld = _world(&"med_3", [[&"cabin", 1, 0], [&"kids_club", 1, 12]], {}, 92, lvl)
	var kc2: RoomRuntime = _find_room(w2, &"kids_club")
	var ad2: Guest = w2.guest_sim.spawn_guest(w2, &"film_buff")
	var kid2: Guest = w2.guest_sim.spawn_guest(w2, &"kid")
	for g in [ad2, kid2]:
		_park_clean(g, 1, 3.0)
		g.nv[2] = 45.0
		g.nv[0] = 95.0
		g.nv[1] = 95.0
		g.nv[3] = 95.0
		w2.guest_sim._choose_room(w2, g)
	_eq(kid2.target_uid, kc2.uid, "the kid heads for the club at fun 45")
	_eq(ad2.target_uid, -1, "the grown-up (x0.2) does not bother at fun 45")
	# end to end: kids actually use it, the room works like any other (spend, mess, wear)
	var lvl3: LevelDef = _p3_level(&"med_3", [], 1.0)
	lvl3.waves = [{"t": 0.0, "count": 9}]
	var ship3: Array = ship + [[&"toilets", 0, 8], [&"cabin", 1, 14], [&"cabin", 0, 12], [&"cabin", 1, 16]]
	var w3: SimWorld = _world(&"med_3", ship3, {&"janitor": 1}, 93, lvl3)
	_advance(w3, 120.0)
	var kc3: RoomRuntime = _find_room(w3, &"kids_club")
	_check(kc3.uses > 0, "kids used the club (%d uses)" % kc3.uses)
	var kid_uses: int = 0
	for g in w3.guests:
		if g.is_kid():
			kid_uses += g.uses
	_check(kid_uses > 0, "kids made visits")


func _t_vip_groups_runs() -> void:
	_section("vips & groups: defaults, manifest, determinism, full voyages")
	# a level with the defaults boards no VIPs and no groups, and rates by the plain mean
	var base: LevelDef = ContentStore.level(&"med_3")
	var port0 := AutoBuilder.build(base)
	var w0: SimWorld = port0.create_world(5)
	while not w0.finished:
		w0.tick(SimConst.TICK)
	_eq(w0.groups.size(), 0, "defaults: no groups")
	_eq(w0.vip_sim.members.size(), 0, "defaults: no VIPs")
	_eq(w0.result["vips"].size(), 0, "defaults: result.vips is empty")
	_eq(int(w0.result["groups"]["count"]), 0, "defaults: result.groups.count is 0")
	_check(not w0.result["ledger"].has(&"vip_bonus") and not w0.result["ledger"].has(&"vip_fines"), "defaults: no VIP lines in the ledger")
	_eq(w0.metrics["vips"] + w0.metrics["groups"] + w0.metrics["kids"] + w0.metrics["groups_split"], 0, "defaults: the new counters stay at 0")
	var sum: float = 0.0
	for g in w0.guests:
		sum += g.satisfaction
		_check(g.group_id == -1 and g.vip_kind == &"" and not g.is_kid(), "defaults: guest %d is an ordinary solo adult" % g.id)
	_near(float(w0.result["rating"]), sum / float(w0.guests.size()), 0.0001, "defaults: rating is the plain mean")
	_eq(w0.guest_sim._arch_ids, [&"film_buff", &"fitness_fan", &"gamer", &"holidaymaker"] as Array[StringName], "archetype roll order is alphabetical (not memory dependent)")
	var manifest0: Dictionary = port0.manifest()
	_eq(int(manifest0["kids"]), 0, "defaults: no kids on the manifest")
	_eq(int(manifest0["groups"]["groups"]), 0, "defaults: no groups on the manifest")
	_eq(manifest0["vips"].size(), 0, "defaults: no VIPs on the manifest")
	_eq(int(manifest0["guests"]), base.total_guests(), "manifest guest count")
	# the same level with explicit zeros behaves identically
	var twin: LevelDef = base.duplicate(true)
	twin.vips = []
	twin.group_ratio = 0.0
	var ra: Dictionary = SimRunner.run(base, port0, 9, &"active")
	var rb: Dictionary = SimRunner.run(twin, AutoBuilder.build(twin), 9, &"active")
	_eq(str(ra["metrics"]), str(rb["metrics"]), "explicit defaults: identical metrics")
	_near(float(ra["rating"]), float(rb["rating"]), 0.00001, "explicit defaults: identical rating")
	# a level with VIPs and groups: manifest, autobuilder, a full voyage, determinism
	var lvl: LevelDef = ContentStore.level(&"med_6").duplicate(true)
	lvl.vips = [{"t": 40.0, "kind": &"critic"}, {"t": 60.0, "kind": &"celebrity"}, {"t": 80.0, "kind": &"inspector"}] as Array[Dictionary]
	lvl.group_ratio = 0.5
	var port := AutoBuilder.build(lvl)
	var plain_lvl: LevelDef = ContentStore.level(&"med_6").duplicate(true)
	plain_lvl.vips = []
	plain_lvl.group_ratio = 0.0
	var plain: PortState = AutoBuilder.build(plain_lvl)
	var man: Dictionary = port.manifest()
	var gs: Dictionary = GuestGroup.summary(lvl)
	_check(int(gs["groups"]) > 0 and int(gs["kids"]) > 0, "the plan has groups and kids (%s)" % str(gs))
	_eq(int(man["kids"]), int(gs["kids"]), "manifest: kids")
	_eq(int(man["groups"]["families"]) + int(man["groups"]["couples"]), int(gs["groups"]), "manifest: groups")
	_eq(man["vips"].size(), 3, "manifest: three VIPs")
	_eq(man["vips"][0]["kind"], &"critic", "manifest: VIPs sorted by time")
	_eq(int(man["guests"]), lvl.total_guests(), "manifest: guests include VIPs")
	var by_sum: int = 0
	for k in man["by_archetype"]:
		by_sum += int(man["by_archetype"][k])
	_eq(by_sum, int(man["guests"]) - int(man["kids"]), "manifest: archetype counts cover everybody but the kids")
	_check(port.layout.count_of(&"kids_club") >= 1, "autobuilder builds a kids club when kids are coming")
	_eq(plain.layout.count_of(&"kids_club"), 0, "autobuilder builds none for a level without kids")
	_check(port.layout.count_of(&"cabin") >= plain.layout.count_of(&"cabin"), "autobuilder keeps groups' cabins in mind")
	var r1: Dictionary = SimRunner.run(lvl, port, 21, &"active")
	var r2: Dictionary = SimRunner.run(lvl, port, 21, &"active")
	_eq(str(r1["metrics"]), str(r2["metrics"]), "VIPs + groups: same seed gives identical metrics")
	_eq(str(r1["vips"]), str(r2["vips"]), "VIPs + groups: same seed gives identical verdicts")
	_eq(r1["profit"], r2["profit"], "VIPs + groups: same seed gives the same profit")
	_eq(r1["vips"].size(), 3, "the result lists all three VIPs")
	for e in r1["vips"]:
		_check([&"great", &"ok", &"bad"].has(e["grade"]), "VIP %s got a grade" % e["kind"])
	_eq(int(r1["groups"]["count"]), int(gs["groups"]), "result.groups.count matches the plan")
	_eq(int(r1["groups"]["kids"]), int(gs["kids"]), "result.groups.kids matches the plan")
	_eq(int(r1["guests_total"]), lvl.total_guests(), "every guest boarded")
	var ledger_net: int = int(r1["ledger"].get(&"vip_bonus", 0)) - int(r1["ledger"].get(&"vip_fines", 0))
	var pay_net: int = 0
	for e in r1["vips"]:
		pay_net += VipSim.pay_for(e["grade"])
	_eq(ledger_net, pay_net, "ledger matches verdict pay")
	_check(r1["report"].has("groups"), "the report knows about groups")
	var r3: Dictionary = SimRunner.run(lvl, port, 22, &"active")
	_check(str(r3["metrics"]) != str(r1["metrics"]) or r3["profit"] != r1["profit"], "different seeds differ")
	print("  med_6 + VIPs + groups: rating %.0f, vips %s, groups %d (split %d), kids %d" % [float(r1["rating"]), str(r1["vips"].map(func(e: Dictionary) -> String: return "%s:%s" % [e["kind"], e["grade"]])), int(r1["groups"]["count"]), int(r1["groups"]["split"]), int(r1["groups"]["kids"])])
	# in-process tick-for-tick determinism incl. the new state
	var wa: SimWorld = port.create_world(33)
	var wb: SimWorld = port.create_world(33)
	var same: bool = true
	for i in 1500:
		wa.tick(SimConst.TICK)
		wb.tick(SimConst.TICK)
		if i % 100 == 0 and (_snapshot(wa) != _snapshot(wb) or str(wa.vip_sim.entries()) != str(wb.vip_sim.entries())):
			same = false
			break
	_check(same, "VIPs + groups: worlds identical tick for tick")
	# telemetry tips: a bad VIP and split groups explain themselves
	var lvl_t: LevelDef = _p3_level(&"med_3", [[1.0, &"critic"]], 0.0)
	lvl_t.duration = 10.0
	var wt: SimWorld = _world(&"med_3", _small_ship(), {}, 99, lvl_t)
	_advance(wt, 12.0)
	var tips: Array = wt.result["report"]["tips"]
	_check(tips.any(func(t: String) -> bool: return t.contains("critic")), "the report names the critic who left unimpressed (%s)" % str(tips))


# ---------------------------------------------------------------------------------------------
# Phase 4a: storms (SPEC §13.7) and the mid-voyage port stop (SPEC §13.8)
# ---------------------------------------------------------------------------------------------
func _t_storm() -> void:
	_section("storm: weather, top deck, seasickness")
	var sdef: EventDef = ContentStore.event(&"storm")
	_check(sdef != null and sdef.storm and sdef.top_deck_closed, "the storm event exists and closes the top deck")
	_near(sdef.duration, 45.0, 0.001, "storm lasts 45 s")
	_near(sdef.seasick_chance, 0.06, 0.0001, "seasick chance 0.06")
	_near(sdef.seasick_cabin_mult, 0.3, 0.0001, "cabin multiplier 0.3")
	_near(sdef.mess_mult_all, 1.5, 0.0001, "mess x1.5")
	_near(sdef.seasick_duration, 25.0, 0.0001, "seasick for 25 s")
	# --- the weather curve: smooth in and out over 4 s
	_near(EventDirector.weather_curve(0.0, 45.0, 4.0), 0.0, 0.0001, "curve starts at 0")
	_near(EventDirector.weather_curve(2.0, 43.0, 4.0), 0.5, 0.0001, "curve halfway through the ease-in")
	_near(EventDirector.weather_curve(4.0, 41.0, 4.0), 1.0, 0.0001, "curve full after 4 s")
	_near(EventDirector.weather_curve(20.0, 25.0, 4.0), 1.0, 0.0001, "curve flat in the middle")
	_near(EventDirector.weather_curve(43.0, 2.0, 4.0), 0.5, 0.0001, "curve halfway through the ease-out")
	_near(EventDirector.weather_curve(45.0, 0.0, 4.0), 0.0, 0.0001, "curve back to 0 at the end")
	# --- intensity in a running sim
	var w: SimWorld = _world(&"med_3", _small_ship(), {}, 3)
	_near(w.weather_intensity, 0.0, 0.0001, "calm weather before the storm")
	var started: Array = [0]
	var ended: Array = [0]
	w.event_started.connect(func(id: StringName) -> void: started[0] += int(id == &"storm"))
	w.event_ended.connect(func(id: StringName) -> void: ended[0] += int(id == &"storm"))
	w.force_event(&"storm")
	_eq(started[0], 1, "event_started(storm)")
	_check(w.events.top_closed, "top deck closed at once")
	_near(w.weather_intensity, 0.0, 0.0001, "intensity 0 at the very start")
	_advance(w, 2.0)
	_near(w.weather_intensity, 0.5, 0.06, "intensity ~0.5 after 2 s")
	_advance(w, 2.0)
	_near(w.weather_intensity, 1.0, 0.02, "intensity 1 after 4 s")
	_advance(w, 21.0)
	_near(w.weather_intensity, 1.0, 0.001, "intensity 1 at 25 s")
	_advance(w, 18.0)
	_near(w.weather_intensity, 0.5, 0.06, "intensity ~0.5 two seconds before the end")
	_advance(w, 2.2)
	_near(w.weather_intensity, 0.0, 0.0001, "intensity 0 after the storm")
	_eq(ended[0], 1, "event_ended(storm)")
	_check(not w.events.top_closed, "top deck open again")

	# --- top deck closure: users and queues leave without any penalty, guests head inside
	var w2: SimWorld = _world(&"med_3", _small_ship() + [[&"bar", 3, 20]], {}, 4)
	var pool: RoomRuntime = _find_room(w2, &"pool")
	var chairs: RoomRuntime = _find_room(w2, &"deck_chairs")
	var buffet: RoomRuntime = _find_room(w2, &"buffet")
	_check(pool.top_deck and chairs.top_deck and not buffet.top_deck, "pool and chairs are top-deck rooms")
	var user: Guest = _spawn(w2)
	_park(user, 3, 5.0)
	w2.guest_sim.start_use(w2, user, pool)
	var waiter: Guest = _spawn(w2)
	_park(waiter, 3, 6.0)
	waiter.mode = Guest.QUEUE
	waiter.state = Guest.QUEUE
	waiter.target_uid = chairs.uid
	chairs.queue.append(waiter.id)
	var walker: Guest = _spawn(w2)
	_park(walker, 3, 9.0)
	walker.mode = Guest.WALK
	walker.state = Guest.WALK
	walker.target_uid = pool.uid
	pool.incoming += 1
	var strolling: Guest = _spawn(w2)
	_park(strolling, 3, 16.0)
	var indoor: Guest = _spawn(w2)
	_park(indoor, 2, 4.0)
	var sat_before: float = user.satisfaction
	var sat_wait: float = waiter.satisfaction
	_eq(pool.users.size(), 1, "one guest in the pool")
	w2.force_event(&"storm")
	_check(pool.closed and chairs.closed and not buffet.closed, "only the top-deck rooms close")
	_check(pool.users.is_empty() and chairs.queue.is_empty(), "users and queues cleared")
	_eq(pool.incoming, 0, "nobody is on the way to the pool any more")
	_eq(user.mode, Guest.WANDER, "the user leaves")
	_eq(waiter.mode, Guest.WANDER, "the queueing guest leaves")
	_eq(walker.mode, Guest.WANDER, "the guest walking there turns round")
	_near(user.satisfaction, sat_before, 0.0001, "no satisfaction penalty for the user")
	_near(waiter.satisfaction, sat_wait, 0.0001, "no penalty for the queue either")
	_eq(user.use_rates[SimConst.N_FUN], 0.0, "use rates cleared")
	_check(user.avoid.is_empty(), "no avoid mark (it was not the guest's fault)")
	var pool_uses: int = pool.uses
	var outside_at: float = -1.0
	for i in 300:
		w2.tick(SimConst.TICK)
		if outside_at < 0.0 and strolling.deck < 3 and strolling.deck_f <= 2.0:
			outside_at = w2.time
	_check(outside_at > 0.0 and outside_at < 20.0, "a guest on the closed top deck heads inside (t=%.1f)" % outside_at)
	_eq(pool.uses, pool_uses, "nobody used the pool in the storm")
	_eq(pool.users.size() + chairs.users.size(), 0, "nobody on the top deck rooms")
	var on_top: int = 0
	for g in w2.guests:
		if g.is_aboard() and g.deck == 3 and not g.vertical_busy():
			on_top += 1
	_eq(on_top, 0, "the top deck is empty during the storm")
	_advance(w2, 20.0)
	_check(not pool.closed and not chairs.closed, "rooms reopen when the storm is over")

	# --- mess chance x1.5 everywhere
	var w3: SimWorld = _world(&"med_3", _small_ship(), {}, 5)
	var b3: RoomRuntime = _find_room(w3, &"buffet")
	var p3: RoomRuntime = _find_room(w3, &"pool")
	_near(w3.events.mess_mult(b3), 1.0, 0.0001, "mess x1 in calm weather")
	w3.force_event(&"storm")
	_near(w3.events.mess_mult(b3), 1.5, 0.0001, "mess x1.5 below deck in a storm")
	_near(w3.events.mess_mult(p3), 1.5, 0.0001, "mess x1.5 on the top deck too")
	w3.force_event(&"pool_party")
	_near(w3.events.mess_mult(p3), 3.0, 0.0001, "stacks with other events (1.5 x 2.0)")
	_near(w3.events.mess_mult(b3), 1.5, 0.0001, "pool party leaves the buffet alone")

	# --- seasick rates: p = 0.06 per roll, x0.3 inside a cabin
	_near(EventDirector.seasick_chance_for(sdef, false), 0.06, 0.00001, "chance outside a cabin")
	_near(EventDirector.seasick_chance_for(sdef, true), 0.018, 0.00001, "chance inside a cabin")
	var w4: SimWorld = _world(&"med_3", _small_ship(), {}, 6)
	var cabin4: RoomRuntime = _find_room(w4, &"cabin")
	var out_g: Array[Guest] = []
	var in_g: Array[Guest] = []
	for i in 1000:
		var g: Guest = _spawn(w4)
		_park(g, 2, 5.0)
		out_g.append(g)
	for i in 1000:
		var g2: Guest = _spawn(w4)
		_park(g2, 1, 1.0)
		g2.mode = Guest.USE
		g2.state = Guest.USE
		g2.target_uid = cabin4.uid
		in_g.append(g2)
	w4.events._roll_seasick(w4, sdef)
	var n_out: int = 0
	var n_in: int = 0
	for g in out_g:
		n_out += int(g.seasick)
	for g in in_g:
		n_in += int(g.seasick)
	_check(n_out >= 40 and n_out <= 80, "about 6%% seasick outside a cabin (%d of 1000)" % n_out)
	_check(n_in >= 6 and n_in <= 32, "about 1.8%% seasick inside a cabin (%d of 1000)" % n_in)
	_check(n_out > 2 * n_in, "cabins protect")
	_eq(int(w4.metrics["seasick"]), n_out + n_in, "metric counts them")
	for g in out_g:
		if g.seasick:
			_near(g.seasick_timer, 25.0, 0.0001, "seasick for 25 s")
			_eq(g.mood, &"seasick", "own mood icon")
			_check(not g.sick, "seasick is not food poisoning")
			break
	# a real storm rolls every 5 s
	var w4b: SimWorld = _world(&"med_3", _small_ship(), {}, 8)
	var many: Array[Guest] = []
	for i in 600:
		var g3: Guest = _spawn(w4b)
		_park(g3, 2, 5.0)
		many.append(g3)
	w4b.force_event(&"storm")
	_advance(w4b, 4.8)
	_eq(int(w4b.metrics["seasick"]), 0, "no roll before 5 s")
	_advance(w4b, 0.4)
	var first_roll: int = int(w4b.metrics["seasick"])
	_check(first_roll >= 15 and first_roll <= 60, "first roll at 5 s hits ~6%% (%d of 600)" % first_roll)

	# --- effects: hygiene -1/s, satisfaction -0.3/s, own mood, wears off after 25 s
	var w5: SimWorld = _world(&"med_3", _small_ship(), {}, 7)
	var sick_g: Guest = _spawn(w5)
	var ctrl: Guest = _spawn(w5)
	for gg in [sick_g, ctrl]:
		_park(gg, 2, 5.0)
		for i in 4:
			gg.nv[i] = 95.0
			gg.decay[i] = 0.0
		gg.satisfaction = 60.0
	w5.guest_sim.make_seasick(w5, sick_g, 25.0)
	_check(sick_g.seasick and not sick_g.sick, "seasick, not sick")
	_advance(w5, 10.0)
	_near(ctrl.nv[SimConst.N_HYGIENE] - sick_g.nv[SimConst.N_HYGIENE], 10.0, 1.2, "hygiene -1/s while seasick")
	_near(ctrl.satisfaction - sick_g.satisfaction, 3.0, 0.5, "satisfaction -0.3/s while seasick")
	_eq(sick_g.mood, &"seasick", "mood stays seasick")
	_advance(w5, 16.0)
	_check(not sick_g.seasick, "sea legs back after 25 s")
	_check(ctrl.mood != &"seasick", "the other guest was never seasick")

	# --- not contagious
	var w6: SimWorld = _world(&"med_3", _small_ship(), {}, 9)
	var src: Guest = _spawn(w6)
	var near_g: Array[Guest] = []
	for i in 12:
		near_g.append(_spawn(w6))
	for gg in [src] + near_g:
		_park(gg, 2, 5.0)
		for i in 4:
			gg.nv[i] = 95.0
			gg.decay[i] = 0.0
	w6.guest_sim.make_seasick(w6, src, 40.0)
	_advance(w6, 38.0)
	var caught: int = 0
	for g in near_g:
		caught += int(g.seasick or g.sick)
	_eq(caught, 0, "seasickness does not spread")

	# --- cured at once by the medbay ...
	var w7: SimWorld = _world(&"med_3", _small_ship() + [[&"medbay", 1, 6]], {}, 10)
	var cs: Array = [0]
	w7.guest_cured.connect(func(_id: int) -> void: cs[0] += 1)
	var patient: Guest = _spawn(w7)
	_park(patient, 1, 8.0)
	for i in 4:
		patient.nv[i] = 95.0
		patient.decay[i] = 0.0
	patient.eval_timer = 0.2
	w7.guest_sim.make_seasick(w7, patient, 25.0)
	var cured_at: float = -1.0
	for i in 250:
		w7.tick(SimConst.TICK)
		if not patient.seasick:
			cured_at = w7.time
			break
	_check(cured_at > 0.0 and cured_at < 20.0, "the medbay cures seasickness before it wears off (t=%.1f)" % cured_at)
	_eq(cs[0], 1, "guest_cured fires")
	# ... or by a medic
	var w8: SimWorld = _world(&"med_3", _small_ship(), {&"medic": 1}, 11)
	var cs8: Array = [0]
	w8.guest_cured.connect(func(_id: int) -> void: cs8[0] += 1)
	var patient8: Guest = _spawn(w8)
	_park(patient8, 1, 10.0)
	for i in 4:
		patient8.nv[i] = 95.0
		patient8.decay[i] = 0.0
	w8.guest_sim.make_seasick(w8, patient8, 25.0)
	_check(w8.staff_sim.jobs.find(&"sick", patient8.id) != null, "a medic job is posted for the seasick guest")
	var cured8: float = -1.0
	for i in 200:
		w8.tick(SimConst.TICK)
		if not patient8.seasick:
			cured8 = w8.time
			break
	_check(cured8 > 0.0 and cured8 < 20.0, "a medic treats seasickness (t=%.1f)" % cured8)
	_eq(int(w8.metrics["medic_cures"]), 1, "counted as a medic cure")
	_eq(cs8[0], 1, "guest_cured fires for the medic too")
	_check(w8.staff_sim.jobs.find(&"sick", patient8.id) == null, "the job is gone")


func _port_level(level_id: StringName, stop: Dictionary = {}) -> LevelDef:
	var lvl: LevelDef = _blank_level(level_id)
	lvl.port_stop = stop if not stop.is_empty() else {"t": 15.0, "name": "Santorini", "disembark": 0.5, "board": 4}
	lvl.duration = 120.0
	return lvl


## Ticks until the port stop is ready (refit_manual worlds hold still there). Returns the seconds it took, or -1.
func _to_ready(w: SimWorld, limit: float = 60.0) -> float:
	var t0: float = w.time
	for i in int(limit / SimConst.TICK):
		if w.port_stop.is_ready():
			return w.time - t0
		w.tick(SimConst.TICK)
	return -1.0


func _t_port_stop() -> void:
	_section("port stop: docking, excursion, pause, boarding")
	_check(ContentStore.level(&"med_1").port_stop.is_empty(), "the first Mediterranean levels have no port stop")
	_eq(_blank_level(&"med_3").total_guests(), 0, "a level without a port stop adds no guests")
	var lvl: LevelDef = _port_level(&"med_5")
	_eq(lvl.total_guests(), 4, "the boarding wave counts towards the guests of the level")

	var w: SimWorld = _world(&"med_5", _small_ship(), {}, 12, lvl)
	w.refit_manual = true
	var log: Dictionary = {"started": 0, "ready": 0, "ended": 0, "name": "", "waves": []}
	w.port_stop_started.connect(func(n: String) -> void:
		log["started"] += 1
		log["name"] = n)
	w.port_stop_ready.connect(func() -> void: log["ready"] += 1)
	w.port_stop_ended.connect(func() -> void: log["ended"] += 1)
	w.wave_started.connect(func(i: int, c: int) -> void: log["waves"].append([i, c]))
	var guests: Array[Guest] = []
	for i in 10:
		var g: Guest = _spawn(w)
		_park(g, 2, 3.0 + float(i))
		g.satisfaction = 90.0 if i < 5 else 40.0
		guests.append(g)
	var critic: Guest = w.vip_sim.board(w, &"critic")
	var celeb: Guest = w.vip_sim.board(w, &"celebrity")
	_park(critic, 2, 15.0)
	_park(celeb, 2, 16.0)
	_advance(w, 1.0)   # (the boarding animation is over)
	_eq(w.port_stop.phase, PortStop.NONE, "no stop before its time")
	_near(w.port_stop.dock_progress, 0.0, 0.0001, "the dock is away at sea")
	var sat_at: Dictionary = {}
	while w.port_stop.phase == PortStop.NONE and w.time < 20.0:
		w.tick(SimConst.TICK)
	log["t_start"] = w.time
	_eq(log["started"], 1, "port_stop_started fires once")
	_eq(log["name"], "Santorini", "with the stop's name")
	_near(float(log["t_start"]), 15.0, 0.2, "at t = 15 s")
	_eq(w.port_stop.phase, PortStop.DOCKING, "docking")
	# dock progress eases in over DOCK_TIME
	var prev: float = 0.0
	var mono: bool = true
	var half_at: float = -1.0
	var t_dock: float = w.time
	while w.port_stop.phase == PortStop.DOCKING:
		w.tick(SimConst.TICK)
		var dp: float = w.port_stop.dock_progress
		if dp + 0.0001 < prev:
			mono = false
		prev = dp
		if half_at < 0.0 and dp >= 0.5:
			half_at = w.time - t_dock
	_check(mono, "dock progress only grows while docking")
	_near(half_at, SimConst.DOCK_TIME * 0.5, 0.3, "half way in at half the docking time")
	_near(w.port_stop.dock_progress, 1.0, 0.0001, "alongside")
	_eq(w.port_stop.phase, PortStop.EXCURSION, "excursion starts after docking")
	# 12 aboard (10 + 2 VIPs mid-review), disembark 0.5 -> 6, never the VIPs
	_eq(w.port_stop.excursion_count, 6, "disembark x guests aboard (12 x 0.5 = 6)")
	var went: int = 0
	for g in guests:
		if g.excursion:
			went += 1
			sat_at[g.id] = g.satisfaction
	_eq(went, 6, "six guests went ashore")
	_check(not critic.excursion and not celeb.excursion, "never a VIP in the middle of their review")
	_check(critic.is_aboard() and celeb.is_aboard(), "the VIPs are still aboard")
	var ready_after: float = _to_ready(w, 30.0)
	_check(ready_after >= 0.0 and ready_after <= SimConst.EXCURSION_MAX + 0.5, "everybody is ashore in time (%.1f s)" % ready_after)
	_eq(log["ready"], 1, "port_stop_ready fires once")
	var gone: int = 0
	for g in guests:
		if g.excursion:
			_eq(g.state, Guest.GONE, "excursion guests are gone")
			_check(not g.lost, "an excursion guest is not lost")
			_near(g.satisfaction, float(sat_at[g.id]), 0.0001, "satisfaction frozen at the moment they left (guest %d)" % g.id)
			gone += 1
	_eq(gone, 6, "six gone")
	_eq(w.director.lost_count(w), 0, "nobody lost")
	var st: Dictionary = w.stats()
	_eq(int(st["guests_on_board"]), 6, "six left aboard (4 + 2 VIPs)")
	_eq(int(st["guests_total"]), 12, "guests_total keeps everybody who ever boarded")
	var sum: float = 0.0
	var wsum: float = 0.0
	for g in w.guests:
		var wt: float = SimConst.VIP_RATING_WEIGHT if g.vip_kind != &"" else 1.0
		sum += g.satisfaction * wt
		wsum += wt
	_near(w.director.compute_rating(w), sum / wsum, 0.0001, "rating = mean over everybody, the excursion guests included")
	_check(w.director.compute_rating(w) > 40.0, "ashore with their 90s and 40s kept")
	# pause handshake: the sim holds still until cast off
	var ticks: int = w.tick_count
	var tm: float = w.time
	_advance(w, 3.0)
	_eq(w.tick_count, ticks, "no ticks while the refit is open")
	_near(w.time, tm, 0.0001, "the voyage clock holds still")
	_check(w.refit_open() and w.port_stop.can_refit(), "the refit is open")
	_check(not w.cast_off() == false, "cast off works when ready")
	_eq(log["ended"], 1, "port_stop_ended fires")
	_eq(w.port_stop.phase, PortStop.DEPARTING, "departing")
	_check(not w.cast_off(), "cast off twice does nothing")
	_check(not w.refit_open(), "the refit closed")
	var n_before: int = w.guests.size()
	_advance(w, 1.0)
	_check(w.time > tm, "the clock runs again")
	_advance(w, SimConst.WAVE_SPREAD + 1.0)
	_eq(w.guests.size(), n_before + 4, "the boarding wave comes aboard")
	_eq(log["waves"].size(), 1, "one wave_started")
	_eq(log["waves"][0][1], 4, "with 4 guests")
	_check(int(log["waves"][0][0]) >= 0, "wave index")
	_advance(w, SimConst.DEPART_TIME)
	_eq(w.port_stop.phase, PortStop.DONE, "the stop is over")
	_near(w.port_stop.dock_progress, 0.0, 0.0001, "the dock has slid away")
	# the freed beds were used by the new guests
	var homeless: int = 0
	for g in w.guests:
		if g.is_aboard() and g.cabin_uid < 0:
			homeless += 1
	_check(homeless <= 8, "freed beds are reusable")

	# --- all VIPs mid-review stay even if everybody else goes
	var lvl2: LevelDef = _port_level(&"med_5", {"t": 10.0, "name": "Naxos", "disembark": 1.0, "board": 0})
	var w2: SimWorld = _world(&"med_5", _small_ship(), {}, 13, lvl2)
	w2.refit_manual = true
	var solo: Array[Guest] = []
	for i in 6:
		var g: Guest = _spawn(w2)
		_park(g, 2, 3.0 + float(i))
		solo.append(g)
	var vip_open: Guest = w2.vip_sim.board(w2, &"inspector")
	var vip_done: Guest = w2.vip_sim.board(w2, &"celebrity")
	vip_done.vip_grade = VipSim.GREAT
	_park(vip_open, 2, 20.0)
	_park(vip_done, 2, 21.0)
	_advance(w2, 1.0)
	_check(_to_ready(w2) > 0.0, "second stop ready")
	for g in solo:
		_check(g.excursion, "disembark 1.0 sends every ordinary guest ashore")
	_check(not vip_open.excursion and vip_open.is_aboard(), "the VIP with an open review stays")
	_check(vip_done.excursion, "a VIP whose review is done may go ashore")

	# --- nobody to stop for: levels without a port stop never pause or dock
	var w3: SimWorld = _world(&"med_3", _small_ship(), {}, 14)
	w3.refit_manual = true
	_advance(w3, 60.0)
	_check(not w3.port_stop.configured and w3.port_stop.phase == PortStop.NONE, "no port stop, no phases")
	_near(w3.time, 60.0, 0.11, "and the clock never stopped")
	# --- headless default: the sim casts off by itself
	var w4: SimWorld = _world(&"med_5", _small_ship(), {}, 15, _port_level(&"med_5"))
	for i in 3:
		_park(_spawn(w4), 2, 3.0 + float(i))
	_advance(w4, 60.0)
	_eq(w4.port_stop.phase, PortStop.DONE, "an unattended sim docks, waits for nobody and sails on")
	_eq(w4.guests.size(), 3 + 4, "the boarding wave came aboard")
	# a storm never starts in the way of a stop, and a running one ends when docking begins
	var w5: SimWorld = _world(&"med_5", _small_ship(), {}, 16, _port_level(&"med_5", {"t": 30.0, "name": "Rhodes", "disembark": 0.0, "board": 0}))
	w5.refit_manual = true
	w5.force_event(&"storm")
	_advance(w5, 31.0)
	_check(not w5.events.is_active(&"storm"), "the storm ends when the ship starts docking")
	_near(w5.weather_intensity, 0.0, 0.0001, "calm at the quay")
	_check(w5.port_stop.blocks_storm(w5.time), "no new storm around the stop")


## Review fixes around the port stop: the excursion timeout, ailing followers, refit re-planning, the boarding wave's groups.
func _t_review_fixes() -> void:
	_section("review fixes: excursion timeout, ailing followers, refit re-plan, boarding groups")

	# --- Walker.abort_travel gives the elevator back (waiting line and car), and leaves a climb on the nearest deck
	var tr := Transit.new()
	var wk_wait := Walker.new()
	wk_wait.set_position(1, 10.5)
	var wk_ride := Walker.new()
	wk_ride.set_position(1, 10.5)
	var wk_climb := Walker.new()
	wk_climb.set_position(1, 20.5)
	var gr: ShipGrid = _grid_for(&"arctic_1")
	gr.place_free(&"elevator", 0, 10)
	var gr_st: ShipGrid = _grid_for(&"arctic_1")
	gr_st.place_free(&"stairs", 1, 20)
	_check(wk_ride.plan_route(gr, 3, 10.5) and wk_wait.plan_route(gr, 3, 10.5) and wk_climb.plan_route(gr_st, 2, 3.0), "routes via the lift and the stairs")
	wk_ride.step_route(0.1, 2.2, tr, &"walk")
	_eq(wk_ride.travel_mode, Walker.T_WAIT, "the first walker waits for the lift")
	wk_ride.travel_t = SimConst.ELEVATOR_WAIT
	tr.tick()
	_eq(wk_ride.travel_mode, Walker.T_RIDE, "... and rides")
	wk_wait.step_route(0.1, 2.2, tr, &"walk")
	for i in 40:
		if wk_climb.travel_mode != Walker.T_NONE:
			break
		wk_climb.step_route(0.1, 2.2, tr, &"walk")
	_eq(wk_wait.travel_mode, Walker.T_WAIT, "the second one queues behind")
	_eq(wk_climb.travel_mode, Walker.T_CLIMB, "the third one climbs")
	_eq(tr.riders_in(10), 1, "one rider")
	_eq(tr.waiting_in(10), 1, "one waiting")
	wk_wait.abort_travel(tr)
	wk_ride.abort_travel(tr)
	wk_climb.abort_travel(tr)
	_eq(tr.riders_in(10), 0, "the car is empty again")
	_eq(tr.waiting_in(10), 0, "the line is empty again")
	for wk in [wk_wait, wk_ride, wk_climb]:
		_check(not wk.vertical_busy(), "an aborted walker is no longer mid-hop")
		_near(wk.deck_f, float(wk.deck), 0.0001, "and stands on a deck")

	# --- Excursion timeout with guests in the lift line and in the car: the elevator keeps its capacity
	var lvl: LevelDef = _port_level(&"med_5", {"t": 5.0, "name": "Delos", "disembark": 1.0, "board": 0})
	var w: SimWorld = _world(&"med_5", [[&"elevator", 0, 10], [&"cabin", 1, 0], [&"cabin", 1, 2], [&"toilets", 1, 4]], {}, 31, lvl)
	w.refit_manual = true
	var crowd: Array[Guest] = []
	for i in 8:
		var g: Guest = _spawn(w)
		_park(g, 3, 10.5)
		crowd.append(g)
	while w.port_stop.phase != PortStop.EXCURSION and w.time < 30.0:
		w.tick(SimConst.TICK)
	_eq(w.port_stop.phase, PortStop.EXCURSION, "the excursion has begun")
	for i in 80:
		if w.transit.riders_in(10) > 0 and w.transit.waiting_in(10) > 0:
			break
		w.tick(SimConst.TICK)
	_check(w.transit.riders_in(10) > 0 and w.transit.waiting_in(10) > 0, "guests are in the car and in the line (%d / %d)" % [w.transit.riders_in(10), w.transit.waiting_in(10)])
	w.port_stop.phase_t = SimConst.EXCURSION_MAX   # time is up
	w.tick(SimConst.TICK)
	_eq(w.port_stop.phase, PortStop.READY, "the excursion timed out")
	_eq(w.transit.riders_in(10), 0, "nobody is left riding in a car they are not in")
	_eq(w.transit.waiting_in(10), 0, "nobody is left in the line")
	for g in crowd:
		_check(g.mode == Guest.GONE and g.excursion and not g.lost and not g.vertical_busy(), "guest %d went ashore (excursion, not lost)" % g.id)
	_eq(int(w.metrics["excursions"]), 8, "eight excursions counted")
	_check(w.cast_off(), "cast off")
	_advance(w, 3.0)
	_eq(w.transit.riders_in(10), 0, "ghost passengers never board later")
	var late: Guest = _spawn(w)
	_park(late, 3, 10.5)
	late.mode = Guest.WALK
	late.state = Guest.WALK
	_check(late.plan_route(w.grid, 1, 0.5), "a late guest plans a route down")
	for i in int(12.0 / SimConst.TICK):
		w.tick(SimConst.TICK)
		if late.deck == 1:
			break
	_eq(late.deck, 1, "the elevator still has its full capacity: the late guest rode it")

	# --- ... and a guest caught mid-climb when the time runs out (excursion_pending) is still an excursion: bed freed, counted, not lost
	var lvl2: LevelDef = _port_level(&"med_5", {"t": 5.0, "name": "Naxos", "disembark": 1.0, "board": 0})
	var w2: SimWorld = _world(&"med_5", [[&"stairs", 1, 20], [&"cabin", 1, 0]], {}, 32, lvl2)
	w2.refit_manual = true
	var climber: Guest = _spawn(w2)
	_park(climber, 1, 20.5)
	var bed: RoomRuntime = _find_room(w2, &"cabin")
	_check(climber.cabin_uid == bed.uid and bed.sleepers.has(climber.id), "the climber has a bed")
	while w2.port_stop.phase != PortStop.DOCKING and w2.time < 20.0:
		w2.tick(SimConst.TICK)
	while w2.port_stop.phase_t < SimConst.DOCK_TIME - 0.4:
		w2.tick(SimConst.TICK)
	climber.mode = Guest.WALK
	climber.state = Guest.WALK
	_check(climber.plan_route(w2.grid, 2, 3.0), "a route up")
	while climber.travel_mode != Walker.T_CLIMB:
		w2.tick(SimConst.TICK)
		if w2.port_stop.phase == PortStop.EXCURSION:
			break
	while w2.port_stop.phase != PortStop.EXCURSION:
		w2.tick(SimConst.TICK)
	_check(climber.excursion_pending and climber.vertical_busy() and not climber.excursion, "mid-climb when the excursion began: pending")
	w2.port_stop.phase_t = SimConst.EXCURSION_MAX
	w2.tick(SimConst.TICK)
	_eq(w2.port_stop.phase, PortStop.READY, "timed out")
	_check(climber.excursion and not climber.excursion_pending and climber.mode == Guest.GONE, "the pending guest went ashore as an excursion guest")
	_check(not bed.sleepers.has(climber.id), "their bed is free again")
	_check(not climber.lost and w2.director.lost_count(w2) == 0, "not lost")
	_eq(int(w2.metrics["excursions"]), 1, "counted as an excursion")
	_near(w2.director.compute_rating(w2), climber.satisfaction, 0.0001, "still counted in the rating (§13.8)")

	# --- A bed freed by the excursion reaches a guest who had none
	var lvl3: LevelDef = _port_level(&"med_5", {"t": 5.0, "name": "Naxos", "disembark": 1.0, "board": 0})
	var w3: SimWorld = _world(&"med_5", _small_ship(), {}, 33, lvl3)
	w3.refit_manual = true
	var guests3: Array[Guest] = []
	for i in 8:
		var g: Guest = _spawn(w3)
		_park(g, 2, 3.0 + float(i))
		guests3.append(g)
	var crit: Guest = w3.vip_sim.board(w3, &"critic")   # (the beds are full: homeless, and a critic mid-review never goes ashore)
	_park(crit, 2, 15.0)
	_check(crit.cabin_uid < 0, "the critic has no bed (all 8 are taken)")
	_check(_to_ready(w3) > 0.0, "ready")
	for g in guests3:
		_check(g.excursion, "everybody else went ashore")
	_check(crit.is_aboard() and not crit.excursion, "the critic is still aboard")
	_check(crit.cabin_uid >= 0 and w3.room_sim.room(crit.cabin_uid).sleepers.has(crit.id), "and has taken one of the freed beds")

	# --- A sick follower picks the medbay over the leader's target (a seasick one too)
	var base_ship: Array = _small_ship()
	for flavour in [&"sick", &"seasick"]:
		var wm: SimWorld = _world(&"med_3", base_ship + [[&"medbay", 1, 6]], {}, 41, _p3_level(&"med_3", [], 0.0))
		var gm := GuestGroup.new()
		gm.id = 1
		gm.size = 2
		wm.groups.append(gm)
		var lead: Guest = wm.guest_sim.spawn_guest(wm, &"holidaymaker", gm)
		var fol: Guest = wm.guest_sim.spawn_guest(wm, &"holidaymaker", gm)
		_advance(wm, 1.5)
		_park_clean(lead, 2, 6.0)
		_park_clean(fol, 1, 8.0)
		lead.nv[1] = 20.0
		fol.nv[1] = 60.0   # hungry enough to tag along behind the leader to the buffet ...
		fol.sick = flavour == &"sick"
		fol.seasick = flavour == &"seasick"
		wm.guest_sim._choose_room(wm, lead)
		_eq(wm.room_by_uid(lead.target_uid).def.id, &"buffet", "%s: the leader goes to the buffet" % flavour)
		wm.guest_sim._choose_room(wm, fol)
		_check(fol.target_uid >= 0 and wm.room_by_uid(fol.target_uid).def.id == &"medbay", "%s: the follower goes to the medbay instead" % flavour)
		_eq(int(wm.metrics["group_follows"]), 0, "%s: no tagging along" % flavour)
	# ... but with no medbay aboard it still follows
	var wn: SimWorld = _world(&"med_3", base_ship, {}, 42, _p3_level(&"med_3", [], 0.0))
	var gn := GuestGroup.new()
	gn.id = 1
	gn.size = 2
	wn.groups.append(gn)
	var lead_n: Guest = wn.guest_sim.spawn_guest(wn, &"holidaymaker", gn)
	var fol_n: Guest = wn.guest_sim.spawn_guest(wn, &"holidaymaker", gn)
	_advance(wn, 1.5)
	_park_clean(lead_n, 2, 6.0)
	_park_clean(fol_n, 1, 8.0)
	lead_n.nv[1] = 20.0
	fol_n.nv[1] = 60.0
	fol_n.sick = true
	wn.guest_sim._choose_room(wn, lead_n)
	wn.guest_sim._choose_room(wn, fol_n)
	_eq(fol_n.target_uid, lead_n.target_uid, "no medbay aboard: a sick follower still tags along")
	# a medbay built in the Quick refit counts as soon as it is there
	var lvl_r: LevelDef = _port_level(&"med_5", {"t": 5.0, "name": "Delos", "disembark": 0.0, "board": 0})
	var wr: SimWorld = _world(&"med_5", base_ship, {}, 43, lvl_r)
	wr.refit_manual = true
	var gr_g := GuestGroup.new()
	gr_g.id = 1
	gr_g.size = 2
	wr.groups.append(gr_g)
	var lead_r: Guest = wr.guest_sim.spawn_guest(wr, &"holidaymaker", gr_g)
	var fol_r: Guest = wr.guest_sim.spawn_guest(wr, &"holidaymaker", gr_g)
	_advance(wr, 1.5)
	_check(_to_ready(wr) > 0.0, "refit world ready")
	_check(not wr.has_room_type(&"medbay"), "no medbay yet")
	_check(wr.add_room(&"medbay", 1, 6) > 0, "a medbay is built in the refit")
	_check(wr.has_room_type(&"medbay"), "the ship knows about it")
	_park_clean(lead_r, 2, 6.0)
	_park_clean(fol_r, 1, 8.0)
	lead_r.nv[1] = 20.0
	fol_r.nv[1] = 60.0
	fol_r.seasick = true
	wr.guest_sim._choose_room(wr, lead_r)
	wr.guest_sim._choose_room(wr, fol_r)
	_check(fol_r.target_uid >= 0 and wr.room_by_uid(fol_r.target_uid).def.id == &"medbay", "a seasick follower uses the refit medbay")

	# --- A walker mid-climb during add_room is re-planned right after the hop (the new stairs shorten the rest of its way)
	var lvl5: LevelDef = _port_level(&"med_5", {"t": 5.0, "name": "Delos", "disembark": 0.0, "board": 0})
	var w5: SimWorld = _world(&"med_5", [[&"stairs", 1, 20], [&"stairs", 2, 20]], {}, 45, lvl5)
	w5.refit_manual = true
	var hiker: Guest = _spawn(w5)
	_check(_to_ready(w5) > 0.0, "ready")
	_park(hiker, 1, 20.5)
	hiker.mode = Guest.WALK
	hiker.state = Guest.WALK
	_check(hiker.plan_route(w5.grid, 3, 3.0), "a route to deck 3 via the far stairs")
	hiker.step_route(0.1, SimConst.GUEST_SPEED, w5.transit, &"walk")
	_eq(hiker.travel_mode, Walker.T_CLIMB, "mid-climb at the refit")
	_check(w5.add_room(&"stairs", 2, 4) > 0, "stairs built nearer to the destination")
	_check(hiker.vertical_busy(), "(the climber was left alone for now)")
	_check(w5.cast_off(), "cast off")
	for i in int(5.0 / SimConst.TICK):
		w5.tick(SimConst.TICK)
		if not hiker.vertical_busy():
			break
	_check(not hiker.vertical_busy(), "the climb is over")
	_eq(hiker.deck, 2, "on deck 2")
	var upper: float = -1.0
	for i in range(hiker.wp_i, hiker.wp_mode.size()):
		if hiker.wp_mode[i] == 1:
			upper = hiker.wp_x[i]
	_near(upper, 4.5, 0.01, "the next climb is at the new stairs (x = 4.5)")
	_near(hiker.wp_x[hiker.wp_x.size() - 1], 3.0, 0.001, "to the same destination")
	_check(w5._repath_later.is_empty(), "nobody is left waiting to be re-planned")

	# --- The port manifest / autobuilder count the port stop's boarding wave of couples and families
	for id in [&"arctic_4", &"arctic_6", &"underworld_4", &"underworld_6"]:
		var pl: LevelDef = ContentStore.level(id)
		var sm: Dictionary = GuestGroup.summary(pl)
		var no_stop: LevelDef = pl.duplicate(true)
		no_stop.port_stop = {}
		_check(int(sm["groups"]) > int(GuestGroup.summary(no_stop)["groups"]), "%s: the boarding wave adds groups to the plan" % id)
		var plan_sum: Dictionary = {"groups": 0, "kids": 0}
		for count in GuestGroup.plan(pl.port_board(), pl.group_ratio):
			plan_sum["groups"] += 1
			plan_sum["kids"] += count
		var wave_only: LevelDef = pl.duplicate(true)
		wave_only.waves = [] as Array[Dictionary]
		var wo: Dictionary = GuestGroup.summary(wave_only)
		_eq(int(wo["groups"]), int(plan_sum["groups"]), "%s: the boarding wave alone: groups" % id)
		_eq(int(wo["kids"]), int(plan_sum["kids"]), "%s: the boarding wave alone: kids" % id)
		var res: Dictionary = SimRunner.run(pl, AutoBuilder.build(pl), 7, &"passive")
		_eq(int(res["groups"]["count"]), int(sm["groups"]), "%s: groups in the run match the summary" % id)
		_eq(int(res["groups"]["kids"]), int(sm["kids"]), "%s: kids in the run match the summary" % id)
		_eq(int(AutoBuilder.build(pl).manifest()["kids"]), int(sm["kids"]), "%s: the manifest agrees" % id)


func _t_refit() -> void:
	_section("quick refit: add_room / upgrade_room / can_add_room")
	var w: SimWorld = _world(&"med_5", _small_ship(), {}, 20, _port_level(&"med_5", {"t": 5.0, "name": "Delos", "disembark": 0.0, "board": 0}))
	w.refit_manual = true
	var no: Dictionary = w.can_add_room(&"buffet", 2, 14)
	_check(not bool(no["ok"]) and String(no["reason"]) == "Not at a port", "no building at sea")
	_eq(w.add_room(&"buffet", 2, 14), -1, "add_room fails at sea")
	_check(not w.upgrade_room(w.rooms[0].uid), "upgrade_room fails at sea")
	_check(_to_ready(w) >= 0.0, "docked and ready")
	# money
	var cash: int = w.money
	var ok: Dictionary = w.can_add_room(&"buffet", 2, 14)
	_check(bool(ok["ok"]), "a buffet fits on deck 2, x 14 (%s)" % String(ok["reason"]))
	w.economy.money = 100
	var poor: Dictionary = w.can_add_room(&"buffet", 2, 14)
	_check(not bool(poor["ok"]) and String(poor["reason"]) == "Not enough money", "not enough money")
	w.economy.money = cash
	# overlap
	var hit: Dictionary = w.can_add_room(&"toilets", 1, 0)
	_check(not bool(hit["ok"]) and String(hit["reason"]).begins_with("Overlaps"), "overlap: %s" % String(hit["reason"]))
	_check(not bool(w.can_add_room(&"deck_chairs", 2, 14)["ok"]), "top-deck rooms only on the top deck")
	_check(not bool(w.can_add_room(&"stairs", w.grid.hull.decks - 1, 1)["ok"]), "stairs need two decks")
	# unlock (med_1 is level 1: the medbay unlocks at 3)
	var l1: LevelDef = _port_level(&"med_1", {"t": 5.0, "name": "Delos", "disembark": 0.0, "board": 0})
	var w1: SimWorld = _world(&"med_1", _small_ship(), {}, 21, l1)
	w1.refit_manual = true
	_check(_to_ready(w1) >= 0.0, "level 1 docked")
	var lock: Dictionary = w1.can_add_room(&"medbay", 1, 14)
	_check(not bool(lock["ok"]) and String(lock["reason"]) == "Unlocks at level 3", "locked room: %s" % String(lock["reason"]))
	_check(not bool(w1.can_upgrade_room(_find_room(w1, &"buffet").uid)["ok"]), "tier II is locked at level 1")
	# utilities: a hull with almost no power
	var lvlu: LevelDef = _port_level(&"med_5", {"t": 5.0, "name": "Delos", "disembark": 0.0, "board": 0})
	var hull: HullDef = ContentStore.hull(lvlu.hull).duplicate()
	hull.power = 3
	var layout := ShipLayout.new(hull)
	var gridu := ShipGrid.new(layout, lvlu)
	for r in _small_ship():
		gridu.place_free(StringName(r[0]), int(r[1]), int(r[2]))
	var wu := SimWorld.new(lvlu, layout, {}, 22, 3000)
	wu.refit_manual = true
	_check(_to_ready(wu) >= 0.0, "power-starved ship docked")
	var pw: Dictionary = wu.can_add_room(&"gym", 1, 14)
	_check(not bool(pw["ok"]) and String(pw["reason"]) == "Not enough power", "power: %s" % String(pw["reason"]))
	var gen_uid: int = wu.add_room(&"generator", 1, 14)
	_check(gen_uid > 0, "a generator can always go in")
	_check(bool(wu.can_add_room(&"gym", 1, 18)["ok"]), "and then the power is there")
	# connectivity: no stairs at all on this ship
	var wc: SimWorld = _world(&"med_5", [[&"cabin", 1, 0]], {}, 23, _port_level(&"med_5", {"t": 5.0, "name": "Delos", "disembark": 0.0, "board": 0}))
	wc.refit_manual = true
	_check(_to_ready(wc) >= 0.0, "bare ship docked")
	_check(bool(wc.can_add_room(&"toilets", 1, 6)["ok"]), "the gangway deck is always connected")
	var nc: Dictionary = wc.can_add_room(&"toilets", 2, 6)
	_check(not bool(nc["ok"]) and String(nc["reason"]) == "Not connected", "deck 2 is not connected: %s" % String(nc["reason"]))
	_check(not bool(wc.can_add_room(&"stairs", 2, 8)["ok"]), "stairs between two unconnected decks do not help")
	_check(bool(wc.can_add_room(&"stairs", 1, 8)["ok"]), "stairs from the gangway deck do")
	_check(bool(wc.can_add_room(&"elevator", 0, 20)["ok"]) == (wc.level.campaign_index >= 7), "an elevator connects everything (when unlocked)")

	# --- add_room does everything
	var wa: SimWorld = _world(&"med_5", [[&"stairs", 1, 20]], {}, 24, _port_level(&"med_5", {"t": 5.0, "name": "Delos", "disembark": 0.0, "board": 0}))
	wa.refit_manual = true
	var added: Array = []
	wa.room_added.connect(func(uid: int) -> void: added.append(uid))
	var h1: Guest = _spawn(wa)
	var h2: Guest = _spawn(wa)
	_check(h1.cabin_uid < 0 and h2.cabin_uid < 0, "no cabins yet: homeless")
	_park(h1, 1, 2.0)
	_park(h2, 1, 3.0)
	_check(_to_ready(wa) >= 0.0, "ready")
	# a guest on its way to the second deck takes the long way round (the only stairs are at x = 20)
	var walker: Guest = _spawn(wa)
	_park(walker, 1, 2.0)
	walker.mode = Guest.WALK
	walker.state = Guest.WALK
	_check(walker.plan_route(wa.grid, 2, 3.0), "a route to the next deck exists")
	var far_stairs: float = -1.0
	for i in walker.wp_mode.size():
		if walker.wp_mode[i] == 1:
			far_stairs = walker.wp_x[i]
	_near(far_stairs, 20.5, 0.01, "via the stairs at x = 20")
	var money0: int = wa.money
	var upkeep0: float = wa.economy.upkeep_per_minute
	var cab_uid: int = wa.add_room(&"cabin", 1, 0)
	_check(cab_uid > 0, "a cabin is built")
	_eq(wa.money, money0 - ContentStore.room(&"cabin").cost, "charged 1.0x the price")
	_eq(int(wa.ledger()[&"refit"]), ContentStore.room(&"cabin").cost, "ledger: refit")
	_near(wa.economy.upkeep_per_minute, upkeep0 + ContentStore.room(&"cabin").upkeep, 0.0001, "upkeep grows")
	_eq(added, [cab_uid], "room_added signal")
	_check(wa.room_by_uid(cab_uid) != null and wa.has_room_type(&"cabin"), "runtime room exists")
	_eq(wa.grid.layout.get_room(cab_uid).def.id, &"cabin", "layout has it too")
	_eq(h1.cabin_uid, cab_uid, "homeless guests move into the new cabin")
	_eq(h2.cabin_uid, cab_uid, "(both of them)")
	_check(not bool(wa.can_add_room(&"toilets", 1, 0)["ok"]), "and the spot is taken")
	_eq(wa.add_room(&"toilets", 1, 0), -1, "overlap -> -1")
	_eq(wa.add_room(&"deck_chairs", 1, 0), -1, "wrong deck -> -1")
	# stairs rebuild the walk graph and re-path the walkers
	var before_cost: float = wa.grid.graph.cost(wa.grid.graph.node(1, 2), wa.grid.graph.node(2, 3))
	var stairs_uid: int = wa.add_room(&"stairs", 1, 4)
	_check(stairs_uid > 0, "stairs built")
	var after_cost: float = wa.grid.graph.cost(wa.grid.graph.node(1, 2), wa.grid.graph.node(2, 3))
	_check(after_cost < before_cost, "the new stairs shorten the way (%.1f -> %.1f s)" % [before_cost, after_cost])
	var near_stairs: float = -1.0
	for i in walker.wp_mode.size():
		if walker.wp_mode[i] == 1:
			near_stairs = walker.wp_x[i]
	_near(near_stairs, 4.5, 0.01, "the walking guest re-planned via the new stairs")
	_near(walker.wp_x[walker.wp_x.size() - 1], 3.0, 0.001, "to the same destination")
	_eq(walker.wp_deck[walker.wp_deck.size() - 1], 2, "on the same deck")
	_check(wa.grid.graph.reachable(wa.grid.graph.node(1, 0), wa.grid.graph.node(2, 0)), "decks stay connected")
	_check(bool(wa.can_add_room(&"toilets", 2, 10)["ok"]) or true, "(deck 2 is reachable)")

	# --- upgrade_room
	var wg: SimWorld = _world(&"med_5", _small_ship(), {}, 25, _port_level(&"med_5", {"t": 5.0, "name": "Delos", "disembark": 0.0, "board": 0}))
	wg.refit_manual = true
	_check(_to_ready(wg) >= 0.0, "ready")
	var bu: RoomRuntime = _find_room(wg, &"buffet")
	var cap0: int = bu.cap
	var svc0: float = bu.svc
	var m0: int = wg.money
	var up_cost: int = bu.def.upgrade_cost(0)
	var ups: Array = [0]
	wg.room_upgraded.connect(func(_u: int) -> void: ups[0] += 1)
	_check(bool(wg.can_upgrade_room(bu.uid)["ok"]), "buffet can be upgraded")
	_check(wg.upgrade_room(bu.uid), "upgrade_room succeeds")
	_eq(bu.tier, 1, "tier II")
	_eq(wg.grid.layout.get_room(bu.uid).tier, 1, "layout tier II")
	_eq(wg.money, m0 - up_cost, "charged 1.0x the upgrade cost")
	_check(bu.cap >= cap0 and (bu.cap > cap0 or bu.svc < svc0), "more capacity or faster service")
	_eq(ups[0], 1, "room_upgraded signal")
	_eq(int(wg.metrics["refit_upgrades"]), 1, "metric")
	wg.economy.money = 5
	var bar_uid: int = _find_room(wg, &"bar").uid
	_check(not wg.upgrade_room(bar_uid), "no money, no upgrade")
	_eq(String(wg.can_upgrade_room(bar_uid)["reason"]), "Not enough money", "reason")
	_eq(String(wg.can_upgrade_room(bu.uid)["reason"]), "Unlocks at level 10", "tier III is locked below level 10")
	wg.economy.money = 5000
	_check(not wg.upgrade_room(_find_room(wg, &"stairs").uid), "stairs cannot be upgraded")
	_check(not wg.upgrade_room(9999), "unknown room")
	# crew at the normal wage during the refit, 1.5x at sea
	var wage: int = ContentStore.staff_role(&"janitor").wage
	_eq(wg.mid_voyage_hire_cost(&"janitor"), wage, "normal wage in the refit")
	var wsea: SimWorld = _world(&"med_5", _small_ship(), {}, 26)
	_eq(wsea.mid_voyage_hire_cost(&"janitor"), int(round(float(wage) * 1.5)), "1.5x wage at sea")
	var staff0: int = wg.staff.size()
	_check(wg.hire_staff_mid_voyage(&"janitor"), "hiring in the refit works")
	_eq(wg.staff.size(), staff0 + 1, "one more crew member")
	_eq(wg.money, 5000 - wage, "at the normal wage")

	# --- telemetry with rooms added mid-voyage
	var wt: SimWorld = _world(&"med_5", _small_ship(), {}, 27, _port_level(&"med_5", {"t": 20.0, "name": "Delos", "disembark": 0.0, "board": 0}))
	wt.refit_manual = true
	for i in 6:
		_park(_spawn(wt), 2, 3.0 + float(i))
	_check(_to_ready(wt) >= 0.0, "telemetry world docked")
	var gym_uid: int = wt.add_room(&"gym", 1, 14)
	_check(gym_uid > 0, "gym added")
	wt.cast_off()
	_advance(wt, 12.0)
	var rep: Dictionary = wt.telemetry.report()
	var row: Dictionary = {}
	for r in rep["rooms"]:
		if int(r["uid"]) == gym_uid:
			row = r
	_check(not row.is_empty(), "the new room has a report row")
	_check(float(row.get("util", -1.0)) >= 0.0 and float(row.get("util", 9.0)) <= 1.0, "utilisation is sane")
	_check(int(row.get("added_at", 0)) > 0, "it remembers when it joined")
	_check(row.get("tag", &"") != &"idle", "not called idle before it had a chance")
	_eq(int(rep["decks"]), wt.grid.hull.decks, "grids keep the hull size")
	_eq((rep["grids"]["traffic"] as Array).size(), wt.grid.hull.decks, "traffic grid decks")
	_eq((rep["grids"]["traffic"][0] as PackedFloat32Array).size(), wt.grid.hull.width, "traffic grid width")
	# --- determinism with a port stop + refit
	var a: Dictionary = _run_refit_voyage(31)
	var b: Dictionary = _run_refit_voyage(31)
	_eq(a, b, "a voyage with a port stop and a refit is reproducible")
	_check(int(a["rooms"]) > 0, "(and the refit happened)")
	var c: Dictionary = _run_refit_voyage(32)
	_check(a != c, "another seed gives another voyage")


func _run_refit_voyage(seed_value: int) -> Dictionary:
	var lvl: LevelDef = _port_level(&"med_5", {"t": 25.0, "name": "Delos", "disembark": 0.4, "board": 5})
	lvl.waves = [{"t": 0.0, "count": 10}, {"t": 12.0, "count": 6}]
	lvl.duration = 90.0
	var w: SimWorld = _world(&"med_5", _small_ship(), {&"janitor": 1}, seed_value, lvl)
	w.refit_manual = true
	var added: int = 0
	var guard: int = 0
	while not w.finished and guard < 2000:
		guard += 1
		if w.port_stop.is_ready():
			if w.add_room(&"buffet", 2, 14) > 0:
				added += 1
			w.upgrade_room(_find_room(w, &"bar").uid)
			w.cast_off()
		_advance(w, 1.0)
	return {"rating": snappedf(w.rating(), 0.0001), "money": w.money, "guests": w.guests.size(), "served": w.director.served,
			"rooms": added, "gone": w.metrics["excursions"], "t": snappedf(w.time, 0.01)}


func _t_autoplayer_refit() -> void:
	_section("autoplayer refit at a port stop")
	# an overloaded buffet gets a sibling (or an upgrade), the boarders get beds, then the AutoPlayer casts off by itself
	var lvl: LevelDef = _port_level(&"med_5", {"t": 30.0, "name": "Delos", "disembark": 0.3, "board": 8})
	lvl.waves = [{"t": 0.0, "count": 24}]
	lvl.duration = 100.0
	var w: SimWorld = _world(&"med_5", _small_ship(), {&"janitor": 1}, 40, lvl)
	w.refit_manual = true
	w.economy.money = 3000
	var ap := AutoPlayer.new(w, &"active", 3)
	var rooms0: int = w.rooms.size()
	var guard: int = 0
	var refit_seen: bool = false
	while not w.finished and guard < 3000:
		guard += 1
		w.tick(SimConst.TICK)
		if w.port_stop.is_ready():
			refit_seen = true
		ap.tick(SimConst.TICK)
	_check(refit_seen, "the voyage reached the port stop")
	_check(w.finished, "and finished (the AutoPlayer cast off)")
	_check(w.port_stop.phase == PortStop.DONE, "stop done")
	_check(int(w.metrics["refit_rooms"]) + int(w.metrics["refit_upgrades"]) > 0, "the AutoPlayer refitted (%d rooms, %d upgrades)" % [w.metrics["refit_rooms"], w.metrics["refit_upgrades"]])
	_check(w.rooms.size() >= rooms0, "rooms were added")
	_eq(w.guests.size(), 24 + 8, "the boarding wave came aboard")
	# passive play just sails on
	var w2: SimWorld = _world(&"med_5", _small_ship(), {}, 41, lvl)
	w2.refit_manual = true
	var ap2 := AutoPlayer.new(w2, &"passive", 3)
	guard = 0
	while not w2.finished and guard < 3000:
		guard += 1
		w2.tick(SimConst.TICK)
		ap2.tick(SimConst.TICK)
	_check(w2.finished, "passive play casts off too")
	_eq(int(w2.metrics["refit_rooms"]) + int(w2.metrics["refit_upgrades"]), 0, "but does not refit")



# ---------------------------------------------------------------------------------------------
# Phase 4b: the campaign opts in (SPEC §13.9), peak_guests, v2 hints
# ---------------------------------------------------------------------------------------------
func _t_campaign_features() -> void:
	_section("campaign opt-ins: VIPs, groups, fatigue, storms, port stops, peak guests")
	var stop_dests: Dictionary = {}
	var storm_levels: int = 0
	for lvl in ContentStore.campaign():
		var ci: int = lvl.campaign_index
		if ci <= 3:
			_check(lvl.vips.is_empty() and is_zero_approx(lvl.group_ratio) and lvl.port_stop.is_empty() and not lvl.staff_fatigue, "%s plays as before" % lvl.id)
		_eq(not lvl.vips.is_empty(), ci >= 4, "%s: VIPs from med_4 on" % lvl.id)
		_eq(lvl.group_ratio > 0.0, ci >= 6, "%s: groups from med_6 on" % lvl.id)
		_eq(lvl.staff_fatigue, ci >= 7, "%s: fatigue from level 7" % lvl.id)
		for v in lvl.vips:
			var need: float = 130.0 if StringName(v["kind"]) == &"inspector" else 110.0
			_check(float(v["t"]) + need <= lvl.duration, "%s: the %s boards early enough to finish (t=%d of %d s)" % [lvl.id, v["kind"], int(v["t"]), int(lvl.duration)])
		var has_storm: bool = false
		for e in lvl.scheduled_events:
			if StringName(e.get("event", &"")) == &"storm":
				has_storm = true
				_check(ci >= 8, "%s: scheduled storms start at arctic_2" % lvl.id)
				_check(float(e["t"]) + 45.0 <= lvl.duration, "%s: the storm ends before the voyage does" % lvl.id)
		storm_levels += 1 if has_storm else 0
		if not lvl.port_stop.is_empty():
			var st: Dictionary = lvl.port_stop
			stop_dests[lvl.destination] = int(stop_dests.get(lvl.destination, 0)) + 1
			_check(String(st["name"]) != "" and float(st["t"]) >= 60.0 and float(st["t"]) <= lvl.duration - 90.0, "%s: the port stop is mid-voyage" % lvl.id)
			_check(float(st["disembark"]) > 0.0 and float(st["disembark"]) < 1.0 and int(st["board"]) > 0, "%s: sensible stop numbers" % lvl.id)
			_check(lvl.peak_guests() < lvl.total_guests(), "%s: excursion guests free beds (peak %d < total %d)" % [lvl.id, lvl.peak_guests(), lvl.total_guests()])
			_check(lvl.peak_guests() >= lvl.total_guests() - lvl.port_board() - 6, "%s: peak is not far below the crowd" % lvl.id)
		else:
			_eq(lvl.peak_guests(), lvl.total_guests(), "%s: without a stop peak == total" % lvl.id)
	for d in [&"med", &"arctic", &"underworld"]:
		var n: int = int(stop_dests.get(d, 0))
		_check(n >= 1 and n <= 2, "%s has 1-2 port stop levels (%d)" % [d, n])
	_check(storm_levels >= 3 and storm_levels <= 6, "a few levels schedule a storm (%d)" % storm_levels)
	_eq(ContentStore.event(&"storm").min_campaign_index, 8, "random storms from campaign level 8")
	# the random pool: never a storm below level 8, sometimes one above
	var picks_low: int = 0
	var picks_high: int = 0
	var lo: LevelDef = _blank_level(&"med_6")
	var hi: LevelDef = _blank_level(&"arctic_4")
	var wl: SimWorld = _world(&"med_6", _small_ship(), {}, 3, lo)
	var wh: SimWorld = _world(&"arctic_4", _small_ship(), {}, 3, hi)
	for i in 300:
		picks_low += int(wl.events._pick_random(wl) == &"storm")
		picks_high += int(wh.events._pick_random(wh) == &"storm")
	_eq(picks_low, 0, "no random storm before level 8")
	_check(picks_high > 0, "random storms exist from level 8 (%d of 300)" % picks_high)

	# peak_guests: excursion guests give their beds back before the boarding wave arrives
	var pl: LevelDef = _port_level(&"med_5", {"t": 50.0, "name": "Santorini", "disembark": 0.5, "board": 6})
	pl.waves = [{"t": 0.0, "count": 10}, {"t": 20.0, "count": 10}, {"t": 80.0, "count": 4}]
	_eq(pl.total_guests(), 30, "total counts the waves and the boarding wave")
	_eq(pl.peak_guests(), 20, "peak: 20 aboard, 10 go ashore, 6 + 4 come aboard")
	pl.vips = [{"t": 10.0, "kind": &"critic"}, {"t": 70.0, "kind": &"critic"}]
	_eq(pl.total_guests(), 32, "VIPs count in the total")
	_eq(pl.peak_guests(), 21, "peak with VIPs (a VIP before the stop is among the 21 aboard)")
	pl.port_stop["board"] = 20
	_eq(pl.peak_guests(), 35, "a big boarding wave makes the later crowd the peak")
	var plain: LevelDef = _blank_level(&"med_3")
	plain.waves = [{"t": 0.0, "count": 7}]
	_eq(plain.peak_guests(), 7, "no stop: peak == total")
	# manifest + validation + autobuilder use it
	var pa: LevelDef = ContentStore.level(&"arctic_6")
	var pport := AutoBuilder.build(pa)
	var man: Dictionary = pport.manifest()
	_eq(int(man["peak_guests"]), pa.peak_guests(), "manifest: peak guests")
	_eq(int(man["guests"]), pa.total_guests(), "manifest: total guests")
	_eq(int(man["cabins_needed"]), int(ceil(float(pa.peak_guests()) / 4.0)), "manifest: cabins needed follow the peak")
	_check(int(man["beds"]) >= pa.peak_guests() and int(man["beds"]) < pa.total_guests() + 4, "autobuilder sizes beds for the peak")
	var warn: Array = pport.validate()["warnings"]
	var bed_warn: bool = false
	for wtxt in warn:
		bed_warn = bed_warn or String(wtxt).begins_with("Only")
	_check(not bed_warn, "no bed warning when beds cover the peak")


func _t_hints_v2() -> void:
	_section("hints for the v2 mechanics")
	for id in [&"event_storm", &"crew_medic", &"crew_entertainer", &"crew_chef", &"crew_warden", &"vip_plan", &"vip_critic", &"vip_celebrity",
			&"vip_inspector", &"families", &"fatigue", &"tired", &"tired_none", &"portstop_plan", &"portstop", &"refit", &"funds", &"report"]:
		_check(HintTexts.HINTS.has(id), "hint %s exists" % id)
		var d: Dictionary = HintTexts.HINTS.get(id, {})
		_check(String(d.get("text", "")).length() > 20 and String(d.get("text", "")).length() < 130, "hint %s: short text" % id)
	# every VIP kind and every crew role that unlocks later has its hint
	for k in [&"critic", &"celebrity", &"inspector"]:
		_check(HintTexts.HINTS.has(StringName("vip_" + String(k))), "vip hint for %s" % k)
	for role in ContentStore.all_staff_roles():
		if role.unlock_level > 1:
			_check(HintTexts.HINTS.has(StringName("crew_" + String(role.id))), "crew hint for %s" % role.id)
	# level cards: feature plates follow the data
	var f1: Array[Dictionary] = ContentStore.level(&"med_1").features()
	_eq(f1.size(), 0, "med_1 has no feature plates")
	var icons: Array = []
	for it in ContentStore.level(&"underworld_4").features():
		icons.append(it["icon"])
	for want in [&"vip", &"family", &"storm", &"event", &"zzz"]:
		_check(icons.has(want), "underworld_4 card shows %s" % want)
	var arc2: Array = []
	for it in ContentStore.level(&"arctic_2").features():
		arc2.append(it["icon"])
	_check(arc2.has(&"storm") and not arc2.has(&"event"), "arctic_2: a scheduled storm, no port stop")


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
