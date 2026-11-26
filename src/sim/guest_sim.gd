class_name GuestSim
extends RefCounted
## Guest behaviour: need decay, room choice (utility scoring), movement, queues, use, satisfaction,
## sickness bookkeeping and storming off. Stateless apart from archetype tables; all state lives on
## Guest / RoomRuntime. Methods take the world explicitly (no back-reference, no ref cycles).

const SLOW_DT: float = 0.5
const CHOOSE_THRESHOLD: float = 0.02

## Hospitality School perk: multiplies every guest's queue patience (SimWorld.apply_perks).
var patience_perk_mult: float = 1.0
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
	# Sorted as Strings: sorting StringNames compares their memory addresses, which differ from process to process and
	# made the archetype roll (and with it the whole voyage) non-reproducible between runs.
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
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
	# Kids never appear in the level's archetype weights: they only board inside families (spawn_guest by id).
	var kid_def: ArchetypeDef = ContentStore.archetype(&"kid")
	if kid_def != null:
		var kid_fav: Dictionary = {}
		for r in w.room_sim.service_rooms:
			if kid_def.likes(r.def):
				kid_fav[r.uid] = true
		_arch_defs[&"kid"] = kid_def
		_arch_fav[&"kid"] = kid_fav


## A room was built in the quick refit: archetypes that love it count it among their favourites (the dictionaries are shared with the
## guests aboard, so they see it at once).
func on_room_added(_w: SimWorld, r: RoomRuntime) -> void:
	if not r.def.is_service_room():
		return
	for id in _arch_defs:
		var def: ArchetypeDef = _arch_defs[id]
		if def.likes(r.def):
			(_arch_fav[id] as Dictionary)[r.uid] = true


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


## Boards a new guest at the gangway (ticket paid, cabin assigned). `group` makes the guest the next member of that
## GuestGroup (the first one boarding books the shared cabin for everybody, or splits the group up).
func spawn_guest(w: SimWorld, archetype_id: StringName = &"", group: GuestGroup = null) -> Guest:
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
	if group != null:
		g.group_id = group.id
		g.group_slot = group.members.size()
		if group.members.is_empty():
			w.room_sim.plan_group_cabin(group)
			if group.split:
				w.metrics["groups_split"] += 1
		group.members.append(g.id)
		if group.split:
			g.satisfaction = maxf(g.satisfaction - SimConst.GROUP_SPLIT_SAT, 0.0)
	w.room_sim.assign_cabin(g, group)
	w.economy_earn(&"tickets", w.ticket_price, &"tickets")
	w.guest_boarded.emit(g.id)
	return g


func tick(w: SimWorld, dt: float) -> void:
	for g in w.guests:
		if g.mode == Guest.GONE:
			continue
		_fast(w, g, dt)
		if g.excursion and g.mode == Guest.GONE:
			continue   # just stepped ashore: the satisfaction they keep is the one they left with
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
	if g.excursion_pending and not g.vertical_busy():
		g.excursion_pending = false
		begin_excursion(w, g)
		m = g.mode
	elif g.storm_pending and not g.vertical_busy() and m != Guest.STORM_OFF:
		g.storm_pending = false
		_begin_storm(w, g)
		m = g.mode
	match m:
		Guest.BOARDING:
			g.mode_t -= dt
			if g.mode_t <= 0.0:
				if g.vip_kind == VipSim.INSPECTOR:
					w.vip_sim.inspect_begin(w, g)
				else:
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
		Guest.INSPECT:
			if g.slip_timer <= 0.0:
				if _move(w, g, dt, SimConst.GUEST_SPEED * SimConst.INSPECT_SPEED_MULT, Guest.INSPECT):
					w.vip_sim.inspect_arrived(w, g)
		Guest.STORM_OFF:
			if g.slip_timer <= 0.0:
				if _move(w, g, dt, SimConst.GUEST_SPEED * 1.25, Guest.STORM_OFF):
					g.mode = Guest.GONE
					g.state = Guest.GONE
					g.clear_route()
		Guest.EXCURSION:
			if g.slip_timer <= 0.0:
				if _move(w, g, dt, SimConst.GUEST_SPEED * SimConst.EXCURSION_SPEED_MULT, Guest.EXCURSION):
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
		if g.hold_until > w.time:
			return false   # a medic is treating this guest: stand still
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
	if w.events.top_closed and g.deck == _top_deck and not g.vertical_busy() and not _heads_inside(g):
		_shelter(w, g)
	if g.has_route() or g.vertical_busy():
		if g.slip_timer <= 0.0:
			var stroll: float = 1.0 if w.events.top_deck_rush else SimConst.STROLL_SPEED_MULT
			if g.group_slot > 0:
				stroll *= SimConst.GROUP_CATCHUP_MULT   # followers trot to keep up with their leader
			if _move(w, g, dt, SimConst.GUEST_SPEED * stroll, Guest.WANDER):
				g.clear_route()
				g.wander_pause = w.rng.randf_range(0.6, 2.6) if g.group_slot == 0 else 0.3
	else:
		g.wander_pause -= dt
		if g.wander_pause <= 0.0:
			_pick_wander(w, g)
	g.eval_timer -= dt
	if g.eval_timer <= 0.0 and not g.vertical_busy():
		g.eval_timer = (0.5 if g.min_need() < 45.0 else 1.5) + w.rng.randf() * 0.2
		_choose_room(w, g)


