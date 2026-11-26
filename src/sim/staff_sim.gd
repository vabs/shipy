class_name StaffSim
extends RefCounted
## Crew behaviour (docs/SPEC.md §5 "Staff & jobs", §13.3, §13.4): nearest-first job claiming, walking, working,
## the aura roles (entertainer, chef), fatigue + rest, and the player override.
##
## Job kinds: mess (janitor), repair (mechanic), sick (medic, target = guest id: food poisoning or seasickness), ghost (warden, target = ghost id).
## sick / ghost jobs follow their target: Job.deck / Job.x are refreshed every tick and the chase is re-planned
## every SimConst.FOLLOW_REPLAN seconds. Aura roles never claim jobs: the entertainer walks to the longest queue
## (>= 3) and juggles, the chef stations at the busiest food room.

const CLAIM_INTERVAL: float = 0.5

var jobs: JobQueue = JobQueue.new()
var _next_staff_id: int = 1
## Crew Training perk (SimWorld.apply_perks): applied to every member, including mid-voyage hires.
var crew_speed_mult: float = 1.0
var crew_work_mult: float = 1.0
var _has_chef: bool = false


func setup(w: SimWorld, staff_counts: Dictionary) -> void:
	for role in staff_counts:
		for i in int(staff_counts[role]):
			add_staff(w, StringName(role))


func add_staff(w: SimWorld, role: StringName) -> StaffMember:
	var def: StaffDef = ContentStore.staff_role(role)
	if def == null:
		return null
	var s := StaffMember.new()
	s.id = _next_staff_id
	_next_staff_id += 1
	s.def = def
	s.role = role
	var d: int = 0
	var g: WalkGraph = w.grid.graph
	if not g.reachable(g.node(0, 1), g.node(w.grid.hull.gangway_deck, 1)):
		d = w.grid.hull.gangway_deck
	s.set_position(d, SimConst.CREW_SPAWN_X)
	s.last_job_deck = d
	s.last_job_x = SimConst.CREW_SPAWN_X
	s.state = &"idle"
	s.speed_mult = crew_speed_mult
	s.work_mult = crew_work_mult
	s.fatigue_on = w.level.staff_fatigue
	s.claim_timer = w.rng.randf_range(0.0, CLAIM_INTERVAL)
	s.patrol_wait = w.rng.randf_range(1.0, 3.0)
	if role == &"chef":
		_has_chef = true
	w.staff.append(s)
	return s


func set_crew_perk(w: SimWorld, speed_mult: float, work_mult: float) -> void:
	crew_speed_mult = speed_mult
	crew_work_mult = work_mult
	for s in w.staff:
		s.speed_mult = speed_mult
		s.work_mult = work_mult


func staff_by_id(w: SimWorld, id: int) -> StaffMember:
	for s in w.staff:
		if s.id == id:
			return s
	return null


func tick(w: SimWorld, dt: float) -> void:
	if not jobs.jobs.is_empty():
		_sync_follow_jobs(w)
	for s in w.staff:
		if s.fatigue_on and s.energy <= 0.0 and not s.is_resting() and s.goal != &"rest" and not s.vertical_busy():
			_begin_rest(w, s, -1)
		match s.state:
			&"idle":
				_tick_idle(w, s, dt)
			&"walk":
				_tick_walk(w, s, dt)
			&"work":
				_tick_work(w, s, dt)
			&"perform":
				_tick_perform(w, s, dt)
			&"station":
				_tick_station(w, s, dt)
			&"rest":
				_tick_rest(w, s, dt)
			&"nap":
				_tick_nap(w, s, dt)
		if s.fatigue_on:
			_drain(w, s, dt)
	if _has_chef:
		_refresh_chefs(w)


# ---------------------------------------------------------------------------------------------
# Fatigue (docs/SPEC.md §13.4)
# ---------------------------------------------------------------------------------------------
func _drain(w: SimWorld, s: StaffMember, dt: float) -> void:
	var rate: float = 0.0
	match s.state:
		&"work":
			rate = SimConst.STAFF_DRAIN_WORK
		&"walk":
			rate = SimConst.STAFF_DRAIN_WALK
		&"perform", &"station":
			rate = SimConst.STAFF_DRAIN_AURA
	if rate > 0.0:
		s.energy = maxf(s.energy - rate * dt, 0.0)
	if s.energy < SimConst.STAFF_TIRED_ENERGY:
		if not s.tired_notified and not s.is_resting():
			s.tired_notified = true
			w.staff_tired.emit(s.id)
	elif s.energy >= 50.0:
		s.tired_notified = false


