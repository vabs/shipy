class_name VoyageSelfTest
extends Node
## Interaction self-tests: run with  --scene=level --level=<id> --phase=voyage --selftest=clean|repair|assign|ghost|roster|crew
## (`crew`: --level=underworld_3 --crew=janitor:1,medic:1,entertainer:1,chef:1,warden:1; real clicks send each new role
## to its target and the crew quarters)
## The test zooms the camera onto the target (so the zoom/pan AND the ship bob transforms are involved), then
## injects REAL InputEvents (Viewport.push_input) at the screen position of a mess / broken room / crew / ghost
## and prints PASS or FAIL depending on whether the sim reacted. Exit code 0 = pass, 1 = fail.

var screen: Node = null
var mode: String = ""
var world: SimWorld = null
var ctl: VoyageController = null
var renderer: VoyageRenderer = null
var input: VoyageInput = null
var cam: ShipCamera = null
var hud: VoyageHud = null


func setup(p_screen: Node, p_mode: String) -> void:
	screen = p_screen
	mode = p_mode
	world = screen.world
	ctl = screen.ctl
	renderer = screen.renderer
	input = screen.input
	cam = screen.cam
	hud = screen.hud
	if mode == "flow":
		_test_flow()
		return
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _done(ok: bool, detail: String) -> void:
	print("SELFTEST %s: %s (%s)" % [mode, "PASS" if ok else "FAIL", detail])
	get_tree().quit(0 if ok else 1)


# ---- helpers ----------------------------------------------------------------------------------
func _advance_until(pred: Callable, max_seconds: float) -> bool:
	var t: float = 0.0
	while t < max_seconds:
		if pred.call():
			return true
		ctl.fast_forward(2.0)
		t += 2.0
	return pred.call()


func _focus_and_screen(local: Vector2) -> Vector2:
	cam.focus_on(local, 1)
	await _frames(50)
	renderer.update(0.0)
	return input.local_to_screen(local)


