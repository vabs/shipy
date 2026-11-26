class_name VoyageRenderer
extends Node
## Draws a running SimWorld into a ShipView: guests (interpolated), crew, messes, ghosts, in-room users,
## mood bubbles, problem icons, queue counters, selection / path overlays. Also answers picking queries.
##
## Layering (ShipView layers):
##   rooms_back -> [entities: users inside rooms] -> rooms_front -> [overlay: corridor walkers, crew, messes,
##   ghosts, then bubbles / icons / rings] -> [fx: VoyageFx]
##
## Usage: attach(view, world, controller) once; call refresh_rooms() when the room set changes (it only
## changes once per voyage); call update() every frame after the controller advanced the sim.
## Interaction state (hover/selection) is written by VoyageInput; the renderer only reads it.

const U := preload("res://src/render/art/art_util.gd")

const LANES: int = 3
const MAX_BUBBLES: int = 14
const MAX_SOFT_BUBBLES: int = 3
## Problem badges / bubbles / counters are counter-scaled against the camera zoom so they stay readable but
## never swallow the rooms when zoomed in: k = (K_REF_ZOOM / zoom) ^ K_POW, clamped.
const K_REF_ZOOM: float = 1.2
const K_POW: float = 0.7
const K_MIN: float = 0.4
const K_MAX: float = 1.35

# guest categories for the frame
const C_HIDDEN: int = 0
const C_CORRIDOR: int = 1
const C_ROOM: int = 2
const C_RIDER: int = 3

var world: SimWorld = null
var view: ShipView = null
var ctl: VoyageController = null
var fx: VoyageFx = null

var anim_t: float = 0.0
var colorblind: bool = false
## Camera zoom (screen px per ship px) and the badge counter-scale derived from it (updated every frame).
var screen_zoom: float = 1.0
var zoom_k: float = 1.0

# ---- interaction state (written by VoyageInput / HUD) -----------------------------------------
var hover_kind: StringName = &""
var hover_id: int = -1
var pinned_guest_id: int = -1
var selected_staff_id: int = -1
var hold_room_uid: int = -1
## Ship-local polyline of the route preview for the selected crew member.
var path_points: PackedVector2Array = PackedVector2Array()
## &"mess" | &"repair" | &"sick" | &"ghost" | &"perform" | &"station" | &"" -> what glows as a valid target for the
## selected crew member (their own job kind or aura order).
var target_kind: StringName = &""
## The selected crew member can also be sent to rest: crew quarters with a free bunk glow too.
var rest_targets: bool = false

# ---- per-frame prepared data --------------------------------------------------------------------
var g_feet: PackedVector2Array = PackedVector2Array()
var g_cat: PackedByteArray = PackedByteArray()
var s_feet: PackedVector2Array = PackedVector2Array()
var gh_pos: PackedVector2Array = PackedVector2Array()
var _lanes: Array[PackedInt32Array] = []
var _riders: PackedInt32Array = PackedInt32Array()
var _room_users: PackedInt32Array = PackedInt32Array()
## Indices into world.staff of crew asleep in a crew quarters bunk (drawn inside the room) and their bunk feet.
var _sleepers: PackedInt32Array = PackedInt32Array()
var _sleeper_feet: PackedVector2Array = PackedVector2Array()
var _rects: Dictionary = {}
var _car_f: Dictionary = {}
var _car_lead: Dictionary = {}
var _pods: Dictionary = {}
var _bubbles: Array[Dictionary] = []
var _bub_state: Dictionary = {}
var _body_cols: Dictionary = {}
var _seen_t: Dictionary = {}
var _go: Dictionary = {}
var _so: Dictionary = {}
var _last_room_state: Dictionary = {}
var _closed_t: Dictionary = {}

var _n_occ: _Occupants
var _n_corr: _Corridor
var _n_bub: _Bubbles


class _Occupants extends Node2D:
	var r: VoyageRenderer
	func _draw() -> void:
		r._draw_occupants(self)


class _Corridor extends Node2D:
	var r: VoyageRenderer
	func _draw() -> void:
		r._draw_corridor(self)


class _Bubbles extends Node2D:
	var r: VoyageRenderer
	func _draw() -> void:
		r._draw_bubbles(self)


func attach(p_view: ShipView, p_world: SimWorld, p_ctl: VoyageController) -> void:
	view = p_view
	world = p_world
	ctl = p_ctl
	for i in LANES:
		_lanes.append(PackedInt32Array())
	_n_occ = _Occupants.new()
	_n_occ.r = self
	view.get_layer(&"entities").add_child(_n_occ)
	_n_corr = _Corridor.new()
	_n_corr.r = self
	view.get_layer(&"overlay").add_child(_n_corr)
	_n_bub = _Bubbles.new()
	_n_bub.r = self
	view.get_layer(&"overlay").add_child(_n_bub)
	fx = VoyageFx.new()
	fx.r = self
	view.get_layer(&"fx").add_child(fx)
	refresh_rooms()


func detach() -> void:
	for n in [_n_occ, _n_corr, _n_bub, fx]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()


func refresh_rooms() -> void:
	_rects.clear()
	for r in world.rooms:
		_rects[r.uid] = view.room_rect(r.uid)


# =================================================================================================
# per-frame update
# =================================================================================================
func update(_delta: float) -> void:
	if world == null:
		return
	anim_t = ctl.anim_clock
	colorblind = Settings.colorblind
	_update_zoom_k()
	_prepare()
	_note_inspectors()
	_push_room_states(_delta)
	_n_occ.queue_redraw()
	_n_corr.queue_redraw()
	_n_bub.queue_redraw()
	fx.queue_redraw()


## "Noted!" pops up whenever the inspector writes a problem on his clipboard.
var _inspector_seen: Dictionary = {}


