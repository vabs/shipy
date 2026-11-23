class_name EventDirector
extends RefCounted
## Fires scheduled and random events, tracks active modifiers and queries for the sim/UI.

const GENERIC_POOL: Array[StringName] = [
	&"film_night", &"lunch_rush", &"pool_party", &"food_poisoning", &"power_surge", &"captains_dinner",
]

## [{id: StringName, def: EventDef, time_left: float}]
var active: Array[Dictionary] = []
var top_deck_rush: bool = false
var top_deck_fun_rate: float = 0.0
var cold_suspended: bool = false
## Product of active hygiene decay multipliers (cached).
var hyg_mult: float = 1.0
var _sched: Array[Dictionary] = []
var _sched_i: int = 0
var _next_random: float = -1.0
var fired: int = 0


func setup(w: SimWorld) -> void:
	_sched = []
	for e in w.level.scheduled_events:
		_sched.append({"t": float(e.get("t", 0.0)), "event": StringName(e.get("event", &""))})
	_sched.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	_sched_i = 0
	if w.level.random_event_interval > 0.0:
		_next_random = w.level.random_event_interval * w.rng.randf_range(0.8, 1.2)


func tick(w: SimWorld, dt: float) -> void:
	# Expire timed events.
	var ended: Array[Dictionary] = []
	for a in active:
		a["time_left"] = float(a["time_left"]) - dt
		if float(a["time_left"]) <= 0.0:
			ended.append(a)
	if not ended.is_empty():
		for a in ended:
			active.erase(a)
		_recompute()
		w.room_sim.refresh_appeal(w)
		for a in ended:
			w.event_ended.emit(a["id"])
	# Scheduled events.
	while _sched_i < _sched.size() and float(_sched[_sched_i]["t"]) <= w.time:
		var sid: StringName = _sched[_sched_i]["event"]
		var sdef: EventDef = ContentStore.event(sid)
		# an event with nothing to act on (no restaurant, no cinema, no pool ...) is skipped silently: no banner
		if sdef != null and _feasible(w, sdef):
			start_event(w, sid)
		_sched_i += 1
	# Random events (never while a timed event is running).
	if _next_random > 0.0 and w.time >= _next_random and w.time < w.duration - 40.0:
		var timed_running: bool = false
		for a in active:
			if float((a["def"] as EventDef).duration) > 0.0:
				timed_running = true
		if timed_running:
			_next_random = w.time + 4.0
		else:
			var pick: StringName = _pick_random(w)
			if pick != &"":
				start_event(w, pick)
			_next_random = w.time + w.level.random_event_interval * w.rng.randf_range(0.8, 1.2)


func _feasible(w: SimWorld, def: EventDef) -> bool:
	match def.id:
		&"film_night":
			return w.has_room_type(&"cinema")
		&"captains_dinner":
			return w.has_room_type(&"restaurant")
		&"pool_party":
			return w.has_room_type(&"pool")
		&"food_poisoning":
			return w.has_room_type(&"buffet") or w.has_room_type(&"restaurant")
		&"power_surge":
			for r in w.room_sim.service_rooms:
				if r.is_breakable() and not r.broken:
					return true
			return false
		&"heat_wave":
			return w.has_room_type(&"pool")
		_:
			return true


func _pick_random(w: SimWorld) -> StringName:
	var pool: Array[StringName] = []
	if w.destination != null:
		for id in w.destination.random_events:
			pool.append(id)
	for id in GENERIC_POOL:
		pool.append(id)
	var ok: Array[StringName] = []
	for id in pool:
		var def: EventDef = ContentStore.event(id)
		if def == null:
			continue
		if def.destination_lock != &"" and w.destination != null and def.destination_lock != w.destination.id:
			continue
		if _feasible(w, def):
			ok.append(id)
	if ok.is_empty():
		return &""
	return ok[w.rng.randi() % ok.size()]


func is_active(id: StringName) -> bool:
	for a in active:
		if a["id"] == id:
			return true
	return false


## Starts an event now (scheduled, random or forced by the tutorial/tests).
func start_event(w: SimWorld, id: StringName) -> void:
	var def: EventDef = ContentStore.event(id)
	if def == null:
		return
	fired += 1
	if def.duration > 0.0:
		# Restart if already running.
		for a in active:
			if a["id"] == id:
				active.erase(a)
				break
		active.append({"id": id, "def": def, "time_left": def.duration})
		_recompute()
		w.room_sim.refresh_appeal(w)
	w.metrics["events"] += 1
	w.event_started.emit(id)
	# Instant effects.
	for need in def.need_set:
		var idx: int = SimConst.NEEDS.find(StringName(need))
		if idx < 0:
			continue
		var cap: float = float(def.need_set[need])
		for g in w.guests:
			if g.mode == Guest.GONE or g.mode == Guest.STORM_OFF:
				continue
			if g.nv[idx] > cap:
				g.nv[idx] = cap
			g.eval_timer = minf(g.eval_timer, w.rng.randf_range(0.1, 1.0))
	if def.top_deck_rush:
		_rush_top_deck(w)
	if def.sick_count > 0:
		_poison(w, def.sick_count)
	if def.break_count > 0:
		_surge(w, def.break_count)
	for i in def.ghost_count:
		w.problems.spawn_ghost(w)
	if def.duration <= 0.0:
		w.event_ended.emit(id)


