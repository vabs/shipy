extends Control
## Gallery page: a full voyage moment (sea + ship + fake guests/staff/messes/ghost/bubbles).
## Flags: --dest=med|arctic|underworld  --hull=small|medium|large  --zoom=0|1|2  --focus=x,deck  --nohud  --nobob

const U := preload("res://src/render/art/art_util.gd")
const PROPS: Array[StringName] = [&"sun_hat", &"headband", &"glasses_3d", &"headphones"]
const ARCH: Array[StringName] = [&"holidaymaker", &"fitness_fan", &"film_buff", &"gamer"]

var dest: StringName = &"med"
var hull: String = "medium"
var zoom_arg: int = 0
var focus_arg: Vector2 = Vector2(-1, -1)
var show_hud: bool = true
var bob: bool = true

var view: ShipView
var cam: ShipCamera
var sea: SeaBackground
var life: _Life
var _rooms: Array = []
var _states: Dictionary = {}
var _t: float = 0.0
var _nolife: bool = false
var _nosea: bool = false
var _norooms: bool = false
var _bench: bool = false
var _bench_frames: int = 0
var _bench_acc: float = 0.0
var _w: int = 32
var _decks: int = 5


func setup(d: StringName) -> void:
	dest = d


func setup_params(p: Dictionary) -> void:
	hull = String(p.get("hull", "medium"))
	zoom_arg = int(p.get("zoom", "0"))
	if p.has("focus"):
		var parts := String(p["focus"]).split(",")
		focus_arg = Vector2(float(parts[0]), float(parts[1]))
	show_hud = not p.has("nohud")
	bob = not p.has("nobob")
	_bench = p.has("bench")
	_nolife = p.has("nolife")
	_nosea = p.has("nosea")
	_norooms = p.has("norooms")


func _ready() -> void:
	theme = UITheme.build()
	match hull:
		"small":
			_w = 24
			_decks = 4
		"large":
			_w = 40
			_decks = 6
		_:
			_w = 32
			_decks = 5
	sea = SeaBackground.attach_to(self)
	sea.set_destination(dest)
	if _nosea:
		sea.visible = false
		sea.foreground.visible = false
		sea.set_process(false)
	view = ShipView.new()
	view.bob_enabled = bob
	add_child(view)
	view.set_hull(_w, _decks, 1 if hull != "small" else 0, dest)
	cam = ShipCamera.new()
	add_child(cam)
	cam.set_ship_rect(view.ship_rect())
	cam.set_insets(96.0 if show_hud else 20.0, 232.0 if show_hud else 20.0)
	sea.bind_camera(cam, ShipArt.WATERLINE_Y)
	_build_layout()
	if not _norooms:
		view.set_rooms(_rooms)
	life = _Life.new()
	life.page = self
	if not _nolife:
		view.get_layer(&"entities").add_child(life)
		var fxl := _FxLayer.new()
		fxl.page = self
		view.get_layer(&"fx").add_child(fxl)
	if zoom_arg > 0:
		cam.set_zoom_level(zoom_arg)
	if focus_arg.x >= 0.0:
		cam.focus_on(SimConst.to_px(focus_arg.x, focus_arg.y + 0.5), zoom_arg)
	if show_hud:
		_build_hud()
	# apply initial states
	for r in _rooms:
		view.set_room_state(r["uid"], {"busy_ratio": 0.5})
	if _norooms:
		_rooms.clear()


func _add(room_id: StringName, deck: int, x: int, tier: int = 1, tall: int = 1) -> int:
	var uid := _rooms.size() + 1
	_rooms.append({"uid": uid, "room_id": room_id, "deck": deck, "x": x, "width": RoomArt.default_width(room_id), "tier": tier, "decks_tall": tall})
	return uid