func _note_inspectors() -> void:
	if world.vip_sim.members.is_empty():
		return
	for v in world.vip_sim.members:
		if v.vip_kind != VipSim.INSPECTOR:
			continue
		var n: int = int(v.vip_score)
		var prev: int = int(_inspector_seen.get(v.id, 0))
		if n > prev:
			_inspector_seen[v.id] = n
			var p: Vector2 = local_pos_of(&"guest", v.id)
			if p != Vector2.INF and fx != null:
				fx.spawn(&"text", p + Vector2(0, -30), 1.2, {"amount": 0, "text": "Noted!", "color": Palette.CORAL})


func _update_zoom_k() -> void:
	var z: float = 1.0
	if view != null and view.is_inside_tree():
		z = view.get_viewport().get_canvas_transform().get_scale().x
	screen_zoom = z
	zoom_k = clampf(pow(K_REF_ZOOM / maxf(z, 0.05), K_POW), K_MIN, K_MAX)


static func _ix(prev: float, cur: float, a: float) -> float:
	if absf(cur - prev) > 3.0:
		return cur
	return lerpf(prev, cur, a)


func body_color(g: Guest) -> Color:
	var id: StringName = g.archetype.id
	if not _body_cols.has(id):
		_body_cols[id] = Palette.archetype_color(id)
	return _body_cols[id]


func _first_seen(key: String) -> float:
	if not _seen_t.has(key):
		_seen_t[key] = anim_t
	return anim_t - float(_seen_t[key])


func _prepare() -> void:
	var a: float = ctl.alpha
	var n: int = world.guests.size()
	g_feet.resize(n)
	g_cat.resize(n)
	for l in LANES:
		_lanes[l].resize(0)
	_riders.resize(0)
	_room_users.resize(0)
	_sleepers.resize(0)
	_sleeper_feet.resize(0)
	_pods.clear()
	for i in n:
		var g: Guest = world.guests[i]
		var st: StringName = g.state
		if st == Guest.GONE:
			g_cat[i] = C_HIDDEN
			continue
		if st == Guest.USE and g.slot >= 0:
			g_cat[i] = C_ROOM
			var rr: RoomRuntime = world.room_by_uid(g.target_uid)
			if rr != null and _rects.has(rr.uid):
				g_feet[i] = RoomArt.slot_position(rr.def.id, _rects[rr.uid], g.slot, rr.cap)
				_room_users.append(i)
			else:
				g_cat[i] = C_HIDDEN
			continue
		var x: float = _ix(g.prev_x, g.x, a)
		var df: float = _ix(g.prev_deck_f, g.deck_f, a)
		var lane: int = g.id % LANES
		if st == Guest.QUEUE:
			lane = 0
		var feet: Vector2 = SimConst.to_px(x, df)
		if st == &"elevator_ride":
			g_cat[i] = C_RIDER
			feet += Vector2(float((g.id % 3) - 1) * 6.0, -5.0)
			g_feet[i] = feet
			_riders.append(i)
			continue
		if st == &"elevator_wait":
			feet.x += float((g.id % 5) - 2) * 3.5
		feet.y -= float(lane) * 2.3
		g_feet[i] = feet
		g_cat[i] = C_CORRIDOR
		_lanes[lane].append(i)
	# crew
	var ns: int = world.staff.size()
	s_feet.resize(ns)
	for i in ns:
		var s: StaffMember = world.staff[i]
		s_feet[i] = SimConst.to_px(_ix(s.prev_x, s.x, a), _ix(s.prev_deck_f, s.deck_f, a))
		if s.state == &"perform":
			s_feet[i].y += 3.0   # the entertainer works the front of the queue
		elif s.state == &"rest":
			var q: RoomRuntime = world.room_by_uid(s.rest_uid)
			if q != null and _rects.has(q.uid):
				var slot: int = maxi(q.slot_of(s.id), 0)
				var fp: Vector2 = RoomArt.slot_position(&"crew_quarters", _rects[q.uid], slot, q.cap)
				s_feet[i] = fp
				_sleepers.append(i)
				_sleeper_feet.append(fp)
	var ng: int = world.ghosts.size()
	gh_pos.resize(ng)
	for i in ng:
		var gh: Ghost = world.ghosts[i]
		gh_pos[i] = SimConst.to_px(_ix(gh.prev_x, gh.x, a), _ix(gh.prev_deck_f, gh.deck_f, a)) + Vector2(0, -4)
		if fx != null:
			fx.note_ghost(gh.id, gh_pos[i])
	_prepare_bubbles()


func _prepare_bubbles() -> void:
	_bubbles.clear()
	var cand: Array[Dictionary] = []
	var n: int = world.guests.size()
	var now: float = world.time
	for i in n:
		var cat: int = g_cat[i]
		if cat == C_HIDDEN:
			continue
		var g: Guest = world.guests[i]
		var icon: StringName = &""
		var prio: int = 0
		var soft: bool = false
		var alpha: float = 1.0
		var problem: bool = false
		if g.state == Guest.STORM_OFF:
			icon = &"angry"
			prio = 95
			problem = true
		elif g.sick:
			icon = &"sick"
			prio = 90
			problem = true
		elif g.seasick:
			icon = &"seasick"   # storm: its own face, prominent but not a "needs you" ring (many guests may be queasy at once)
			prio = 80
		elif cat == C_ROOM:
			continue
		else:
			match g.mood:
				&"angry":
					icon = &"angry"
					prio = 100
					problem = true
				&"need_rest", &"need_hunger", &"need_fun", &"need_hygiene":
					icon = g.mood
					prio = 70
				&"unhappy":
					if g.bubble_timer > 0.0:
						icon = &"frown"
						prio = 50
						soft = true
				&"happy":
					if g.bubble_timer > 0.0:
						icon = &"heart"
						prio = 20
						soft = true
			if soft:
				alpha = clampf(g.bubble_timer / 0.6, 0.0, 1.0)
		if icon == &"":
			_bub_state.erase(g.id)
			continue
		var bs: Dictionary = _bub_state.get(g.id, {})
		if bs.get("icon", &"") != icon:
			bs = {"icon": icon, "t0": anim_t}
			_bub_state[g.id] = bs
		# ambient bubbles (needs, hearts, frowns) are smaller / fainter than problems so "needs you" reads first
		var sc: float = 1.12 if problem else (0.7 if soft else (1.0 if icon == &"seasick" else 0.88))
		if not problem:
			alpha *= 0.78 if soft else 0.94
		cand.append({"idx": i, "icon": icon, "prio": prio, "alpha": alpha, "t": anim_t - float(bs["t0"]), "soft": soft,
				"problem": problem, "scale": sc})
	cand.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		if p["prio"] != q["prio"]:
			return int(p["prio"]) > int(q["prio"])
		return int(p["idx"]) < int(q["idx"]))
	var soft_n: int = 0
	for c in cand:
		if _bubbles.size() >= MAX_BUBBLES:
			break
		if c["soft"] and soft_n >= MAX_SOFT_BUBBLES:
			continue
		var p: Vector2 = g_feet[int(c["idx"])]
		var clash: bool = false
		for b in _bubbles:
			var bp: Vector2 = g_feet[int(b["idx"])]
			if absf(bp.x - p.x) < 26.0 and absf(bp.y - p.y) < 40.0:
				clash = true
				break
		if clash:
			continue
		if c["soft"]:
			soft_n += 1
		_bubbles.append(c)


