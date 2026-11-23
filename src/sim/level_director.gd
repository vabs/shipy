class_name LevelDirector
extends RefCounted
## Waves, rating, mutiny, star scoring and the final result dictionary.

var served: int = 0
var mutiny_active: bool = false
var mutiny_time_left: float = SimConst.MUTINY_TIME
var ended: bool = false
var guests_planned: int = 0
var wave_index: int = -1
var mutiny: bool = false

var _spawns: Array[Dictionary] = []
var _spawn_i: int = 0
var _rating: float = 72.0
var _last_warn_sec: int = -1


func setup(w: SimWorld) -> void:
	_spawns = []
	_spawn_i = 0
	guests_planned = 0
	var waves: Array[Dictionary] = []
	for wv in w.level.waves:
		waves.append(wv)
	waves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	for wi in waves.size():
		var t0: float = float(waves[wi]["t"])
		var count: int = int(waves[wi]["count"])
		guests_planned += count
		for k in count:
			_spawns.append({
				"t": t0 + SimConst.WAVE_SPREAD * float(k) / float(maxi(count, 1)),
				"wave": wi, "first": k == 0, "count": count,
			})
	_spawns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))


func tick(w: SimWorld, _dt: float) -> void:
	while _spawn_i < _spawns.size() and float(_spawns[_spawn_i]["t"]) <= w.time:
		var s: Dictionary = _spawns[_spawn_i]
		_spawn_i += 1
		if bool(s["first"]):
			wave_index = int(s["wave"])
			w.wave_started.emit(wave_index, int(s["count"]))
		w.guest_sim.spawn_guest(w)


## Rating = mean satisfaction over all guests boarded so far (guests who left count 0).
func compute_rating(w: SimWorld) -> float:
	var n: int = w.guests.size()
	if n == 0:
		return 72.0
	var sum: float = 0.0
	for g in w.guests:
		sum += g.satisfaction
	return sum / float(n)


func rating() -> float:
	return _rating


func post_tick(w: SimWorld, dt: float) -> void:
	_rating = compute_rating(w)
	if w.level.mutiny_enabled and not w.guests.is_empty() and _rating < SimConst.MUTINY_RATING:
		if not mutiny_active:
			mutiny_active = true
			mutiny_time_left = SimConst.MUTINY_TIME
			_last_warn_sec = -1
		mutiny_time_left -= dt
		var sec: int = int(ceil(maxf(mutiny_time_left, 0.0)))
		if sec != _last_warn_sec:
			_last_warn_sec = sec
			w.mutiny_warning.emit(maxf(mutiny_time_left, 0.0))
		if mutiny_time_left <= 0.0:
			end_voyage(w, true)
			return
	elif mutiny_active:
		mutiny_active = false
		mutiny_time_left = SimConst.MUTINY_TIME
		_last_warn_sec = -1
		w.mutiny_cleared.emit()
	if w.time >= w.duration:
		end_voyage(w, false)


func lost_count(w: SimWorld) -> int:
	var n: int = 0
	for g in w.guests:
		if g.lost:
			n += 1
	return n


func goal_text(goal: Dictionary) -> String:
	match String(goal.get("type", "")):
		"rating":
			return "Reach a ship rating of %d%%" % int(goal.get("value", 0))
		"profit":
			return "Earn $%d profit" % int(goal.get("value", 0))
		"no_lost_guests":
			return "Don't lose a single guest"
		"served":
			return "Serve %d room visits" % int(goal.get("value", 0))
	return "?"


func goal_met(w: SimWorld, goal: Dictionary, rating_now: float) -> bool:
	match String(goal.get("type", "")):
		"rating":
			return rating_now >= float(goal.get("value", 0))
		"profit":
			return w.economy.profit() >= int(goal.get("value", 0))
		"no_lost_guests":
			return lost_count(w) == 0
		"served":
			return served >= int(goal.get("value", 0))
	return false


func end_voyage(w: SimWorld, by_mutiny: bool) -> void:
	if ended:
		return
	ended = true
	mutiny = by_mutiny
	w.finished = true
	_rating = compute_rating(w)
	var goals: Array[Dictionary] = []
	var stars: int = 0
	for goal in w.level.star_goals:
		var met: bool = (not by_mutiny) and goal_met(w, goal, _rating)
		if met:
			stars += 1
		goals.append({"text": goal_text(goal), "met": met, "type": String(goal.get("type", ""))})
	var avg_queue: float = 0.0
	if int(w.metrics["queue_ticks"]) > 0:
		avg_queue = float(w.metrics["queue_sum"]) / float(w.metrics["queue_ticks"])
	var result: Dictionary = {
		"stars": 0 if by_mutiny else stars,
		"goals": goals,
		"rating": _rating,
		"profit": w.economy.profit(),
		"ledger": w.economy.ledger.duplicate(),
		"guests_total": w.guests.size(),
		"guests_lost": lost_count(w),
		"served": served,
		"mutiny": by_mutiny,
		"level_id": w.level.id,
		"time": w.time,
		"avg_queue": avg_queue,
		"peak_queue": int(w.metrics["peak_queue"]),
		"avg_problems": float(w.metrics["problem_sum"]) / maxf(float(w.metrics["problem_samples"]), 1.0),
		"peak_problems": int(w.metrics["problem_peak"]),
		"problems_spawned": int(w.metrics["messes"]) + int(w.metrics["breakdowns"]) + int(w.metrics["sick"]) + int(w.metrics["ghosts"]),
		"problems_handled": int(w.metrics["cleaned"]) + int(w.metrics["repairs"]) + int(w.metrics["banished"]),
		"metrics": w.metrics.duplicate(),
	}
	w.result = result
	w.voyage_ended.emit(result)