## True when the guest's current route ends below the top deck.
func _heads_inside(g: Guest) -> bool:
	var n: int = g.wp_deck.size()
	return n > 0 and g.has_route() and g.wp_deck[n - 1] < _top_deck


## Storm: a guest out on the closed top deck heads for the deck below (the walk graph finds the nearest stairs / elevator).
func _shelter(w: SimWorld, g: Guest) -> void:
	g.clear_route()
	var below: int = maxi(_top_deck - 1, 0)
	if below == g.deck or not g.plan_route(w.grid, below, clampf(g.x, 1.0, float(w.grid.hull.width) - 1.0)):
		g.wander_pause = 1.0


func _pick_wander(w: SimWorld, g: Guest) -> void:
	if g.group_slot > 0 and _wander_with_leader(w, g):
		return
	var hull: HullDef = w.grid.hull
	var top: int = hull.decks - 1
	var td: int = g.deck
	var tx: float = g.x
	var roll: float = w.rng.randf()
	var cold: bool = w.destination != null and w.destination.top_deck_satisfaction_drain > 0.0 and not w.events.cold_suspended
	var shut: bool = w.events.top_closed
	if w.events.top_deck_rush and roll < 0.9:
		td = top
		tx = w.rng.randf_range(1.5, float(hull.width) - 1.5)
	elif roll < 0.14 and hull.decks > 1:
		var d: int = w.rng.randi_range(0, hull.decks - 1)
		if d == g.deck or (cold and d == top):
			d = (g.deck + 1) % hull.decks
			if cold and d == top:
				d = 0
		if shut and d == top:
			d = maxi(top - 1, 0)
		td = d
		tx = w.rng.randf_range(1.0, float(hull.width) - 1.0)
	else:
		var dx: float = w.rng.randf_range(2.0, 6.0)
		if w.rng.randf() < 0.5:
			dx = -dx
		tx = clampf(g.x + dx, 0.5, float(hull.width) - 0.5)
		if shut and td == top:
			td = maxi(top - 1, 0)   # (the shelter logic in _wander normally catches this first)
	if not g.plan_route(w.grid, td, tx):
		g.wander_pause = 1.0