func _build_layout() -> void:
	var W := _w
	var top := _decks - 1
	if _decks == 4:
		# small hull 24 x 4
		_add(&"generator", 0, 0)
		_add(&"water_tank", 0, 1)
		_add(&"gym", 0, 3)
		_add(&"stairs", 0, 7, 1, 2)
		_add(&"cabin", 0, 9)
		_add(&"cabin", 0, 11, 2)
		_add(&"toilets", 1, 1)
		_add(&"buffet", 1, 4, 2)
		_add(&"stairs", 1, 9, 1, 2)
		_add(&"bar", 1, 11)
		_add(&"cabin", 2, 0)
		_add(&"cabin", 2, 2)
		_add(&"cabin", 2, 4, 3)
		_add(&"stairs", 2, 9, 1, 2)
		_add(&"medbay", 2, 11)
		_add(&"pool", top, 1)
		_add(&"deck_chairs", top, 8)
		_add(&"deck_chairs", top, 12, 2)
		return
	var e := _add(&"elevator", 0, 17, 1, _decks)
	# deck 0
	_add(&"generator", 0, 0)
	_add(&"water_tank", 0, 1)
	_add(&"gym", 0, 3, 2)
	_add(&"arcade", 0, 7)
	if dest == &"med":
		_add(&"sauna", 0, 10)
	_add(&"stairs", 0, 13, 1, 2)
	match dest:
		&"arctic": _add(&"ice_rink", 0, 19)
		&"underworld": _add(&"casino", 0, 19, 2)
		_:
			_add(&"cabin", 0, 19)
			_add(&"cabin", 0, 21)
			_add(&"cabin", 0, 23, 2)
	# deck 1 (gangway)
	_add(&"toilets", 1, 1)
	_add(&"buffet", 1, 4, 2)
	_add(&"bar", 1, 8)
	_add(&"stairs", 1, 12, 1, 2)
	_add(&"restaurant", 1, 19)
	_add(&"medbay", 1, 24)
	_add(&"toilets", 1, 27, 2)
	# deck 2
	for i in range(4):
		_add(&"cabin", 2, i * 2, 1 + (i % 3))
	_add(&"cinema", 2, 8, 2)
	_add(&"stairs", 2, 14, 1, 2)
	for i in range(4):
		_add(&"cabin", 2, 19 + i * 2)
	# deck 3
	for i in range(4):
		_add(&"cabin", 3, i * 2, 1 + (i % 2))
	_add(&"toilets", 3, 8)
	_add(&"stairs", 3, 12, 1, 2)
	_add(&"cabin", 3, 19)
	_add(&"cabin", 3, 21, 3)
	if _decks >= 6:
		for i in range(4):
			_add(&"cabin", 4, i * 2)
	# top deck
	_add(&"pool", top, 1, 2)
	_add(&"deck_chairs", top, 8)
	_add(&"deck_chairs", top, 19, 3)


func _room(room_id: StringName, nth: int = 0) -> Dictionary:
	var k := 0
	for r in _rooms:
		if r["room_id"] == room_id:
			if k == nth:
				return r
			k += 1
	return {}


