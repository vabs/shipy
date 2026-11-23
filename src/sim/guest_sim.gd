class_name GuestSim
extends RefCounted
## Guest behaviour: need decay, room choice (utility scoring), movement, queues, use, satisfaction,
## sickness bookkeeping and storming off. Stateless apart from archetype tables; all state lives on
## Guest / RoomRuntime. Methods take the world explicitly (no back-reference, no ref cycles).

const SLOW_DT: float = 0.5
const CHOOSE_THRESHOLD: float = 0.02

var _cold_drain: float = 0.0
var _hyg_base: float = 1.0
var _top_deck: int = 0
var _arch_ids: Array[StringName] = []
var _arch_weights: Array[float] = []
var _arch_defs: Dictionary = {}
var _arch_fav: Dictionary = {}


func setup(w: SimWorld) -> void:
	_top_deck = w.grid.hull.decks - 1
	_cold_drain = 0.0
	_hyg_base = 1.0
	if w.destination != null:
		_cold_drain = w.destination.top_deck_satisfaction_drain
		_hyg_base = w.destination.hygiene_decay_mult
	_arch_ids = []
	_arch_weights = []
	_arch_defs = {}
	_arch_fav = {}
	var ids: Array = w.level.archetype_weights.keys()
	ids.sort()
	var total: float = 0.0
	for k in ids:
		var id: StringName = StringName(k)
		var def: ArchetypeDef = ContentStore.archetype(id)
		if def == null:
			continue
		_arch_ids.append(id)
		var wt: float = float(w.level.archetype_weights[k])
		_arch_weights.append(wt)
		total += wt
		_arch_defs[id] = def
		var fav: Dictionary = {}
		for r in w.room_sim.service_rooms:
			if def.likes(r.def):
				fav[r.uid] = true
		_arch_fav[id] = fav
	if _arch_ids.is_empty():
		var def2: ArchetypeDef = ContentStore.archetype(&"holidaymaker")
		_arch_ids.append(&"holidaymaker")
		_arch_weights.append(1.0)
		_arch_defs[&"holidaymaker"] = def2
		_arch_fav[&"holidaymaker"] = {}


func _pick_archetype(w: SimWorld) -> StringName:
	var total: float = 0.0
	for wt in _arch_weights:
		total += wt
	var roll: float = w.rng.randf() * total
	for i in _arch_ids.size():
		roll -= _arch_weights[i]
		if roll <= 0.0:
			return _arch_ids[i]
	return _arch_ids[_arch_ids.size() - 1]


## Boards a new guest at the gangway (ticket paid, cabin assigned).
func spawn_guest(w: SimWorld, archetype_id: StringName = &"") -> Guest:
	if archetype_id == &"" or not _arch_defs.has(archetype_id):
		archetype_id = _pick_archetype(w)
	var g := Guest.new()
	g.id = w.guests.size() + 1
	g.archetype = _arch_defs[archetype_id]
	g.fav = _arch_fav.get(archetype_id, {})
	for i in 4:
		g.nv[i] = w.rng.randf_range(SimConst.INITIAL_NEED_MIN, SimConst.INITIAL_NEED_MAX)
		var base: float = SimConst.BASE_DECAY[i]
		g.decay[i] = base * float(g.archetype.decay_mult.get(SimConst.NEEDS[i], 1.0)) * w.level.decay_mult
	g.satisfaction = 72.0
	g.set_position(w.grid.hull.gangway_deck, SimConst.GANGWAY_X)
	g.mode = Guest.BOARDING
	g.state = Guest.BOARDING
	g.mode_t = w.rng.randf_range(0.5, 1.0)
	g.boarded_at = w.time
	g.slow_t = w.rng.randf_range(0.0, SLOW_DT)
	g.mood = &"ok"
	g.facing = 1
	w.guests.append(g)
	w.room_sim.assign_cabin(g)
	w.economy_earn(&"tickets", w.level.ticket_price, &"tickets")
	w.guest_boarded.emit(g.id)
	return g