# ---------------------------------------------------------------------------------------------
# Choosing a room
# ---------------------------------------------------------------------------------------------
func _choose_room(w: SimWorld, g: Guest) -> void:
	if w.events.top_deck_rush and g.min_need() >= 35.0 and g.deck == _top_deck:
		return  # content guests stay on deck to watch the lights
	# A sick or seasick follower heads for the medbay instead of tagging along (without one aboard there is nothing to choose).
	if g.group_slot > 0 and not (g.is_ailing() and w.has_room_type(&"medbay")) and _follow_leader(w, g):
		return
	var u: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for i in 4:
		var n: float = g.nv[i]
		if n < 90.0:
			u[i] = pow(clampf((90.0 - n) / 90.0, 0.0, 1.0), 1.5)
	var kid: bool = g.archetype.kid
	var graph: WalkGraph = w.grid.graph
	var src: int = graph.node(g.deck, int(g.x))
	var best: RoomRuntime = null
	var best_score: float = 0.0
	var unreach: float = WalkGraph.UNREACHABLE * 0.5
	for r in w.room_sim.service_rooms:
		if r.broken or r.closed:
			continue
		var def: RoomDef = r.def
		var sum: float = 0.0
		var need_ok: bool = false
		var is_cabin: bool = def.id == &"cabin"
		if def.id == &"medbay":
			if not g.sick and not g.seasick:
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
				wait = float(ahead) * r.svc * r.svc_mult / float(maxi(r.cap, 1))
			if r.queue.size() >= r.cap:
				crowd = 0.6
		var fav: float = 1.6 if g.fav.has(r.uid) else 1.0
		var score: float = sum * r.appeal_now * fav * crowd / (walk + wait + 4.0)
		if r.adult_mult != 1.0 and not kid:
			score *= r.adult_mult   # the kids' club is built for kids
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
	if g.group_id >= 0 and g.group_slot == 0:
		_nudge_followers(w, g)


func _arrive(w: SimWorld, g: Guest) -> void:
	g.clear_route()
	var r: RoomRuntime = w.room_sim.room(g.target_uid)
	if r == null:
		g.mode = Guest.WANDER
		g.eval_timer = 0.3
		return
	r.incoming = maxi(r.incoming - 1, 0)
	if r.closed:
		# the storm shut it while this guest was still climbing the stairs: turn around, no harm done
		g.mode = Guest.WANDER
		g.eval_timer = 0.3
		g.wander_pause = 0.2
		return
	if r.def.id == &"cabin":
		start_use(w, g, r)
	elif not r.broken and r.queue.is_empty() and r.users.size() < r.cap:
		g.queue_since = Guest.NOT_QUEUED
		w.vip_sim.critic_arrived(w, g, r)
		start_use(w, g, r)
	else:
		w.vip_sim.critic_arrived(w, g, r)
		g.queue_since = w.time
		r.queue.append(g.id)
		g.mode = Guest.QUEUE
		g.state = Guest.QUEUE
		g.queue_index = r.queue.size() - 1
		g.queue_x = w.room_sim.queue_spot_x(w, r, g.queue_index)
		g.facing = 1 if g.queue_x <= r.door_x else -1
		var p: float = SimConst.QUEUE_PATIENCE * w.level.patience_mult * patience_perk_mult * w.rng.randf_range(0.9, 1.1)
		if not g.fav.has(r.uid):
			p *= g.archetype.patience_mult_non_favorite
		if g.vip_kind == VipSim.CELEBRITY:
			p *= SimConst.CELEB_PATIENCE_MULT
		g.patience = p
		w.metrics["queue_joins"] += 1


func _queue_tick(w: SimWorld, g: Guest, dt: float) -> void:
	var r: RoomRuntime = w.room_sim.room(g.target_uid)
	if r == null:
		g.mode = Guest.WANDER
		return
	var drain: float = SimConst.BROKEN_QUEUE_PATIENCE_MULT if r.broken else 1.0
	if g.cheer_until > w.time:
		drain *= SimConst.AURA_PATIENCE_MULT   # an entertainer is juggling nearby
	g.patience -= dt * drain
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
	g.queue_since = Guest.NOT_QUEUED
	g.satisfaction = maxf(g.satisfaction - 10.0, 0.0)
	g.angry_timer = 4.0
	g.avoid[r.uid] = w.time + SimConst.AVOID_ROOM_TIME
	g.mode = Guest.WANDER
	g.eval_timer = 0.4
	g.wander_pause = 0.5
	w.metrics["patience_outs"] += 1
	w.telemetry.on_patience_out(r.uid)
	w.guest_patience_out.emit(g.id, r.uid)


