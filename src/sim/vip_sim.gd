class_name VipSim
extends RefCounted
## VIP guests (docs/SPEC.md §13.5): boarding, the three review rules, verdict grades and their money.
##
## A VIP is an ordinary Guest with `vip_kind` set; this class holds everything that makes them special and keeps the rest of
## the sim free of VIP rules (GuestSim only calls the hooks below). Pure RefCounted: no nodes, no rng of its own.
##   critic     boards hungry; every food use scores by waiting time and a clean door; verdict after two meals.
##   celebrity  impatient and fun-seeking, lifts the appeal of the rooms they use; judged on mean satisfaction over a
##              90 s review window.
##   inspector  strolls every deck end to end (Guest.INSPECT), counting spills and broken rooms; judged on that count.
## A VIP who storms off gives a `bad` verdict on the way out. Signals live on SimWorld: vip_boarded(guest_id, kind) and
## vip_verdict(guest_id, kind, grade), each fired once per VIP.

const CRITIC: StringName = &"critic"
const CELEBRITY: StringName = &"celebrity"
const INSPECTOR: StringName = &"inspector"
const KINDS: Array[StringName] = [CRITIC, CELEBRITY, INSPECTOR]

const GREAT: StringName = &"great"
const OK: StringName = &"ok"
const BAD: StringName = &"bad"

## Every VIP that boarded, in boarding order.
var members: Array[Guest] = []


# ---------------------------------------------------------------------------------------------
# Rules as pure functions (tests and UI use them directly)
# ---------------------------------------------------------------------------------------------
static func is_kind(kind: StringName) -> bool:
	return KINDS.has(kind)


static func kind_label(kind: StringName) -> String:
	match kind:
		CRITIC: return "Food critic"
		CELEBRITY: return "Celebrity"
		INSPECTOR: return "Inspector"
	return String(kind).capitalize()


static func grade_label(grade: StringName) -> String:
	match grade:
		GREAT: return "Great"
		OK: return "Fine"
		BAD: return "Bad"
	return "Pending"


## Points one meal earns the critic: quick service at a clean door scores best; the restaurant counts 1.5x.
static func critic_points(wait: float, clean: bool, restaurant: bool) -> float:
	var pts: float = 0.0
	if wait <= SimConst.CRITIC_FAST_WAIT and clean:
		pts = SimConst.CRITIC_POINTS_FAST
	elif wait <= SimConst.CRITIC_OK_WAIT:
		pts = SimConst.CRITIC_POINTS_OK
	return pts * (SimConst.CRITIC_RESTAURANT_MULT if restaurant else 1.0)


static func critic_grade(score: float) -> StringName:
	if score >= SimConst.CRITIC_GREAT:
		return GREAT
	if score >= SimConst.CRITIC_OK:
		return OK
	return BAD


static func celebrity_grade(mean_satisfaction: float) -> StringName:
	if mean_satisfaction >= SimConst.CELEB_GREAT:
		return GREAT
	if mean_satisfaction >= SimConst.CELEB_OK:
		return OK
	return BAD


static func inspector_grade(issues: int) -> StringName:
	if issues <= SimConst.INSPECTOR_GREAT:
		return GREAT
	if issues <= SimConst.INSPECTOR_OK:
		return OK
	return BAD


## Money a verdict pays (negative = a fine).
static func pay_for(grade: StringName) -> int:
	match grade:
		GREAT: return SimConst.VIP_GREAT_PAY
		BAD: return -SimConst.VIP_BAD_COST
	return 0


# ---------------------------------------------------------------------------------------------
# Boarding
# ---------------------------------------------------------------------------------------------
## Boards a VIP of `kind` at the gangway (ticket paid like everybody else) and announces it.
func board(w: SimWorld, kind: StringName) -> Guest:
	var g: Guest = w.guest_sim.spawn_guest(w)
	g.vip_kind = kind
	match kind:
		CRITIC:
			g.nv[SimConst.N_HUNGER] = SimConst.CRITIC_HUNGER
		CELEBRITY:
			g.nv[SimConst.N_FUN] = SimConst.CELEB_START_FUN
			g.decay[SimConst.N_FUN] *= SimConst.CELEB_FUN_DECAY_MULT
	members.append(g)
	w.metrics["vips"] += 1
	w.vip_boarded.emit(g.id, kind)
	return g