func tick(w: SimWorld, dt: float) -> void:
	for g in w.guests:
		if g.mode == Guest.GONE:
			continue
		_fast(w, g, dt)
		g.slow_t += dt
		if g.slow_t >= SLOW_DT:
			var sdt: float = g.slow_t
			g.slow_t = 0.0
			_slow(w, g, sdt)


# ---------------------------------------------------------------------------------------------
# Fast tick
# ---------------------------------------------------------------------------------------------
func _fast(w: SimWorld, g: Guest, dt: float) -> void:
	var m: StringName = g.mode
	if m == Guest.USE:
		# Cheap path (about half of all guest-ticks): angry timer and storm-off are handled in _slow.
		g.use_timer -= dt
		if g.use_timer <= 0.0:
			_finish_use(w, g)
			g.state = g.mode
		return
	if g.slip_timer > 0.0:
		g.slip_timer = maxf(g.slip_timer - dt, 0.0)
	if g.storm_pending and not g.vertical_busy() and m != Guest.STORM_OFF:
		g.storm_pending = false
		_begin_storm(w, g)
		m = g.mode
	match m:
		Guest.BOARDING:
			g.mode_t -= dt
			if g.mode_t <= 0.0:
				g.mode = Guest.WANDER
				g.eval_timer = w.rng.randf_range(0.2, 1.2)
				g.wander_pause = 0.0
		Guest.WANDER:
			_wander(w, g, dt)
		Guest.WALK:
			if g.slip_timer <= 0.0:
				if _move(w, g, dt, SimConst.GUEST_SPEED, Guest.WALK):
					_arrive(w, g)
		Guest.QUEUE:
			_queue_tick(w, g, dt)
		Guest.STORM_OFF:
			if g.slip_timer <= 0.0:
				if _move(w, g, dt, SimConst.GUEST_SPEED * 1.25, Guest.STORM_OFF):
					g.mode = Guest.GONE
					g.state = Guest.GONE
					g.clear_route()
	if g.state != g.mode and not g.vertical_busy():
		g.state = g.mode


## Moves along the planned route with sickness/mess speed effects and slip checks.
## Returns true when the route is finished.
func _move(w: SimWorld, g: Guest, dt: float, speed: float, base: StringName) -> bool:
	var sp: float = speed
	if g.sick:
		sp *= 0.8
	if not g.vertical_busy():
		var cell: int = int(g.x)
		var entered: bool = cell != g.last_cell
		g.last_cell = cell
		if not w.problems.mess_cells.is_empty():
			var key: int = w.problems.cell_key(g.deck, cell)
			if w.problems.mess_cells.has(key):
				sp *= 0.5
				if entered and w.rng.randf() < SimConst.MESS_SLIP_CHANCE:
					g.slip_timer = SimConst.SLIP_TIME
					g.satisfaction = maxf(g.satisfaction - 4.0, 0.0)
					w.metrics["slips"] += 1
					w.guest_slipped.emit(g.id)
					return false
	return g.step_route(dt, sp, w.transit, base)


func _wander(w: SimWorld, g: Guest, dt: float) -> void:
	if g.has_route() or g.vertical_busy():
		if g.slip_timer <= 0.0:
			var stroll: float = 1.0 if w.events.top_deck_rush else SimConst.STROLL_SPEED_MULT
			if _move(w, g, dt, SimConst.GUEST_SPEED * stroll, Guest.WANDER):
				g.clear_route()
				g.wander_pause = w.rng.randf_range(0.6, 2.6)
	else:
		g.wander_pause -= dt
		if g.wander_pause <= 0.0:
			_pick_wander(w, g)
	g.eval_timer -= dt
	if g.eval_timer <= 0.0 and not g.vertical_busy():
		g.eval_timer = (0.5 if g.min_need() < 45.0 else 1.5) + w.rng.randf() * 0.2
		_choose_room(w, g)