# ---------------------------------------------------------------------------------------------
# Using rooms
# ---------------------------------------------------------------------------------------------
func start_use(w: SimWorld, g: Guest, r: RoomRuntime) -> void:
	g.use_wait = 0.0 if g.queue_since == Guest.NOT_QUEUED else maxf(w.time - g.queue_since, 0.0)
	g.queue_since = Guest.NOT_QUEUED
	if g.vip_kind != &"":
		if g.vip_kind == VipSim.CRITIC and r.def.category == &"food":
			g.saw_mess = g.saw_mess or w.vip_sim.mess_at_door(w, r)
		elif g.vip_kind == VipSim.CELEBRITY:
			_celeb_enter(w, g, r)
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
	var svc: float = r.svc * r.svc_mult   # a stationed chef shortens food service
	g.use_dur = svc
	g.use_timer = svc
	g.use_applied = 0.0
	for i in 4:
		g.use_rates[i] = 0.0
	for k in r.need_idx.size():
		g.use_rates[r.need_idx[k]] = r.need_amt[k] / svc
	g.use_favorite = g.fav.has(r.uid)


func _finish_use(w: SimWorld, g: Guest) -> void:
	var r: RoomRuntime = w.room_sim.room(g.target_uid)
	if g.vip_kind != &"":
		_celeb_exit(w, g)
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
	if def.id == &"medbay" and g.is_ailing():
		cure(w, g, true)
	if def.satisfies.has(&"fun"):
		g.last_fun_tag = def.fun_tag
	if g.vip_kind == VipSim.CRITIC:
		w.vip_sim.critic_meal(w, g, r)


## Room broke while `g` was using it.
func eject_from_use(w: SimWorld, g: Guest, r: RoomRuntime) -> void:
	_celeb_exit(w, g)
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
	if not g.sick and not g.seasick:
		return
	g.sick = false
	g.sick_timer = 0.0
	g.seasick = false
	g.seasick_timer = 0.0
	if at_medbay:
		g.satisfaction = minf(g.satisfaction + 3.0, 100.0)
	w.staff_sim.on_target_resolved(w, &"sick", g.id)
	w.guest_cured.emit(g.id)


## Storm (docs/SPEC.md §13.7): the guest turns seasick for `duration` s. Not contagious; a medic can treat them like a sick guest.
func make_seasick(w: SimWorld, g: Guest, duration: float) -> void:
	if g.seasick or not g.is_aboard():
		return
	g.seasick = true
	g.seasick_timer = duration
	g.mood = &"seasick"
	g.bubble_timer = 3.0
	g.eval_timer = minf(g.eval_timer, 0.4)
	w.metrics["seasick"] += 1
	if w.staff_sim.jobs.find(&"sick", g.id) == null:
		w.staff_sim.jobs.post(&"sick", g.deck, g.x, g.id)
	w.guest_got_seasick.emit(g.id)


# ---------------------------------------------------------------------------------------------
# Closed rooms (storm) and the port-stop excursion
# ---------------------------------------------------------------------------------------------
## A room was shut under its users: everybody inside, in line or on the way leaves without penalty and wanders off.
func evacuate_room(w: SimWorld, r: RoomRuntime) -> void:
	for gid in r.users.duplicate():
		var g: Guest = w.guest_by_id(gid)
		if g != null and g.mode == Guest.USE and g.target_uid == r.uid:
			send_away(w, g)
	for gid in r.queue.duplicate():
		var q: Guest = w.guest_by_id(gid)
		if q != null and q.mode == Guest.QUEUE and q.target_uid == r.uid:
			send_away(w, q)
	for g in w.guests:
		if g.mode == Guest.WALK and g.target_uid == r.uid and not g.vertical_busy():
			send_away(w, g)
	r.queue.clear()
	r.incoming = 0


## Drops whatever the guest was doing at its target room (using, queueing, walking there) and sends them wandering. No penalty.
func send_away(w: SimWorld, g: Guest) -> void:
	var was_vertical: bool = g.vertical_busy()
	_leave_current(w, g)
	for i in 4:
		g.use_rates[i] = 0.0
	g.slot = -1
	g.queue_index = -1
	g.queue_since = Guest.NOT_QUEUED
	g.target_uid = -1
	if not was_vertical:
		g.clear_route()
	g.mode = Guest.WANDER
	g.state = Guest.WANDER
	g.eval_timer = w.rng.randf_range(0.3, 0.9)
	g.wander_pause = 0.2