# ---------------------------------------------------------------------------------------------
# Per tick: celebrity window, inspector scanning
# ---------------------------------------------------------------------------------------------
func tick(w: SimWorld, dt: float) -> void:
	for g in members:
		if g.vip_grade != &"":
			continue
		match g.vip_kind:
			CELEBRITY:
				g.vip_scan_t += dt
				if g.vip_scan_t >= 0.5:
					g.vip_scan_t -= 0.5
					g.vip_score += g.satisfaction
					g.vip_n += 1
				if w.time - g.boarded_at >= SimConst.CELEB_REVIEW_WINDOW:
					_grade(w, g, celebrity_grade(_celeb_mean(g)))
			INSPECTOR:
				if g.mode == Guest.INSPECT and not g.vertical_busy():
					g.vip_scan_t += dt
					if g.vip_scan_t >= SimConst.INSPECT_SCAN:
						g.vip_scan_t = 0.0
						_scan(w, g)


func _celeb_mean(g: Guest) -> float:
	return g.vip_score / float(g.vip_n) if g.vip_n > 0 else g.satisfaction


## The inspector notes every spill within INSPECT_RADIUS cells and every broken room he walks past (once each).
func _scan(w: SimWorld, g: Guest) -> void:
	for m in w.problems.deck_messes.get(g.deck, []):
		if absf(m.x - g.x) <= SimConst.INSPECT_RADIUS and not g.vip_seen.has(m.id):
			g.vip_seen[m.id] = true
			_noticed(w, g)
	for r in w.room_sim.service_rooms:
		if r.broken and r.deck == g.deck and g.x >= float(r.x) - 1.0 and g.x <= float(r.x + r.width) + 1.0:
			var key: int = -(r.uid * 1000 + r.broken_count)
			if not g.vip_seen.has(key):
				g.vip_seen[key] = true
				_noticed(w, g)


func _noticed(w: SimWorld, g: Guest) -> void:
	g.vip_score += 1.0
	w.metrics["inspector_issues"] += 1


# ---------------------------------------------------------------------------------------------
# Inspector route: every deck, end to end
# ---------------------------------------------------------------------------------------------
## Called once the inspector has finished boarding: plans the legs and sets off.
func inspect_begin(w: SimWorld, g: Guest) -> void:
	var hull: HullDef = w.grid.hull
	var order: Array[int] = []
	var gw: int = hull.gangway_deck
	for d in range(gw, hull.decks):
		order.append(d)
	for d in range(gw - 1, -1, -1):
		order.append(d)
	g.inspect_legs = []
	var right: float = float(hull.width) - 0.5
	for i in order.size():
		var first: float = 0.5 if i % 2 == 0 else right
		var second: float = right if i % 2 == 0 else 0.5
		g.inspect_legs.append(Vector2(float(order[i]), first))
		g.inspect_legs.append(Vector2(float(order[i]), second))
	g.inspect_i = 0
	g.mode = Guest.INSPECT
	g.state = Guest.INSPECT
	g.eval_timer = 1.0e6
	inspect_next(w, g)


## Heads for the next leg (skipping decks that cannot be reached); wraps up the inspection after the last one.
func inspect_next(w: SimWorld, g: Guest) -> void:
	while g.inspect_i < g.inspect_legs.size():
		var leg: Vector2 = g.inspect_legs[g.inspect_i]
		g.clear_route()
		if g.plan_route(w.grid, int(leg.x), leg.y):
			return
		# unreachable deck: skip both of its legs
		g.inspect_i += 2 - (g.inspect_i % 2)
	g.clear_route()
	g.mode = Guest.WANDER
	g.state = Guest.WANDER
	g.eval_timer = 0.5
	g.wander_pause = 0.5
	if g.vip_grade == &"":
		_grade(w, g, inspector_grade(int(g.vip_score)))


## The inspector reached the end of his current leg.
func inspect_arrived(w: SimWorld, g: Guest) -> void:
	if g.inspect_i < g.inspect_legs.size() and g.inspect_i % 2 == 1:
		g.inspected_decks[int(g.inspect_legs[g.inspect_i].x)] = true
	g.inspect_i += 1
	_scan(w, g)
	inspect_next(w, g)


# ---------------------------------------------------------------------------------------------
# Critic hooks (called by GuestSim)
# ---------------------------------------------------------------------------------------------
## True when a spill lies within CRITIC_MESS_RADIUS cells of the room's door.
func mess_at_door(w: SimWorld, r: RoomRuntime) -> bool:
	for m in w.problems.deck_messes.get(r.deck, []):
		if absf(m.x - r.door_x) <= SimConst.CRITIC_MESS_RADIUS:
			return true
	return false


## The critic reaches a food room (queue or straight in): resets and checks the door.
func critic_arrived(w: SimWorld, g: Guest, r: RoomRuntime) -> void:
	if g.vip_kind == CRITIC and r.def.category == &"food":
		g.saw_mess = mess_at_door(w, r)