func _pick_wander(w: SimWorld, g: Guest) -> void:
	var hull: HullDef = w.grid.hull
	var top: int = hull.decks - 1
	var td: int = g.deck
	var tx: float = g.x
	var roll: float = w.rng.randf()
	var cold: bool = w.destination != null and w.destination.top_deck_satisfaction_drain > 0.0 and not w.events.cold_suspended
	if w.events.top_deck_rush and roll < 0.9:
		td = top
		tx = w.rng.randf_range(1.5, float(hull.width) - 1.5)
	elif roll < 0.14 and hull.decks > 1:
		var d: int = w.rng.randi_range(0, hull.decks - 1)
		if d == g.deck or (cold and d == top):
			d = (g.deck + 1) % hull.decks
			if cold and d == top:
				d = 0
		td = d
		tx = w.rng.randf_range(1.0, float(hull.width) - 1.0)
	else:
		var dx: float = w.rng.randf_range(2.0, 6.0)
		if w.rng.randf() < 0.5:
			dx = -dx
		tx = clampf(g.x + dx, 0.5, float(hull.width) - 0.5)
	if not g.plan_route(w.grid, td, tx):
		g.wander_pause = 1.0


# ---------------------------------------------------------------------------------------------
# Choosing a room
# ---------------------------------------------------------------------------------------------
func _choose_room(w: SimWorld, g: Guest) -> void:
	if w.events.top_deck_rush and g.min_need() >= 35.0 and g.deck == _top_deck:
		return  # content guests stay on deck to watch the lights
	var u: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for i in 4:
		var n: float = g.nv[i]
		if n < 90.0:
			u[i] = pow(clampf((90.0 - n) / 90.0, 0.0, 1.0), 1.5)
	var graph: WalkGraph = w.grid.graph
	var src: int = graph.node(g.deck, int(g.x))
	var best: RoomRuntime = null
	var best_score: float = 0.0
	var unreach: float = WalkGraph.UNREACHABLE * 0.5
	for r in w.room_sim.service_rooms:
		if r.broken:
			continue
		var def: RoomDef = r.def
		var sum: float = 0.0
		var need_ok: bool = false
		var is_cabin: bool = def.id == &"cabin"
		if def.id == &"medbay":
			if not g.sick:
				continue
			sum = 10.0
			need_ok = true
		else:
			if is_cabin and r.uid != g.cabin_uid:
				continue
			for k in r.need_idx.size():
				var ni: int = r.need_idx[k]
				if g.nv[ni] < 75.0:
					need_ok = true
				sum += u[ni] * r.need_amt[k] * 0.01
		if not need_ok or sum <= 0.0:
			continue
		if not g.avoid.is_empty() and g.avoid.has(r.uid) and float(g.avoid[r.uid]) > w.time:
			continue
		var walk: float = graph.cost(src, r.door_node)
		if walk >= unreach:
			continue
		var wait: float = 0.0
		var crowd: float = 1.0
		if not is_cabin:
			var ahead: int = r.queue.size() + r.users.size() - r.cap + 1
			if ahead > 0:
				wait = float(ahead) * r.svc / float(maxi(r.cap, 1))
			if r.queue.size() >= r.cap:
				crowd = 0.6
		var fav: float = 1.6 if g.fav.has(r.uid) else 1.0
		var score: float = sum * r.appeal_now * fav * crowd / (walk + wait + 4.0)
		score *= 1.0 + w.rng.randf() * 0.06
		if score > best_score:
			best_score = score
			best = r
	if best != null and best_score >= CHOOSE_THRESHOLD:
		_go_to_room(w, g, best)


func _go_to_room(w: SimWorld, g: Guest, r: RoomRuntime) -> void:
	var tx: float = r.door_x
	if r.def.id != &"cabin":
		tx = w.room_sim.queue_spot_x(w, r, r.queue.size())
	g.clear_route()
	if not g.plan_route(w.grid, r.deck, tx):
		g.avoid[r.uid] = w.time + 10.0
		return
	g.target_uid = r.uid
	g.mode = Guest.WALK
	g.state = Guest.WALK
	r.incoming += 1


