class_name PortStopSelfTest
extends Node
## Scripted end-to-end check of the mid-voyage port stop (docs/SPEC.md §13.8) with REAL InputEvents (pushed into the viewport so they travel
## the normal _input -> GUI -> _unhandled_input path): the voyage docks and pauses, the Quick refit panel opens, a cabin card is dragged onto
## the ship, a buffet is upgraded from its popover (which offers no Move / Sell), a janitor is hired and "Cast off!" is pressed: the boarding
## wave comes aboard and the voyage runs on.
## Run:  godot --path . -- --scene=level --level=med_5 --phase=voyage --autobuild --portstop=20 --board=5 --speed=3 --selftest=portstop
## Prints PASS / FAIL per check and exits with code 0 (all pass) or 1.

var _screen: Node
var _world: SimWorld
var _ctl: VoyageController
var _passed: int = 0
var _failed: int = 0
var _last: Vector2 = Vector2.ZERO


func setup(screen: Node, _mode: String) -> void:
	_screen = screen
	_world = screen.world
	_ctl = screen.ctl
	Input.use_accumulated_input = false
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("  PASS: ", what)
	else:
		_failed += 1
		print("  FAIL: ", what)


func _motion(p: Vector2, mask: int = 0) -> void:
	var e := InputEventMouseMotion.new()
	e.device = InputEvent.DEVICE_ID_EMULATION
	e.position = p
	e.global_position = p
	e.relative = p - _last
	e.button_mask = mask
	_last = p
	get_viewport().push_input(e, true)