## Sends a member to rest: the crew quarters `quarters_uid` (must have a free bunk) or, with -1, the nearest one with
## a free bunk. No quarters (or all bunks taken, or unreachable) -> naps on the spot. Always drops the current task.
func _begin_rest(w: SimWorld, s: StaffMember, quarters_uid: int) -> void:
	_release(w, s)
	var q: RoomRuntime = null
	if quarters_uid >= 0:
		q = w.room_sim.room(quarters_uid)
	else:
		q = _nearest_quarters(w, s)
	if q != null and q.free_bunks() > 0:
		q.users.append(s.id)
		q.take_slot(s.id)
		s.rest_uid = q.uid
		if s.vertical_busy():
			s.need_replan = true
		else:
			s.clear_route()
			if not s.plan_route(w.grid, q.deck, q.door_x):
				_free_bunk(w, s)
				q = null
		if q != null:
			s.goal = &"rest"
			s.state = &"walk"
			return
	if not s.vertical_busy():
		s.clear_route()
	s.state = &"nap"
	w.metrics["naps"] += 1


func _nearest_quarters(w: SimWorld, s: StaffMember) -> RoomRuntime:
	var g: WalkGraph = w.grid.graph
	var src: int = g.node(s.deck, int(s.x))
	var best: RoomRuntime = null
	var best_cost: float = WalkGraph.UNREACHABLE * 0.5
	for q in w.room_sim.crew_rooms:
		if q.free_bunks() <= 0:
			continue
		var c: float = g.cost(src, q.door_node)
		if c < best_cost - 0.0001:
			best_cost = c
			best = q
	return best


func _free_bunk(w: SimWorld, s: StaffMember) -> void:
	if s.rest_uid < 0:
		return
	var q: RoomRuntime = w.room_sim.room(s.rest_uid)
	if q != null:
		q.users.erase(s.id)
		q.free_slot(s.id)
	s.rest_uid = -1


## Gives up everything the member was doing (job returns to the queue, bunk and aura spot are freed).
func _release(w: SimWorld, s: StaffMember) -> void:
	if s.job != null:
		if s.job.claimed_by == s.id:
			s.job.claimed_by = -1
		s.job = null
	_free_bunk(w, s)
	s.goal = &""
	s.aura_uid = -1
	s.aura_until = 0.0
	s.work_kind = &""
	s.work_target_id = -1
	s.need_replan = false


func _tick_rest(w: SimWorld, s: StaffMember, dt: float) -> void:
	var q: RoomRuntime = w.room_sim.room(s.rest_uid)
	if q == null:
		_wake(w, s)
		return
	s.energy = minf(s.energy + SimConst.STAFF_REST_RATE * q.def.speed_at(q.tier) * dt, 100.0)
	if s.energy >= 100.0:
		w.metrics["rests"] += 1
		_wake(w, s)


func _tick_nap(w: SimWorld, s: StaffMember, dt: float) -> void:
	s.energy = minf(s.energy + SimConst.STAFF_NAP_RATE * dt, 100.0)
	if s.energy >= 100.0:
		_wake(w, s)


func _wake(w: SimWorld, s: StaffMember) -> void:
	_free_bunk(w, s)
	s.goal = &""
	s.state = &"idle"
	s.claim_timer = 0.0
	s.aura_eval = 0.0
	s.tired_notified = false
	w.staff_rested.emit(s.id)


# ---------------------------------------------------------------------------------------------
# Jobs
# ---------------------------------------------------------------------------------------------
func _target_alive(w: SimWorld, job: Job) -> bool:
	match job.kind:
		&"mess":
			return w.mess_by_id(job.target_id) != null
		&"sick":
			var g: Guest = w.guest_by_id(job.target_id)
			return g != null and g.is_ailing() and g.is_aboard()
		&"ghost":
			var gh: Ghost = w.ghost_by_id(job.target_id)
			return gh != null and not gh.banished
	var r: RoomRuntime = w.room_sim.room(job.target_id)
	return r != null and r.broken


