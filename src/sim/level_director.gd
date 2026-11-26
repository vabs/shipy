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
## Waves scheduled so far (the level's own plus the boarding wave of a port stop): the next one gets this index.
var wave_count: int = 0

var _spawns: Array[Dictionary] = []
var _spawn_i: int = 0
## Group descriptors of the whole schedule ({kids, size}) and the GuestGroups already created for them.
var _group_descs: Array[Dictionary] = []
var _groups_made: Dictionary = {}
var _rating: float = 72.0
var _last_warn_sec: int = -1


func setup(w: SimWorld) -> void:
	_spawns = []
	_spawn_i = 0
	guests_planned = 0
	_group_descs = []
	_groups_made = {}
	var waves: Array[Dictionary] = []
	for wv in w.level.waves:
		waves.append(wv)
	waves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	wave_count = waves.size()
	guests_planned += w.level.port_board()   # the guests joining at the port stop board later (add_wave)
	for wi in waves.size():
		var t0: float = float(waves[wi]["t"])
		var count: int = int(waves[wi]["count"])
		guests_planned += count
		if w.level.group_ratio > 0.0 and count > 1:
			var members: Array[Dictionary] = wave_members(count, w.level.group_ratio, _group_descs)
			for k in count:
				var m: Dictionary = members[k]
				_spawns.append({
					"t": t0 + SimConst.WAVE_SPREAD * float(k) / float(maxi(count, 1)),
					"wave": wi, "first": k == 0, "count": count, "gd": int(m["gd"]), "kid": bool(m["kid"]),
				})
		else:
			for k in count:
				_spawns.append({
					"t": t0 + SimConst.WAVE_SPREAD * float(k) / float(maxi(count, 1)),
					"wave": wi, "first": k == 0, "count": count,
				})
	for v in w.level.vips:
		var kind: StringName = StringName(v.get("kind", &""))
		if VipSim.is_kind(kind):
			guests_planned += 1
			_spawns.append({"t": float(v.get("t", 0.0)), "wave": -1, "first": false, "count": 0, "vip": kind})
	_spawns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))


func tick(w: SimWorld, _dt: float) -> void:
	while _spawn_i < _spawns.size() and float(_spawns[_spawn_i]["t"]) <= w.time:
		var s: Dictionary = _spawns[_spawn_i]
		_spawn_i += 1
		if s.has("vip"):
			w.vip_sim.board(w, StringName(s["vip"]))
			continue
		if bool(s["first"]):
			wave_index = int(s["wave"])
			w.wave_started.emit(wave_index, int(s["count"]))
		if s.has("gd") and int(s["gd"]) >= 0:
			w.guest_sim.spawn_guest(w, &"kid" if bool(s["kid"]) else &"", _group_for(w, int(s["gd"])))
		else:
			w.guest_sim.spawn_guest(w)


## Port stop (docs/SPEC.md §13.8): `count` new guests board as an extra wave starting now (spread over WAVE_SPREAD seconds, couples and
## families included when the level has them). Does not change `guests_planned` (the level's port stop is counted in setup).
func add_wave(w: SimWorld, count: int) -> void:
	if count <= 0:
		return
	var wi: int = wave_count
	wave_count += 1
	var members: Array[Dictionary] = []
	var grouped: bool = w.level.group_ratio > 0.0 and count > 1
	if grouped:
		members = wave_members(count, w.level.group_ratio, _group_descs)
	var at: int = _spawn_i
	for k in count:
		var t_new: float = w.time + SimConst.WAVE_SPREAD * float(k) / float(maxi(count, 1))
		var sp: Dictionary = {"t": t_new, "wave": wi, "first": k == 0, "count": count}
		if grouped:
			sp["gd"] = int(members[k]["gd"])
			sp["kid"] = bool(members[k]["kid"])
		while at < _spawns.size() and float(_spawns[at]["t"]) <= t_new:
			at += 1
		_spawns.insert(at, sp)
		at += 1