func _arrive(w: SimWorld, g: Guest) -> void:
	g.clear_route()
	var r: RoomRuntime = w.room_sim.room(g.target_uid)
	if r == null:
		g.mode = Guest.WANDER
		g.eval_timer = 0.3
		return
	r.incoming = maxi(r.incoming - 1, 0)
	if r.def.id == &"cabin":
		start_use(w, g, r)
	elif not r.broken and r.queue.is_empty() and r.users.size() < r.cap:
		start_use(w, g, r)
	else:
		r.queue.append(g.id)
		g.mode = Guest.QUEUE
		g.state = Guest.QUEUE
		g.queue_index = r.queue.size() - 1
		g.queue_x = w.room_sim.queue_spot_x(w, r, g.queue_index)
		g.facing = 1 if g.queue_x <= r.door_x else -1
		var p: float = SimConst.QUEUE_PATIENCE * w.level.patience_mult * w.rng.randf_range(0.9, 1.1)
		if not g.fav.has(r.uid):
			p *= g.archetype.patience_mult_non_favorite
		g.patience = p
		w.metrics["queue_joins"] += 1


func _queue_tick(w: SimWorld, g: Guest, dt: float) -> void:
	var r: RoomRuntime = w.room_sim.room(g.target_uid)
	if r == null:
		g.mode = Guest.WANDER
		return
	g.patience -= dt * (SimConst.BROKEN_QUEUE_PATIENCE_MULT if r.broken else 1.0)
	var dx: float = g.queue_x - g.x
	if absf(dx) > 0.02:
		var step: float = minf(absf(dx), 2.0 * dt)
		g.x += signf(dx) * step
		g.facing = 1 if dx > 0.0 else -1
		g.walk_phase += step * 1.7
	else:
		g.facing = 1 if g.queue_x <= r.door_x else -1
	if g.patience <= 0.0:
		_patience_out(w, g, r)


func _patience_out(w: SimWorld, g: Guest, r: RoomRuntime) -> void:
	r.queue.erase(g.id)
	w.room_sim.reindex_queue(w, r)
	g.queue_index = -1
	g.satisfaction = maxf(g.satisfaction - 10.0, 0.0)
	g.angry_timer = 4.0
	g.avoid[r.uid] = w.time + SimConst.AVOID_ROOM_TIME
	g.mode = Guest.WANDER
	g.eval_timer = 0.4
	g.wander_pause = 0.5
	w.metrics["patience_outs"] += 1
	w.guest_patience_out.emit(g.id, r.uid)


# ---------------------------------------------------------------------------------------------
# Using rooms
# ---------------------------------------------------------------------------------------------
func start_use(w: SimWorld, g: Guest, r: RoomRuntime) -> void:
	g.target_uid = r.uid
	g.mode = Guest.USE
	g.state = Guest.USE
	g.clear_route()
	r.users.append(g.id)
	g.slot = r.take_slot(g.id)
	g.x = r.door_x
	g.deck = r.deck
	g.deck_f = float(r.deck)
	g.queue_index = -1
	g.use_dur = r.svc
	g.use_timer = r.svc
	g.use_applied = 0.0
	for i in 4:
		g.use_rates[i] = 0.0
	for k in r.need_idx.size():
		g.use_rates[r.need_idx[k]] = r.need_amt[k] / r.svc
	g.use_favorite = g.fav.has(r.uid)