## Keeps sick / ghost jobs glued to their target and removes the ones whose target is gone.
func _sync_follow_jobs(w: SimWorld) -> void:
	var dead: Array[Job] = []
	var hi: float = float(w.grid.hull.width) - 0.3
	for j in jobs.jobs:
		if j.kind == &"sick":
			var g: Guest = w.guest_by_id(j.target_id)
			if g == null or not g.is_ailing() or not g.is_aboard():
				dead.append(j)
				continue
			j.deck = g.deck
			j.x = clampf(g.x, 0.3, hi)
		elif j.kind == &"ghost":
			var gh: Ghost = w.ghost_by_id(j.target_id)
			if gh == null or gh.banished:
				dead.append(j)
				continue
			j.deck = gh.deck
			j.x = clampf(gh.x, 0.3, hi)
	for j in dead:
		_remove_job(w, j)


func _remove_job(w: SimWorld, j: Job) -> void:
	jobs.remove(j)
	for s in w.staff:
		if s.job == j:
			if s.state == &"work":
				s.last_job_deck = j.deck
				s.last_job_x = j.x
			_drop_job(s)


func _tick_idle(w: SimWorld, s: StaffMember, dt: float) -> void:
	# Finish any leftover vertical hop / route first.
	if s.vertical_busy() or s.has_route():
		s.step_route(dt, s.eff_speed() * 0.5, w.transit, &"idle")
		s.state = &"idle"
		return
	if s.def.is_aura():
		s.aura_eval -= dt
		if s.aura_eval <= 0.0:
			s.aura_eval = SimConst.ENTERTAINER_INTERVAL
			var r: RoomRuntime = _pick_perform_room(w, s) if s.role == &"entertainer" else _pick_food_room(w, s)
			if r != null and _begin_aura(w, s, r, false):
				return
	else:
		s.claim_timer -= dt
		if s.claim_timer <= 0.0:
			s.claim_timer = CLAIM_INTERVAL
			var j: Job = _find_nearest(w, s)
			if j != null:
				_assign(w, s, j)
				return
	s.patrol_wait -= dt
	if s.patrol_wait <= 0.0:
		s.patrol_wait = w.rng.randf_range(2.0, 5.0)
		var tx: float = clampf(s.last_job_x + w.rng.randf_range(-3.0, 3.0), 0.5, float(w.grid.hull.width) - 0.5)
		s.plan_route(w.grid, s.last_job_deck, tx)


func _find_nearest(w: SimWorld, s: StaffMember) -> Job:
	var best: Job = null
	var best_cost: float = WalkGraph.UNREACHABLE
	var g: WalkGraph = w.grid.graph
	var src: int = g.node(s.deck, int(s.x))
	var kind: StringName = s.job_kind()
	for j in jobs.jobs:
		if j.kind != kind or j.claimed_by != -1:
			continue
		var c: float = g.cost(src, g.node(j.deck, int(j.x)))
		if c < best_cost - 0.0001 or (absf(c - best_cost) <= 0.0001 and best != null and j.id < best.id):
			best_cost = c
			best = j
	if best_cost >= WalkGraph.UNREACHABLE * 0.5:
		return null
	return best


func _assign(w: SimWorld, s: StaffMember, j: Job) -> void:
	if s.vertical_busy():
		return
	s.clear_route()
	if not s.plan_route(w.grid, j.deck, j.x):
		return
	j.claimed_by = s.id
	s.job = j
	s.goal = &""
	s.state = &"walk"
	s.work_kind = &""
	s.need_replan = false
	s.plan_deck = j.deck
	s.plan_x = j.x
	s.follow_timer = SimConst.FOLLOW_REPLAN


func _tick_walk(w: SimWorld, s: StaffMember, dt: float) -> void:
	match s.goal:
		&"rest", &"perform", &"station":
			_walk_goal(w, s, dt)
		_:
			_walk_job(w, s, dt)


func _is_follow(j: Job) -> bool:
	return j.kind == &"sick" or j.kind == &"ghost"


