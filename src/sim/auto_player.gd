class_name AutoPlayer
extends RefCounted
## A scripted "player" for balance runs and tests. Uses only SimWorld's public player API.
##   passive: does nothing (crew still do their jobs).
##   human  : a distracted but competent player. Notices problems after ~3 s, manages ~1.5 actions per
##            second, is "busy elsewhere" for 2-4 s about a quarter of the time, never assigns crew and
##            works the problem nearest to where it last acted (plus a little mouse/camera travel time
##            when it moves to another spot).
##   active : an expert. ~1.5 s reaction, ~3 clicks per second, never busy; clicks messes, holds repairs,
##            banishes ghosts, sometimes assigns idle crew and sends tired crew to the crew quarters.
##   At a mid-voyage port stop (docs/SPEC.md §13.8) active and human play do a Quick refit (`refit()`) and cast off; passive
##   play just casts off.
## Call `tick(dt)` once per world tick.

## Fraction of time a human is busy: rate * mean_busy / (1 + rate * mean_busy) = 0.25 -> rate = 1/9 per s.
const HUMAN_BUSY_RATE: float = 0.111

var world: SimWorld
var mode: StringName = &"active"
var reaction_delay: float = 1.5
var clicks_per_second: float = 3.0
var assigns_crew: bool = true
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _seen: Dictionary = {}
var _budget: float = 0.0
var _hold_uid: int = -1
var _assign_cd: float = 3.0
var _rest_cd: float = 2.0
# Human state
var _busy_left: float = 0.0
var _focus_deck: float = 0.0
var _focus_x: float = 0.0
var _target_key: String = ""
## Total seconds spent "busy elsewhere" (for tests and reports).
var busy_time: float = 0.0


func _init(w: SimWorld, play_mode: StringName = &"active", seed_value: int = 7) -> void:
	world = w
	mode = play_mode
	rng.seed = seed_value + 9973
	if mode == &"human":
		reaction_delay = 3.0
		clicks_per_second = 1.5
		assigns_crew = false
	_focus_deck = float(w.grid.hull.gangway_deck)
	_focus_x = float(w.grid.hull.width) * 0.5


func tick(dt: float) -> void:
	if world.finished:
		return
	if world.port_stop.is_ready():
		# at a port stop the player spends the quiet moment on the Quick refit, then casts off (passive play just sails on)
		if mode != &"passive":
			refit()
		world.cast_off()
		return
	if mode == &"active":
		_tick_active(dt)
	elif mode == &"human":
		_tick_human(dt)


# ---------------------------------------------------------------------------------------------
# Active: priority ghosts > repairs > messes, sometimes assigns crew
# ---------------------------------------------------------------------------------------------
func _tick_active(dt: float) -> void:
	_budget = minf(_budget + dt, 0.6)
	_observe()
	_assign_cd -= dt
	_rest_cd -= dt
	if assigns_crew and _rest_cd <= 0.0:
		_rest_cd = 1.5
		_send_tired_to_rest()
	var click_cost: float = 1.0 / clicks_per_second
	var guard: int = 0
	while guard < 6:
		guard += 1
		var gh: Ghost = _eligible_ghost()
		if gh != null and _budget >= click_cost:
			world.player_banish_ghost(gh.id)
			_budget -= click_cost
			continue
		var room: RoomRuntime = _current_or_next_broken()
		if room != null:
			var held: float = minf(_budget, dt)
			if held > 0.0:
				world.player_hold_repair(room.uid, held)
				_budget -= held
			break
		var m: Mess = _eligible_mess()
		if m != null and _budget >= click_cost:
			world.player_click_mess(m.id)
			_budget -= click_cost
			continue
		if assigns_crew and _assign_cd <= 0.0 and _budget >= 0.4:
			_assign_cd = rng.randf_range(3.0, 6.0)
			if _assign_idle_staff():
				_budget -= 0.4
				continue
		break