func _push_room_states(delta: float) -> void:
	var a: float = ctl.alpha
	for r in world.rooms:
		var uid: int = r.uid
		var def: RoomDef = r.def
		if def.id == &"elevator":
			_update_car(r, delta)
			continue
		if def.is_transport() or def.is_utility():
			continue
		var st: Dictionary = LayoutBridge.room_state(r)
		st["busy_ratio"] = snappedf(float(st["busy_ratio"]), 0.05)
		st["repair_progress"] = snappedf(float(st["repair_progress"]), 0.02)
		st["highlight"] = 2 if uid == hold_room_uid else (1 if (hover_kind == &"room" and hover_id == uid) else 0)
		view.set_room_state(uid, st)


## The sim lets every rider travel on its own clock (no shared car), so the visual car follows the rider that
## has been riding longest; the other riders get a little glass pod so they never look like they float.
func _update_car(r: RoomRuntime, delta: float) -> void:
	var col: int = r.x
	var lead: int = -1
	var lead_t: float = -1.0
	for i in _riders:
		var g: Guest = world.guests[i]
		if int(g.x) == col:
			_pods[i] = true
			if g.travel_t > lead_t:
				lead_t = g.travel_t
				lead = i
	var cur: float = float(_car_f.get(r.uid, 0.0))
	if lead >= 0:
		_pods.erase(lead)
		_car_lead[r.uid] = lead
		cur = -(g_feet[lead].y + 5.0) / SimConst.DECK_H
	else:
		_car_lead.erase(r.uid)
		var target: float = cur
		var lowest: float = 99.0
		for g in world.guests:
			if g.state == &"elevator_wait" and int(g.x) == col:
				lowest = minf(lowest, g.deck_f)
		if lowest < 98.0:
			target = lowest
		cur = lerpf(cur, target, clampf(delta * 5.0, 0.0, 1.0))
	_car_f[r.uid] = cur
	view.set_room_state(r.uid, {"car_deck_f": snappedf(cur, 0.02), "busy_ratio": snappedf(float(r.busy_ratio), 0.1)})


# =================================================================================================
# drawing
# =================================================================================================
func _prop_of(g: Guest) -> StringName:
	match g.vip_kind:
		&"critic": return &"beret"
		&"celebrity": return &"sunglasses"
		&"inspector": return &"inspector_cap"
	return g.archetype.prop


func _setup_guest_opts(g: Guest, pose: StringName, facing: int, wp: float, hl: int) -> Dictionary:
	_go["prop"] = _prop_of(g)
	_go["body_color"] = body_color(g)
	_go["facing"] = facing
	_go["pose"] = pose
	_go["walk_phase"] = wp
	_go["sick"] = g.sick
	_go["seasick"] = g.seasick
	_go["body_scale"] = g.archetype.body_scale
	_go["vip"] = g.vip_kind
	if g.group_id >= 0:
		_go["group_color"] = Palette.group_color(g.group_id)
	else:
		_go.erase("group_color")
	_go["colorblind"] = colorblind
	_go["t"] = anim_t
	_go["highlight"] = hl
	_go["alpha"] = 1.0
	_go.erase("slip_t")
	_go.erase("scale")
	return _go


func _hl_for_guest(g: Guest) -> int:
	if g.id == pinned_guest_id:
		return 2
	if hover_kind == &"guest" and hover_id == g.id:
		return 1
	return 0


func _draw_occupants(ci: CanvasItem) -> void:
	for i in _room_users:
		var g: Guest = world.guests[i]
		var rr: RoomRuntime = world.room_by_uid(g.target_uid)
		if rr == null:
			continue
		var pose: StringName = RoomArt.slot_pose(rr.def.id)
		var rect: Rect2 = _rects[rr.uid]
		var face: int = RoomArt.slot_facing(rr.def.id, rect, g.slot, rr.cap)
		var wp: float = anim_t * 9.0 + float(g.slot)
		var o: Dictionary = _setup_guest_opts(g, pose, face, wp, _hl_for_guest(g))
		# little pop-in when a use starts
		var since: float = g.use_dur - g.use_timer
		var k: float = clampf(since / 0.22, 0.0, 1.0)
		o["alpha"] = k
		if k < 1.0:
			o["scale"] = 0.75 + 0.25 * U.ease_out_back(k)
		GuestArt.draw_guest(ci, g_feet[i], o)
	for k in _sleepers.size():
		var s: StaffMember = world.staff[_sleepers[k]]
		var q: RoomRuntime = world.room_by_uid(s.rest_uid)
		if q == null or not _rects.has(q.uid):
			continue
		var slot: int = maxi(q.slot_of(s.id), 0)
		var so: Dictionary = {"role": s.role, "pose": &"sleep", "t": anim_t, "scale": 1.0,
				"facing": RoomArt.slot_facing(&"crew_quarters", _rects[q.uid], slot, q.cap), "skip_zzz": true,
				"highlight": 2 if s.id == selected_staff_id else (1 if (hover_kind == &"staff" and hover_id == s.id) else 0)}
		GuestArt.draw_staff(ci, _sleeper_feet[k], so)