func _walk_job(w: SimWorld, s: StaffMember, dt: float) -> void:
	var j: Job = s.job
	if j == null or not jobs.jobs.has(j) or not _target_alive(w, j):
		_drop_job(s)
		return
	if _is_follow(j):
		# Chase: start working as soon as the target is within reach, otherwise keep the route fresh.
		if not s.vertical_busy():
			var reach: float = SimConst.MEDIC_REACH if j.kind == &"sick" else SimConst.WARDEN_REACH
			if s.deck == j.deck and absf(s.x - j.x) <= reach:
				s.clear_route()
				_start_work(s, j)
				return
			s.follow_timer -= dt
			if s.need_replan or (s.follow_timer <= 0.0 and (not s.has_route() or s.plan_deck != j.deck or absf(s.plan_x - j.x) > 0.5)):
				s.need_replan = false
				s.follow_timer = SimConst.FOLLOW_REPLAN
				s.clear_route()
				if not s.plan_route(w.grid, j.deck, j.x):
					j.claimed_by = -1
					_drop_job(s)
					return
				s.plan_deck = j.deck
				s.plan_x = j.x
		var fdone: bool = s.step_route(dt, s.eff_speed(), w.transit, &"walk")
		s.state = &"walk"
		if fdone:
			# Reached the old spot but the target moved on: re-plan on the next tick.
			s.plan_deck = -1
			s.follow_timer = 0.0
		return
	if s.need_replan and not s.vertical_busy():
		s.need_replan = false
		s.clear_route()
		if not s.plan_route(w.grid, j.deck, j.x):
			j.claimed_by = -1
			_drop_job(s)
			return
	var done: bool = s.step_route(dt, s.eff_speed(), w.transit, &"walk")
	s.state = &"walk"
	if done:
		s.clear_route()
		_start_work(s, j)
		s.last_job_deck = j.deck
		s.last_job_x = j.x
		s.x = j.x
		s.deck = j.deck
		s.deck_f = float(j.deck)


func _start_work(s: StaffMember, j: Job) -> void:
	s.state = &"work"
	s.work_kind = j.kind
	s.work_target_id = j.target_id
	s.last_job_deck = j.deck
	s.last_job_x = j.x


func _tick_work(w: SimWorld, s: StaffMember, dt: float) -> void:
	var j: Job = s.job
	if j == null or not jobs.jobs.has(j) or not _target_alive(w, j):
		_drop_job(s)
		return
	s.walk_phase += dt * 6.0
	match j.kind:
		&"mess":
			var m: Mess = w.mess_by_id(j.target_id)
			if w.problems.add_clean(w, m, dt / maxf(s.eff_work_time(), 0.1)):
				s.jobs_done += 1
		&"sick":
			_work_sick(w, s, j, dt)
		&"ghost":
			_work_ghost(w, s, j, dt)
		_:
			var r: RoomRuntime = w.room_sim.room(j.target_id)
			if w.room_sim.add_repair(w, r, dt / maxf(s.eff_work_time(), 0.1)):
				s.jobs_done += 1


## Medic: the guest stands still while treated; `eff_work_time()` seconds later they are cured.
func _work_sick(w: SimWorld, s: StaffMember, j: Job, dt: float) -> void:
	var g: Guest = w.guest_by_id(j.target_id)
	if g.vertical_busy() or g.deck != s.deck or absf(g.x - s.x) > SimConst.MEDIC_REACH * 1.5:
		# The guest got away (stairs, elevator): chase again, keep the progress.
		s.state = &"walk"
		s.work_kind = &""
		s.plan_deck = -1
		s.follow_timer = 0.0
		return
	g.hold_until = w.time + 0.25
	s.facing = 1 if g.x >= s.x else -1
	j.progress += dt / maxf(s.eff_work_time(), 0.1)
	if j.progress >= 1.0:
		s.jobs_done += 1
		w.metrics["medic_cures"] += 1
		w.guest_sim.cure(w, g, true)   # resolves this job and drops the medic


## Warden: glides along with the ghost while channelling; `eff_work_time()` seconds later it is banished.
func _work_ghost(w: SimWorld, s: StaffMember, j: Job, dt: float) -> void:
	var gh: Ghost = w.ghost_by_id(j.target_id)
	if gh.deck != s.deck or absf(gh.x - s.x) > SimConst.WARDEN_REACH * 1.5:
		s.state = &"walk"
		s.work_kind = &""
		j.progress = 0.0
		s.plan_deck = -1
		s.follow_timer = 0.0
		return
	var dx: float = gh.x - s.x
	var step: float = s.eff_speed() * dt
	if absf(dx) > 0.15:
		s.x += clampf(dx, -step, step)
	s.facing = 1 if dx >= 0.0 else -1
	j.progress += dt / maxf(s.eff_work_time(), 0.1)
	if j.progress >= 1.0:
		s.jobs_done += 1
		w.metrics["warden_banishes"] += 1
		w.problems.banish_ghost(w, gh)   # resolves this job and drops the warden


