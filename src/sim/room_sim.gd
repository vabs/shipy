class_name RoomSim
extends RefCounted
## Room runtimes: queues, service slots, health/breakdown and repair.

var rooms: Array[RoomRuntime] = []
var by_uid: Dictionary = {}
## Rooms guests can be served in (incl. cabins and medbay).
var service_rooms: Array[RoomRuntime] = []
var cabins_by_distance: Array[RoomRuntime] = []
var elevators: Array[RoomRuntime] = []
## Crew quarters (staff bunks; never guest-facing, so not in service_rooms).
var crew_rooms: Array[RoomRuntime] = []
var _appeal_timer: float = 0.0
## Maintenance Contract perk: multiplies every room's breakdown health (SimWorld.apply_perks).
var health_perk_mult: float = 1.0


func setup(w: SimWorld) -> void:
	rooms = []
	by_uid = {}
	service_rooms = []
	cabins_by_distance = []
	elevators = []
	crew_rooms = []
	for p in w.grid.layout.rooms:
		_register(_make_runtime(w, p), p)
	_sort_cabins(w)
	refresh_appeal(w)


## The runtime of a placed room (health rolled from the sim rng, so call it in placement order).
func _make_runtime(w: SimWorld, p: PlacedRoom) -> RoomRuntime:
	var top: int = w.grid.hull.decks - 1
	var r := RoomRuntime.new()
	r.uid = p.uid
	r.def = p.def
	r.deck = p.deck
	r.x = p.x
	r.width = p.def.width
	r.tier = p.tier
	r.locked = p.locked
	r.door_x = p.door_x()
	r.top_deck = p.deck == top and not p.is_transport()
	r.cap = p.def.capacity_at(p.tier)
	r.breakable = p.def.breakdown_time > 0.0
	r.svc = p.def.service_time_at(p.tier)
	r.door_node = w.grid.graph.node(p.deck, int(r.door_x))
	r.adult_mult = p.def.adult_mult
	for need in p.def.satisfies:
		var ni: int = SimConst.NEEDS.find(StringName(need))
		if ni >= 0:
			r.need_idx.append(ni)
			r.need_amt.append(float(p.def.satisfies[need]))
	r.resize_slots()
	if p.def.breakdown_time > 0.0:
		r.max_health = p.def.health_at(p.tier) * w.level.health_mult * health_perk_mult
		r.health = r.max_health * w.rng.randf_range(0.55, 1.5)  # wide spread so rooms do not all fail together
	return r


func _register(r: RoomRuntime, p: PlacedRoom) -> void:
	rooms.append(r)
	by_uid[r.uid] = r
	if p.def.is_service_room():
		service_rooms.append(r)
	if p.def.id == &"cabin":
		cabins_by_distance.append(r)
	if p.is_elevator():
		elevators.append(r)
	if p.def.id == &"crew_quarters":
		crew_rooms.append(r)


## Cabins are filled in order of walking distance from the gangway.
func _sort_cabins(w: SimWorld) -> void:
	var g: WalkGraph = w.grid.graph
	var gw: int = g.node(w.grid.hull.gangway_deck, 0)
	var cost_of: Dictionary = {}
	for c in cabins_by_distance:
		cost_of[c.uid] = g.cost(gw, g.node(c.deck, int(c.door_x)))
	cabins_by_distance.sort_custom(func(a: RoomRuntime, b: RoomRuntime) -> bool:
		var ca: float = cost_of[a.uid]
		var cb: float = cost_of[b.uid]
		if ca != cb:
			return ca < cb
		return a.uid < b.uid)


# ---------------------------------------------------------------------------------------------
# Quick refit at a port stop (docs/SPEC.md §13.8)
# ---------------------------------------------------------------------------------------------
## Runtime for a room just added to the layout (the walk graph has been rebuilt already). Homeless guests move into new beds.
func add_runtime(w: SimWorld, p: PlacedRoom) -> RoomRuntime:
	var r: RoomRuntime = _make_runtime(w, p)
	_register(r, p)
	if p.def.id == &"cabin" or p.is_transport():
		_sort_cabins(w)   # a new staircase can change which cabin is nearest
	if p.def.is_service_room():
		refresh_room_appeal(w, r)
	if p.def.id == &"cabin":
		fill_homeless(w)
	return r


