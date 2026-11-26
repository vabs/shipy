class_name ProblemSim
extends RefCounted
## Messes, sickness spread and ghosts.

## cell key (deck * 128 + cell) -> mess id
var mess_cells: Dictionary = {}
## deck -> Array[Mess]
var deck_messes: Dictionary = {}
var _next_mess_id: int = 1
var _next_ghost_id: int = 1
var _sick_timer: float = 0.0
var _ghost_spawn_timer: float = 0.0
var _ghost_hit_timer: float = 0.0


func setup(w: SimWorld) -> void:
	mess_cells = {}
	deck_messes = {}
	var dest: DestinationDef = w.destination
	if dest != null and dest.ghost_interval.y > 0.0:
		_ghost_spawn_timer = w.rng.randf_range(dest.ghost_interval.x, dest.ghost_interval.y) * w.level.ghost_interval_mult


func cell_key(deck: int, cell: int) -> int:
	return deck * 128 + cell


# ---------------------------------------------------------------------------------------------
# Messes
# ---------------------------------------------------------------------------------------------
func near_mess(deck: int, x: float) -> bool:
	var list: Array = deck_messes.get(deck, [])
	for m in list:
		if absf(m.x - x) <= 1.5:
			return true
	return false


## Possibly spawns a mess after a finished use in room `r`.
func try_mess(w: SimWorld, r: RoomRuntime) -> void:
	var chance: float = r.def.mess_chance
	if chance <= 0.0:
		return
	chance *= w.events.mess_mult(r) * w.level.mess_mult * r.mess_mult
	if w.rng.randf() < chance:
		spawn_mess(w, r)


func spawn_mess(w: SimWorld, r: RoomRuntime) -> Mess:
	return _place_mess(w, r.deck, int(r.door_x), [0, -1, 1, -2, 2, -3, 3], r.uid)


## Puts a mess on the first free cell of `base + offsets` (deck cap respected).
func _place_mess(w: SimWorld, deck: int, base: int, offsets: Array, room_uid: int) -> Mess:
	var list: Array = deck_messes.get(deck, [])
	if list.size() >= SimConst.MAX_MESSES_PER_DECK:
		return null
	var hull_w: int = w.grid.hull.width
	var picked: int = -1
	for off in offsets:
		var c: int = base + int(off)
		if c < 0 or c >= hull_w:
			continue
		if mess_cells.has(cell_key(deck, c)):
			continue
		picked = c
		break
	if picked < 0:
		return null
	var m := Mess.new()
	m.id = _next_mess_id
	_next_mess_id += 1
	m.deck = deck
	m.x = float(picked) + 0.5
	m.room_uid = room_uid
	list.append(m)
	deck_messes[deck] = list
	mess_cells[cell_key(deck, picked)] = m.id
	w.messes.append(m)
	w.metrics["messes"] += 1
	w.staff_sim.jobs.post(&"mess", m.deck, m.x, m.id)
	w.mess_spawned.emit(m.id)
	return m


## Neglected messes grow: once per second, old messes may spawn a neighbour.
func _spread_messes(w: SimWorld) -> void:
	if w.messes.is_empty():
		return
	for m in w.messes.duplicate():
		m.age += 1.0
		if m.age < SimConst.MESS_SPREAD_AGE:
			continue
		m.spread_t -= 1.0
		if m.spread_t > 0.0:
			continue
		m.spread_t = SimConst.MESS_SPREAD_INTERVAL
		if w.rng.randf() < SimConst.MESS_SPREAD_CHANCE:
			if _place_mess(w, m.deck, int(m.x), [1, -1, 2, -2], m.room_uid) != null:
				w.metrics["mess_spread"] += 1


## Adds cleaning progress (0..1 per mess). Returns true if the mess got cleaned.
func add_clean(w: SimWorld, m: Mess, amount: float) -> bool:
	m.clean_progress += amount
	if m.clean_progress >= 1.0:
		_remove_mess(w, m)
		w.metrics["cleaned"] += 1
		w.staff_sim.on_target_resolved(w, &"mess", m.id)
		w.mess_cleaned.emit(m.id)
		return true
	return false


func _remove_mess(w: SimWorld, m: Mess) -> void:
	var list: Array = deck_messes.get(m.deck, [])
	list.erase(m)
	mess_cells.erase(cell_key(m.deck, int(m.x)))
	w.messes.erase(m)


# ---------------------------------------------------------------------------------------------
# Sickness
# ---------------------------------------------------------------------------------------------
func infect(w: SimWorld, g: Guest) -> void:
	if g.sick or not g.is_aboard():
		return
	g.sick = true
	var has_medbay: bool = false
	for r in w.room_sim.service_rooms:
		if r.def.id == &"medbay":
			has_medbay = true
			break
	g.sick_timer = 150.0 if has_medbay else SimConst.SICK_RECOVER_TIME
	g.mood = &"sick"
	g.bubble_timer = 3.0
	g.eval_timer = 0.2
	w.metrics["sick"] += 1
	w.staff_sim.jobs.post(&"sick", g.deck, g.x, g.id)
	w.guest_got_sick.emit(g.id)