func _drop_job(s: StaffMember) -> void:
	s.job = null
	s.state = &"idle"
	s.work_kind = &""
	s.work_target_id = -1
	s.claim_timer = 0.0
	if not s.vertical_busy():
		s.clear_route()


## Called when a mess is cleaned / a room repaired / a guest cured / a ghost banished by anyone: frees the job and
## any worker.
func on_target_resolved(w: SimWorld, kind: StringName, target_id: int) -> void:
	var j: Job = jobs.find(kind, target_id)
	if j == null:
		return
	_remove_job(w, j)


# ---------------------------------------------------------------------------------------------
# Aura roles: entertainer (perform) and chef (station)
# ---------------------------------------------------------------------------------------------
## Entertainer: the service room (never a cabin) with the longest queue of at least ENTERTAINER_MIN_QUEUE.
func _pick_perform_room(w: SimWorld, s: StaffMember) -> RoomRuntime:
	var g: WalkGraph = w.grid.graph
	var src: int = g.node(s.deck, int(s.x))
	var best: RoomRuntime = null
	var best_cost: float = 0.0
	for r in w.room_sim.service_rooms:
		if r.def.id == &"cabin" or r.queue.size() < SimConst.ENTERTAINER_MIN_QUEUE:
			continue
		var c: float = g.cost(src, r.door_node)
		if c >= WalkGraph.UNREACHABLE * 0.5:
			continue
		if best == null or r.queue.size() > best.queue.size() \
				or (r.queue.size() == best.queue.size() and c < best_cost - 0.0001):
			best = r
			best_cost = c
	return best


## Chef: the unbroken food room with the most users + queue (a room another chef already holds counts less, so a
## second chef takes the second food room); ties go to the room the chef already holds, then the lowest uid.
func _pick_food_room(w: SimWorld, s: StaffMember) -> RoomRuntime:
	var g: WalkGraph = w.grid.graph
	var src: int = g.node(s.deck, int(s.x))
	var best: RoomRuntime = null
	var best_score: float = -1.0e9
	for r in w.room_sim.service_rooms:
		if r.def.category != &"food" or r.broken:
			continue
		if g.cost(src, r.door_node) >= WalkGraph.UNREACHABLE * 0.5:
			continue
		var score: float = float(r.users.size() + r.queue.size())
		for o in w.staff:
			if o != s and o.role == &"chef" and o.aura_uid == r.uid:
				score -= 50.0
		if r.uid == s.aura_uid:
			score += 0.5
		if score > best_score + 0.0001:
			best_score = score
			best = r
	return best


## Where the aura role stands for room `r`: the middle of the queue (entertainer) / beside the door (chef).
func _aura_spot(w: SimWorld, s: StaffMember, r: RoomRuntime) -> float:
	if s.role == &"entertainer":
		return w.room_sim.queue_spot_x(w, r, r.queue.size() / 2)
	return clampf(r.door_x + 0.7, 0.3, float(w.grid.hull.width) - 0.3)


## Sends an aura role to `r`. `ordered` = the player asked (the member stays at least ENTERTAINER_STAY s).
func _begin_aura(w: SimWorld, s: StaffMember, r: RoomRuntime, ordered: bool) -> bool:
	if s.vertical_busy():
		return false
	var spot: float = _aura_spot(w, s, r)
	if not s.plan_route(w.grid, r.deck, spot):
		return false
	_release(w, s)
	s.aura_uid = r.uid
	s.goal = s.aura_kind()
	s.aura_until = w.time + SimConst.ENTERTAINER_STAY if ordered else 0.0
	s.aura_eval = SimConst.ENTERTAINER_INTERVAL if s.role == &"entertainer" else SimConst.CHEF_INTERVAL
	s.state = &"walk"
	return true


func _end_aura(s: StaffMember) -> void:
	s.goal = &""
	s.aura_uid = -1
	s.aura_until = 0.0
	s.state = &"idle"
	s.aura_eval = SimConst.ENTERTAINER_INTERVAL
	s.claim_timer = 0.0