func _draw_guest_corridor(ci: CanvasItem, i: int) -> void:
	var g: Guest = world.guests[i]
	var st: StringName = g.state
	var moving: bool = absf(g.x - g.prev_x) > 0.0004 or absf(g.deck_f - g.prev_deck_f) > 0.0004
	var pose: StringName = &"stand"
	var wp: float = 0.0
	var feet: Vector2 = g_feet[i]
	match st:
		&"climb":
			pose = &"walk"
			wp = anim_t * 10.0 + float(g.id)
		&"storm_off":
			pose = &"storm"
			wp = feet.x * 0.083 + float(g.id)
		&"queue":
			pose = &"walk" if moving else &"queue"
			wp = feet.x * 0.083 + float(g.id)
		&"elevator_wait", &"boarding":
			pose = &"stand"
		_:
			pose = &"walk" if moving else &"stand"
			wp = feet.x * 0.083 + float(g.id)
	var o: Dictionary = _setup_guest_opts(g, pose, g.facing, wp, _hl_for_guest(g))
	if g.slip_timer > 0.0:
		o["pose"] = &"slip"
		o["slip_t"] = SimConst.SLIP_TIME - g.slip_timer
	if st == &"boarding":
		o["alpha"] = clampf((world.time - g.boarded_at) / 0.4, 0.0, 1.0)
	GuestArt.draw_guest(ci, feet, o)


## Storm: closed top-deck rooms get a dim veil, hazard tape across the doorway and a hanging "Closed" sign.
func _draw_closed_rooms(ci: CanvasItem) -> void:
	var any: bool = false
	for r in world.room_sim.service_rooms:
		if r.closed and _rects.has(r.uid):
			any = true
			if not _closed_t.has(r.uid):
				_closed_t[r.uid] = Time.get_ticks_msec() * 0.001   # (real time: the pop-in also plays while paused)
		elif _closed_t.has(r.uid):
			_closed_t.erase(r.uid)
	if not any:
		return
	for r in world.room_sim.service_rooms:
		if not r.closed or not _rects.has(r.uid):
			continue
		var rc: Rect2 = _rects[r.uid]
		var k: float = clampf((Time.get_ticks_msec() * 0.001 - float(_closed_t[r.uid])) / 0.5, 0.0, 1.0)
		var kk: float = U.ease_out_back(k)
		U.rr(ci, rc.grow(-1.0), 6.0, Color(0.1, 0.15, 0.3, 0.46 * k))
		# hazard tape
		var band := Rect2(rc.position.x + 2.0, rc.end.y - 38.0, rc.size.x - 4.0, 13.0)
		U.rect(ci, band, Color(Palette.NAVY_DARK.r, Palette.NAVY_DARK.g, Palette.NAVY_DARK.b, k))
		var x: float = band.position.x - band.size.y
		var h: float = band.size.y
		var flip: bool = false
		while x < band.end.x:
			var p0: float = clampf(x, band.position.x, band.end.x)
			var p1: float = clampf(x + 9.0, band.position.x, band.end.x)
			var p2: float = clampf(x + 9.0 + h, band.position.x, band.end.x)
			var p3: float = clampf(x + h, band.position.x, band.end.x)
			U.poly(ci, PackedVector2Array([Vector2(p0, band.end.y), Vector2(p1, band.end.y), Vector2(p2, band.position.y), Vector2(p3, band.position.y)]), Color(Palette.SUN.r, Palette.SUN.g, Palette.SUN.b, k))
			x += 18.0
			flip = not flip
		# posts at both ends
		for px in [band.position.x + 1.0, band.end.x - 1.0]:
			U.rr(ci, Rect2(px - 3.0, band.position.y - 6.0, 6.0, 26.0), 2.0, Color(Palette.NAVY.r, Palette.NAVY.g, Palette.NAVY.b, k))
		# the sign
		var sc: Vector2 = Vector2(rc.get_center().x, rc.position.y + 30.0 + (1.0 - kk) * -14.0)
		var sw: float = 70.0
		var sh: float = 22.0
		U.rr(ci, Rect2(sc.x - sw * 0.5, sc.y - sh * 0.5 + 2.0, sw, sh), 7.0, Color(0.05, 0.08, 0.16, 0.3 * k))
		U.rr(ci, Rect2(sc.x - sw * 0.5, sc.y - sh * 0.5, sw, sh), 7.0, Color(Palette.CREAM.r, Palette.CREAM.g, Palette.CREAM.b, k))
		U.rr_outline(ci, Rect2(sc.x - sw * 0.5, sc.y - sh * 0.5, sw, sh), 7.0, Color(Palette.CORAL.r, Palette.CORAL.g, Palette.CORAL.b, k), 2.0)
		IconArt.draw_icon(ci, &"storm", Vector2(sc.x - sw * 0.5 + 12.0, sc.y), 17.0, anim_t, colorblind)
		U.text(ci, "Closed", Vector2(sc.x - sw * 0.5 + 24.0, sc.y + 4.6), 13, Color(Palette.CORAL_DARK.r, Palette.CORAL_DARK.g, Palette.CORAL_DARK.b, k), HORIZONTAL_ALIGNMENT_LEFT, -1.0, U.font_bold())


