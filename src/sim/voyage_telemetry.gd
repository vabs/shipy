class_name VoyageTelemetry
extends RefCounted
## Records what happened on the ship during a voyage so the results screen can explain it (docs/SPEC.md §13.2).
##
## Owned by SimWorld as `telemetry`. Sampled once per second of sim time (SimWorld.tick -> `tick`), purely read-only
## on the sim: no rng, no signals. Per (deck, cell) it counts guest-seconds of `traffic` (guests standing or walking
## there, not using a room), `unhappy` (satisfaction < 40) and `queue` (guests waiting in line). Per guest room it sums
## utilisation (users / capacity), queue length, broken seconds, patience-outs and uses. The rating is sampled every
## 5 s for the sparkline.
##
## `report()` -> {
##   rooms: [{uid, id, name, deck, x, util, avg_queue, broken_frac, patience_outs, uses, tag}],
##   tips: Array[String]            (at most 3, most useful first)
##   rating_curve: Array[float]     (one point per RATING_INTERVAL s, plus the final rating)
##   grids: {traffic, unhappy, queue}   each an Array (one PackedFloat32Array of `width` cells per deck, deck 0 first)
##          holding guest-seconds per cell
##   decks, width, samples, duration, homeless
## }
## `tag` is one of TAG_OVERLOADED / TAG_UNRELIABLE / TAG_IDLE / TAG_OK.

const SAMPLE_INTERVAL: float = 1.0
const RATING_INTERVAL: float = 5.0
const UNHAPPY_BELOW: float = 40.0
const MAX_TIPS: int = 3

const TAG_OK: StringName = &"ok"
const TAG_OVERLOADED: StringName = &"overloaded"
const TAG_IDLE: StringName = &"idle"
const TAG_UNRELIABLE: StringName = &"unreliable"

const OVERLOADED_QUEUE: float = 2.0
const OVERLOADED_PATIENCE_OUTS: int = 3
const IDLE_UTIL: float = 0.15
const IDLE_USES: int = 3
const UNRELIABLE_FRAC: float = 0.2
## A room added in a Quick refit is only called idle after it has been aboard this many sample seconds.
const MIN_IDLE_SAMPLES: int = 40

var decks: int = 0
var width: int = 0
var samples: int = 0
var duration: float = 0.0
var homeless: int = 0
## Groups that boarded / had to split up (no cabin with enough free beds) and the VIPs who left a bad review: [{kind, detail}].
var groups_total: int = 0
var groups_split: int = 0
var _vip_bad: Array[Dictionary] = []

var _traffic: Array[PackedFloat32Array] = []
var _unhappy: Array[PackedFloat32Array] = []
var _queue: Array[PackedFloat32Array] = []
var _rooms: Array[RoomRuntime] = []
var _util_sum: Dictionary = {}
var _queue_sum: Dictionary = {}
var _broken_s: Dictionary = {}
var _patience_outs: Dictionary = {}
## room uid -> sample count when the room joined the ship (0 for the rooms the voyage started with; a Quick refit adds later ones).
var _born: Dictionary = {}
var _rating_curve: Array[float] = []
var _next_sample: float = SAMPLE_INTERVAL
var _next_rating: float = RATING_INTERVAL
var _mess_sum: float = 0.0
var _broken_room_sum: float = 0.0
var _top_deck: int = 0


## Reads the layout once. Call after RoomSim.setup (SimWorld does).
func setup(w: SimWorld) -> void:
	decks = w.grid.hull.decks
	width = w.grid.hull.width
	_top_deck = decks - 1
	samples = 0
	duration = 0.0
	homeless = 0
	groups_total = 0
	groups_split = 0
	_vip_bad = []
	_traffic = _blank_grid()
	_unhappy = _blank_grid()
	_queue = _blank_grid()
	_rooms = []
	_util_sum = {}
	_queue_sum = {}
	_broken_s = {}
	_patience_outs = {}
	_born = {}
	_rating_curve = []
	_next_sample = SAMPLE_INTERVAL
	_next_rating = RATING_INTERVAL
	_mess_sum = 0.0
	_broken_room_sum = 0.0
	for r in w.room_sim.service_rooms:
		_rooms.append(r)
		_util_sum[r.uid] = 0.0
		_queue_sum[r.uid] = 0.0
		_broken_s[r.uid] = 0.0
		_patience_outs[r.uid] = 0