## Walking to a crew quarters bunk, a performance spot or a food room station.
func _walk_goal(w: SimWorld, s: StaffMember, dt: float) -> void:
	var td: int = -1
	var tx: float = 0.0
	match s.goal:
		&"rest":
			var q: RoomRuntime = w.room_sim.room(s.rest_uid)
			if q != null:
				td = q.deck
				tx = q.door_x
		_:
			var r: RoomRuntime = w.room_sim.room(s.aura_uid)
			if r != null:
				td = r.deck
				tx = _aura_spot(w, s, r)
	if td < 0:
		_release(w, s)
		s.state = &"idle"
		return
	if s.need_replan and not s.vertical_busy():
		s.need_replan = false
		s.clear_route()
		if not s.plan_route(w.grid, td, tx):
			if s.goal == &"rest":
				_begin_nap_here(w, s)
			else:
				_end_aura(s)
			return
	var done: bool = s.step_route(dt, s.eff_speed(), w.transit, &"walk")
	s.state = &"walk"
	if not done:
		return
	s.clear_route()
	s.x = tx
	s.deck = td
	s.deck_f = float(td)
	s.walk_phase = 0.0
	match s.goal:
		&"rest":
			s.state = &"rest"
			s.facing = 1
		&"perform":
			s.state = &"perform"
			s.facing = -1
		_:
			s.state = &"station"
			s.facing = -1
	if s.goal != &"rest":
		s.last_job_deck = td
		s.last_job_x = tx


func _begin_nap_here(w: SimWorld, s: StaffMember) -> void:
	_free_bunk(w, s)
	s.goal = &""
	s.state = &"nap"
	w.metrics["naps"] += 1


func _tick_perform(w: SimWorld, s: StaffMember, dt: float) -> void:
	var r: RoomRuntime = w.room_sim.room(s.aura_uid)
	if r == null:
		_end_aura(s)
		return
	s.walk_phase += dt * 6.0
	var rad: float = SimConst.ENTERTAINER_RADIUS
	for gid in r.queue:
		var g: Guest = w.guest_by_id(gid)
		if g != null and g.deck == s.deck and absf(g.x - s.x) <= rad:
			g.cheer_until = w.time + 0.6
	s.aura_eval -= dt
	if s.aura_eval > 0.0:
		return
	s.aura_eval = SimConst.ENTERTAINER_INTERVAL
	var target: RoomRuntime = r
	if s.aura_until <= w.time:
		var best: RoomRuntime = _pick_perform_room(w, s)
		if best == null:
			if r.queue.size() < 2:
				_end_aura(s)
				return
		elif best.uid != r.uid and best.queue.size() >= r.queue.size() + 2:
			target = best
	# Stay (re-centre on the queue) or move to the longer one.
	var spot: float = _aura_spot(w, s, target)
	if target.uid != r.uid or absf(spot - s.x) > 0.9:
		var keep_until: float = s.aura_until
		if _begin_aura(w, s, target, false):
			s.aura_until = keep_until


func _tick_station(w: SimWorld, s: StaffMember, dt: float) -> void:
	var r: RoomRuntime = w.room_sim.room(s.aura_uid)
	if r == null or r.broken:
		_end_aura(s)
		return
	s.walk_phase += dt * 6.0
	s.aura_eval -= dt
	if s.aura_eval > 0.0:
		return
	s.aura_eval = SimConst.CHEF_INTERVAL
	if s.aura_until > w.time:
		return
	var best: RoomRuntime = _pick_food_room(w, s)
	if best != null and best.uid != r.uid:
		_begin_aura(w, s, best, false)


## Food rooms with a stationed chef get shorter service and fewer messes (one chef's worth, never stacked).
func _refresh_chefs(w: SimWorld) -> void:
	for r in w.room_sim.service_rooms:
		if r.def.category == &"food":
			r.svc_mult = 1.0
			r.mess_mult = 1.0
			r.chef_on = false
	for s in w.staff:
		if s.role == &"chef" and s.state == &"station":
			var r: RoomRuntime = w.room_sim.room(s.aura_uid)
			if r != null:
				r.svc_mult = SimConst.CHEF_SERVICE_MULT
				r.mess_mult = SimConst.CHEF_MESS_MULT
				r.chef_on = true


