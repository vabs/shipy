class_name VoyageFx
extends Node2D
## One-shot juice drawn in ShipView's "fx" layer: floating money text (bursts merge), hearts / stars on happy
## uses, cleaning puffs, repair sparkles, breakdown sparks (+ tiny camera shake), banish poofs.
## Created and owned by VoyageRenderer; call bind() once the world exists.

const U := preload("res://src/render/art/art_util.gd")
const MAX_FX: int = 48

var r: VoyageRenderer = null
var camera: ShipCamera = null

var _fx: Array[Dictionary] = []
var _clock: float = 0.0
var _mess_last: Dictionary = {}
var _ghost_last: Dictionary = {}
var _world: SimWorld = null


func bind(w: SimWorld) -> void:
	_world = w
	w.room_used.connect(_on_room_used)
	w.room_broken.connect(_on_room_broken)
	w.room_repaired.connect(_on_room_repaired)
	w.mess_spawned.connect(_on_mess_spawned)
	w.mess_cleaned.connect(_on_mess_cleaned)
	w.ghost_banished.connect(_on_ghost_banished)
	w.guest_slipped.connect(_on_slipped)
	w.guest_cured.connect(_on_cured)
	w.guest_got_sick.connect(_on_sick)
	w.money_changed.connect(_on_money)
	for m in w.messes:
		_mess_last[m.id] = SimConst.to_px(m.x, float(m.deck))


func note_ghost(id: int, pos: Vector2) -> void:
	_ghost_last[id] = pos


func _process(delta: float) -> void:
	if r != null and r.ctl != null and r.ctl.speed > 0:
		_clock += delta


# ---- spawning ---------------------------------------------------------------------------------
func spawn(kind: StringName, pos: Vector2, dur: float, data: Dictionary = {}) -> void:
	if _fx.size() >= MAX_FX:
		_fx.remove_at(0)
	_fx.append({"kind": kind, "pos": pos, "t0": _clock, "dur": dur, "data": data})


## Floating text that merges with a recent nearby one of the same colour (bursts add up).
func float_text(pos: Vector2, amount: int, color: Color, prefix: String = "+$") -> void:
	for e in _fx:
		if e["kind"] == &"text" and (_clock - float(e["t0"])) < 0.45 and (e["pos"] as Vector2).distance_to(pos) < 40.0 and (e["data"]["color"] as Color) == color:
			e["data"]["amount"] = int(e["data"]["amount"]) + amount
			e["data"]["text"] = "%s%d" % [prefix, int(e["data"]["amount"])]
			e["t0"] = _clock - 0.12
			return
	spawn(&"text", pos, 1.15, {"amount": amount, "text": "%s%d" % [prefix, amount], "color": color})


func _room(uid: int) -> RoomRuntime:
	return _world.room_by_uid(uid)


func _door_pos(rr: RoomRuntime, up: float = 50.0) -> Vector2:
	return SimConst.to_px(rr.door_x, float(rr.deck)) + Vector2(0, -up)


func _on_room_used(room_uid: int, guest_id: int, spend: int) -> void:
	var rr: RoomRuntime = _room(room_uid)
	if rr == null:
		return
	var pos: Vector2 = _door_pos(rr, 52.0) + Vector2(randf_range(-8.0, 8.0), 0.0)
	if spend > 0:
		float_text(pos, spend, Palette.SUN)
	var g: Guest = _world.guest_by_id(guest_id)
	if g != null:
		if g.use_favorite:
			spawn(&"stars", _door_pos(rr, 30.0), 0.9)
		elif g.satisfaction >= 70.0 and rr.def.id != &"cabin":
			if _count(&"hearts") < 4:
				spawn(&"hearts", _door_pos(rr, 30.0), 1.0)


func _count(kind: StringName) -> int:
	var n: int = 0
	for e in _fx:
		if e["kind"] == kind:
			n += 1
	return n


func _on_room_broken(uid: int) -> void:
	var rr: RoomRuntime = _room(uid)
	if rr == null:
		return
	var c: Vector2 = r.room_rect(uid).get_center()
	spawn(&"spark", c + Vector2(-16, -4), 0.55)
	spawn(&"spark", c + Vector2(14, 8), 0.5)
	if camera != null:
		camera.shake(2.6, 0.28)


func _on_room_repaired(uid: int) -> void:
	var c: Vector2 = r.room_rect(uid).get_center()
	var rc: Rect2 = r.room_rect(uid)
	spawn(&"popring", Vector2(c.x, rc.end.y - 30.0), 0.6, {"color": Palette.MINT_DARK, "r": 26.0})
	spawn(&"starburst", Vector2(c.x, rc.end.y - 34.0), 0.85, {"color": Palette.SUN})
	spawn(&"sparkle", c + Vector2(-14, 4), 0.8, {"color": Palette.MINT})
	spawn(&"sparkle", c + Vector2(16, -10), 0.9, {"color": Palette.SUN})
	spawn(&"sparkle", c + Vector2(0, 14), 0.7, {"color": Palette.MINT})
	spawn(&"text", c + Vector2(0, -30), 1.1, {"amount": 0, "text": "Fixed!", "color": Palette.MINT})


func _on_mess_spawned(id: int) -> void:
	var m: Mess = _world.mess_by_id(id)
	if m != null:
		_mess_last[id] = SimConst.to_px(m.x, float(m.deck))
		spawn(&"puff", _mess_last[id] + Vector2(0, -4), 0.45, {"small": true})