## Brings the runtime of an upgraded room up to its new tier (capacity, speed, sturdier parts).
func upgrade_runtime(w: SimWorld, r: RoomRuntime, tier: int) -> void:
	r.tier = tier
	r.cap = r.def.capacity_at(tier)
	r.svc = r.def.service_time_at(tier)
	r.resize_slots()
	if r.breakable:
		var old_max: float = r.max_health
		r.max_health = r.def.health_at(tier) * w.level.health_mult * health_perk_mult
		if not r.broken:
			r.health = minf(r.health + (r.max_health - old_max), r.max_health)
	if r.def.id == &"cabin":
		fill_homeless(w)


## Guests without a bed take a free one (after a cabin was built or upgraded).
func fill_homeless(w: SimWorld) -> void:
	for g in w.guests:
		if g.cabin_uid < 0 and g.is_aboard():
			assign_cabin(g)


## A guest leaves the ship for good: their bed is free again.
func release_bed(g: Guest) -> void:
	var c: RoomRuntime = room(g.cabin_uid)
	if c != null:
		c.sleepers.erase(g.id)


## Storm: shuts (or reopens) every top-deck room. Closing sends everybody using, queueing for or heading to those rooms away
## without any penalty.
func set_top_closed(w: SimWorld, closed: bool) -> void:
	for r in service_rooms:
		if not r.top_deck or r.closed == closed:
			continue
		r.closed = closed
		if closed:
			w.guest_sim.evacuate_room(w, r)


func room(uid: int) -> RoomRuntime:
	return by_uid.get(uid) as RoomRuntime


## Sets the durability perk multiplier and rescales the health rooms already rolled (so the rng stream is untouched).
func set_health_perk_mult(m: float) -> void:
	var ratio: float = m / maxf(health_perk_mult, 0.0001)
	health_perk_mult = m
	if is_equal_approx(ratio, 1.0):
		return
	for r in rooms:
		if r.breakable:
			r.max_health *= ratio
			if not r.broken:
				r.health *= ratio


func refresh_appeal(w: SimWorld) -> void:
	for r in service_rooms:
		refresh_room_appeal(w, r)


## Recomputes one room's appeal (event / destination multipliers, plus x1.5 while a celebrity VIP is using it).
func refresh_room_appeal(w: SimWorld, r: RoomRuntime) -> void:
	var dest: DestinationDef = w.destination
	var a: float = r.def.appeal
	if dest != null:
		if r.def.id == &"pool":
			a *= dest.pool_appeal_mult
		if r.top_deck:
			a *= dest.top_deck_appeal_mult
	a *= w.events.appeal_mult(r)
	if r.celeb_users > 0:
		a *= SimConst.CELEB_APPEAL_MULT
	r.appeal_now = a


func broken_on_deck(deck: int) -> int:
	var n: int = 0
	for r in rooms:
		if r.broken and r.deck == deck:
			n += 1
	return n


func broken_total() -> int:
	var n: int = 0
	for r in service_rooms:
		if r.broken:
			n += 1
	return n


func total_queue() -> int:
	var n: int = 0
	for r in service_rooms:
		n += r.queue.size()
	return n


## Books the shared cabin for a boarding group: the nearest cabin with enough free beds for all of them (the beds are held
## until each member boards). No such cabin: the group splits up (`group.split`, each member then boards alone).
func plan_group_cabin(group: GuestGroup) -> void:
	group.cabin_uid = -1
	group.split = true
	for c in cabins_by_distance:
		if c.free_beds() >= group.size:
			c.reserved += group.size
			group.cabin_uid = c.uid
			group.split = false
			return


## Assigns a cabin bed (fills cabins in order of distance to the gangway). A member of a group with a booked cabin takes
## one of the beds held for it.
func assign_cabin(g: Guest, group: GuestGroup = null) -> void:
	if group != null and group.cabin_uid >= 0:
		var gc: RoomRuntime = room(group.cabin_uid)
		if gc != null and gc.reserved > 0:
			gc.reserved -= 1
			gc.sleepers.append(g.id)
			g.cabin_uid = gc.uid
			g.bed_slot = gc.sleepers.size() - 1
			return
	for c in cabins_by_distance:
		if c.free_beds() > 0:
			c.sleepers.append(g.id)
			g.cabin_uid = c.uid
			g.bed_slot = c.sleepers.size() - 1
			return
	g.cabin_uid = -1
	g.bed_slot = -1