## Boarding order of one wave: `count` guests, of which round(count x ratio) travel in groups (GuestGroup.plan). Groups are
## contiguous and spread evenly between the solo guests; adults first, kids last. Returns [{gd, kid}] (gd = index into `descs`,
## -1 for a solo guest); every new group appends {kids, size} to `descs`. Deterministic, no rng.
static func wave_members(count: int, ratio: float, descs: Array[Dictionary]) -> Array[Dictionary]:
	var plan: Array[int] = GuestGroup.plan(count, ratio)
	var grouped: int = 0
	for kids_n in plan:
		grouped += 2 + kids_n
	var units: int = plan.size() + (count - grouped)
	var out: Array[Dictionary] = []
	var gi: int = 0
	for u in units:
		if gi < plan.size() and (u * plan.size()) % units < plan.size():
			var kids_n: int = plan[gi]
			gi += 1
			descs.append({"kids": kids_n, "size": 2 + kids_n})
			var gd: int = descs.size() - 1
			for i in 2:
				out.append({"gd": gd, "kid": false})
			for i in kids_n:
				out.append({"gd": gd, "kid": true})
		else:
			out.append({"gd": -1, "kid": false})
	return out


## The GuestGroup for schedule descriptor `gd`, created when its first member boards.
func _group_for(w: SimWorld, gd: int) -> GuestGroup:
	if _groups_made.has(gd):
		return _groups_made[gd]
	var d: Dictionary = _group_descs[gd]
	var grp := GuestGroup.new()
	grp.id = w.groups.size() + 1
	grp.size = int(d["size"])
	grp.kids = int(d["kids"])
	grp.kind = GuestGroup.kind_of(grp.kids)
	w.groups.append(grp)
	_groups_made[gd] = grp
	w.metrics["groups"] += 1
	w.metrics["kids"] += grp.kids
	return grp


## Rating = mean satisfaction over all guests boarded so far (guests who left count 0). VIPs weigh x3.
func compute_rating(w: SimWorld) -> float:
	var n: int = w.guests.size()
	if n == 0:
		return 72.0
	var sum: float = 0.0
	var weight: float = 0.0
	for g in w.guests:
		var wt: float = SimConst.VIP_RATING_WEIGHT if g.vip_kind != &"" else 1.0
		sum += g.satisfaction * wt
		weight += wt
	return sum / weight


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


## Share of the final cash that becomes company funds, indexed by stars (0..3). Stars make skill pay.
const PAYOUT_STAR_MULT: Array[float] = [0.25, 0.6, 0.8, 1.0]


static func payout_for(money_end: int, stars: int) -> int:
	return int(round(float(maxi(0, money_end)) * PAYOUT_STAR_MULT[clampi(stars, 0, 3)]))


func end_voyage(w: SimWorld, by_mutiny: bool) -> void:
	if ended:
		return
	ended = true
	mutiny = by_mutiny
	w.finished = true
	w.vip_sim.finish(w)   # unfinished reviews are judged now (their money counts towards the final cash and payout)
	_rating = compute_rating(w)
	var goals: Array[Dictionary] = []
	var stars: int = 0
	for goal in w.level.star_goals:
		var met: bool = (not by_mutiny) and goal_met(w, goal, _rating)
		if met:
			stars += 1
		goals.append({"text": goal_text(goal), "met": met, "type": String(goal.get("type", ""))})
	w.telemetry.finish(w)
	var money_end: int = w.economy.money
	var avg_queue: float = 0.0
	if int(w.metrics["queue_ticks"]) > 0:
		avg_queue = float(w.metrics["queue_sum"]) / float(w.metrics["queue_ticks"])
	var result: Dictionary = {
		"stars": 0 if by_mutiny else stars,
		"goals": goals,
		"rating": _rating,
		"profit": w.economy.profit(),
		"money_start": w.economy.money_start,
		"money_end": money_end,
		# Company funds credit (SPEC §13.1): cash on hand at the end scaled by stars, nothing after a mutiny.
		"payout": 0 if by_mutiny else payout_for(money_end, stars),
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
		"report": w.telemetry.report(),
		"vips": w.vip_sim.entries(),
		"groups": group_summary(w),
	}
	if w.port_stop.configured:
		# mid-voyage port stop (SPEC §13.8): how it went (only levels with one carry this key)
		result["port_stop"] = {"name": w.port_stop.stop_name, "excursion": w.port_stop.excursion_count, "boarded": w.port_stop.boarded,
				"refit_spent": w.port_stop.refit_spent, "rooms": w.port_stop.refit_rooms, "upgrades": w.port_stop.refit_upgrades}
	w.result = result
	w.voyage_ended.emit(result)


## {count, split, kids, members}: how many couples / families boarded, how many had to split up, how many kids came.
func group_summary(w: SimWorld) -> Dictionary:
	var split: int = 0
	var kids: int = 0
	var members: int = 0
	for grp in w.groups:
		if grp.split:
			split += 1
		kids += grp.kids
		members += grp.members.size()
	return {"count": w.groups.size(), "split": split, "kids": kids, "members": members}