## Idle guests head for the top deck (northern lights).
func _rush_top_deck(w: SimWorld) -> void:
	var top: int = w.grid.hull.decks - 1
	var width: float = float(w.grid.hull.width)
	for g in w.guests:
		if g.mode != Guest.WANDER or g.vertical_busy():
			continue
		if w.rng.randf() < 0.95:
			g.clear_route()
			if g.plan_route(w.grid, top, w.rng.randf_range(2.0, width - 2.0)):
				g.wander_pause = 1.0


func _poison(w: SimWorld, count: int) -> void:
	var foods: Array[RoomRuntime] = []
	for r in w.room_sim.service_rooms:
		if r.def.id == &"buffet" or r.def.id == &"restaurant":
			foods.append(r)
	var cand: Array[Dictionary] = []
	for g in w.guests:
		if g.sick or g.mode == Guest.GONE or g.mode == Guest.STORM_OFF or g.mode == Guest.BOARDING:
			continue
		var best: float = 1.0e9
		for r in foods:
			var d: float = absf(g.x - r.door_x) + 8.0 * absf(g.deck_f - float(r.deck))
			best = minf(best, d)
		cand.append({"g": g, "d": best})
	cand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for i in mini(count, cand.size()):
		w.problems.infect(w, cand[i]["g"])


func _surge(w: SimWorld, count: int) -> void:
	var cand: Array[RoomRuntime] = []
	for r in w.room_sim.service_rooms:
		if r.is_breakable() and not r.broken:
			cand.append(r)
	# Prefer busy rooms so the surge is felt.
	for i in count:
		if cand.is_empty():
			break
		var pick: RoomRuntime = null
		var tries: int = 0
		while pick == null and tries < 6 and not cand.is_empty():
			var c: RoomRuntime = cand[w.rng.randi() % cand.size()]
			tries += 1
			if w.room_sim.broken_on_deck(c.deck) < SimConst.MAX_BROKEN_PER_DECK:
				pick = c
		if pick == null:
			# the random tries all hit a full deck: take any room whose deck still has space, else break fewer rooms
			for c in cand:
				if w.room_sim.broken_on_deck(c.deck) < SimConst.MAX_BROKEN_PER_DECK:
					pick = c
					break
		if pick == null:
			break
		cand.erase(pick)
		w.room_sim.break_room(w, pick)


func _recompute() -> void:
	top_deck_rush = false
	top_deck_fun_rate = 0.0
	cold_suspended = false
	hyg_mult = 1.0
	for a in active:
		var def: EventDef = a["def"]
		if def.top_deck_rush:
			top_deck_rush = true
		top_deck_fun_rate = maxf(top_deck_fun_rate, def.top_deck_fun_rate)
		if def.suspend_cold:
			cold_suspended = true
		hyg_mult *= def.hygiene_decay_mult


# --- modifier queries -------------------------------------------------------------------------
func appeal_mult(r: RoomRuntime) -> float:
	var m: float = 1.0
	for a in active:
		var table: Dictionary = (a["def"] as EventDef).room_appeal_mult
		if table.is_empty():
			continue
		if table.has(r.def.id):
			m *= float(table[r.def.id])
		if r.def.fun_tag != &"" and table.has(r.def.fun_tag):
			m *= float(table[r.def.fun_tag])
		if r.top_deck and table.has(&"top_deck"):
			m *= float(table[&"top_deck"])
	return m


func hygiene_mult() -> float:
	return hyg_mult


func mess_mult(r: RoomRuntime) -> float:
	var m: float = 1.0
	if r.top_deck:
		for a in active:
			m *= (a["def"] as EventDef).mess_mult_top_deck
	return m


func full_room_bonus(r: RoomRuntime) -> float:
	var b: float = 0.0
	for a in active:
		var table: Dictionary = (a["def"] as EventDef).full_room_bonus
		if table.has(r.def.id):
			b += float(table[r.def.id])
	return b


func active_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in active:
		out.append({"id": a["id"], "def": a["def"], "time_left": a["time_left"]})
	return out