func _draw_corridor(ci: CanvasItem) -> void:
	_draw_closed_rooms(ci)
	# messes lie on the floor (under everybody)
	for m in world.messes:
		ProblemArt.draw_mess(ci, SimConst.to_px(m.x, float(m.deck)), m.id % 4, minf(m.clean_progress, 1.0), anim_t, colorblind)
	for l in range(LANES - 1, -1, -1):
		for i in _lanes[l]:
			_draw_guest_corridor(ci, i)
	for i in _riders:
		if _pods.has(i):
			var fp: Vector2 = g_feet[i]
			U.rr(ci, Rect2(fp.x - 11.0, fp.y - 30.0, 22.0, 33.0), 9.0, Color(0.22, 0.5, 0.72, 0.45))
			U.rr(ci, Rect2(fp.x - 9.6, fp.y - 28.6, 19.2, 30.0), 8.0, Color(1.0, 0.95, 0.82, 0.55))
		_draw_guest_corridor(ci, i)
	# crew
	for i in mini(world.staff.size(), s_feet.size()):
		var s: StaffMember = world.staff[i]
		if s.state == &"rest":
			continue   # asleep inside the crew quarters: drawn with the room occupants
		var feet: Vector2 = s_feet[i]
		var moving: bool = absf(s.x - s.prev_x) > 0.0004 or absf(s.deck_f - s.prev_deck_f) > 0.0004
		var pose: StringName = &"stand"
		var wp: float = feet.x * 0.087
		match s.state:
			&"work":
				pose = &"work"
			&"perform":
				pose = &"perform"
			&"station":
				pose = &"cook"
			&"nap":
				pose = &"sleep"
			_:
				if moving or s.travel_mode == Walker.T_CLIMB:
					pose = &"walk"
					if s.travel_mode == Walker.T_CLIMB:
						wp = anim_t * 10.0
		_so["tired"] = s.is_tired() and s.state != &"nap"
		_so["role"] = s.role
		_so["pose"] = pose
		_so["facing"] = s.facing
		_so["walk_phase"] = wp
		_so["t"] = anim_t
		_so["highlight"] = 2 if s.id == selected_staff_id else (1 if (hover_kind == &"staff" and hover_id == s.id) else 0)
		GuestArt.draw_staff(ci, feet, _so)
	# ghosts
	for i in mini(world.ghosts.size(), gh_pos.size()):
		var gh: Ghost = world.ghosts[i]
		var wdt: float = float(world.grid.hull.width)
		var edge: float = clampf(minf(gh.x + 1.0, wdt + 1.0 - gh.x) / 2.0, 0.0, 1.0)
		var al: float = (0.62 + 0.2 * sin(anim_t * 2.1 + float(gh.id))) * minf(1.0, gh.age / 0.8) * edge
		if hover_kind == &"ghost" and hover_id == gh.id:
			al = minf(1.0, al + 0.3)
		ProblemArt.draw_ghost(ci, gh_pos[i], anim_t + gh.bob_phase, al, gh.dir, colorblind)


## Soft pulsing "needs you" ring: the ONE consistent treatment shared by every problem marker (spill badge,
## broken-room badge, sick / angry bubble, ghost, long queue). `r` is the radius of the thing being ringed.
func _ping(ci: CanvasItem, c: Vector2, r: float, phase: float, strength: float = 1.0, halo: bool = true) -> void:
	var col: Color = Palette.alert_color(colorblind)
	var k: float = clampf(zoom_k, 0.55, 1.2)
	var breathe: float = U.pulse(anim_t + phase, 1.1)
	if halo:
		U.circ(ci, c, r + (3.0 + 2.5 * breathe) * k, Color(col.r, col.g, col.b, (0.16 + 0.1 * breathe) * strength))
	var p: float = fposmod(anim_t * 0.8 + phase, 1.0)
	var rr: float = r + (3.0 + p * 10.0) * k
	_ring(ci, c, rr, Color(col.r, col.g, col.b, 0.75 * (1.0 - p) * strength), 2.2 * k + 0.4)


## Ship-local centre of a spill's badge. The badge bottom stays ~18 px above the floor and the badge shrinks
## towards the puddle when zoomed in, so it never swallows the room.
func mess_badge_center(floor_p: Vector2) -> Vector2:
	return floor_p + Vector2(0.0, -(18.0 + 12.0 * zoom_k))


## Full ring as a cached outline mesh (a rounded rect whose radius is its half size): smooth at any zoom and
## ~100x cheaper than draw_arc. Radius / width are quantized so the mesh cache stays tiny.
func _ring(ci: CanvasItem, c: Vector2, r: float, color: Color, w: float) -> void:
	var q: float = roundf(r * 2.0) * 0.5
	var bw: float = clampf(roundf(w * 2.0) * 0.5, 1.0, q)
	U.rr_outline(ci, Rect2(c - Vector2(q, q), Vector2(q, q) * 2.0), q, color, bw)


## Smooth arc via the engine (U.arc draws separate segments + joint discs, which shows as beads when the
## stroke is translucent or the camera is zoomed in).
func _arc(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, color: Color, w: float, n: int = 32) -> void:
	ci.draw_arc(c, r, a0, a1, n, U.col(color), w, true)