func _blank_grid() -> Array[PackedFloat32Array]:
	var g: Array[PackedFloat32Array] = []
	for d in decks:
		var row := PackedFloat32Array()
		row.resize(width)
		row.fill(0.0)
		g.append(row)
	return g


## Called every sim tick by SimWorld; samples when a whole second of sim time has passed.
func tick(w: SimWorld) -> void:
	while w.time >= _next_sample - 0.0001:
		_next_sample += SAMPLE_INTERVAL
		_sample(w)
	while w.time >= _next_rating - 0.0001:
		_next_rating += RATING_INTERVAL
		_rating_curve.append(w.director.rating())


## A room joined the ship mid-voyage (Quick refit at a port stop): its numbers are averaged over the time it has been there.
func on_room_added(_w: SimWorld, r: RoomRuntime) -> void:
	if not r.def.is_service_room() or _util_sum.has(r.uid):
		return
	_rooms.append(r)
	_util_sum[r.uid] = 0.0
	_queue_sum[r.uid] = 0.0
	_broken_s[r.uid] = 0.0
	_patience_outs[r.uid] = 0
	_born[r.uid] = samples


## GuestSim reports a guest giving up on `room_uid`'s queue.
func on_patience_out(room_uid: int) -> void:
	if _patience_outs.has(room_uid):
		_patience_outs[room_uid] = int(_patience_outs[room_uid]) + 1


func _sample(w: SimWorld) -> void:
	samples += 1
	for g in w.guests:
		var m: StringName = g.mode
		if m == Guest.GONE or m == Guest.EXCURSION:
			continue
		var d: int = clampi(int(round(g.deck_f)), 0, decks - 1)
		var c: int = clampi(int(g.x), 0, width - 1)
		if m != Guest.USE:
			_traffic[d][c] += SAMPLE_INTERVAL
		if g.satisfaction < UNHAPPY_BELOW:
			_unhappy[d][c] += SAMPLE_INTERVAL
		if m == Guest.QUEUE:
			_queue[d][c] += SAMPLE_INTERVAL
	var broken_rooms: int = 0
	for r in _rooms:
		_util_sum[r.uid] = float(_util_sum[r.uid]) + float(r.users.size()) / float(maxi(r.capacity(), 1))
		_queue_sum[r.uid] = float(_queue_sum[r.uid]) + float(r.queue.size())
		if r.broken:
			_broken_s[r.uid] = float(_broken_s[r.uid]) + SAMPLE_INTERVAL
			broken_rooms += 1
	_mess_sum += float(w.messes.size())
	_broken_room_sum += float(broken_rooms)


## Closes the books at the end of a voyage (LevelDirector.end_voyage): final rating point, duration, homeless count.
func finish(w: SimWorld) -> void:
	duration = w.time
	_rating_curve.append(w.director.rating())
	homeless = 0
	for g in w.guests:
		if g.cabin_uid < 0 and not g.excursion:
			homeless += 1
	groups_total = w.groups.size()
	groups_split = 0
	for grp in w.groups:
		if grp.split:
			groups_split += 1
	_vip_bad = []
	for v in w.vip_sim.members:
		if v.vip_grade == VipSim.BAD:
			_vip_bad.append({"kind": v.vip_kind, "detail": VipSim.detail(v)})


# ---------------------------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------------------------
## Tag for one room's numbers (see the class docs for the rules). `def` decides whether idle applies.
static func tag_for(def: RoomDef, util: float, avg_queue: float, broken_frac: float, patience_outs: int, uses: int) -> StringName:
	if avg_queue >= OVERLOADED_QUEUE or patience_outs >= OVERLOADED_PATIENCE_OUTS:
		return TAG_OVERLOADED
	if broken_frac >= UNRELIABLE_FRAC:
		return TAG_UNRELIABLE
	if util < IDLE_UTIL and uses < IDLE_USES and _idle_applies(def):
		return TAG_IDLE
	return TAG_OK


