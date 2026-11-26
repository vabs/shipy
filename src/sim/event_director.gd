class_name EventDirector
extends RefCounted
## Fires scheduled and random events, tracks active modifiers and queries for the sim/UI.

## The generic random pool. The storm joins it from campaign level 8 (`EventDef.min_campaign_index`); it can also be scheduled in any
## level, and the dev flag `--storm=<t>` forces one.
const GENERIC_POOL: Array[StringName] = [
	&"film_night", &"lunch_rush", &"pool_party", &"food_poisoning", &"power_surge", &"captains_dinner", &"storm",
]
## Seconds around a mid-voyage port stop in which no storm may start (the storm would spoil the docking).
const STORM_PORT_BUFFER: float = 40.0

## [{id: StringName, def: EventDef, time_left: float}]
var active: Array[Dictionary] = []
var top_deck_rush: bool = false
var top_deck_fun_rate: float = 0.0
var cold_suspended: bool = false
## A storm event is running (docs/SPEC.md §13.7): the top deck is shut, spills are more likely, guests may get seasick.
var top_closed: bool = false
var mess_all_mult: float = 1.0
var _seasick_t: float = 0.0
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
		_recompute(w)
		w.room_sim.refresh_appeal(w)
		for a in ended:
			w.event_ended.emit(a["id"])
	if not active.is_empty() or w.weather_intensity > 0.0:
		_update_weather(w, dt)
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
		&"storm":
			# never in the way of a port stop (before, during or while docking)
			return not w.port_stop.blocks_storm(w.time)
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
		if def.min_campaign_index > 0 and (w.level == null or w.level.campaign_index < def.min_campaign_index):
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
		_recompute(w)
		w.room_sim.refresh_appeal(w)
		if def.storm:
			_seasick_t = 0.0
			_update_weather(w, 0.0)
	w.metrics["events"] += 1
	w.event_started.emit(id)
	# Instant effects.
	for need in def.need_set:
		var idx: int = SimConst.NEEDS.find(StringName(need))
		if idx < 0:
			continue
		var cap: float = float(def.need_set[need])
		for g in w.guests:
			if not g.is_aboard():
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
	if top_closed:
		return
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
		if g.sick or not g.is_aboard() or g.mode == Guest.BOARDING:
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


func _recompute(w: SimWorld = null) -> void:
	top_deck_rush = false
	top_deck_fun_rate = 0.0
	cold_suspended = false
	hyg_mult = 1.0
	mess_all_mult = 1.0
	var closed: bool = false
	for a in active:
		var def: EventDef = a["def"]
		if def.top_deck_rush:
			top_deck_rush = true
		top_deck_fun_rate = maxf(top_deck_fun_rate, def.top_deck_fun_rate)
		if def.suspend_cold:
			cold_suspended = true
		hyg_mult *= def.hygiene_decay_mult
		mess_all_mult *= def.mess_mult_all
		if def.top_deck_closed:
			closed = true
	if closed:
		top_deck_rush = false   # nobody dawdles outside in a storm
	if closed != top_closed:
		top_closed = closed
		if w != null:
			w.room_sim.set_top_closed(w, closed)


# --- storms (docs/SPEC.md §13.7) --------------------------------------------------------------
## 0..1 weather curve of a storm event: ramps up over `ease_s` seconds from its start and back down over `ease_s` seconds before it
## ends (smoothstep), flat in between.
static func weather_curve(elapsed: float, time_left: float, ease_s: float) -> float:
	if ease_s <= 0.0:
		return 1.0 if time_left > 0.0 else 0.0
	return smoothstep(0.0, 1.0, clampf(minf(elapsed, time_left) / ease_s, 0.0, 1.0))


## Chance that one guest turns seasick in one roll of a storm: `def.seasick_chance`, x `def.seasick_cabin_mult` inside a cabin.
static func seasick_chance_for(def: EventDef, in_cabin: bool) -> float:
	return def.seasick_chance * (def.seasick_cabin_mult if in_cabin else 1.0)


## Updates SimWorld.weather_intensity from the running storms and rolls seasickness every `seasick_interval` seconds.
func _update_weather(w: SimWorld, dt: float) -> void:
	var intensity: float = 0.0
	for a in active:
		var def: EventDef = a["def"]
		if not def.storm:
			continue
		var left: float = float(a["time_left"])
		intensity = maxf(intensity, weather_curve(def.duration - left, left, def.weather_ease))
		if def.seasick_chance > 0.0 and dt > 0.0:
			_seasick_t += dt
			if _seasick_t >= def.seasick_interval - 0.0001:
				_seasick_t -= def.seasick_interval
				_roll_seasick(w, def)
	w.weather_intensity = intensity


## Every aboard guest rolls the seasickness chance (ascending id order, so the rng stream is stable).
func _roll_seasick(w: SimWorld, def: EventDef) -> void:
	for g in w.guests:
		if not g.is_aboard() or g.seasick or g.mode == Guest.BOARDING or g.mode == Guest.INSPECT:
			continue
		var in_cabin: bool = false
		if g.mode == Guest.USE:
			var r: RoomRuntime = w.room_sim.room(g.target_uid)
			in_cabin = r != null and r.def.id == &"cabin"
		if w.rng.randf() < seasick_chance_for(def, in_cabin):
			w.guest_sim.make_seasick(w, g, def.seasick_duration)


## Ends every running storm at once (the ship is docking).
func end_storms(w: SimWorld) -> void:
	var ended: Array[Dictionary] = []
	for a in active:
		if (a["def"] as EventDef).storm:
			ended.append(a)
	if ended.is_empty():
		return
	for a in ended:
		active.erase(a)
	_recompute(w)
	w.room_sim.refresh_appeal(w)
	w.weather_intensity = 0.0
	for a in ended:
		w.event_ended.emit(a["id"])


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
	var m: float = mess_all_mult
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
