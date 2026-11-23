class_name AutoPlayer
extends RefCounted
## A scripted "player" for balance runs and tests. Uses only SimWorld's public player API.
##   passive: does nothing (crew still do their jobs).
##   human  : a distracted but competent player. Notices problems after ~3 s, manages ~1.5 actions per
##            second, is "busy elsewhere" for 2-4 s about a quarter of the time, never assigns crew and
##            works the problem nearest to where it last acted (plus a little mouse/camera travel time
##            when it moves to another spot).
##   active : an expert. ~1.5 s reaction, ~3 clicks per second, never busy; clicks messes, holds repairs,
##            banishes ghosts and sometimes assigns idle crew.
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


func _eligible_mess() -> Mess:
	var best: Mess = null
	var best_age: float = -1.0
	for m in world.messes:
		var a: float = _age("m%d" % m.id)
		if a < reaction_delay:
			continue
		var job: Job = world.staff_sim.jobs.find(&"mess", m.id)
		if job != null and job.claimed_by != -1 and m.clean_progress > 0.5:
			continue
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