func _on_mess_cleaned(id: int) -> void:
	var p: Vector2 = _mess_last.get(id, Vector2.INF)
	if p == Vector2.INF:
		return
	# satisfying "pop": the badge bursts (ring + dots), a puff of soap, a little burst of stars
	var bp: Vector2 = r.mess_badge_center(p) if r != null else p + Vector2(0, -30)
	spawn(&"puff", p + Vector2(0, -6), 0.55)
	spawn(&"popring", bp, 0.55, {"color": Palette.MINT_DARK, "r": 16.0})
	spawn(&"starburst", bp + Vector2(0, -2), 0.8, {"color": Palette.SUN})
	spawn(&"sparkle", p + Vector2(8, -16), 0.7, {"color": Color(0.8, 0.95, 1.0)})
	_mess_last.erase(id)


## Small poof when the player scrubs a mess without finishing it.
func scrub(id: int) -> void:
	var p: Vector2 = _mess_last.get(id, Vector2.INF)
	if p != Vector2.INF:
		spawn(&"puff", p + Vector2(randf_range(-6.0, 6.0), -6.0), 0.4, {"small": true})


func _on_ghost_banished(id: int) -> void:
	var p: Vector2 = _ghost_last.get(id, Vector2.INF)
	if p == Vector2.INF:
		return
	spawn(&"puff", p + Vector2(0, -16), 0.6)
	spawn(&"sparkle", p + Vector2(-10, -24), 0.8, {"color": Palette.LILAC})
	spawn(&"sparkle", p + Vector2(12, -10), 0.9, {"color": Color(0.8, 1.0, 0.9)})
	_ghost_last.erase(id)


func _on_slipped(gid: int) -> void:
	var p: Vector2 = r.local_pos_of(&"guest", gid)
	if p != Vector2.INF:
		spawn(&"stars", p + Vector2(0, -10), 0.9)


func _on_cured(gid: int) -> void:
	var p: Vector2 = r.local_pos_of(&"guest", gid)
	if p != Vector2.INF:
		spawn(&"hearts", p + Vector2(0, -14), 1.0)


func _on_sick(gid: int) -> void:
	var p: Vector2 = r.local_pos_of(&"guest", gid)
	if p != Vector2.INF:
		spawn(&"puff", p + Vector2(0, -8), 0.5, {"small": true})


func _on_money(_money: int, delta: int, reason: StringName) -> void:
	if reason == &"tickets" and delta > 0:
		var gp: Vector2 = SimConst.to_px(0.6, float(_world.grid.hull.gangway_deck)) + Vector2(10, -52)
		float_text(gp, delta, Palette.MINT)


# ---- drawing ----------------------------------------------------------------------------------
func _draw() -> void:
	if _fx.is_empty():
		return
	var i: int = 0
	while i < _fx.size():
		var e: Dictionary = _fx[i]
		var k: float = (_clock - float(e["t0"])) / float(e["dur"])
		if k >= 1.0:
			_fx.remove_at(i)
			continue
		i += 1
		if k < 0.0:
			continue
		var p: Vector2 = e["pos"]
		match e["kind"]:
			&"text":
				# counter-scaled against the camera zoom and kept clear of the top / bottom bars
				var tk: float = clampf(r.zoom_k, 0.55, 1.2) if r != null else 1.0
				var tp: Vector2 = _clamp_to_play_area(p, tk)
				U.xf(self, tp, 0.0, Vector2(tk, tk))
				FxArt.draw_float_text(self, Vector2.ZERO, e["data"]["text"], e["data"]["color"], k)
				U.xf_end(self)
			&"popring":
				FxArt.draw_pop_ring(self, p, k, e["data"]["color"], float(e["data"].get("r", 20.0)))
			&"starburst":
				FxArt.draw_star_burst(self, p, k, e["data"]["color"])
			&"hearts":
				FxArt.draw_hearts(self, p, k)
			&"stars":
				FxArt.draw_stars(self, p, k)
			&"puff":
				if e["data"].get("small", false):
					U.xf(self, p, 0.0, Vector2(0.55, 0.55))
					FxArt.draw_puff(self, Vector2.ZERO, k)
					U.xf_end(self)
				else:
					FxArt.draw_puff(self, p, k)
			&"sparkle":
				FxArt.draw_sparkle(self, p, k, e["data"]["color"])
			&"spark":
				FxArt.draw_spark(self, p, k)


## Keeps floating texts (money, "Fixed!") on screen and out from under the top / bottom HUD bars: `p` is a
## ship-local point; returns a ship-local point whose screen position is inside the free play area.
func _clamp_to_play_area(p: Vector2, tk: float) -> Vector2:
	if not is_inside_tree():
		return p
	var xf: Transform2D = get_global_transform_with_canvas()
	var sp: Vector2 = xf * p
	var vr: Rect2 = get_viewport_rect()
	var zoom: float = xf.x.length()
	var top: float = VoyageHud.TOP_H + 30.0 + 20.0 * zoom * tk
	var bottom: float = vr.size.y - VoyageHud.BOTTOM_H - 14.0
	var cs := Vector2(clampf(sp.x, 64.0, vr.size.x - 64.0), clampf(sp.y, top, maxf(bottom, top)))
	if cs.is_equal_approx(sp):
		return p
	return xf.affine_inverse() * cs