static func _idle_applies(def: RoomDef) -> bool:
	if def.id == &"cabin" or def.id == &"crew_quarters":
		return false
	return not def.is_transport() and not def.is_utility()


static func tag_text(tag: StringName) -> String:
	match tag:
		TAG_OVERLOADED: return "Overloaded"
		TAG_UNRELIABLE: return "Unreliable"
		TAG_IDLE: return "Idle"
	return "OK"


## "deck 3" / "the top deck" for a 0-based deck index.
func deck_label(deck: int) -> String:
	if deck >= _top_deck and decks > 1:
		return "the top deck"
	return "deck %d" % (deck + 1)


## The per-room numbers so far (the `rooms` rows of `report()`), for anybody who wants to look mid-voyage (the AutoPlayer's refit).
func live_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for r in _rooms:
		# a room built at a port stop is averaged over the time it was aboard (and is not called idle before it had a fair chance)
		var age: int = samples - int(_born.get(r.uid, 0))
		var n: float = float(maxi(age, 1))
		var util: float = float(_util_sum[r.uid]) / n
		var avg_q: float = float(_queue_sum[r.uid]) / n
		var broken_frac: float = float(_broken_s[r.uid]) / n
		var outs: int = int(_patience_outs[r.uid])
		var tag: StringName = tag_for(r.def, util, avg_q, broken_frac, outs, r.uses)
		if tag == TAG_IDLE and _born.has(r.uid) and age < MIN_IDLE_SAMPLES:
			tag = TAG_OK
		rows.append({
			"uid": r.uid, "id": r.def.id, "name": r.def.display_name, "deck": r.deck, "x": r.x,
			"util": util, "avg_queue": avg_q, "broken_frac": broken_frac,
			"patience_outs": outs, "uses": r.uses, "tier": r.tier, "added_at": int(_born.get(r.uid, 0)),
			"tag": tag,
		})
	return rows


func report() -> Dictionary:
	var rows: Array[Dictionary] = live_rows()
	var curve: Array[float] = _rating_curve.duplicate()
	return {
		"rooms": rows,
		"tips": _tips(rows),
		"rating_curve": curve,
		"grids": {"traffic": _copy_grid(_traffic), "unhappy": _copy_grid(_unhappy), "queue": _copy_grid(_queue)},
		"decks": decks, "width": width, "samples": samples, "duration": duration, "homeless": homeless,
		"groups": groups_total, "groups_split": groups_split,
	}


static func _copy_grid(g: Array[PackedFloat32Array]) -> Array:
	var out: Array = []
	for row in g:
		out.append(row.duplicate())
	return out