func sick_count(w: SimWorld) -> int:
	var n: int = 0
	for g in w.guests:
		if g.sick and g.mode != Guest.GONE:
			n += 1
	return n


## Guests who are seasick right now (a storm; not part of `sick_count`, they are not a "problem" in the HUD tally).
func seasick_count(w: SimWorld) -> int:
	var n: int = 0
	for g in w.guests:
		if g.seasick and g.is_aboard():
			n += 1
	return n


# ---------------------------------------------------------------------------------------------
# Ghosts
# ---------------------------------------------------------------------------------------------
func spawn_ghost(w: SimWorld) -> Ghost:
	var hull: HullDef = w.grid.hull
	var gh := Ghost.new()
	gh.id = _next_ghost_id
	_next_ghost_id += 1
	gh.deck = w.rng.randi_range(0, hull.decks - 1)
	gh.deck_f = float(gh.deck)
	gh.prev_deck_f = gh.deck_f
	gh.dir = 1 if w.rng.randf() < 0.5 else -1
	gh.x = -1.0 if gh.dir > 0 else float(hull.width) + 1.0
	gh.prev_x = gh.x
	gh.bob_phase = w.rng.randf() * TAU
	w.ghosts.append(gh)
	w.metrics["ghosts"] += 1
	w.staff_sim.jobs.post(&"ghost", gh.deck, clampf(gh.x, 0.3, float(hull.width) - 0.3), gh.id)
	w.ghost_spawned.emit(gh.id)
	return gh


func banish_ghost(w: SimWorld, gh: Ghost) -> void:
	if gh.banished or not w.ghosts.has(gh):
		return
	gh.banished = true
	w.ghosts.erase(gh)
	w.metrics["banished"] += 1
	w.staff_sim.on_target_resolved(w, &"ghost", gh.id)
	w.ghost_banished.emit(gh.id)


func tick(w: SimWorld, dt: float) -> void:
	# Sickness spread, once per second.
	_sick_timer += dt
	if _sick_timer >= 1.0:
		_sick_timer -= 1.0
		_spread_sickness(w)
		_spread_messes(w)
	# Ghosts.
	var dest: DestinationDef = w.destination
	if dest != null and dest.ghost_interval.y > 0.0:
		_ghost_spawn_timer -= dt
		if _ghost_spawn_timer <= 0.0:
			_ghost_spawn_timer = w.rng.randf_range(dest.ghost_interval.x, dest.ghost_interval.y) * w.level.ghost_interval_mult
			spawn_ghost(w)
	if w.ghosts.is_empty():
		return
	var width: float = float(w.grid.hull.width)
	var remove: Array[Ghost] = []
	for gh in w.ghosts:
		gh.age += dt
		gh.x += float(gh.dir) * gh.speed * dt
		gh.bob_phase += dt * 2.2
		if gh.x < -2.0 or gh.x > width + 2.0:
			remove.append(gh)
	for gh in remove:
		w.ghosts.erase(gh)
	_ghost_hit_timer += dt
	if _ghost_hit_timer >= 0.3:
		_ghost_hit_timer = 0.0
		for gh in w.ghosts:
			for g in w.guests:
				if g.deck != gh.deck or not g.is_aboard() or g.mode == Guest.BOARDING:
					continue
				if gh.hit.has(g.id):
					continue
				if absf(g.x - gh.x) <= SimConst.GHOST_RADIUS:
					gh.hit[g.id] = true
					g.satisfaction = maxf(g.satisfaction - 4.0, 0.0)
					if g.mode == Guest.QUEUE:
						g.patience -= 8.0
					w.metrics["ghost_hits"] += 1


func _spread_sickness(w: SimWorld) -> void:
	var sick: Array[Guest] = []
	for g in w.guests:
		if g.sick and g.is_aboard():
			sick.append(g)
	if sick.is_empty():
		return
	for s in sick:
		# Each second a sick guest infects one random healthy guest within the radius with p = 0.04.
		var near: Array[Guest] = []
		for g in w.guests:
			if g.sick or g.deck != s.deck or not g.is_aboard() or g.mode == Guest.BOARDING:
				continue
			if absf(g.x - s.x) <= SimConst.SICK_INFECT_RADIUS:
				near.append(g)
		if near.is_empty():
			continue
		if w.rng.randf() < SimConst.SICK_INFECT_CHANCE:
			infect(w, near[w.rng.randi() % near.size()])