# ---------------------------------------------------------------------------------------------
# Player override
# ---------------------------------------------------------------------------------------------
## Sends a specific crew member somewhere (docs/SPEC.md §13.3). kind / target:
##   mess (janitor -> mess id) | repair or breakdown (mechanic -> broken room uid) | sick (medic -> guest id) |
##   ghost (warden -> ghost id) | perform (entertainer -> service room uid, stays 20 s) |
##   station (chef -> food room uid) | rest (any crew -> crew quarters uid, needs a free bunk and energy < 100).
## Returns false for unknown crew / targets, the wrong role, or a target that is not (or no longer) valid.
func player_assign(w: SimWorld, staff_id: int, kind: StringName, target_id: int) -> bool:
	var s: StaffMember = staff_by_id(w, staff_id)
	if s == null:
		return false
	if kind == &"breakdown":
		kind = &"repair"
	match kind:
		&"mess", &"repair", &"sick", &"ghost":
			return _assign_job(w, s, kind, target_id)
		&"perform", &"station":
			return _assign_aura(w, s, kind, target_id)
		&"rest":
			return _assign_rest(w, s, target_id)
	return false


func _assign_job(w: SimWorld, s: StaffMember, kind: StringName, target_id: int) -> bool:
	if s.job_kind() != kind:
		return false
	var j: Job = jobs.find(kind, target_id)
	if j == null:
		j = _post_follow_job(w, kind, target_id)
	if j == null or not _target_alive(w, j):
		return false
	if s.job == j and (s.state == &"walk" or s.state == &"work"):
		return true
	# Steal the job from whoever had it.
	for o in w.staff:
		if o != s and o.job == j:
			_drop_job(o)
	if s.goal != &"":
		_release(w, s)
	# Release this member's current job back to the queue.
	if s.job != null and s.job != j:
		s.job.claimed_by = -1
	j.claimed_by = s.id
	s.job = j
	s.state = &"walk"
	s.work_kind = &""
	s.plan_deck = j.deck
	s.plan_x = j.x
	s.follow_timer = SimConst.FOLLOW_REPLAN
	if s.vertical_busy():
		s.need_replan = true
	else:
		s.clear_route()
		if not s.plan_route(w.grid, j.deck, j.x):
			j.claimed_by = -1
			s.job = null
			s.state = &"idle"
			return false
	return true


## A sick / ghost job normally exists already (posted when the guest fell ill / the ghost spawned); recreate it if not.
func _post_follow_job(w: SimWorld, kind: StringName, target_id: int) -> Job:
	if kind == &"sick":
		var g: Guest = w.guest_by_id(target_id)
		if g == null or not g.is_ailing() or not g.is_aboard():
			return null
		return jobs.post(&"sick", g.deck, g.x, g.id)
	if kind == &"ghost":
		var gh: Ghost = w.ghost_by_id(target_id)
		if gh == null or gh.banished:
			return null
		return jobs.post(&"ghost", gh.deck, clampf(gh.x, 0.3, float(w.grid.hull.width) - 0.3), gh.id)
	return null


func _assign_aura(w: SimWorld, s: StaffMember, kind: StringName, room_uid: int) -> bool:
	if s.aura_kind() != kind:
		return false
	var r: RoomRuntime = w.room_sim.room(room_uid)
	if r == null:
		return false
	if kind == &"perform":
		if not r.def.is_service_room() or r.def.id == &"cabin":
			return false
	elif r.def.category != &"food":
		return false
	if not _begin_aura(w, s, r, true):
		# vertical hop in progress: remember the order, the walk re-plans after the hop
		if s.vertical_busy():
			_release(w, s)
			s.aura_uid = r.uid
			s.goal = kind
			s.aura_until = w.time + SimConst.ENTERTAINER_STAY
			s.aura_eval = SimConst.ENTERTAINER_INTERVAL if kind == &"perform" else SimConst.CHEF_INTERVAL
			s.need_replan = true
			s.state = &"walk"
			return true
		return false
	return true


func _assign_rest(w: SimWorld, s: StaffMember, quarters_uid: int) -> bool:
	var q: RoomRuntime = w.room_sim.room(quarters_uid)
	if q == null or not q.is_crew_quarters():
		return false
	if s.energy >= 100.0:
		return false
	if s.rest_uid == q.uid and (s.state == &"rest" or (s.state == &"walk" and s.goal == &"rest")):
		return true
	if q.free_bunks() <= 0:
		return false
	var g: WalkGraph = w.grid.graph
	if g.cost(g.node(s.deck, int(s.x)), q.door_node) >= WalkGraph.UNREACHABLE * 0.5:
		return false
	_begin_rest(w, s, q.uid)
	return s.rest_uid == q.uid
