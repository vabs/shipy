class_name MenuStage
extends Node2D
## The title-screen ship: a believable cut-away cruise ship (ShipView) with fake guests living inside it
## and a few beans waving from the top deck. Bobbing is done by ShipView itself.
##   MenuStage.new(); add_child; then read `ship_rect` (ship-local px) to place/scale it.

const U := preload("res://src/render/art/art_util.gd")
const PROPS: Array[StringName] = [&"sun_hat", &"headband", &"glasses_3d", &"headphones"]
const ARCH: Array[StringName] = [&"holidaymaker", &"fitness_fan", &"film_buff", &"gamer"]
const W: int = 32
const DECKS: int = 5

var view: ShipView
var ship_rect: Rect2 = Rect2()
var _rooms: Array = []
var _t: float = 0.0
var _life: _Life
var _state_acc: float = 0.0


func _ready() -> void:
	view = ShipView.new()
	add_child(view)
	view.set_hull(W, DECKS, 1, &"med")
	ship_rect = view.ship_rect()
	_build_layout()
	view.set_rooms(_rooms)
	_life = _Life.new()
	_life.stage = self
	view.get_layer(&"entities").add_child(_life)
	for r in _rooms:
		view.set_room_state(r["uid"], {"busy_ratio": 0.5})


func _add(room_id: StringName, deck: int, x: int, tier: int = 1, tall: int = 1) -> void:
	var uid: int = _rooms.size() + 1
	_rooms.append({"uid": uid, "room_id": room_id, "deck": deck, "x": x, "width": RoomArt.default_width(room_id), "tier": tier, "decks_tall": tall})


func _build_layout() -> void:
	var top: int = DECKS - 1
	_add(&"elevator", 0, 17, 1, DECKS)
	_add(&"generator", 0, 0)
	_add(&"water_tank", 0, 1)
	_add(&"gym", 0, 3, 2)
	_add(&"arcade", 0, 7)
	_add(&"sauna", 0, 10)
	_add(&"stairs", 0, 13, 1, 2)
	_add(&"cabin", 0, 19)
	_add(&"cabin", 0, 21)
	_add(&"cabin", 0, 23, 2)
	_add(&"cabin", 0, 25)
	_add(&"toilets", 1, 1)
	_add(&"buffet", 1, 4, 2)
	_add(&"bar", 1, 8)
	_add(&"stairs", 1, 12, 1, 2)
	_add(&"restaurant", 1, 19)
	_add(&"medbay", 1, 24)
	_add(&"toilets", 1, 27, 2)
	for i in range(4):
		_add(&"cabin", 2, i * 2, 1 + (i % 3))
	_add(&"cinema", 2, 8, 2)
	_add(&"stairs", 2, 14, 1, 2)
	for i in range(4):
		_add(&"cabin", 2, 19 + i * 2)
	for i in range(4):
		_add(&"cabin", 3, i * 2, 1 + (i % 2))
	_add(&"toilets", 3, 8)
	_add(&"stairs", 3, 12, 1, 2)
	_add(&"cabin", 3, 19)
	_add(&"cabin", 3, 21, 3)
	_add(&"pool", top, 1, 2)
	_add(&"deck_chairs", top, 8)
	_add(&"deck_chairs", top, 12, 3)


func _process(delta: float) -> void:
	_t += delta
	_state_acc += delta
	if _state_acc < 0.25 or view == null:
		return
	_state_acc = 0.0
	for r in _rooms:
		var uid: int = r["uid"]
		var cap: int = RoomArt.capacity_for(r["room_id"], r["tier"])
		var st := {}
		st["busy_ratio"] = clampf(0.5 + 0.4 * sin(_t * 0.2 + float(uid) * 1.7), 0.0, 1.0) if cap > 0 else 0.0
		if r["room_id"] == &"elevator":
			st["car_deck_f"] = 2.0 + sin(_t * 0.4) * 1.9
		view.set_room_state(uid, st)