# ---------------------------------------------------------------------------------------------
# Tips: short, actionable, rule based. Each candidate has a priority; the best MAX_TIPS survive.
# ---------------------------------------------------------------------------------------------
func _tips(rows: Array[Dictionary]) -> Array[String]:
	var cands: Array[Dictionary] = []
	var worst_over: Dictionary = {}
	var worst_broken: Dictionary = {}
	var idle_rows: Array[Dictionary] = []
	for row in rows:
		match row["tag"]:
			TAG_OVERLOADED:
				if worst_over.is_empty() or _over_score(row) > _over_score(worst_over):
					worst_over = row
			TAG_UNRELIABLE:
				if worst_broken.is_empty() or float(row["broken_frac"]) > float(worst_broken["broken_frac"]):
					worst_broken = row
			TAG_IDLE:
				idle_rows.append(row)
	if not _vip_bad.is_empty():
		var vb: Dictionary = _vip_bad[0]
		var vtext: String = ""
		match vb["kind"]:
			VipSim.CRITIC:
				vtext = "The food critic left unimpressed: keep the food queue short and the door free of spills."
			VipSim.CELEBRITY:
				vtext = "The celebrity got fed up: they lose patience fast, so keep fun rooms free of queues."
			_:
				vtext = "The inspector noticed %s: clean spills and fix breakdowns before he strolls by." % String(vb["detail"]).trim_suffix(" noticed")
		cands.append({"p": 120.0, "text": vtext})
	if groups_split > 0:
		cands.append({"p": 75.0 + float(groups_split), "text": "%d group%s split up with no shared cabin. Build bigger cabins (or upgrade them) so families stay together." % [groups_split, "" if groups_split == 1 else "s"]})
	if not worst_over.is_empty():
		var q: float = float(worst_over["avg_queue"])
		var outs: int = int(worst_over["patience_outs"])
		var why: String = "the queue averaged %.1f guests" % q if q >= OVERLOADED_QUEUE else "%d guest%s gave up waiting" % [outs, "" if outs == 1 else "s"]
		cands.append({"p": 100.0 + _over_score(worst_over), "text": "%s: %s. Add another or upgrade it to serve more at once." % [_name_of(worst_over, false), why]})
	if not worst_broken.is_empty():
		var pct: int = int(round(float(worst_broken["broken_frac"]) * 100.0))
		cands.append({"p": 80.0 + float(pct) * 0.2, "text": "%s was broken %d%% of the voyage. Keep a mechanic close or upgrade it for sturdier parts." % [_name_of(worst_broken, true), pct]})
	if homeless > 0:
		cands.append({"p": 70.0 + float(homeless), "text": "%d guest%s had no bed. Build more cabins before the next wave boards." % [homeless, "" if homeless == 1 else "s"]})
	var sad: Dictionary = _unhappiest_deck()
	if not sad.is_empty():
		cands.append({"p": 60.0 + float(sad["share"]) * 20.0, "text": "Most unhappy guests were on %s. Put food, fun or a restroom within reach there." % deck_label(int(sad["deck"]))})
	var probs: float = (_mess_sum + _broken_room_sum) / float(maxi(samples, 1))
	if probs >= 1.5:
		var role: String = "janitor" if _mess_sum >= _broken_room_sum else "mechanic"
		cands.append({"p": 50.0 + probs, "text": "About %.0f problems were open at any moment. Hire another %s or step in faster." % [probs, role]})
	if not idle_rows.is_empty():
		idle_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["uses"]) < int(b["uses"]))
		var idle: Dictionary = idle_rows[0]
		cands.append({"p": 40.0, "text": "%s hardly got used (%d visit%s). Swap it for something your manifest likes." % [_name_of(idle, true), int(idle["uses"]), "" if int(idle["uses"]) == 1 else "s"]})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["p"]) > float(b["p"]))
	var out: Array[String] = []
	for c in cands:
		if out.size() >= MAX_TIPS:
			break
		out.append(String(c["text"]))
	return out


static func _over_score(row: Dictionary) -> float:
	return float(row["avg_queue"]) + 0.5 * float(row["patience_outs"])


## "The Buffet" / "Buffet" subject; with two of a kind the deck helps tell them apart.
func _name_of(row: Dictionary, article: bool) -> String:
	var same: int = 0
	for r in _rooms:
		if r.def.id == row["id"]:
			same += 1
	var lead: String = "The " if article else ""
	if same > 1:
		return "%s%s on %s" % [lead, String(row["name"]), deck_label(int(row["deck"]))]
	return "%s%s" % [lead, String(row["name"])]


## {deck, share} of the deck with the most unhappy guest-seconds, or {} when nobody was unhappy for long.
func _unhappiest_deck() -> Dictionary:
	var per_deck: Array[float] = []
	var total: float = 0.0
	for d in decks:
		var s: float = 0.0
		for v in _unhappy[d]:
			s += v
		per_deck.append(s)
		total += s
	if total < 20.0:
		return {}
	var best: int = 0
	for d in decks:
		if per_deck[d] > per_deck[best]:
			best = d
	var share: float = per_deck[best] / total
	if share < 0.34:
		return {}
	return {"deck": best, "share": share}