## Port stop: the guest goes ashore on the excursion. They leave whatever they were doing, give up their bed and walk to the
## gangway; they keep their current satisfaction in the rating and are not counted as lost.
func begin_excursion(w: SimWorld, g: Guest) -> void:
	if not g.is_aboard() or g.mode == Guest.BOARDING:
		return
	if g.vertical_busy():
		g.excursion_pending = true   # finishes the climb / ride first
		return
	_leave_current(w, g)
	for i in 4:
		g.use_rates[i] = 0.0
	g.slot = -1
	g.queue_index = -1
	g.queue_since = Guest.NOT_QUEUED
	g.excursion = true
	g.excursion_pending = false
	w.room_sim.release_bed(g)
	g.clear_route()
	g.mode = Guest.EXCURSION
	g.state = Guest.EXCURSION
	g.mood = &"happy"
	g.bubble_timer = 0.0
	g.hold_until = 0.0
	w.metrics["excursions"] += 1
	if not g.plan_route(w.grid, w.grid.hull.gangway_deck, SimConst.GANGWAY_X):
		g.mode = Guest.GONE
		g.state = Guest.GONE


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
			_celeb_exit(w, g)
		Guest.WALK:
			r.incoming = maxi(r.incoming - 1, 0)
		_:
			pass


func _begin_storm(w: SimWorld, g: Guest) -> void:
	_leave_current(w, g)
	g.satisfaction = 0.0
	g.lost = true
	if g.vip_kind != &"":
		w.vip_sim.on_leave(w, g)
	if g.group_id >= 0:
		_group_storm_penalty(w, g)
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
	if mode == Guest.BOARDING or mode == Guest.STORM_OFF or mode == Guest.INSPECT or mode == Guest.EXCURSION:
		return   # (an inspecting VIP is all business: no needs, no mood until the walk-round is over)
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
	if g.seasick:
		n3 -= SimConst.SEASICK_HYGIENE_RATE * dt
	var top: bool = g.deck == _top_deck
	if top and ev.top_deck_fun_rate > 0.0 and mode == Guest.WANDER:
		n2 += ev.top_deck_fun_rate * dt
	var cheered: bool = mode == Guest.QUEUE and g.cheer_until > w.time
	if cheered:
		n2 += SimConst.AURA_FUN_RATE * dt
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
	if g.seasick:
		s -= SimConst.SEASICK_SAT_RATE
	if g.cabin_uid < 0:
		s -= 0.15
	if mode == Guest.QUEUE:
		s += SimConst.AURA_SAT_RATE if cheered else -0.15
		var qr: RoomRuntime = w.room_sim.room(g.target_uid)
		if qr != null and qr.broken:
			s -= SimConst.BROKEN_QUEUE_SAT_DRAIN
	if not w.messes.is_empty() and w.problems.near_mess(g.deck, g.x):
		s -= 0.5
	if g.group_id >= 0 and _group_together(w, g):
		s += SimConst.GROUP_TOGETHER_RATE
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
	if g.seasick:
		g.seasick_timer -= dt
		if g.seasick_timer <= 0.0:
			g.seasick = false   # sea legs are back (the medic's job for this guest disappears with the flag)
	# Mood
	var m: StringName
	if g.sick:
		m = &"sick"
	elif g.seasick:
		m = &"seasick"
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


# ---------------------------------------------------------------------------------------------
# Groups (docs/SPEC.md §13.6)
# ---------------------------------------------------------------------------------------------
func _leader_of(w: SimWorld, g: Guest) -> Guest:
	if g.group_id < 1 or g.group_id > w.groups.size():
		return null
	var grp: GuestGroup = w.groups[g.group_id - 1]
	if grp.members.is_empty():
		return null
	var lead: Guest = w.guest_by_id(grp.members[0])
	if lead == null or lead == g or not lead.is_aboard():
		return null
	return lead