func tick(w: SimWorld, dt: float) -> void:
	_appeal_timer -= dt
	if _appeal_timer <= 0.0:
		_appeal_timer = 1.0
		refresh_appeal(w)
	var k: float = minf(dt * 4.0, 1.0)
	for r in service_rooms:
		if r.breakable and not r.broken:
			r.health -= dt
			if r.health <= 0.0:
				_try_break(w, r)
		if not r.queue.is_empty() and not r.broken and not r.closed:
			advance_queue(w, r)
		var target: float = float(r.users.size()) / float(maxi(r.cap, 1))
		r.busy_ratio += (target - r.busy_ratio) * k
	for q in crew_rooms:
		q.busy_ratio += (float(q.users.size()) / float(maxi(q.cap, 1)) - q.busy_ratio) * k
	for e in elevators:
		e.busy_ratio = float(w.transit.riders_in(e.x)) / float(SimConst.ELEVATOR_CAPACITY)


func advance_queue(w: SimWorld, r: RoomRuntime) -> void:
	var cap: int = r.capacity()
	var moved: bool = false
	while not r.queue.is_empty() and r.users.size() < cap:
		var gid: int = r.queue[0]
		r.queue.remove_at(0)
		moved = true
		var g: Guest = w.guest_by_id(gid)
		if g != null:
			w.guest_sim.start_use(w, g, r)
	if moved:
		reindex_queue(w, r)


func reindex_queue(w: SimWorld, r: RoomRuntime) -> void:
	for i in r.queue.size():
		var g: Guest = w.guest_by_id(r.queue[i])
		if g != null:
			g.queue_index = i
			g.queue_x = queue_spot_x(w, r, i)


## Corridor x of line position `index`: left of the door, spaced 0.45 cells, wrapping right at x=0.
func queue_spot_x(w: SimWorld, r: RoomRuntime, index: int) -> float:
	var sp: float = SimConst.QUEUE_SPACING
	var x: float = r.door_x - 0.35 - sp * float(index)
	if x < 0.3:
		var left_slots: int = maxi(int(floor((r.door_x - 0.35 - 0.3) / sp)) + 1, 1)
		var k: int = index - left_slots
		x = r.door_x + 0.35 + sp * float(k)
		x = minf(x, float(w.grid.hull.width) - 0.3)
	return x


func _try_break(w: SimWorld, r: RoomRuntime) -> void:
	if broken_on_deck(r.deck) >= SimConst.MAX_BROKEN_PER_DECK:
		r.health = 10.0
		return
	break_room(w, r)


func break_room(w: SimWorld, r: RoomRuntime) -> void:
	if r.broken or not r.is_breakable():
		return
	r.broken = true
	r.health = 0.0
	r.repair_progress = 0.0
	r.broken_count += 1
	w.metrics["breakdowns"] += 1
	# Eject current users.
	var ejected: Array[int] = r.users.duplicate()
	for gid in ejected:
		var g: Guest = w.guest_by_id(gid)
		if g != null:
			w.guest_sim.eject_from_use(w, g, r)
	w.staff_sim.jobs.post(&"repair", r.deck, r.door_x, r.uid)
	w.room_broken.emit(r.uid)


## Adds repair progress (0..1). Returns true if it completed the repair.
func add_repair(w: SimWorld, r: RoomRuntime, amount: float) -> bool:
	if not r.broken:
		return false
	r.repair_progress += amount
	if r.repair_progress >= 1.0:
		repair_room(w, r)
		return true
	return false


func repair_room(w: SimWorld, r: RoomRuntime) -> void:
	r.broken = false
	r.repair_progress = 0.0
	r.max_health = r.def.health_at(r.tier) * w.level.health_mult * health_perk_mult
	r.health = r.max_health * w.rng.randf_range(0.75, 1.25)
	w.metrics["repairs"] += 1
	w.staff_sim.on_target_resolved(w, &"repair", r.uid)
	w.room_repaired.emit(r.uid)


## Called by GuestSim when a use completes (wear).
func on_use_finished(r: RoomRuntime) -> void:
	r.uses += 1
	if r.is_breakable() and not r.broken:
		r.health -= r.def.wear_per_use