# ---------------------------------------------------------------------------------------------
# Human: nearest problem to the last action, distracted a quarter of the time
# ---------------------------------------------------------------------------------------------
func _tick_human(dt: float) -> void:
	_observe()
	if _busy_left > 0.0:
		_busy_left -= dt
		busy_time += dt
		return
	if rng.randf() < HUMAN_BUSY_RATE * dt:
		_busy_left = rng.randf_range(2.0, 4.0)
		_budget = minf(_budget, 0.0)
		return
	_budget = minf(_budget + dt, 0.7)
	var click_cost: float = 1.0 / clicks_per_second
	var guard: int = 0
	while guard < 6:
		guard += 1
		var t: Dictionary = _nearest_problem()
		if t.is_empty():
			break
		var key: String = "%s%d" % [t["kind"], t["id"]]
		if key != _target_key:
			# Moving to a different spot costs a little time (mouse, camera).
			var dd: float = absf(float(t["deck"]) - _focus_deck)
			var dx: float = absf(float(t["x"]) - _focus_x)
			_budget -= 0.25 + 0.04 * dx + 0.35 * dd
			_target_key = key
		if _budget < 0.0:
			break
		match t["kind"]:
			"ghost":
				if _budget < click_cost:
					break
				world.player_banish_ghost(int(t["id"]))
				_budget -= click_cost
			"mess":
				if _budget < click_cost:
					break
				world.player_click_mess(int(t["id"]))
				_budget -= click_cost
			"room":
				var held: float = minf(_budget, dt)
				if held > 0.0:
					world.player_hold_repair(int(t["id"]), held)
					_budget -= held
				_focus_deck = float(t["deck"])
				_focus_x = float(t["x"])
				break
		_focus_deck = float(t["deck"])
		_focus_x = float(t["x"])


## Eligible problem closest to where the player last acted: {kind, id, deck, x} or {}.
func _nearest_problem() -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = 1.0e9
	for gh in world.ghosts:
		if _age("g%d" % gh.id) < reaction_delay:
			continue
		var d: float = absf(float(gh.deck) - _focus_deck) * 12.0 + absf(gh.x - _focus_x)
		if d < best_d:
			best_d = d
			best = {"kind": "ghost", "id": gh.id, "deck": gh.deck, "x": gh.x}
	for m in world.messes:
		if _age("m%d" % m.id) < reaction_delay:
			continue
		var d2: float = absf(float(m.deck) - _focus_deck) * 12.0 + absf(m.x - _focus_x)
		if d2 < best_d:
			best_d = d2
			best = {"kind": "mess", "id": m.id, "deck": m.deck, "x": m.x}
	for r in world.rooms:
		if not r.broken:
			continue
		if _age("r%d_%d" % [r.uid, r.broken_count]) < reaction_delay:
			continue
		var d3: float = absf(float(r.deck) - _focus_deck) * 12.0 + absf(r.door_x - _focus_x)
		# Keep working a room that is already being repaired.
		if r.repair_progress > 0.0:
			d3 -= 6.0
		if d3 < best_d:
			best_d = d3
			best = {"kind": "room", "id": r.uid, "deck": r.deck, "x": r.door_x}
	return best


# ---------------------------------------------------------------------------------------------
func _age(key: String) -> float:
	return world.time - float(_seen.get(key, world.time))


func _observe() -> void:
	for m in world.messes:
		var k: String = "m%d" % m.id
		if not _seen.has(k):
			_seen[k] = world.time + rng.randf_range(0.0, 1.0)
	for r in world.rooms:
		if r.broken:
			var k2: String = "r%d_%d" % [r.uid, r.broken_count]
			if not _seen.has(k2):
				_seen[k2] = world.time + rng.randf_range(0.0, 1.0)
	for gh in world.ghosts:
		var k3: String = "g%d" % gh.id
		if not _seen.has(k3):
			_seen[k3] = world.time + rng.randf_range(0.0, 1.0)


func _eligible_ghost() -> Ghost:
	for gh in world.ghosts:
		if _age("g%d" % gh.id) >= reaction_delay:
			return gh
	return null