func _finish_use(w: SimWorld, g: Guest) -> void:
	var r: RoomRuntime = w.room_sim.room(g.target_uid)
	var rem: float = 1.0 - g.use_applied
	if rem > 0.0:
		for i in 4:
			g.nv[i] = minf(g.nv[i] + g.use_rates[i] * g.use_dur * rem, 100.0)
	for i in 4:
		g.use_rates[i] = 0.0
	g.slot = -1
	g.uses += 1
	g.mode = Guest.WANDER
	g.state = Guest.WANDER
	g.eval_timer = w.rng.randf_range(0.4, 1.4)
	g.wander_pause = w.rng.randf_range(0.3, 1.0)
	if r == null:
		return
	var was_full: bool = r.users.size() >= r.cap
	r.users.erase(g.id)
	r.free_slot(g.id)
	var def: RoomDef = r.def
	var gain: float = SimConst.SAT_USE_GAIN_FAV if g.use_favorite else SimConst.SAT_USE_GAIN
	var bonus: float = w.events.full_room_bonus(r) if was_full else 0.0
	g.satisfaction = minf(g.satisfaction + gain + bonus, 100.0)
	g.x = r.door_x + w.rng.randf_range(-0.3, 0.3)
	if def.spend > 0:
		w.economy_earn(&"spending", def.spend, &"spending")
	w.room_used.emit(r.uid, g.id, def.spend)
	w.room_sim.on_use_finished(r)
	if def.id != &"cabin":
		w.director.served += 1
	w.problems.try_mess(w, r)
	if def.sick_chance > 0.0 and not g.sick and w.rng.randf() < def.sick_chance:
		w.problems.infect(w, g)
	if def.id == &"medbay" and g.sick:
		cure(w, g, true)
	if def.satisfies.has(&"fun"):
		g.last_fun_tag = def.fun_tag


## Room broke while `g` was using it.
func eject_from_use(w: SimWorld, g: Guest, r: RoomRuntime) -> void:
	r.users.erase(g.id)
	r.free_slot(g.id)
	g.slot = -1
	for i in 4:
		g.use_rates[i] = 0.0
	g.satisfaction = maxf(g.satisfaction - 3.0, 0.0)
	g.mode = Guest.WANDER
	g.state = Guest.WANDER
	g.eval_timer = w.rng.randf_range(0.3, 0.9)
	g.wander_pause = 0.3
	g.avoid[r.uid] = w.time + 6.0


func cure(w: SimWorld, g: Guest, at_medbay: bool) -> void:
	if not g.sick:
		return
	g.sick = false
	g.sick_timer = 0.0
	if at_medbay:
		g.satisfaction = minf(g.satisfaction + 3.0, 100.0)
	w.guest_cured.emit(g.id)


# ---------------------------------------------------------------------------------------------
# Storming off
# ---------------------------------------------------------------------------------------------
func _leave_current(w: SimWorld, g: Guest) -> void:
	var r: RoomRuntime = w.room_sim.room(g.target_uid)
	if r == null:
		return
	match g.mode:
		Guest.QUEUE:
			r.queue.erase(g.id)
			w.room_sim.reindex_queue(w, r)
		Guest.USE:
			r.users.erase(g.id)
			r.free_slot(g.id)
			g.slot = -1
		Guest.WALK:
			r.incoming = maxi(r.incoming - 1, 0)
		_:
			pass


func _begin_storm(w: SimWorld, g: Guest) -> void:
	_leave_current(w, g)
	g.satisfaction = 0.0
	g.lost = true
	g.queue_index = -1
	for i in 4:
		g.use_rates[i] = 0.0
	g.mode = Guest.STORM_OFF
	g.state = Guest.STORM_OFF
	g.mood = &"angry"
	g.angry_timer = 999.0
	g.bubble_timer = 4.0
	g.clear_route()
	w.metrics["storm_offs"] += 1
	w.guest_stormed_off.emit(g.id)
	if not g.plan_route(w.grid, w.grid.hull.gangway_deck, SimConst.GANGWAY_X):
		g.mode = Guest.GONE
		g.state = Guest.GONE