## Hovering / pinning a member of a couple or family: a soft ring under every member and a dashed heart link from the
## leader to each of them, all in the group's colour.
func _draw_group_links(ci: CanvasItem) -> void:
	var done: Dictionary = {}
	var ids: Array[int] = [pinned_guest_id]
	if hover_kind == &"guest":
		ids.append(hover_id)
	for gid in ids:
		if gid < 1:
			continue
		var g: Guest = world.guest_by_id(gid)
		if g == null or g.group_id < 1 or g.group_id > world.groups.size() or done.has(g.group_id):
			continue
		done[g.group_id] = true
		var col: Color = Palette.group_color(g.group_id)
		var pts: Array[Vector2] = []
		for mid in world.groups[g.group_id - 1].members:
			var i: int = mid - 1
			if i < 0 or i >= g_cat.size() or g_cat[i] == C_HIDDEN:
				continue
			var mg: Guest = world.guests[i]
			var sc: float = mg.archetype.body_scale
			var f: Vector2 = g_feet[i]
			U.ellipse(ci, f + Vector2(0, 0.5), 12.0 * sc, 3.8 * sc, Color(col.r, col.g, col.b, 0.28))
			U.dashed_ring(ci, f + Vector2(0, 0.5), 12.0 * sc, 3.8 * sc, col, 1.8, anim_t * 0.6, 10)
			pts.append(f + Vector2(0, -GuestArt.HEIGHT * sc * 0.62))
		for k in range(1, pts.size()):
			var a: Vector2 = pts[0]
			var b: Vector2 = pts[k]
			var ctrl: Vector2 = (a + b) * 0.5 + Vector2(0, -10.0 - a.distance_to(b) * 0.18)
			var curve := PackedVector2Array()
			for j in range(13):
				var u: float = float(j) / 12.0
				curve.append(a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u))
			_dashed_polyline(ci, curve, Color(col.r, col.g, col.b, 0.85), 2.0, 6.0, 4.0, anim_t * 14.0)
			var mid: Vector2 = curve[6] + Vector2(0, -1.5 + sin(anim_t * 3.0 + float(k)) * 1.4)
			GuestArt.draw_heart(ci, mid, 5.2 * clampf(zoom_k, 0.7, 1.2), col)


## Bubbles sit above the head: kids are shorter, VIPs carry a floating star that the bubble stacks over.
func _bubble_dy(g: Guest) -> float:
	var dy: float = -GuestArt.HEIGHT * g.archetype.body_scale - 5.0
	if g.vip_kind != &"":
		dy -= 13.0
	return dy