func _process(delta: float) -> void:
	_t += delta
	if _bench:
		_bench_frames += 1
		if _bench_frames > 60:
			_bench_acc += Performance.get_monitor(Performance.TIME_PROCESS)
		if _bench_frames == 360:
			print("BENCH fps=%.1f process_ms=%.2f draw_calls=%d objects=%d" % [Engine.get_frames_per_second(), _bench_acc / 300.0 * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
			get_tree().quit()
	# dynamic room states
	for r in _rooms:
		var uid: int = r["uid"]
		var st := {}
		var cap := RoomArt.capacity_for(r["room_id"], r["tier"])
		var ph := float(uid) * 1.7
		st["busy_ratio"] = clampf(0.45 + 0.4 * sin(_t * 0.2 + ph), 0.0, 1.0) if cap > 0 else 0.0
		if r["room_id"] == &"gym":
			st["broken"] = true
			st["repair_progress"] = fmod(_t * 0.08, 1.0)
		if r["room_id"] == &"pool":
			st["highlight"] = 0
		if r["room_id"] == &"restaurant":
			st["highlight"] = 1
		if r["room_id"] == &"elevator":
			st["car_deck_f"] = 2.0 + sin(_t * 0.4) * 1.9
		view.set_room_state(uid, st)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var top := UIKit.navy_bar()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, 84)
	top.offset_bottom = 84
	var tb := UIKit.hbox(18)
	var m := UIKit.stat_pill(&"coin", "$1,240")
	tb.add_child(UIKit.with_margin(m, 10))
	var vp := UIKit.make_voyage_progress()
	vp.value = 0.42
	vp.custom_minimum_size = Vector2(520, 40)
	tb.add_child(vp)
	tb.add_child(UIKit.h_spacer())
	var meter := UIKit.make_meter()
	meter.value = 72.0
	meter.custom_minimum_size = Vector2(420, 40)
	tb.add_child(meter)
	var stars := UIKit.star_row(2)
	tb.add_child(stars)
	for ic in [&"pause", &"play", &"fast", &"faster"]:
		tb.add_child(UIKit.icon_button(ic, "", 52.0, true))
	top.add_child(UIKit.with_margin(tb, 14))
	root.add_child(top)
	var bottom := UIKit.navy_bar_bottom()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.custom_minimum_size = Vector2(0, 210)
	bottom.offset_top = -210
	var bb := UIKit.hbox(16)
	for i in range(4):
		var card := UIKit.card()
		var v := UIKit.vbox(4)
		var bp := BeanPortrait.new()
		bp.staff_role = &"janitor" if i < 2 else &"mechanic"
		bp.custom_minimum_size = Vector2(96, 96)
		v.add_child(bp)
		v.add_child(UIKit.small_label("Janitor" if i < 2 else "Mechanic"))
		card.add_child(UIKit.with_margin(v, 10))
		bb.add_child(card)
	bb.add_child(UIKit.h_spacer())
	var alerts := UIKit.card()
	var av := UIKit.vbox(6)
	av.add_child(UIKit.header_label("Alerts"))
	av.add_child(UIKit.small_label("Gym broke down!"))
	av.add_child(UIKit.small_label("Mess at the buffet"))
	alerts.add_child(UIKit.with_margin(av, 14))
	alerts.custom_minimum_size = Vector2(420, 0)
	bb.add_child(alerts)
	bottom.add_child(UIKit.with_margin(bb, 18))
	root.add_child(bottom)


# =================================================================================================
# fake life drawn into the ship's entities layer
# =================================================================================================
class _Life extends Node2D:
	var page: Control
	var walkers: Array[Dictionary] = []
	var inited := false

	func _init_life() -> void:
		inited = true
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var w := float(page._w)
		var decks: int = page._decks
		for i in range(14):
			var deck := rng.randi_range(0, decks - 2)
			walkers.append({
				"deck": deck, "x": rng.randf_range(1.0, w - 2.0), "speed": rng.randf_range(1.2, 2.2) * (1.0 if rng.randf() > 0.5 else -1.0),
				"prop": page.PROPS[i % 4], "arch": page.ARCH[i % 4], "ph": rng.randf() * 6.0,
				"mood": [&"heart", &"smile", &"", &"need_hunger", &"meh", &""][i % 6], "run": i == 5,
			})

	func _process(delta: float) -> void:
		if not inited:
			_init_life()
		for g in walkers:
			g["x"] += g["speed"] * delta * 0.9
			g["ph"] += delta * 8.0 * absf(g["speed"]) * 0.5
			var w := float(page._w)
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
		var t: float = page._t
		# guests inside rooms
		for r in page._rooms:
			var id: StringName = r["room_id"]
			var cap := RoomArt.capacity_for(id, r["tier"])
			if cap <= 0:
				continue
			var rect := SimConst.room_rect(r["deck"], r["x"], r["width"], r["decks_tall"])
			var busy := clampf(0.45 + 0.4 * sin(t * 0.2 + float(r["uid"]) * 1.7), 0.0, 1.0)
			if id == &"gym":
				continue
			var n := int(round(busy * float(cap)))
			if busy > 0.0 and n == 0:
				n = 1
			var pose := RoomArt.slot_pose(id)
			for s in range(n):
				var feet := RoomArt.slot_position(id, rect, s, cap)
				var k: int = (int(r["uid"]) + s) % 4
				GuestArt.draw_guest(self, feet, {
					"prop": page.PROPS[k], "body_color": Palette.archetype_color(page.ARCH[k]), "facing": RoomArt.slot_facing(id, rect, s, cap),
					"pose": pose, "t": t, "walk_phase": t * 8.0 + float(s), "sick": false,
				})
		# queues
		_queue(&"buffet", 1, 4, [&"need_hunger", &"meh", &"angry", &""], t)
		_queue(&"bar", 1, 8, [&"smile", &""], t)
		_queue(&"toilets", 1, 1, [&"need_hygiene"], t)
		_queue(&"cinema", 2, 8, [&"need_fun", &""], t)
		# walkers
		for g in walkers:
			var feet := SimConst.to_px(g["x"], float(g["deck"]))
			var face := 1 if g["speed"] > 0.0 else -1
			GuestArt.draw_guest(self, feet, {
				"prop": g["prop"], "body_color": Palette.archetype_color(g["arch"]), "facing": face,
				"pose": &"run" if g["run"] else &"walk", "walk_phase": g["ph"], "t": t, "sick": g["run"] and false,
			})
			var mood: StringName = g["mood"]
			if mood != &"":
				IconArt.draw_bubble(self, feet + Vector2(0, -GuestArt.HEIGHT - 5.0), mood, fmod(t + float(g["ph"]), 6.0), 1.0)
		# a sick guest, a slipping guest, a storming guest
		var sf := SimConst.to_px(22.5, 1.0)
		GuestArt.draw_guest(self, sf, {"prop": &"sun_hat", "body_color": Palette.archetype_color(&"holidaymaker"), "pose": &"stand", "sick": true, "t": t})
		IconArt.draw_bubble(self, sf + Vector2(0, -27.0), &"sick", fmod(t, 5.0), 1.0)
		var slip := SimConst.to_px(15.4, 2.0)
		GuestArt.draw_guest(self, slip, {"prop": &"headband", "body_color": Palette.archetype_color(&"fitness_fan"), "pose": &"slip", "t": t, "slip_t": fmod(t, 3.0), "facing": 1})
		var storm := SimConst.to_px(3.0, 1.0)
		GuestArt.draw_guest(self, storm, {"prop": &"headphones", "body_color": Palette.archetype_color(&"gamer"), "pose": &"storm", "walk_phase": t * 10.0, "t": t, "facing": -1})
		IconArt.draw_bubble(self, storm + Vector2(0, -27.0), &"angry", fmod(t, 4.0), 1.0)
		# messes
		ProblemArt.draw_mess(self, SimConst.to_px(7.3, 1.0), 0, 0.0, t)
		ProblemArt.draw_mess(self, SimConst.to_px(12.0, 2.0), 2, fmod(t * 0.2, 1.0), t)
		ProblemArt.draw_mess(self, SimConst.to_px(11.4, 0.0), 1, 0.0, t)
		ProblemArt.draw_mess(self, SimConst.to_px(24.6, 2.0), 3, 0.0, t)
		IconArt.draw_icon(self, &"mess", SimConst.to_px(7.3, 1.0) + Vector2(0, -22.0 + sin(t * 4.0) * 2.0), 18.0)
		# staff
		GuestArt.draw_staff(self, SimConst.to_px(11.7, 2.0), {"role": &"janitor", "pose": &"work", "facing": 1, "t": t, "highlight": 2})
		GuestArt.draw_staff(self, SimConst.to_px(4.6, 0.0), {"role": &"mechanic", "pose": &"work", "facing": 1, "t": t})
		var sx := 14.0 + fmod(t * 2.5, 6.0)
		GuestArt.draw_staff(self, SimConst.to_px(sx, 1.0), {"role": &"janitor", "pose": &"walk", "facing": 1, "t": t, "walk_phase": t * 9.0})
		IconArt.draw_icon(self, &"breakdown", SimConst.to_px(4.5, 0.0) + Vector2(0, -80.0 + sin(t * 5.0) * 2.0), 24.0, t)
		# ghost (underworld)
		if page.dest == &"underworld":
			var gx := fmod(t * 1.2, 30.0) + 1.0
			ProblemArt.draw_ghost(self, SimConst.to_px(gx, 2.0) + Vector2(0, -4), t, 0.85, 1)
			ProblemArt.draw_ghost(self, SimConst.to_px(28.0 - fmod(t * 0.9, 24.0), 3.0), t + 1.0, 0.7, -1)

	func _queue(id: StringName, deck: int, x: int, moods: Array, t: float) -> void:
		var door_x := float(x) + float(RoomArt.default_width(id)) * 0.5
		for i in range(moods.size() + 1):
			var feet := SimConst.to_px(door_x - 0.45 * float(i + 1) - 0.2, float(deck))
			var k := (i + x) % 4
			GuestArt.draw_guest(self, feet, {"prop": page.PROPS[k], "body_color": Palette.archetype_color(page.ARCH[k]), "facing": 1, "pose": &"queue", "t": t})
			if i < moods.size() and moods[i] != &"":
				IconArt.draw_bubble(self, feet + Vector2(0, -27.0), moods[i], fmod(t * 0.9 + float(i), 5.0), 1.0)


class _FxLayer extends Node2D:
	var page: Control

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var t: float = page._t
		# floating money text over the bar, hearts over the pool, sparkle on the broken gym
		FxArt.draw_float_text(self, SimConst.to_px(9.5, 1.0) + Vector2(0, -50.0), "+$9", Palette.SUN, fmod(t * 0.5, 1.0))
		FxArt.draw_float_text(self, SimConst.to_px(6.0, 1.0) + Vector2(0, -56.0), "+$4", Palette.MINT, fmod(t * 0.5 + 0.4, 1.0))
		FxArt.draw_hearts(self, SimConst.to_px(10.0, 2.0) + Vector2(0, -30.0), fmod(t * 0.6, 1.0))
		FxArt.draw_spark(self, SimConst.to_px(3.6, 0.0) + Vector2(0, -34.0), fmod(t * 1.3, 1.0))
		FxArt.draw_sparkle(self, SimConst.to_px(5.2, 0.0) + Vector2(0, -34.0), fmod(t * 0.9 + 0.3, 1.0), Palette.MINT)
		FxArt.draw_puff(self, SimConst.to_px(12.0, 2.0) + Vector2(0, -6.0), fmod(t * 0.7, 1.0))