# ---------------------------------------------------------------------------------------------
# Slow tick (needs, satisfaction, mood) every 0.5 s per guest
# ---------------------------------------------------------------------------------------------
func _slow(w: SimWorld, g: Guest, dt: float) -> void:
	var mode: StringName = g.mode
	if mode == Guest.BOARDING or mode == Guest.STORM_OFF:
		return
	if g.angry_timer > 0.0:
		g.angry_timer -= dt
	var ev: EventDirector = w.events
	var hyg: float = ev.hyg_mult * _hyg_base
	var fun_mult: float = 1.0
	if g.archetype.off_tag_fun_decay_mult != 1.0 and not g.archetype.favorite_tags.has(g.last_fun_tag):
		fun_mult = g.archetype.off_tag_fun_decay_mult
	var nv: PackedFloat32Array = g.nv
	var dc: PackedFloat32Array = g.decay
	# Needs: rest, hunger, fun, hygiene (unrolled for speed).
	var n0: float = nv[0] - dc[0] * dt
	var n1: float = nv[1] - dc[1] * dt
	var n2: float = nv[2] - dc[2] * dt * fun_mult
	var n3: float = nv[3] - dc[3] * dt * hyg
	if mode == Guest.USE:
		var ur: PackedFloat32Array = g.use_rates
		n0 += ur[0] * dt
		n1 += ur[1] * dt
		n2 += ur[2] * dt
		n3 += ur[3] * dt
		g.use_applied += dt / maxf(g.use_dur, 0.01)
	var top: bool = g.deck == _top_deck
	if top and ev.top_deck_fun_rate > 0.0 and mode == Guest.WANDER:
		n2 += ev.top_deck_fun_rate * dt
	n0 = clampf(n0, 0.0, 100.0)
	n1 = clampf(n1, 0.0, 100.0)
	n2 = clampf(n2, 0.0, 100.0)
	n3 = clampf(n3, 0.0, 100.0)
	nv[0] = n0
	nv[1] = n1
	nv[2] = n2
	nv[3] = n3
	# Satisfaction
	var s: float = 0.0
	var low: float = SimConst.SAT_LOW_RATE
	var crit: float = SimConst.SAT_CRIT_RATE
	if n0 < 30.0:
		s -= low
		if n0 < 15.0:
			s -= crit
	if n1 < 30.0:
		s -= low
		if n1 < 15.0:
			s -= crit
	if n2 < 30.0:
		s -= low
		if n2 < 15.0:
			s -= crit
	if n3 < 30.0:
		s -= low
		if n3 < 15.0:
			s -= crit
	var lowest: float = minf(minf(n0, n1), minf(n2, n3))
	if lowest >= 50.0:
		s += SimConst.SAT_GOOD_RATE
	elif lowest >= 30.0:
		s += SimConst.SAT_OK_RATE
	if g.sick:
		s -= 0.6
	if g.cabin_uid < 0:
		s -= 0.15
	if mode == Guest.QUEUE:
		s -= 0.15
		var qr: RoomRuntime = w.room_sim.room(g.target_uid)
		if qr != null and qr.broken:
			s -= SimConst.BROKEN_QUEUE_SAT_DRAIN
	if not w.messes.is_empty() and w.problems.near_mess(g.deck, g.x):
		s -= 0.5
	if top and _cold_drain > 0.0 and not ev.cold_suspended:
		s -= _cold_drain
	var sat: float = clampf(g.satisfaction + s * dt, 0.0, 100.0)
	g.satisfaction = sat
	if sat <= 5.0:
		g.storm_timer += dt
		if g.storm_timer >= 8.0:
			g.storm_pending = true
			if mode == Guest.USE:
				g.storm_pending = false
				_begin_storm(w, g)
				return
	else:
		g.storm_timer = 0.0
	if g.sick:
		g.sick_timer -= dt
		if g.sick_timer <= 0.0:
			cure(w, g, false)
	# Mood
	var m: StringName
	if g.sick:
		m = &"sick"
	elif g.angry_timer > 0.0:
		m = &"angry"
	elif lowest < 25.0:
		var li: int = 0
		if n1 == lowest:
			li = 1
		elif n2 == lowest:
			li = 2
		elif n3 == lowest:
			li = 3
		m = Guest.NEED_MOODS[li]
	elif sat < 35.0:
		m = &"unhappy"
	elif sat >= 70.0:
		m = &"happy"
	else:
		m = &"ok"
	if m != g.mood:
		g.mood = m
		g.bubble_timer = 3.0 if m != &"ok" else 0.0
	elif g.bubble_timer > 0.0:
		g.bubble_timer = maxf(g.bubble_timer - dt, 0.0)