class _Life extends Node2D:
	var stage: MenuStage
	var walkers: Array[Dictionary] = []
	var inited: bool = false

	func _init_life() -> void:
		inited = true
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for i in range(11):
			var deck: int = rng.randi_range(0, MenuStage.DECKS - 2)
			walkers.append({
				"deck": deck, "x": rng.randf_range(1.0, float(MenuStage.W) - 2.0),
				"speed": rng.randf_range(1.1, 2.0) * (1.0 if rng.randf() > 0.5 else -1.0),
				"prop": MenuStage.PROPS[i % 4], "arch": MenuStage.ARCH[i % 4], "ph": rng.randf() * 6.0,
				"mood": [&"heart", &"smile", &"", &"meh", &"", &"smile"][i % 6],
			})

	func _process(delta: float) -> void:
		if not inited:
			_init_life()
		for g in walkers:
			g["x"] += g["speed"] * delta * 0.9
			g["ph"] += delta * 8.0 * absf(g["speed"]) * 0.5
			var w: float = float(MenuStage.W)
			if g["x"] > w - 1.0:
				g["x"] = w - 1.0
				g["speed"] = -absf(g["speed"])
			if g["x"] < 1.0:
				g["x"] = 1.0
				g["speed"] = absf(g["speed"])
		queue_redraw()

	func _draw() -> void:
		if not inited:
			_init_life()
		var t: float = stage._t
		for r in stage._rooms:
			var id: StringName = r["room_id"]
			var cap: int = RoomArt.capacity_for(id, r["tier"])
			if cap <= 0:
				continue
			var rect := SimConst.room_rect(r["deck"], r["x"], r["width"], r["decks_tall"])
			var busy: float = clampf(0.5 + 0.4 * sin(t * 0.2 + float(r["uid"]) * 1.7), 0.0, 1.0)
			var n: int = int(round(busy * float(cap)))
			if busy > 0.0 and n == 0:
				n = 1
			var pose := RoomArt.slot_pose(id)
			for s in range(n):
				var feet := RoomArt.slot_position(id, rect, s, cap)
				var k: int = (int(r["uid"]) + s) % 4
				GuestArt.draw_guest(self, feet, {
					"prop": MenuStage.PROPS[k], "body_color": Palette.archetype_color(MenuStage.ARCH[k]),
					"facing": RoomArt.slot_facing(id, rect, s, cap), "pose": pose, "t": t, "walk_phase": t * 8.0 + float(s), "sick": false,
				})
		for g in walkers:
			var feet2 := SimConst.to_px(g["x"], float(g["deck"]))
			var face: int = 1 if g["speed"] > 0.0 else -1
			GuestArt.draw_guest(self, feet2, {
				"prop": g["prop"], "body_color": Palette.archetype_color(g["arch"]), "facing": face,
				"pose": &"walk", "walk_phase": g["ph"], "t": t,
			})
			var mood: StringName = g["mood"]
			if mood != &"":
				IconArt.draw_bubble(self, feet2 + Vector2(0, -GuestArt.HEIGHT - 5.0), mood, fmod(t + float(g["ph"]), 6.0), 1.0)
		# waving beans on the top deck, near the bow
		var top: float = float(MenuStage.DECKS - 1)
		var xs: Array[float] = [21.6, 23.3, 25.2, 27.0, 28.8]
		for i in range(xs.size()):
			var sc: float = 1.45
			var bob: float = absf(sin(t * 4.0 + float(i) * 1.1)) * 2.5
			var feet3 := SimConst.to_px(xs[i], top) + Vector2(0, -bob)
			var col: Color = Palette.archetype_color(MenuStage.ARCH[i % 4])
			GuestArt.draw_guest(self, feet3, {
				"prop": MenuStage.PROPS[i % 4], "body_color": col, "facing": 1,
				"pose": &"stand", "t": t, "scale": sc,
			})
			_wave_arm(feet3, 1, sc, col, t, float(i) * 1.3)
			if i == 1 or i == 3:
				IconArt.draw_bubble(self, feet3 + Vector2(0, -GuestArt.HEIGHT * sc - 6.0), &"heart" if i == 1 else &"smile", fmod(t * 0.7 + float(i), 5.0), 1.0)

	func _wave_arm(feet: Vector2, facing: int, s: float, col: Color, t: float, ph: float) -> void:
		var f: float = float(facing)
		var sh := feet + Vector2(f * 6.5 * s, -10.5 * s)
		var ang: float = -PI * 0.5 + f * 0.6 + sin(t * 7.0 + ph) * 0.55 * f
		var hand := sh + Vector2(cos(ang), sin(ang)) * 9.5 * s
		var dark: Color = Palette.shade(col, 0.22)
		ArtUtil.capsule(self, sh, hand, 2.9 * s, dark)
		ArtUtil.capsule(self, sh, hand, 2.2 * s, col)
		ArtUtil.circ(self, hand, 2.9 * s, dark)
		ArtUtil.circ(self, hand, 2.3 * s, Palette.tint(col, 0.3))