func _current_or_next_broken() -> RoomRuntime:
	if _hold_uid >= 0:
		var cur: RoomRuntime = world.room_by_uid(_hold_uid)
		if cur != null and cur.broken:
			return cur
		_hold_uid = -1
	var best: RoomRuntime = null
	var best_score: float = -1.0
	for r in world.rooms:
		if not r.broken:
			continue
		if _age("r%d_%d" % [r.uid, r.broken_count]) < reaction_delay:
			continue
		var score: float = float(r.queue.size()) * 2.0 + float(r.users.size()) + r.repair_progress * 3.0
		if score > best_score:
			best_score = score
			best = r
	if best != null:
		_hold_uid = best.uid
	return best


## Where an attentive player keeps an eye out while VIPs are being judged: the stretch of deck ahead of the inspector and
## the door of the food room a critic is heading for. [{deck, x, r}] (empty without VIPs on the review).
func _vip_spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v in world.vip_sim.members:
		if v.vip_grade != &"" or not v.is_aboard():
			continue
		if v.vip_kind == VipSim.INSPECTOR and v.mode == Guest.INSPECT:
			out.append({"deck": v.deck, "x": v.x + float(v.facing) * 3.0, "r": 6.0})
		elif v.vip_kind == VipSim.CRITIC and v.target_uid >= 0:
			var r: RoomRuntime = world.room_by_uid(v.target_uid)
			if r != null and r.def.category == &"food":
				out.append({"deck": r.deck, "x": r.door_x, "r": 3.0})
	return out


func _eligible_mess() -> Mess:
	var best: Mess = null
	var best_age: float = -1.0
	var spots: Array[Dictionary] = []
	if not world.vip_sim.members.is_empty():
		spots = _vip_spots()
	for m in world.messes:
		var a: float = _age("m%d" % m.id)
		if a < reaction_delay:
			continue
		var job: Job = world.staff_sim.jobs.find(&"mess", m.id)
		if job != null and job.claimed_by != -1 and m.clean_progress > 0.5:
			continue
		for sp in spots:
			if int(sp["deck"]) == m.deck and absf(float(sp["x"]) - m.x) <= float(sp["r"]):
				a += 100.0   # a VIP is about to see this one
				break
		if a > best_age:
			best_age = a
			best = m
	return best


func _assign_idle_staff() -> bool:
	for s in world.staff:
		if s.state != &"idle":
			continue
		var kind: StringName = s.job_kind()
		var best_id: int = -1
		var best_cost: float = 1.0e9
		var g: WalkGraph = world.grid.graph
		var src: int = g.node(s.deck, int(s.x))
		for j in world.staff_sim.jobs.jobs:
			if j.kind != kind or j.claimed_by != -1:
				continue
			var c: float = g.cost(src, g.node(j.deck, int(j.x)))
			if c < best_cost:
				best_cost = c
				best_id = j.target_id
		if best_id >= 0 and world.assign_staff(s.id, kind, best_id):
			return true
	return false


## Tired crew (energy < 30) go to a free crew quarters bunk, idle crew already when below 60: an attentive player
## rests staff before they collapse on the job. Does nothing without crew quarters or without fatigue.
func _send_tired_to_rest() -> void:
	if world.room_sim.crew_rooms.is_empty():
		return
	var g: WalkGraph = world.grid.graph
	for s in world.staff:
		if not s.fatigue_on or s.is_resting() or s.goal == &"rest":
			continue
		if not (s.energy < SimConst.STAFF_TIRED_ENERGY or (s.state == &"idle" and s.energy < 60.0)):
			continue
		var src: int = g.node(s.deck, int(s.x))
		var best: RoomRuntime = null
		var best_cost: float = WalkGraph.UNREACHABLE * 0.5
		for q in world.room_sim.crew_rooms:
			if q.free_bunks() <= 0:
				continue
			var c: float = g.cost(src, q.door_node)
			if c < best_cost:
				best_cost = c
				best = q
		if best != null:
			world.assign_staff(s.id, &"rest", best.uid)