func _draw_bubbles(ci: CanvasItem) -> void:
	var kk: float = zoom_k
	_draw_group_links(ci)
	# --- valid-target glow for a selected crew member
	if selected_staff_id >= 0 and (target_kind != &"" or rest_targets):
		var pulse: float = U.pulse(anim_t, 1.4)
		var glow := Color(Palette.SUN.r, Palette.SUN.g, Palette.SUN.b, 0.95)
		match target_kind:
			&"mess":
				for m in world.messes:
					var p: Vector2 = SimConst.to_px(m.x, float(m.deck)) + Vector2(0, -4)
					U.dashed_ring(ci, p, 22.0 + pulse * 2.0, 9.0 + pulse, glow, 2.4, anim_t * 0.6, 12)
			&"sick":
				for i in mini(world.guests.size(), g_feet.size()):
					var sg: Guest = world.guests[i]
					if sg.is_ailing() and g_cat[i] != C_HIDDEN:
						U.dashed_ring(ci, g_feet[i] + Vector2(0, -2), 14.0 + pulse * 2.0, 6.0 + pulse, glow, 2.4, anim_t * 0.6, 10)
			&"ghost":
				for i in mini(world.ghosts.size(), gh_pos.size()):
					U.dashed_ring(ci, gh_pos[i] + Vector2(0, -16), 20.0 + pulse * 2.0, 24.0 + pulse * 2.0, glow, 2.4, anim_t * 0.6, 12)
			&"perform", &"station":
				for r in world.rooms:
					if not _rects.has(r.uid) or not r.def.is_service_room() or r.def.id == &"cabin":
						continue
					if target_kind == &"station" and r.def.category != &"food":
						continue
					var strong: bool = target_kind == &"station" or r.queue.size() >= SimConst.ENTERTAINER_MIN_QUEUE
					var rc2: Rect2 = _rects[r.uid]
					U.rr_outline(ci, rc2.grow(1.0 + pulse * 2.0), 5.0, Color(glow.r, glow.g, glow.b, (0.5 + 0.4 * pulse) if strong else 0.3), 3.0 if strong else 2.0)
			&"repair":
				for r in world.rooms:
					if r.broken and _rects.has(r.uid):
						var rc: Rect2 = _rects[r.uid]
						U.rr_outline(ci, rc.grow(1.0 + pulse * 2.0), 5.0, Color(glow.r, glow.g, glow.b, 0.5 + 0.4 * pulse), 3.0)
		if rest_targets:
			for q in world.room_sim.crew_rooms:
				if _rects.has(q.uid) and q.free_bunks() > 0:
					U.rr_outline(ci, (_rects[q.uid] as Rect2).grow(1.0 + pulse * 2.0), 5.0, Color(Palette.MINT.r, Palette.MINT.g, Palette.MINT.b, 0.55 + 0.4 * pulse), 3.0)
	# --- ghosts: pulsing "needs you" ring (the sprite itself is drawn with the corridor layer)
	for i in mini(world.ghosts.size(), gh_pos.size()):
		var gh: Ghost = world.ghosts[i]
		var wdt: float = float(world.grid.hull.width)
		var edge: float = clampf(minf(gh.x + 1.0, wdt + 1.0 - gh.x) / 2.0, 0.0, 1.0)
		var gp: Vector2 = gh_pos[i] + Vector2(0, -17)
		var old_a: float = U.alpha
		U.alpha = old_a * minf(1.0, gh.age / 0.8) * edge
		_ping(ci, gp, 15.0 + 6.0 * kk, float(gh.id) * 0.37, 0.9, false)
		if hover_kind == &"ghost" and hover_id == gh.id:
			U.dashed_ring(ci, gp, 22.0, 26.0, Color(1, 1, 1, 0.95), 2.4, anim_t, 12)
		U.alpha = old_a
	# --- mess icons
	for m in world.messes:
		var floor_p: Vector2 = SimConst.to_px(m.x, float(m.deck))
		var born: float = _first_seen("m%d" % m.id)
		var pop: float = U.ease_out_back(clampf(born / 0.4, 0.0, 1.0))
		var bob: float = sin(anim_t * 4.0 + float(m.id)) * 1.6 * kk
		var c: Vector2 = mess_badge_center(floor_p) + Vector2(0, bob)
		var br: float = 12.0 * kk
		if pop > 0.02:
			_ping(ci, c, br * pop, float(m.id) * 0.29)
			U.circ(ci, c + Vector2(0, 1.5 * kk), (br + 0.5) * pop, Color(0.1, 0.15, 0.3, 0.22))
			U.circ(ci, c, br * pop, Palette.CREAM)
			IconArt.draw_icon(ci, &"mess", c, 17.0 * kk * pop, anim_t, colorblind)
		if m.clean_progress > 0.01:
			_arc(ci, c, br + 2.5 * kk, -PI * 0.5, -PI * 0.5 + TAU * clampf(m.clean_progress, 0.0, 1.0), Palette.MINT, 3.5 * clampf(kk, 0.7, 1.1), 24)
		if hover_kind == &"mess" and hover_id == m.id:
			U.dashed_ring(ci, floor_p + Vector2(0, -4), 24.0, 10.0, Color(1, 1, 1, 0.95), 2.4, anim_t, 12)
	# --- broken rooms
	for r in world.rooms:
		if not r.broken or not _rects.has(r.uid):
			continue
		var rc: Rect2 = _rects[r.uid]
		var born: float = _first_seen("r%d_%d" % [r.uid, r.broken_count])
		var pop: float = U.ease_out_back(clampf(born / 0.45, 0.0, 1.0))
		var holding: bool = r.uid == hold_room_uid
		var wob: float = 1.0 + (0.1 if holding else 0.06) * sin(anim_t * (13.0 if holding else 7.0))
		var c: Vector2 = Vector2(rc.position.x + rc.size.x * 0.5, rc.end.y - 30.0)
		var rad: float = (16.0 + (2.0 if holding else 0.0)) * pop * kk
		var rw: float = 4.5 * clampf(kk, 0.6, 1.1)
		if pop > 0.02:
			_ping(ci, c, rad + rw * 0.5, float(r.uid) * 0.41)
		U.circ(ci, c + Vector2(0, 2.0 * kk), rad + 2.0 * kk, Color(0.1, 0.15, 0.3, 0.3))
		U.circ(ci, c, rad + 1.5 * kk, Palette.NAVY)
		U.circ(ci, c, rad, Palette.CREAM)
		IconArt.draw_icon(ci, &"breakdown", c, 23.0 * pop * wob * kk, anim_t, colorblind)
		var prog: float = clampf(r.repair_progress, 0.0, 1.0)
		var ring_r: float = rad + rw
		_ring(ci, c, ring_r + rw * 0.5, Color(0.1, 0.15, 0.3, 0.45), rw)
		if prog > 0.005:
			_arc(ci, c, ring_r, -PI * 0.5, -PI * 0.5 + TAU * prog, Palette.MINT, rw)
		if holding:
			_ring(ci, c, ring_r + 5.0 * kk + 1.0, Color(1, 1, 1, 0.35 + 0.25 * U.pulse(anim_t, 3.0)), 2.0)
			# little repair sparks orbiting the ring while the player holds
			for j in range(3):
				var ang: float = anim_t * 5.0 + float(j) * TAU / 3.0
				var sp: Vector2 = c + Vector2(cos(ang), sin(ang)) * (ring_r + 7.0 * kk)
				U.circ(ci, sp, 2.2 * kk + 0.6, Color(Palette.MINT.r, Palette.MINT.g, Palette.MINT.b, 0.9))
	# --- queue counters
	for r in world.room_sim.service_rooms:
		var qn: int = r.queue.size()
		if qn <= 3:
			continue
		var p: Vector2 = SimConst.to_px(r.door_x, float(r.deck)) + Vector2(0, -(30.0 + 12.0 * kk))
		var col: Color = Palette.SUN if qn < 6 else Palette.CORAL
		var txt: String = "%d" % qn
		var qk: float = clampf(kk, 0.55, 1.2)
		var w: float = 34.0 * qk
		var h: float = 17.0 * qk
		if qn >= 6:
			_ping(ci, p, w * 0.42, float(r.uid) * 0.23, 0.9)
		U.rr(ci, Rect2(p.x - w * 0.5, p.y - h * 0.5 + 1.5, w, h), h * 0.5, Color(0.1, 0.15, 0.3, 0.25))
		U.rr(ci, Rect2(p.x - w * 0.5, p.y - h * 0.5, w, h), h * 0.5, Palette.NAVY)
		U.rr(ci, Rect2(p.x - w * 0.5 + 1.2, p.y - h * 0.5 + 1.2, w - 2.4, h - 2.4), h * 0.5 - 1.2, col)
		IconArt.draw_icon(ci, &"guest", Vector2(p.x - 8.0 * qk, p.y + 0.5 * qk), 12.0 * qk, anim_t, false)
		U.text(ci, txt, Vector2(p.x + 1.0 * qk, p.y + 5.1 * qk), maxi(int(round(15.0 * qk)), 9), Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, U.font_bold())
	# --- mood bubbles: ambient first (small, faint), problems on top (bigger, tinted, ringed)
	for pass_i in 2:
		var want_problem: bool = pass_i == 1
		for b in _bubbles:
			if bool(b["problem"]) != want_problem:
				continue
			var feet: Vector2 = g_feet[int(b["idx"])]
			var bk: float = kk * float(b["scale"])
			var anchor: Vector2 = feet + Vector2(0, _bubble_dy(world.guests[int(b["idx"])]))
			if want_problem and float(b["t"]) > 0.28:
				var gi: int = int(b["idx"])
				_ping(ci, anchor + Vector2(0, -21.0 * bk), 15.0 * bk, float(gi) * 0.31, float(b["alpha"]))
			IconArt.draw_bubble(ci, anchor, b["icon"], float(b["t"]), float(b["alpha"]), bk, colorblind, want_problem)
	# --- sleepers in the crew quarters: z z z over the room's blankets
	for k in _sleepers.size():
		var sl: StaffMember = world.staff[_sleepers[k]]
		GuestArt.draw_zzz(ci, _sleeper_feet[k] + Vector2(-2.0, -22.0), anim_t, float(sl.id) * 0.9)
	# --- tired crew: a "zzz" bubble above the hat
	for i in mini(world.staff.size(), s_feet.size()):
		var ts: StaffMember = world.staff[i]
		if ts.is_tired() and ts.state != &"rest" and ts.state != &"nap":
			var ta: Vector2 = s_feet[i] + Vector2(0, -GuestArt.staff_top(ts.role) - 3.0)
			IconArt.draw_bubble(ci, ta, &"zzz", anim_t + float(ts.id) * 0.7, 1.0, kk * 0.8, colorblind, false)
	# --- route preview + selected crew ring text
	if path_points.size() >= 2:
		_dashed_polyline(ci, path_points, Color(Palette.SUN.r, Palette.SUN.g, Palette.SUN.b, 0.95), 3.0, 9.0, 7.0, anim_t * 24.0)
		var endp: Vector2 = path_points[path_points.size() - 1]
		U.circ(ci, endp, 4.0, Palette.SUN)
		U.circ(ci, endp, 2.0, Palette.NAVY)