## The critic's meal is over: score it; the second meal closes the review.
func critic_meal(w: SimWorld, g: Guest, r: RoomRuntime) -> void:
	if g.vip_kind != CRITIC or g.vip_grade != &"" or r.def.category != &"food":
		return
	g.vip_score += critic_points(g.use_wait, not g.saw_mess, r.def.id == &"restaurant")
	g.vip_n += 1
	if g.vip_n >= SimConst.CRITIC_MEALS:
		_grade(w, g, critic_grade(g.vip_score))


# ---------------------------------------------------------------------------------------------
# Verdicts
# ---------------------------------------------------------------------------------------------
## A VIP leaves the ship before the review is over (storming off): that is a bad review.
func on_leave(w: SimWorld, g: Guest) -> void:
	if g.vip_kind != &"" and g.vip_grade == &"":
		_grade(w, g, BAD)


## End of the voyage: every unfinished review is judged on what the VIP has seen so far (a critic who never ate: bad).
func finish(w: SimWorld) -> void:
	for g in members:
		if g.vip_grade != &"":
			continue
		match g.vip_kind:
			CRITIC:
				_grade(w, g, critic_grade(g.vip_score) if g.vip_n > 0 else BAD)
			CELEBRITY:
				_grade(w, g, celebrity_grade(_celeb_mean(g)))
			_:
				_grade(w, g, inspector_grade(int(g.vip_score)))


func _grade(w: SimWorld, g: Guest, grade: StringName) -> void:
	if g.vip_grade != &"":
		return
	g.vip_grade = grade
	var pay: int = pay_for(grade)
	g.vip_pay = pay
	if pay > 0:
		w.economy_earn(&"vip_bonus", pay, &"vip")
	elif pay < 0:
		w.economy_spend(&"vip_fines", -pay, &"vip")
	if grade == BAD:
		for o in w.guests:
			if o == g or not o.is_aboard():
				continue
			if int(round(o.deck_f)) == int(round(g.deck_f)) and absf(o.x - g.x) <= SimConst.VIP_BAD_RADIUS:
				o.satisfaction = maxf(o.satisfaction - SimConst.VIP_BAD_SAT, 0.0)
	w.metrics["vip_" + String(grade)] += 1
	w.vip_verdict.emit(g.id, g.vip_kind, grade)


# ---------------------------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------------------------
## One-line description of how the review went / stands, e.g. "2 meals, 80 points" (results panel, tooltip).
static func detail(g: Guest) -> String:
	match g.vip_kind:
		CRITIC:
			return "%d of %d meals reviewed, %d points" % [g.vip_n, SimConst.CRITIC_MEALS, int(g.vip_score)]
		CELEBRITY:
			var mean: float = g.vip_score / float(g.vip_n) if g.vip_n > 0 else g.satisfaction
			return "mood averaged %d%%" % int(round(mean))
		INSPECTOR:
			var n: int = int(g.vip_score)
			return "%d problem%s noticed" % [n, "" if n == 1 else "s"]
	return ""


## Live review meter for the guest tooltip: {value 0..1 (how well it is going), caption, detail}.
func meter(w: SimWorld, g: Guest) -> Dictionary:
	var value: float = 0.5
	var caption: String = ""
	match g.vip_kind:
		CRITIC:
			value = clampf(g.vip_score / SimConst.CRITIC_GREAT, 0.0, 1.0)
			caption = "%d/%d meals" % [g.vip_n, SimConst.CRITIC_MEALS]
		CELEBRITY:
			var mean: float = _celeb_mean(g)
			value = clampf(mean / 100.0, 0.0, 1.0)
			var left: int = int(ceil(maxf(SimConst.CELEB_REVIEW_WINDOW - (w.time - g.boarded_at), 0.0)))
			caption = "%ds left" % left
		INSPECTOR:
			var n: int = int(g.vip_score)
			value = clampf(1.0 - float(n) / float(SimConst.INSPECTOR_OK + 1), 0.0, 1.0)
			caption = "%d spotted" % n
	if g.vip_grade != &"":
		value = {GREAT: 1.0, OK: 0.6, BAD: 0.15}.get(g.vip_grade, value)
		caption = grade_label(g.vip_grade)
	return {"value": value, "caption": caption, "detail": detail(g)}


## Review results in boarding order: [{id, kind, grade, pay, detail}] (the `vips` entry of the result dictionary).
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in members:
		out.append({"id": g.id, "kind": g.vip_kind, "grade": g.vip_grade, "pay": g.vip_pay, "detail": detail(g)})
	return out


func pending() -> int:
	var n: int = 0
	for g in members:
		if g.vip_grade == &"":
			n += 1
	return n