func _motion(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	get_viewport().push_input(ev, true)


func _button(p: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = p
	ev.global_position = p
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(ev, true)


func _click(p: Vector2) -> void:
	_motion(p)
	await _frames(2)
	_button(p, true)
	await _frames(1)
	_button(p, false)
	await _frames(2)


func _on_screen(p: Vector2) -> bool:
	return get_viewport().get_visible_rect().grow(-4.0).has_point(p)


# ---- tests ------------------------------------------------------------------------------------
func _run() -> void:
	await _frames(4)
	ctl.set_speed(0)
	ctl.start_delay = 0.0
	match mode:
		"clean":
			await _test_clean()
		"repair":
			await _test_repair()
		"assign":
			await _test_assign()
		"crew":
			await _test_crew()
		"ghost":
			await _test_ghost()
		"roster":
			await _test_roster()
		"soak":
			await _test_soak()
		"elevator":
			await _test_elevator()
		"keys":
			await _test_keys()
		"wheel":
			await _test_wheel()
		"hire":
			await _test_hire()
		"demo_assign":
			await _demo_assign()
		"demo_pin":
			await _demo_pin()
		"demo_hover":
			await _demo_hover()
		_:
			_done(false, "unknown self-test")


func _test_clean() -> void:
	if not _advance_until(func() -> bool: return not world.messes.is_empty(), 300.0):
		_done(false, "no mess appeared")
		return
	var m: Mess = world.messes[0]
	var local: Vector2 = renderer.local_pos_of(&"mess", m.id)
	var sp: Vector2 = await _focus_and_screen(local)
	if not _on_screen(sp):
		_done(false, "mess off screen %s" % str(sp))
		return
	var p0: float = m.clean_progress
	var id: int = m.id
	# paused: scrubbing is a free action and must be refused (planning orders stay allowed, see the assign test)
	await _click(sp)
	var refused: bool = ctl.speed == 0 and world.mess_by_id(id) != null and world.mess_by_id(id).clean_progress == p0 and int(world.metrics["player_clicks"]) == 0
	ctl.set_speed(1)
	for i in 3:
		await _click(sp)
	var gone: bool = world.mess_by_id(id) == null
	var ok: bool = refused and (gone or world.mess_by_id(id).clean_progress >= p0 + 0.3)
	_done(ok, "paused click refused=%s; 3 clicks at screen %s, mess %d progress %.2f -> %s, player_clicks=%d" % [refused, str(sp), id, p0, "cleaned" if gone else "%.2f" % world.mess_by_id(id).clean_progress, int(world.metrics["player_clicks"])])


func _test_repair() -> void:
	# remove the crew so only the player's hold can repair
	world.staff.clear()
	var target: RoomRuntime = null
	for r in world.rooms:
		if r.is_breakable() and not r.broken:
			target = r
			break
	if target == null:
		_done(false, "no breakable room")
		return
	world.room_sim.break_room(world, target)
	await _frames(3)
	var local: Vector2 = renderer.room_rect(target.uid).get_center()
	var sp: Vector2 = await _focus_and_screen(local)
	if not _on_screen(sp):
		_done(false, "room off screen")
		return
	input.set_synthetic_hold(true)
	# paused: holding to repair is a free action and must be refused
	_motion(sp)
	await _frames(2)
	_button(sp, true)
	await _frames(20)
	var refused: bool = ctl.speed == 0 and target.broken and target.repair_progress <= 0.0 and ctl.hold_room_uid < 0
	_button(sp, false)
	await _frames(2)
	ctl.set_speed(1)
	_motion(sp)
	await _frames(2)
	_button(sp, true)
	var elapsed: float = 0.0
	var peak: float = 0.0
	while target.broken and elapsed < 8.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		peak = maxf(peak, target.repair_progress)
	_button(sp, false)
	input.set_synthetic_hold(false)
	var ok: bool = refused and not target.broken and float(world.metrics["player_repair_s"]) > 1.5
	_done(ok, "paused hold refused=%s; held %.1fs (sim time), peak progress %.2f, repaired=%s, player_repair_s=%.1f" % [refused, elapsed, peak, str(not target.broken), float(world.metrics["player_repair_s"])])


func _pick_staff(role: StringName) -> StaffMember:
	for s in world.staff:
		if s.role == role:
			return s
	return null


func _test_assign() -> void:
	print("assign: start staff=", world.staff.size())
	var s: StaffMember = _pick_staff(&"janitor")
	if s == null:
		_done(false, "no janitor")
		return
	if not _advance_until(func() -> bool: return world.messes.size() >= 1, 300.0):
		_done(false, "no mess appeared")
		return
	# a mess that this janitor is NOT already working on
	var m: Mess = null
	for c in world.messes:
		if s.job == null or s.job.target_id != c.id:
			m = c
			break
	if m == null:
		var room: RoomRuntime = world.room_sim.service_rooms[0]
		m = world.problems.spawn_mess(world, room)
		if m == null:
			_done(false, "cannot create a second mess")
			return
		await _frames(2)
	print("assign: mess ", m.id)
	# 1) click the crew member on the ship
	var staff_local: Vector2 = renderer.local_pos_of(&"staff", s.id)
	var sp: Vector2 = await _focus_and_screen(staff_local)
	print("assign: click staff at ", sp)
	await _click(sp)
	var selected: bool = input.selected_staff_id == s.id
	if not selected:
		_done(false, "clicking the crew member on the ship did not select it (at %s)" % str(sp))
		return
	# 2) click the mess
	var ml: Vector2 = renderer.local_pos_of(&"mess", m.id)
	var mp: Vector2 = input.local_to_screen(ml)
	cam.focus_on((staff_local + ml) * 0.5, 0)
	await _frames(50)
	renderer.update(0.0)
	mp = input.local_to_screen(renderer.local_pos_of(&"mess", m.id))
	await _click(mp)
	var st: StaffMember = world.staff_by_id(s.id)
	var ok: bool = st.job != null and st.job.target_id == m.id and st.job.claimed_by == st.id and input.selected_staff_id == -1
	_done(ok, "crew %d -> mess %d, job target=%s, state=%s" % [s.id, m.id, str(st.job.target_id) if st.job != null else "none", String(st.state)])


## Screen position of a spot in the ceiling strip of a room (clear of the guests inside it).
func _room_click_spot(uid: int) -> Vector2:
	var rc: Rect2 = renderer.room_rect(uid)
	return await _focus_and_screen(rc.position + Vector2(rc.size.x * 0.5, 22.0))


## Selects a crew member and clicks `screen_p`; true if the click gave that member an order (selection cleared).
func _order(s: StaffMember, screen_p: Vector2) -> bool:
	input.select_staff(s.id)
	await _click(screen_p)
	return input.selected_staff_id == -1


func _test_crew() -> void:
	var by: Dictionary = {}
	for s in world.staff:
		by[s.role] = s
	for role in [&"janitor", &"medic", &"entertainer", &"chef"]:
		if not by.has(role):
			_done(false, "needs --crew=janitor:1,medic:1,entertainer:1,chef:1 (missing %s)" % role)
			return
	var fails: PackedStringArray = []
	var food: RoomRuntime = null
	var fun_room: RoomRuntime = null
	var quarters: RoomRuntime = null
	for r in world.room_sim.service_rooms:
		if food == null and r.def.category == &"food":
			food = r
		if fun_room == null and r.def.category == &"fun":
			fun_room = r
	if not world.room_sim.crew_rooms.is_empty():
		quarters = world.room_sim.crew_rooms[0]
	if food == null or fun_room == null or quarters == null:
		_done(false, "level needs a food room, a fun room and crew quarters")
		return
	# 1) medic -> a sick guest standing in the corridor
	var sick: Guest = null
	for g in world.guests:
		if g.mode == Guest.WANDER and not g.sick:
			sick = g
			break
	if sick == null:
		_done(false, "no wandering guest to make sick")
		return
	sick.clear_route()
	sick.set_position(0, 20.0)
	sick.hold_until = 1.0e9
	world.problems.infect(world, sick)
	var med: StaffMember = by[&"medic"]
	renderer.update(0.0)   # the guest was just moved: refresh the prepared positions before reading them
	await _frames(2)
	var gp: Vector2 = await _focus_and_screen(renderer.local_pos_of(&"guest", sick.id))
	if not await _order(med, gp) or med.job == null or med.job.kind != &"sick" or med.job.target_id != sick.id:
		fails.append("medic -> sick guest")
	# a healthy guest is refused (selection is dropped by the click, no job)
	# 2) entertainer -> a room
	var ent: StaffMember = by[&"entertainer"]
	if not await _order(ent, await _room_click_spot(fun_room.uid)) or ent.aura_uid != fun_room.uid or ent.goal != &"perform":
		fails.append("entertainer -> %s (aura_uid %d)" % [fun_room.def.id, ent.aura_uid])
	# 3) chef -> a food room
	var chef: StaffMember = by[&"chef"]
	if not await _order(chef, await _room_click_spot(food.uid)) or chef.aura_uid != food.uid or chef.goal != &"station":
		fails.append("chef -> %s (aura_uid %d)" % [food.def.id, chef.aura_uid])
	# 4) chef -> a non-food room is refused with the selection kept or dropped, but never assigned
	var chef_goal: int = chef.aura_uid
	input.select_staff(chef.id)
	await _click(await _room_click_spot(fun_room.uid))
	if chef.aura_uid != chef_goal:
		fails.append("chef was sent to a non-food room")
	input.cancel()
	# 5) any crew -> crew quarters (rest)
	var jan: StaffMember = by[&"janitor"]
	jan.energy = 35.0
	if not await _order(jan, await _room_click_spot(quarters.uid)) or jan.rest_uid != quarters.uid:
		fails.append("janitor -> crew quarters (rest_uid %d)" % jan.rest_uid)
	# 6) a fully rested crew member is not sent to bed
	med.energy = 100.0
	input.select_staff(med.id)
	await _click(await _room_click_spot(quarters.uid))
	if med.rest_uid != -1:
		fails.append("a rested medic was sent to rest")
	_done(fails.is_empty(), "medic/entertainer/chef/rest orders by real clicks" if fails.is_empty() else "; ".join(fails))


func _test_roster() -> void:
	var s: StaffMember = world.staff[0] if not world.staff.is_empty() else null
	if s == null:
		_done(false, "no crew")
		return
	hud.refresh(0.0)
	await _frames(4)
	var card: Control = hud._cards.get(s.id)
	if card == null:
		_done(false, "no roster card")
		return
	var p: Vector2 = card.get_global_rect().get_center()
	await _click(p)
	var ok: bool = input.selected_staff_id == s.id
	_done(ok, "roster card at %s -> selected=%d" % [str(p), input.selected_staff_id])


func _test_ghost() -> void:
	var gh: Ghost = world.problems.spawn_ghost(world)
	if gh == null:
		_done(false, "could not spawn a ghost")
		return
	gh.x = float(world.grid.hull.width) * 0.5
	gh.prev_x = gh.x
	gh.age = 5.0
	await _frames(3)
	var local: Vector2 = renderer.local_pos_of(&"ghost", gh.id)
	var sp: Vector2 = await _focus_and_screen(local)
	if not _on_screen(sp):
		_done(false, "ghost off screen %s" % str(sp))
		return
	var id: int = gh.id
	var before: int = int(world.metrics["banished"])
	# paused: banishing is a free action and must be refused
	await _click(sp)
	var refused: bool = ctl.speed == 0 and world.ghost_by_id(id) != null and int(world.metrics["banished"]) == before
	ctl.set_speed(1)
	await _frames(2)
	sp = input.local_to_screen(renderer.local_pos_of(&"ghost", id))   # the ghost drifts while the game runs
	await _click(sp)
	var ok: bool = refused and world.ghost_by_id(id) == null and int(world.metrics["banished"]) == before + 1
	_done(ok, "paused click refused=%s; ghost %d at screen %s, banished=%d" % [refused, id, str(sp), int(world.metrics["banished"])])


# ---- screenshot demos (no pass/fail; leave the scene in an interesting state) ---------------------
func _demo_assign() -> void:
	_advance_until(func() -> bool: return world.messes.size() >= 2, 300.0)
	var s: StaffMember = _pick_staff(&"janitor")
	if s == null or world.messes.is_empty():
		return
	var m: Mess = world.messes[world.messes.size() - 1]
	renderer.update(0.0)
	var mid: Vector2 = (renderer.local_pos_of(&"staff", s.id) + renderer.local_pos_of(&"mess", m.id)) * 0.5
	cam.focus_on(mid, 1)
	await _frames(60)
	renderer.update(0.0)
	input.select_staff(s.id)
	_motion(input.local_to_screen(renderer.local_pos_of(&"mess", m.id)))
	await _frames(10)


func _demo_pin() -> void:
	_advance_until(func() -> bool: return world.guests.size() >= 6, 300.0)
	var pick: Guest = null
	for g in world.guests:
		if g.state == Guest.QUEUE or g.state == Guest.WALK:
			pick = g
			break
	if pick == null:
		pick = world.guests[0]
	renderer.update(0.0)
	var lp: Vector2 = renderer.local_pos_of(&"guest", pick.id)
	cam.focus_on(lp, 1)
	await _frames(60)
	renderer.update(0.0)
	await _click(input.local_to_screen(lp))
	await _frames(5)


func _demo_hover() -> void:
	_advance_until(func() -> bool: return world.guests.size() >= 6, 300.0)
	var r: RoomRuntime = null
	for c in world.room_sim.service_rooms:
		if c.def.id != &"cabin" and not c.users.is_empty():
			r = c
			break
	if r == null:
		r = world.room_sim.service_rooms[0]
	renderer.update(0.0)
	var lp: Vector2 = renderer.room_rect(r.uid).get_center() + Vector2(0, -10)
	cam.focus_on(lp, 1)
	await _frames(60)
	renderer.update(0.0)
	_motion(input.local_to_screen(lp))
	await _frames(10)
	print("demo_hover room=", r.def.id, " hover=", input.hover_kind, " id=", input.hover_id, " over_world=", input.over_world, " screen=", input.local_to_screen(lp))


# ---- keyboard / camera / hire ----------------------------------------------------------------
func _key(code: Key, pressed: bool = true) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	get_viewport().push_input(ev, true)


func _tap(code: Key) -> void:
	_key(code, true)
	await _frames(2)
	_key(code, false)
	await _frames(2)


func _test_keys() -> void:
	ctl.set_speed(1)
	await _frames(2)
	await _tap(KEY_SPACE)
	var paused: bool = ctl.speed == 0
	await _tap(KEY_SPACE)
	var resumed: bool = ctl.speed == 1
	await _tap(KEY_3)
	var fast: bool = ctl.speed == 3
	await _tap(KEY_2)
	var two: bool = ctl.speed == 2
	await _tap(KEY_1)
	var one: bool = ctl.speed == 1
	# Esc opens the pause menu (and pauses the sim), Esc again closes it and restores the speed
	await _tap(KEY_ESCAPE)
	await _frames(30)
	var menu_open: bool = screen._pause_menu != null and ctl.speed == 0
	await _tap(KEY_ESCAPE)
	await _frames(40)
	var menu_closed: bool = screen._pause_menu == null and ctl.speed == 1
	var ok: bool = paused and resumed and fast and two and one and menu_open and menu_closed
	_done(ok, "space=%s resume=%s 3x=%s 2x=%s 1x=%s esc-open=%s esc-close=%s" % [paused, resumed, fast, two, one, menu_open, menu_closed])


func _test_wheel() -> void:
	var z0: int = cam.zoom_level
	var p: Vector2 = get_viewport().get_visible_rect().get_center()
	_motion(p)
	await _frames(2)
	_button(p, true, MOUSE_BUTTON_WHEEL_UP)
	_button(p, false, MOUSE_BUTTON_WHEEL_UP)
	await _frames(40)
	var z1: int = cam.zoom_level
	_button(p, true, MOUSE_BUTTON_WHEEL_DOWN)
	_button(p, false, MOUSE_BUTTON_WHEEL_DOWN)
	await _frames(40)
	var z2: int = cam.zoom_level
	# keyboard pan: hold D for a few frames after zooming in
	_button(p, true, MOUSE_BUTTON_WHEEL_UP)
	_button(p, false, MOUSE_BUTTON_WHEEL_UP)
	await _frames(30)
	var c0: Vector2 = cam.position
	Input.action_press(&"pan_right")
	await _frames(30)
	Input.action_release(&"pan_right")
	var moved: bool = cam.position.x > c0.x + 5.0
	_done(z1 == z0 + 1 and z2 == z0 and moved, "wheel up %d->%d, wheel down ->%d, pan_right moved %.1f px" % [z0, z1, z2, cam.position.x - c0.x])


func _test_hire() -> void:
	ctl.set_speed(1)
	var b: Button = hud._hire_buttons[&"janitor"]
	world.economy.money += 500
	await _frames(20)
	var staff0: int = world.staff.size()
	var money0: int = world.money
	var p: Vector2 = b.get_global_rect().get_center()
	await _click(p)
	await _frames(25)
	var cost: int = world.mid_voyage_hire_cost(&"janitor")
	var ok: bool = world.staff.size() == staff0 + 1 and hud._cards.size() == staff0 + 1 and int(world.economy.ledger[&"hires"]) == cost
	_done(ok, "hire click at %s: crew %d->%d, cards=%d, money %d->%d (cost %d)" % [str(p), staff0, world.staff.size(), hud._cards.size(), money0, world.money, cost])


## Runs the whole voyage with the renderer + HUD updating every step and random clicks / selections thrown at
## the input handler. Passes if nothing crashed (script errors show up in the log).
func _test_soak() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	ctl.autoplayer = AutoPlayer.new(world, &"active", 5)
	var rect: Rect2 = view_rect()
	var steps: int = 0
	var clicks: int = 0
	while not world.finished and steps < 2000:
		steps += 1
		ctl.fast_forward(0.5)
		renderer.update(0.05)
		hud.refresh(0.05)
		if steps % 3 == 0:
			var lp: Vector2 = Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
			if steps % 9 == 0 and not world.staff.is_empty():
				input.select_staff(world.staff[rng.randi() % world.staff.size()].id)
			input._on_press(lp)
			input._on_release()
			clicks += 1
		if steps % 40 == 0:
			input.cancel()
		await get_tree().process_frame
	_done(true, "soak finished: %d steps, %d random clicks, t=%.0f, rating %.0f, guests %d" % [steps, clicks, world.time, world.rating(), world.guests.size()])


func view_rect() -> Rect2:
	return screen.view.ship_rect()


## Whole level flow: port -> set sail -> voyage -> results -> Retry (same layout kept in the new port phase).
func _test_flow() -> void:
	await _frames(8)
	var level_id: StringName = screen.level.id
	var rooms0: int = screen.port.layout.rooms.size()
	var port0: PortState = screen.port
	var in_port: bool = screen.phase == screen.Phase.PORT and screen._port_ui != null
	screen._on_set_sail()
	await _frames(10)
	var voyage: bool = screen.phase == screen.Phase.VOYAGE and screen.world != null and screen.ctl != null
	if not voyage:
		_done(false, "no voyage after set sail (in_port=%s)" % str(in_port))
		return
	var w: SimWorld = screen.world
	screen.ctl.set_speed(3)
	screen.ctl.start_delay = 0.0
	# (a level with a port stop holds still at the Quick refit until somebody presses "Cast off!")
	var casts: int = 0
	while not w.finished and casts < 4:
		screen.ctl.fast_forward(w.duration + 5.0)
		await _frames(4)
		if w.port_stop.is_ready():
			casts += 1
			if screen._refit_ui != null:
				screen._on_cast_off()
			else:
				w.cast_off()
	var waited: float = 0.0
	while screen.phase != screen.Phase.RESULTS and waited < 8.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var results: bool = screen.phase == screen.Phase.RESULTS and screen._results != null
	if not results:
		_done(false, "no results overlay (phase=%d, finished=%s)" % [screen.phase, str(w.finished)])
		return
	var stars: int = int(w.result.get("stars", -1))
	var old_screen: Node = screen
	# this node lives under the screen that Retry frees: move it to the root so the check can finish
	var tree: SceneTree = get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	old_screen.call(&"_retry")
	await _frames(12)
	var cur: Node = Router.current
	var new_ok: bool = cur != old_screen and cur != null and cur.get("phase") == cur.Phase.PORT and cur.port == port0 and cur.port.layout.rooms.size() == rooms0
	_done(in_port and voyage and results and new_ok, "port=%s voyage=%s results=%s (stars %d, rating %.0f) retry->port with %d rooms kept=%s" % [in_port, voyage, results, stars, float(w.result.get("rating", 0.0)), rooms0, new_ok])


## Elevator: whenever guests ride the lift the rendered car must be at (about) their deck.
func _test_elevator() -> void:
	ctl.autoplayer = AutoPlayer.new(world, &"active", 5)
	var checks: int = 0
	var bad: int = 0
	var max_err: float = 0.0
	var t: float = 0.0
	while t < 240.0 and not world.finished:
		ctl.fast_forward(0.1)
		t += 0.1
		ctl.alpha = 1.0
		renderer.update(0.016)
		for r in world.room_sim.elevators:
			if renderer._car_lead.has(r.uid):
				var lead: Guest = world.guests[int(renderer._car_lead[r.uid])]
				var car: float = float(renderer._car_f.get(r.uid, -9.0))
				var err: float = absf(car - lead.deck_f)
				max_err = maxf(max_err, err)
				checks += 1
				if err > 0.3:
					bad += 1
		if int(t * 10.0) % 20 == 0:
			await get_tree().process_frame
	_done(checks > 0 and bad == 0, "elevators=%d, %d car checks, %d off by >0.3 decks, max err %.2f" % [world.room_sim.elevators.size(), checks, bad, max_err])