# ---------------------------------------------------------------------------------------------
# Quick refit at a port stop (docs/SPEC.md §13.8): add / upgrade the most overloaded room type
# ---------------------------------------------------------------------------------------------
## Money kept back after the refit (upkeep and wages go on).
const REFIT_RESERVE: int = 250
const REFIT_ACTIONS: int = 3

## Spends the voyage money on beds for the guests about to board and on the most overloaded kinds of room (queue length and
## patience-outs so far, summed per room kind). Builds a new one next to the busiest, else upgrades the busiest.
func refit() -> void:
	var rep_rows: Array[Dictionary] = world.telemetry.live_rows()
	# 1. beds for the boarding wave
	var need_beds: int = world.port_stop.board
	for r in world.rooms:
		if r.def.id == &"cabin":
			need_beds -= r.free_beds()
	for g in world.guests:
		if g.is_aboard() and g.cabin_uid < 0:
			need_beds += 1
	var guard: int = 0
	while need_beds > 0 and guard < 4 and world.money > REFIT_RESERVE + ContentStore.room(&"cabin").cost:
		guard += 1
		var spot: Vector2i = _find_spot(&"cabin", 1, 0)
		if spot.x < 0 or world.add_room(&"cabin", spot.y, spot.x) < 0:
			break
		need_beds -= ContentStore.room(&"cabin").capacity
	# 2. overloaded kinds
	var load_by: Dictionary = {}
	var busiest: Dictionary = {}
	for row in rep_rows:
		var id: StringName = row["id"]
		if id == &"cabin" or id == &"crew_quarters":
			continue
		var live_q: int = 0
		var rr: RoomRuntime = world.room_by_uid(int(row["uid"]))
		if rr != null:
			live_q = rr.queue.size()
		var score: float = float(row["avg_queue"]) + 0.5 * float(row["patience_outs"]) + 0.5 * float(live_q)
		load_by[id] = float(load_by.get(id, 0.0)) + score
		if not busiest.has(id) or score > float(busiest[id]["score"]):
			busiest[id] = {"uid": int(row["uid"]), "deck": int(row["deck"]), "x": int(row["x"]), "score": score}
	var kinds: Array = load_by.keys()
	kinds.sort_custom(func(a: Variant, b: Variant) -> bool:
		if load_by[a] != load_by[b]:
			return float(load_by[a]) > float(load_by[b])
		return String(a) < String(b))
	var done: int = 0
	for k in kinds:
		if done >= REFIT_ACTIONS or float(load_by[k]) < 0.8:
			break
		var kid: StringName = StringName(k)
		var info: Dictionary = busiest[kid]
		var def: RoomDef = ContentStore.room(kid)
		if def == null or world.money < REFIT_RESERVE + mini(def.cost, maxi(def.upgrade_cost(0), 1)):
			continue
		var acted: bool = false
		if world.money >= REFIT_RESERVE + def.cost:
			var spot2: Vector2i = _find_spot(kid, int(info["deck"]), int(info["x"]))
			if spot2.x >= 0 and world.add_room(kid, spot2.y, spot2.x) > 0:
				acted = true
		if not acted and bool(world.can_upgrade_room(int(info["uid"]))["ok"]):
			var placed: PlacedRoom = world.grid.layout.get_room(int(info["uid"]))
			if world.money - placed.def.upgrade_cost(placed.tier) >= REFIT_RESERVE:
				acted = world.upgrade_room(int(info["uid"]))
		if acted:
			done += 1


## The free spot for `room_id` closest to (pref_deck, pref_x) where the refit rules allow it; (-1, -1) if there is none.
func _find_spot(room_id: StringName, pref_deck: int, pref_x: int) -> Vector2i:
	var def: RoomDef = ContentStore.room(room_id)
	if def == null:
		return Vector2i(-1, -1)
	var hull: HullDef = world.grid.hull
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for d in hull.decks:
		for x in range(0, hull.width - def.width + 1):
			var dist: int = absi(d - pref_deck) * 12 + absi(x - pref_x)
			if dist >= best_d:
				continue
			if bool(world.can_add_room(room_id, d, x)["ok"]):
				best_d = dist
				best = Vector2i(x, d)
	return best