func _dashed_polyline(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, dash: float, gap: float, offset: float) -> void:
	var period: float = dash + gap
	var start: float = -fposmod(offset, period)
	var acc: float = 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg_len: float = a.distance_to(b)
		if seg_len < 0.01:
			continue
		var dir: Vector2 = (b - a) / seg_len
		var seg_a: float = acc
		var seg_b: float = acc + seg_len
		var k: int = int(floor((seg_a - start - dash) / period))
		var guard: int = 0
		while guard < 400:
			guard += 1
			var ds: float = start + float(k) * period
			if ds >= seg_b:
				break
			var de: float = ds + dash
			if de > seg_a:
				var s0: float = maxf(ds, seg_a) - seg_a
				var s1: float = minf(de, seg_b) - seg_a
				if s1 > s0:
					U.line(ci, a + dir * s0, a + dir * s1, col, w)
			k += 1
		acc = seg_b


# =================================================================================================
# picking (ship-local pixel coordinates)
# =================================================================================================
## Topmost interactive thing under `p`: {kind: ghost|mess|staff|guest|room|"", id}. Generous hit areas.
func pick(p: Vector2) -> Dictionary:
	for i in mini(world.ghosts.size(), gh_pos.size()):
		var c: Vector2 = gh_pos[i] + Vector2(0, -18.0)
		if absf(c.x - p.x) < 20.0 and absf(c.y - p.y) < 26.0:
			return {"kind": &"ghost", "id": world.ghosts[i].id}
	var best_m: Mess = null
	var best_md: float = 1e9
	# the hit box is the puddle + its (counter-scaled) badge, so what you see is what you click
	var hx: float = maxf(18.0, 14.0 * zoom_k + 10.0)
	var up: float = 18.0 + 24.0 * zoom_k + 5.0
	for m in world.messes:
		var f: Vector2 = SimConst.to_px(m.x, float(m.deck))
		var dx: float = absf(f.x - p.x)
		if dx < hx and p.y > f.y - up and p.y < f.y + 10.0:
			if dx < best_md:
				best_md = dx
				best_m = m
	if best_m != null:
		return {"kind": &"mess", "id": best_m.id}
	for i in mini(world.staff.size(), s_feet.size()):
		var f: Vector2 = s_feet[i]
		if absf(f.x - p.x) < 13.0 and p.y > f.y - 30.0 and p.y < f.y + 5.0:
			return {"kind": &"staff", "id": world.staff[i].id}
	var best_g: int = -1
	var best_d: float = 1e9
	for i in g_feet.size():
		if g_cat[i] == C_HIDDEN:
			continue
		var f: Vector2 = g_feet[i]
		if absf(f.x - p.x) < 12.0 and p.y > f.y - 28.0 and p.y < f.y + 5.0:
			var d: float = absf(f.x - p.x) + absf(f.y - 11.0 - p.y) * 0.5
			if d < best_d:
				best_d = d
				best_g = i
	if best_g >= 0:
		return {"kind": &"guest", "id": world.guests[best_g].id}
	var rid: int = room_at(p)
	if rid >= 0:
		return {"kind": &"room", "id": rid}
	return {"kind": &"", "id": -1}


## Service room (not stairs/elevator/utilities) whose rect contains `p`, or -1.
func room_at(p: Vector2) -> int:
	for r in world.rooms:
		if r.def.is_transport() or r.def.is_utility():
			continue
		if _rects.has(r.uid) and (_rects[r.uid] as Rect2).has_point(p):
			return r.uid
	return -1


func room_rect(uid: int) -> Rect2:
	return _rects.get(uid, Rect2())


## Ship-local centre of an entity (for camera focus / alerts / tests).
func local_pos_of(kind: StringName, id: int) -> Vector2:
	match kind:
		&"mess":
			var m: Mess = world.mess_by_id(id)
			if m != null:
				return SimConst.to_px(m.x, float(m.deck)) + Vector2(0, -22)
		&"room", &"repair":
			if _rects.has(id):
				return (_rects[id] as Rect2).get_center()
		&"staff":
			for i in mini(world.staff.size(), s_feet.size()):
				if world.staff[i].id == id:
					return s_feet[i] + Vector2(0, -12)
		&"guest":
			var g: Guest = world.guest_by_id(id)
			if g != null:
				var i: int = g.id - 1
				if i < g_feet.size():
					return g_feet[i] + Vector2(0, -12)
		&"ghost":
			for i in mini(world.ghosts.size(), gh_pos.size()):
				if world.ghosts[i].id == id:
					return gh_pos[i] + Vector2(0, -18)
	return Vector2.INF
