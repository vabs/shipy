class_name StaffSim
extends RefCounted
## Crew behaviour: nearest-first job claiming, walking, working, player override.

const CLAIM_INTERVAL: float = 0.5

var jobs: JobQueue = JobQueue.new()
var _next_staff_id: int = 1


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
	s.claim_timer = w.rng.randf_range(0.0, CLAIM_INTERVAL)
	s.patrol_wait = w.rng.randf_range(1.0, 3.0)
	w.staff.append(s)
	return s


func staff_by_id(w: SimWorld, id: int) -> StaffMember:
	for s in w.staff:
		if s.id == id:
			return s
	return null


func tick(w: SimWorld, dt: float) -> void:
	for s in w.staff:
		match s.state:
			&"idle":
				_tick_idle(w, s, dt)
			&"walk":
				_tick_walk(w, s, dt)
			&"work":
				_tick_work(w, s, dt)


func _target_alive(w: SimWorld, job: Job) -> bool:
	if job.kind == &"mess":
		return w.mess_by_id(job.target_id) != null
	var r: RoomRuntime = w.room_sim.room(job.target_id)
	return r != null and r.broken


func _tick_idle(w: SimWorld, s: StaffMember, dt: float) -> void:
	# Finish any leftover vertical hop / route first.
	if s.vertical_busy() or s.has_route():
		s.step_route(dt, s.def.speed * 0.5, w.transit, &"idle")
		s.state = &"idle"
		return
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
	s.state = &"walk"
	s.work_kind = &""
	s.need_replan = false


func _tick_walk(w: SimWorld, s: StaffMember, dt: float) -> void:
	var j: Job = s.job
	if j == null or not jobs.jobs.has(j) or not _target_alive(w, j):
		_drop_job(s)
		return
	if s.need_replan and not s.vertical_busy():
		s.need_replan = false
		s.clear_route()
		if not s.plan_route(w.grid, j.deck, j.x):
			j.claimed_by = -1
			_drop_job(s)
			return
	var done: bool = s.step_route(dt, s.def.speed, w.transit, &"walk")
	s.state = &"walk"
	if done:
		s.clear_route()
		s.state = &"work"
		s.work_kind = j.kind
		s.work_target_id = j.target_id
		s.last_job_deck = j.deck
		s.last_job_x = j.x
		s.x = j.x
		s.deck = j.deck
		s.deck_f = float(j.deck)


func _tick_work(w: SimWorld, s: StaffMember, dt: float) -> void:
	var j: Job = s.job
	if j == null or not jobs.jobs.has(j) or not _target_alive(w, j):
		_drop_job(s)
		return
	var amount: float = dt / maxf(s.def.work_time, 0.1)
	s.walk_phase += dt * 6.0
	if j.kind == &"mess":
		var m: Mess = w.mess_by_id(j.target_id)
		if w.problems.add_clean(w, m, amount):
			s.jobs_done += 1
	else:
		var r: RoomRuntime = w.room_sim.room(j.target_id)
		if w.room_sim.add_repair(w, r, amount):
			s.jobs_done += 1


func _drop_job(s: StaffMember) -> void:
	s.job = null
	s.state = &"idle"
	s.work_kind = &""
	s.work_target_id = -1
	s.claim_timer = 0.0
	if not s.vertical_busy():
		s.clear_route()


## Called when a mess is cleaned / a room repaired by anyone: frees the job and any worker.
func on_target_resolved(w: SimWorld, kind: StringName, target_id: int) -> void:
	var j: Job = jobs.find(kind, target_id)
	if j == null:
		return
	jobs.remove(j)
	for s in w.staff:
		if s.job == j:
			if s.state == &"work":
				s.last_job_deck = j.deck
				s.last_job_x = j.x
			_drop_job(s)


## Player override: send a specific crew member to a problem. kind: &"mess" | &"repair"|&"breakdown".
func player_assign(w: SimWorld, staff_id: int, kind: StringName, target_id: int) -> bool:
	var s: StaffMember = staff_by_id(w, staff_id)
	if s == null:
		return false
	if kind == &"breakdown":
		kind = &"repair"
	if s.job_kind() != kind:
		return false
	var j: Job = jobs.find(kind, target_id)
	if j == null or not _target_alive(w, j):
		return false
	if s.job == j and (s.state == &"walk" or s.state == &"work"):
		return true
	# Steal the job from whoever had it.
	for o in w.staff:
		if o != s and o.job == j:
			_drop_job(o)
	# Release this member's current job back to the queue.
	if s.job != null and s.job != j:
		s.job.claimed_by = -1
	j.claimed_by = s.id
	s.job = j
	s.state = &"walk"
	s.work_kind = &""
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