func _button(p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.device = InputEvent.DEVICE_ID_EMULATION
	e.position = p
	e.global_position = p
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = 1 if pressed else 0
	get_viewport().push_input(e, true)


func _hover(p: Vector2) -> void:
	_motion(p)
	await _frames(2)


func _click(p: Vector2) -> void:
	await _hover(p)
	_button(p, true)
	await _frames(2)
	_button(p, false)
	await _frames(3)


func _drag(a: Vector2, b: Vector2, steps: int = 8) -> void:
	await _hover(a)
	_button(a, true)
	await _frames(1)
	for i in range(1, steps + 1):
		_motion(a.lerp(b, float(i) / float(steps)), 1)
		await get_tree().process_frame
	await _frames(2)
	_button(b, false)
	await _frames(3)


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _run() -> void:
	await _frames(10)
	# 1. run to the quay: the voyage docks, the excursion happens and the sim holds still
	var guard: int = 0
	while _screen.get("_refit_ui") == null and guard < 60 and not _world.finished:
		guard += 1
		_ctl.fast_forward(2.0)
		await _frames(2)
	var ui: PortPhase = _screen.get("_refit_ui") as PortPhase
	_check(ui != null, "the Quick refit panel opens at the port stop")
	if ui == null:
		_finish()
		return
	ui.swallow_real_pointer = true
	await _frames(40)
	_check(_world.port_stop.is_ready() and _world.refit_open(), "the sim is ready and the refit is open")
	_check(_ctl.speed == 0 and _ctl.locked, "paused and locked while refitting")
	_ctl.set_speed(2)
	_check(_ctl.speed == 0, "speed buttons cannot unpause the refit")
	_check(not (_screen.get("hud") as VoyageHud).bottom_bar.visible, "the crew bar steps aside for the refit bar")
	var t0: float = _world.time
	await _frames(20)
	_check(is_equal_approx(_world.time, t0), "the voyage clock holds still")
	_check(_world.port_stop.excursion_count > 0, "guests went ashore (%d)" % _world.port_stop.excursion_count)
	var rooms0: int = _world.rooms.size()
	var money0: int = _world.money
	var cabin_cost: int = ContentStore.room(&"cabin").cost
	_check(ui.bar().sail_button.text == "Cast off!", "the big button says Cast off!")
	_check(not ui.bar().undo_button.visible and not ui.bar().back_button.visible, "no undo, no way back to the map")

	# 2. drag a cabin card onto a free cell of the ship (real input through the camera mapping)
	ui.select_tab(&"rest")
	await _frames(3)
	var spot: Vector2i = Vector2i(-1, -1)
	for d in _world.grid.hull.decks:
		for x in range(0, _world.grid.hull.width - 1):
			if bool(_world.can_add_room(&"cabin", d, x)["ok"]):
				var p: Vector2 = ui.cell_to_screen(d, float(x) + 1.0)
				if p.y > 130.0 and p.y < ui.bar().global_position.y - 20.0 and p.x > 520.0 and p.x < 1800.0:
					spot = Vector2i(x, d)
					break
		if spot.x >= 0:
			break
	_check(spot.x >= 0, "found a free cell on screen")
	var card: PortRoomCard = ui.bar().card_for(&"cabin")
	await _drag(_center(card), ui.cell_to_screen(spot.y, float(spot.x) + 1.0))
	_check(_world.rooms.size() == rooms0 + 1, "the cabin was built by dragging its card (%d -> %d rooms)" % [rooms0, _world.rooms.size()])
	_check(_world.money == money0 - cabin_cost, "charged the voyage money ($%d -> $%d)" % [money0, _world.money])
	var built: RoomRuntime = _world.room_sim.room(_world.grid.layout.rooms[_world.grid.layout.rooms.size() - 1].uid)
	_check(built != null and built.def.id == &"cabin" and built.deck == spot.y, "it is a live room on the right deck")

	# 3. click an upgradable room: the popover offers Upgrade only, press it
	var buffet: RoomRuntime = null
	for r in _world.rooms:
		if r.def.is_service_room() and r.def.id != &"cabin" and bool(_world.can_upgrade_room(r.uid)["ok"]):
			var pp: Vector2 = ui.cell_to_screen(r.deck, r.door_x)
			if pp.y > 130.0 and pp.y < ui.bar().global_position.y - 20.0:
				buffet = r
				break
	_check(buffet != null, "the ship has a room that can still be upgraded")
	if buffet != null:
		var m1: int = _world.money
		var tier0: int = buffet.tier
		await _click(ui.cell_to_screen(buffet.deck, buffet.door_x + 0.0))
		var pop: PortPopover = ui.popover()
		_check(pop.is_open(), "clicking a room opens its popover")
		_check(pop.move_button == null and pop.sell_button == null, "no Move and no Sell at a port stop")
		_check(pop.upgrade_button != null and not pop.upgrade_button.disabled, "Upgrade is offered")
		if pop.upgrade_button != null:
			await _click(_center(pop.upgrade_button))
			_check(buffet.tier == tier0 + 1, "the room moved up a tier")
			_check(_world.money < m1, "the upgrade was paid ($%d -> $%d)" % [m1, _world.money])

	# 4. hire a janitor in the Crew tab at the normal wage
	ui.select_tab(&"crew")
	await _frames(3)
	var staff0: int = _world.staff.size()
	var m2: int = _world.money
	var hb: Button = ui.bar().crew_panel.hire_button(&"janitor")
	if hb != null and not hb.disabled:
		await _click(_center(hb))
		_check(_world.staff.size() == staff0 + 1, "a janitor was hired")
		_check(_world.money == m2 - ContentStore.staff_role(&"janitor").wage, "at the normal wage")
	else:
		_check(false, "the janitor hire button is usable")

	# 5. Cast off!
	var waves: Array = []
	_world.wave_started.connect(func(_i: int, c: int) -> void: waves.append(c))
	var tm: float = _world.time
	await _click(_center(ui.bar().sail_button))
	await _frames(10)
	_check(_screen.get("_refit_ui") == null, "the refit panel is gone")
	_check(not _ctl.locked and _ctl.speed > 0, "the voyage runs again")
	_check((_screen.get("hud") as VoyageHud).bottom_bar.visible, "the crew bar is back")
	_check(_world.port_stop.phase == PortStop.DEPARTING or _world.port_stop.phase == PortStop.DONE, "departing")
	for i in 40:
		_ctl.fast_forward(1.0)
		await _frames(1)
	_check(_world.time > tm, "the clock runs")
	_check(waves.has(_world.port_stop.board), "the boarding wave came aboard (%d guests)" % _world.port_stop.board)
	_check(is_zero_approx(_world.port_stop.dock_progress), "the dock slid away")
	_finish()


func _finish() -> void:
	print("SELFTEST portstop: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)