## An idle follower adopts the leader's current target when it satisfies one of the follower's needs below 75
## (cabins only when it is the follower's own cabin, the medbay only for the sick). Returns true if it set off.
func _follow_leader(w: SimWorld, g: Guest) -> bool:
	var lead: Guest = _leader_of(w, g)
	if lead == null or lead.target_uid < 0:
		return false
	if lead.mode != Guest.WALK and lead.mode != Guest.QUEUE and lead.mode != Guest.USE:
		return false
	var r: RoomRuntime = w.room_sim.room(lead.target_uid)
	if r == null or r.broken or r.closed:
		return false
	var is_cabin: bool = r.def.id == &"cabin"
	if is_cabin and r.uid != g.cabin_uid:
		return false
	if r.def.id == &"medbay" and not g.is_ailing():
		return false
	var wants: bool = false
	for k in r.need_idx.size():
		if g.nv[r.need_idx[k]] < SimConst.GROUP_ADOPT_NEED:
			wants = true
			break
	if not wants and not (r.def.id == &"medbay" and g.is_ailing()):
		return false
	if not g.avoid.is_empty() and g.avoid.has(r.uid) and float(g.avoid[r.uid]) > w.time:
		return false
	var graph: WalkGraph = w.grid.graph
	if graph.cost(graph.node(g.deck, int(g.x)), r.door_node) >= WalkGraph.UNREACHABLE * 0.5:
		return false
	w.metrics["group_follows"] += 1
	_go_to_room(w, g, r)
	return g.mode == Guest.WALK and g.target_uid == r.uid


## A strolling follower stays close behind its leader (same deck: a spot just behind, other deck: that deck).
func _wander_with_leader(w: SimWorld, g: Guest) -> bool:
	var lead: Guest = _leader_of(w, g)
	if lead == null:
		return false
	if lead.vertical_busy() or lead.mode == Guest.BOARDING:
		g.wander_pause = 0.4
		return true
	var tx: float = clampf(lead.x - float(lead.facing) * 0.6 * float(g.group_slot), 0.5, float(w.grid.hull.width) - 0.5)
	if lead.deck == g.deck and absf(g.x - tx) < 0.5:
		g.wander_pause = 0.5
		return true
	if g.plan_route(w.grid, lead.deck, tx):
		return true
	return false


## The leader just set off for a room: followers re-evaluate right away (staggered by their slot) so the group moves together.
func _nudge_followers(w: SimWorld, lead: Guest) -> void:
	var grp: GuestGroup = w.groups[lead.group_id - 1]
	for i in range(1, grp.members.size()):
		var f: Guest = w.guest_by_id(grp.members[i])
		if f != null and f.mode == Guest.WANDER and not f.vertical_busy():
			f.eval_timer = minf(f.eval_timer, 0.15 + 0.12 * float(i))


## True when another aboard member stands within GROUP_TOGETHER_RADIUS cells on the same deck.
func _group_together(w: SimWorld, g: Guest) -> bool:
	if g.group_id < 1 or g.group_id > w.groups.size():
		return false
	var grp: GuestGroup = w.groups[g.group_id - 1]
	for mid in grp.members:
		if mid == g.id:
			continue
		var o: Guest = w.guest_by_id(mid)
		if o == null or not o.is_aboard() or o.mode == Guest.BOARDING:
			continue
		if int(round(o.deck_f)) == int(round(g.deck_f)) and absf(o.x - g.x) <= SimConst.GROUP_TOGETHER_RADIUS:
			return true
	return false


## A member storming off upsets the rest of the group.
func _group_storm_penalty(w: SimWorld, g: Guest) -> void:
	if g.group_id < 1 or g.group_id > w.groups.size():
		return
	for mid in w.groups[g.group_id - 1].members:
		if mid == g.id:
			continue
		var o: Guest = w.guest_by_id(mid)
		if o == null or not o.is_aboard():
			continue
		o.satisfaction = maxf(o.satisfaction - SimConst.GROUP_STORM_SAT, 0.0)
		w.metrics["group_storm_hits"] += 1


# ---------------------------------------------------------------------------------------------
# Celebrity pull
# ---------------------------------------------------------------------------------------------
func _celeb_enter(w: SimWorld, g: Guest, r: RoomRuntime) -> void:
	_celeb_exit(w, g)
	g.celeb_room = r.uid
	r.celeb_users += 1
	w.room_sim.refresh_room_appeal(w, r)


func _celeb_exit(w: SimWorld, g: Guest) -> void:
	if g.celeb_room < 0:
		return
	var r: RoomRuntime = w.room_sim.room(g.celeb_room)
	g.celeb_room = -1
	if r != null:
		r.celeb_users = maxi(r.celeb_users - 1, 0)
		w.room_sim.refresh_room_appeal(w, r)
