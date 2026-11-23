class_name TutorialSelfTest
extends Node
## Drives the med_1 tutorial with REAL InputEvents (Viewport.push_input, through camera zoom/pan and the ship bob)
## and prints PASS / FAIL per step. Exit code 0 = everything passed.
##
##   godot --path . -- --scene=level --level=med_1 --selftest=tutorial
##       full walkthrough: welcome, build cabin / buffet / bar / janitor, set sail, spill, crew, forced power surge,
##       hold-to-repair, speed, meter, done -> the voyage still runs to the results screen. It then restarts the
##       level (fresh hint store) and runs the SKIP scenario: skip in port, build with the auto-builder, sail, make
##       sure the sim never pauses itself and the level still ends in results.
##   godot --path . -- --scene=level --level=med_1 --selftest=tutorial_vskip      skip in the middle of the voyage
##   godot --path . -- --scene=level --level=med_1 --phase=voyage --autobuild --sim-seconds=40 --seed=1 --tutstep=crew --selftest=tutorial_crew
##       the janitor standing under a spill: the tutorial points at the roster card instead of the (unclickable) bean
##   godot --path . -- --scene=level --level=med_2 --phase=voyage --autobuild --selftest=tutorial_hints
##       contextual hints: one at a time, none in the first 5 s of a voyage, once per save, off when disabled.

var screen: Node = null
var mode: String = ""
var _passed: int = 0
var _failed: int = 0
var _last: Vector2 = Vector2.ZERO
var _t: TutorialDirector = null
var _chained: bool = false


func setup(p_screen: Node, p_mode: String) -> void:
	screen = p_screen
	mode = p_mode
	_passed = int(screen.params.get("t_passed", 0))
	_failed = int(screen.params.get("t_failed", 0))
	Input.use_accumulated_input = false
	var watchdog := get_tree().create_timer(300.0)
	watchdog.timeout.connect(func() -> void:
		print("  FAIL: watchdog (test took longer than 300 s)")
		get_tree().quit(1))
	_run.call_deferred()


func _run() -> void:
	match mode:
		"tutorial":
			await _test_full()
		"tutorial_skip":
			await _test_skip_port()
		"tutorial_vskip":
			await _test_skip_voyage()
		"tutorial_hints":
			await _test_hints()
		"tutorial_crew":
			await _test_crew_overlap()
		"tutorial_pose":
			await _pose()
			_chained = true   # leave the scene up for --shot
		_:
			_check(false, "unknown tutorial self-test '%s'" % mode)
	if not _chained:
		_finish()


func _finish() -> void:
	print("SELFTEST %s: %d passed, %d failed" % [mode, _passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


# ---- helpers ---------------------------------------------------------------------------------
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


func _button(p: Vector2, pressed: bool, idx: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.device = InputEvent.DEVICE_ID_EMULATION
	e.position = p
	e.global_position = p
	e.button_index = idx
	e.pressed = pressed
	e.button_mask = (1 << (idx - 1)) if pressed else 0
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


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		get_viewport().push_input(e, true)
		await get_tree().process_frame
	await _frames(2)


## Waits until step `id` is up (bubble visible) or the timeout (real seconds) runs out, then lets it settle.
func _wait_step(id: StringName, timeout: float) -> bool:
	var t0: int = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		if _t.current_id() == id and _t.card_visible():
			await _frames(34)
			return _t.current_id() == id
		await get_tree().process_frame
	return false


func _wait_until(pred: Callable, timeout: float) -> bool:
	var t0: int = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	return bool(pred.call())


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _target_center(i: int = 0) -> Vector2:
	var r: Rect2 = _t.ui._tgt[i]
	return r.get_center()


## A point inside the room that is really a "room" hit (not a janitor, spill or guest standing in front of it).
func _room_click_point(r: RoomRuntime) -> Vector2:
	var rect: Rect2 = _t.tg.room_rt_rect(r.uid)
	var inp: VoyageInput = screen.input
	var rend: VoyageRenderer = screen.renderer
	for fy in [0.45, 0.3, 0.6, 0.2, 0.7]:
		for fx in [0.5, 0.25, 0.75, 0.12, 0.88]:
			var p: Vector2 = rect.position + Vector2(rect.size.x * fx, rect.size.y * fy)
			var pk: Dictionary = rend.pick(inp.screen_to_local(p))
			if pk["kind"] == &"room" and int(pk["id"]) == r.uid:
				return p
	return rect.get_center()


func _mess_point(id: int) -> Vector2:
	return _t.tg.mess_rect(id).get_center()


func _ensure_tutorial() -> bool:
	_t = screen.tutorial
	if _t == null:
		_check(false, "screen has a TutorialDirector")
		return false
	return true


# =================================================================================================
# full run
# =================================================================================================
func _test_full() -> void:
	print("-- tutorial: port")
	if not _ensure_tutorial():
		return
	var pp: PortPhase = screen._port_ui
	pp.swallow_real_pointer = true
	var port: PortState = screen.port
	_check(_t.active and screen.hints != null, "director + hint director exist for med_1")
	_check(await _wait_step(&"welcome", 9.0), "welcome step shows once the intro banner has gone")
	await _click(_center(_t.ui.card.next_button))
	_check(await _wait_step(&"cabin", 3.0), "Next -> cabin step")
	# --- cabin: the card pulses, then an arrow points at a good spot --------------------------------
	var card_rect: Rect2 = pp.bar().card_for(&"cabin").get_global_rect()
	_check(_t.ui._tgt.size() >= 1 and _t.ui._tgt[0].grow(-10.0).intersects(card_rect), "cabin card is the first spotlight target")
	await _click(_center(pp.bar().card_for(&"cabin")))
	_check(pp.armed_room() == &"cabin", "clicking the card arms the cabin tool")
	await _frames(30)
	var spot: Rect2 = _t.tg.spot_rect(&"cabin")
	_check(_t.ui._tgt.size() == 1 and _t.ui._tgt[0].get_center().distance_to(spot.get_center()) < 6.0, "armed: the target moves to the suggested deck spot")
	var cabins0: int = port.layout.count_of(&"cabin")
	await _click(spot.get_center())
	_check(port.layout.count_of(&"cabin") == cabins0 + 1, "clicking the spot places a cabin (%d -> %d)" % [cabins0, port.layout.count_of(&"cabin")])
	_check(await _wait_step(&"buffet", 3.0), "enough beds -> buffet step")
	# --- buffet: Food tab, card, spot --------------------------------------------------------------
	_check(_t.ui._tgt[0].grow(-8.0).intersects(pp.bar().tab_button(&"food").get_global_rect()), "buffet step first points at the Food tab")
	await _click(_center(pp.bar().tab_button(&"food")))
	await _frames(20)
	await _click(_center(pp.bar().card_for(&"buffet")))
	await _frames(25)
	await _click(_t.tg.spot_rect(&"buffet").get_center())
	_check(port.layout.count_of(&"buffet") == 1, "buffet placed")
	_check(await _wait_step(&"rooms", 3.0), "buffet placed -> toilets/stairs info step")
	_check(_t.ui._tgt.size() == 2, "info step lights up the preset toilets and stairs (2 windows)")
	await _click(_center(_t.ui.card.next_button))
	_check(await _wait_step(&"fun", 3.0), "Next -> fun step")
	await _click(_center(pp.bar().tab_button(&"fun")))
	await _frames(20)
	await _click(_center(pp.bar().card_for(&"bar")))
	await _frames(25)
	await _click(_t.tg.spot_rect(&"bar").get_center())
	_check(port.layout.count_of(&"bar") == 1, "bar placed upstairs")
	_check(await _wait_step(&"janitor", 3.0), "fun placed -> janitor step")
	await _click(_center(pp.bar().tab_button(&"crew")))
	await _frames(20)
	await _click(_center(pp.bar().crew_panel.hire_button(&"janitor")))
	_check(port.staff_total() == 1, "janitor hired from the Crew tab")
	_check(await _wait_step(&"sail", 3.0), "janitor hired -> set sail step")
	_check(_t.ui._tgt.size() == 1 and _t.ui._tgt[0].grow(-10.0).intersects(pp.bar().sail_button.get_global_rect()), "set-sail button is spotlit")
	var warn: Array = port.validate()["warnings"]
	_check(warn.is_empty(), "tutorial build leaves no validation warnings")
	await _click(_center(pp.bar().sail_button))
	await _wait_until(func() -> bool: return screen.phase == screen.Phase.VOYAGE, 4.0)
	_check(screen.phase == screen.Phase.VOYAGE and _t.mode == &"voyage", "Set Sail -> voyage, director switched to voyage steps")

	print("-- tutorial: voyage")
	var w: SimWorld = screen.world
	var ctl: VoyageController = screen.ctl
	_check(await _wait_step(&"board", 6.0), "board step: guests are boarding")
	await _key(KEY_3)   # real key press: 3x speed to get to the first spill quickly
	_check(ctl.speed == 3, "key 3 sets speed 3 (real key event)")
	_check(await _wait_step(&"mess", 70.0), "first spill -> mess step")
	_check(ctl.speed == 0, "the game paused itself for the spill")
	var m1: Mess = w.mess_by_id(_t._first_mess_id)
	_check(m1 != null, "tutorial picked a live spill")
	if m1 != null:
		var mid: int = m1.id
		var p0: float = m1.clean_progress
		await _click(_mess_point(mid))
		var mm: Mess = w.mess_by_id(mid)
		_check(mm != null and mm.clean_progress > p0 + 0.3, "click 1 scrubs (progress %.2f)" % (mm.clean_progress if mm != null else 1.0))
		_check(ctl.speed == 0 and _t.current_id() == &"mess", "still paused while scrubbing")
		await _click(_mess_point(mid))
		if w.mess_by_id(mid) != null:
			await _click(_mess_point(mid))
		_check(w.mess_by_id(mid) == null, "3 clicks clean the spill")
	await _frames(70)
	_check(ctl.speed > 0 or _t.current_id() == &"crew", "the game resumed after the spill was cleaned (speed %d, step %s)" % [ctl.speed, _t.current_id()])
	_check(await _wait_step(&"crew", 60.0), "second spill -> crew step")
	_check(ctl.speed == 0, "paused for the crew step")
	var jan: StaffMember = _t._janitor()
	var inp: VoyageInput = screen.input
	_check(jan != null, "a janitor is on board")
	# click wherever the tutorial points first (the janitor on the ship, or their roster card when a spill covers them)
	var crew_pt: Vector2 = _t.ui._tgt[0].get_center()
	await _click(crew_pt)
	_check(inp.selected_staff_id == jan.id, "clicking the highlighted janitor selects them (%s)" % ("roster card" if _t.ui._tgt[0].position.y > 700.0 else "on the ship"))
	await _frames(8)
	_check(_t.ui.card.text_label.get_parsed_text().contains("click the spill"), "wording follows: now click the spill")
	var cm: int = _t._crew_mess_id
	_check(w.mess_by_id(cm) != null, "target spill still exists")
	await _click(_mess_point(cm))
	await _wait_until(func() -> bool: return _t.log_done.has(&"crew") or _t.log_skipped.has(&"crew"), 3.0)
	_check(_t.log_done.has(&"crew"), "janitor sent to the spill -> crew step done")
	await _frames(70)
	_check(ctl.speed > 0, "resumed after the janitor was sent")
	# --- power surge (forced instead of waiting for t=80) -------------------------------------------
	w.force_event(&"power_surge")
	_check(await _wait_step(&"repair", 10.0), "power surge -> repair step")
	_check(ctl.speed == 0, "paused for the repair step")
	var broken: Array[RoomRuntime] = _t._broken_rooms()
	_check(broken.size() >= 1, "%d room(s) broke" % broken.size())
	inp.set_synthetic_hold(true)
	for r in broken:
		var rp: Vector2 = _room_click_point(r)
		await _hover(rp)
		_button(rp, true)
		var ok: bool = await _wait_until(func() -> bool: return not r.broken, 8.0)
		var hov: Control = get_viewport().gui_get_hovered_control()
		var dbg: String = "progress %.2f, hold_uid %d, hovered %s, card at %s, point %s, target rects %s" % [r.repair_progress, ctl.hold_room_uid, str(hov.get_path()) if hov != null else "-", str(_t.ui.card.position), str(rp), str(_t.ui._tgt)]
		_button(rp, false)
		await _frames(3)
		_check(ok, "holding on the %s repairs it%s" % [r.def.display_name, "" if ok else " (" + dbg + ")"])
	inp.set_synthetic_hold(false)
	await _frames(70)
	_check(ctl.speed > 0, "resumed after the repair")
	# --- speed / meter / done ---------------------------------------------------------------------
	_check(await _wait_step(&"speed", 6.0), "speed step")
	var s_rect: Rect2 = _t.ui._tgt[0] if _t.ui._tgt.size() > 0 else Rect2()
	var hud: VoyageHud = screen.hud
	_check(s_rect.size.x > 0.0 and s_rect.grow(-6.0).intersects(hud.speed_buttons[2].get_global_rect()), "speed buttons are spotlit")
	await _key(KEY_2)
	_check(await _wait_step(&"meter", 4.0), "changing the speed (key 2) completes the speed step")
	_check(_t.ui._tgt.size() == 1 and _t.ui._tgt[0].grow(-10.0).intersects(hud.meter.get_global_rect()), "rating meter is spotlit")
	await _click(_center(_t.ui.card.next_button))
	_check(await _wait_step(&"done", 4.0), "Next -> final step")
	await _click(_center(_t.ui.card.next_button))
	await _frames(10)
	_check(not _t.active, "tutorial finished after the last step")
	_check(screen.hint_store.has(&"tutorial"), "tutorial recorded as done (won't replay)")
	await _frames(30)
	_check(not is_instance_valid(_t.ui), "tutorial UI removed")
	_check(ctl.speed > 0, "game keeps running")
	for id in [&"welcome", &"cabin", &"buffet", &"rooms", &"fun", &"janitor", &"sail", &"board", &"mess", &"crew", &"repair", &"speed", &"meter", &"done"]:
		_check(_t.log_shown.has(id), "step '%s' was shown" % id)

	print("-- tutorial: level is still completable")
	ctl.set_speed(3)
	ctl.fast_forward(w.duration + 5.0)
	await _wait_until(func() -> bool: return screen.phase == screen.Phase.RESULTS, 8.0)
	_check(screen.phase == screen.Phase.RESULTS and w.finished, "voyage ends in the results screen (rating %.0f, stars %d)" % [float(w.result.get("rating", 0.0)), int(w.result.get("stars", -1))])
	# --- chain: restart the level with a fresh hint store and run the skip scenario ------------------
	print("-- tutorial: restarting for the Skip scenario")
	var tree: SceneTree = get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	_chained = true
	Router.goto("level", {"level": "med_1", "selftest": "tutorial_skip", "t_passed": _passed, "t_failed": _failed})
	queue_free()


# =================================================================================================
# skip in port, then play the level without any tutorial interference
# =================================================================================================
func _test_skip_port() -> void:
	print("-- skip: port")
	if not _ensure_tutorial():
		return
	var pp: PortPhase = screen._port_ui
	pp.swallow_real_pointer = true
	_check(await _wait_step(&"welcome", 9.0), "fresh run: tutorial starts again (hint store is per run)")
	await _click(_center(_t.ui.card.next_button))
	_check(await _wait_step(&"cabin", 3.0), "cabin step")
	await _click(_center(_t.ui.card.skip_button))
	await _frames(12)
	_check(not _t.active and _t.skipped_by_player, "Skip tutorial stops the director")
	_check(screen.hint_store.has(&"tutorial"), "skipping is remembered")
	await _frames(30)
	_check(not is_instance_valid(_t.ui), "tutorial UI gone")
	# the port still works with real input afterwards
	var port: PortState = screen.port
	var cabins0: int = port.layout.count_of(&"cabin")
	pp.arm_tool(&"cabin")
	await _frames(4)
	var cell: Vector2 = pp.cell_to_screen(1, 5.0)
	await _click(cell)
	_check(port.layout.count_of(&"cabin") == cabins0 + 1, "port is fully usable after Skip (placed a cabin by hand)")
	AutoBuilder.apply(port)
	await _frames(4)
	var warn: Array = port.validate()["warnings"]
	if not warn.is_empty():
		print("  (note: auto-build warnings: %s)" % str(warn))
	screen._on_set_sail()
	await _frames(10)
	_check(screen.phase == screen.Phase.VOYAGE, "voyage started after skip")
	print("-- skip: voyage")
	var ctl: VoyageController = screen.ctl
	var w: SimWorld = screen.world
	ctl.start_delay = 0.0
	ctl.set_speed(3)
	var paused_frames: int = 0
	while not w.finished and w.time < 110.0:
		ctl.fast_forward(1.0)
		await get_tree().process_frame
		if ctl.speed == 0:
			paused_frames += 1
	_check(paused_frames == 0, "the sim never paused itself after Skip (%.0f s of voyage, %d messes spawned)" % [w.time, int(w.metrics["messes"])])
	ctl.fast_forward(w.duration + 5.0)
	await _wait_until(func() -> bool: return screen.phase == screen.Phase.RESULTS, 8.0)
	_check(screen.phase == screen.Phase.RESULTS, "level ends in the results screen after Skip")


func _test_skip_voyage() -> void:
	print("-- skip in the middle of the voyage")
	# phase=port run: build quickly, sail, then skip while the sim is paused for the spill
	if not _ensure_tutorial():
		return
	var pp: PortPhase = screen._port_ui
	pp.swallow_real_pointer = true
	var port: PortState = screen.port
	AutoBuilder.apply(port)
	await _frames(6)
	screen._on_set_sail()
	await _frames(10)
	var ctl: VoyageController = screen.ctl
	var w: SimWorld = screen.world
	_check(await _wait_step(&"board", 6.0), "board step")
	ctl.set_speed(3)
	_check(await _wait_step(&"mess", 70.0), "mess step pauses the game")
	_check(ctl.speed == 0, "game is paused")
	await _click(_center(_t.ui.card.skip_button))
	await _frames(8)
	_check(not _t.active, "Skip works while the game is paused by the tutorial")
	_check(ctl.speed > 0, "the game resumed (speed %d)" % ctl.speed)
	ctl.fast_forward(w.duration + 5.0)
	await _wait_until(func() -> bool: return screen.phase == screen.Phase.RESULTS, 8.0)
	_check(screen.phase == screen.Phase.RESULTS, "level still completes")


# =================================================================================================
# crew step when a spill covers the janitor
# =================================================================================================
func _test_crew_overlap() -> void:
	print("-- crew step with the janitor standing on the spill")
	if not _ensure_tutorial():
		return
	var w: SimWorld = screen.world
	var inp: VoyageInput = screen.input
	var ctl: VoyageController = screen.ctl
	_check(await _wait_step(&"crew", 12.0), "crew step is up")
	var jan: StaffMember = _t._janitor()
	var m: Mess = w.mess_by_id(_t._crew_mess_id)
	if jan == null or m == null:
		_check(false, "janitor and spill exist")
		return
	jan.set_position(m.deck, m.x)
	await _frames(12)
	_check(not _t._janitor_pickable(jan), "a spill under the janitor makes clicking the bean ambiguous")
	_check(_t.ui.card.text_label.get_parsed_text().contains("card"), "wording changes to 'click their card'")
	var card_rect: Rect2 = _t.tg.roster_card_rect(jan.id)
	_check(_t.ui._tgt.size() >= 1 and _t.ui._tgt[0].grow(-10.0).intersects(card_rect), "the first spotlight window is the roster card")
	await _click(_t.ui._tgt[0].get_center())
	_check(inp.selected_staff_id == jan.id, "clicking the roster card selects the janitor")
	await _click(_mess_point(m.id))
	await _wait_until(func() -> bool: return _t.log_done.has(&"crew"), 3.0)
	_check(_t.log_done.has(&"crew"), "janitor sent -> step done")
	await _frames(70)
	_check(ctl.speed > 0 or _t.current_id() != &"", "the game is running again (speed %d)" % ctl.speed)


# =================================================================================================
# contextual hints
# =================================================================================================
func _test_hints() -> void:
	print("-- contextual hints")
	var hd: HintDirector = screen.hints
	var ctl: VoyageController = screen.ctl
	var w: SimWorld = screen.world
	_check(hd != null, "hint director exists on a normal level")
	if hd == null:
		return
	ctl.start_delay = 0.0
	ctl.set_speed(1)
	hd.request(&"ghost", 0.0)
	hd.request(&"queue_anger", 0.0)
	await _frames(20)
	_check(hd.card == null, "no hint during the first 5 s of the voyage (t=%.1f)" % w.time)
	ctl.fast_forward(6.0)
	await _frames(30)
	_check(hd.card != null and hd.shown_log.size() == 1, "one hint appears after 5 s (%s)" % str(hd.shown_log))
	await _frames(20)
	_check(hd.shown_log.size() == 1, "never more than one hint at a time")
	hd.card.close()
	await _wait_until(func() -> bool: return hd.card == null, 2.0)
	_check(hd.card == null, "hint closes on request")
	var first: StringName = hd.shown_log[0]
	hd.request(first, 0.0)
	await _frames(10)
	_check(hd.shown_log.count(first) == 1, "a hint never repeats within a save")
	_check(screen.hint_store.has(first), "shown hints are recorded in the store")
	await get_tree().create_timer(2.8).timeout
	await _frames(30)
	_check(hd.shown_log.size() == 2, "the queued second hint follows after the gap (%s)" % str(hd.shown_log))
	hd.card.close()
	await _wait_until(func() -> bool: return hd.card == null, 2.0)
	Settings.show_tutorial_hints = false
	hd.request(&"mutiny", 0.0)
	await _frames(20)
	_check(hd.card == null and hd.shown_log.size() == 2, "Settings.show_tutorial_hints = false silences hints")
	Settings.show_tutorial_hints = true
	# the sim signals feed the queue
	hd._queue.clear()
	w.guest_got_sick.emit(1)
	w.event_started.emit(&"lunch_rush")
	w.guest_patience_out.emit(1, 1)
	w.mutiny_warning.emit(20.0)
	var ids: Array[StringName] = []
	for q in hd._queue:
		ids.append(q["id"])
	var wanted_sick: StringName = &"sick_have" if w.has_room_type(&"medbay") else &"sick"
	for want in [wanted_sick, &"event_lunch_rush", &"queue_anger", &"mutiny"]:
		var have: bool = ids.has(want) or screen.hint_store.has(want)
		_check(have, "signal -> hint '%s' (queued or already shown)" % want)
	hd._queue.clear()
	# store: persistence format
	var tmp := HintStore.new()
	tmp.path = "user://hints_selftest.json"
	tmp.persist = true
	tmp.mark(&"x")
	var again := HintStore.new()
	again.path = tmp.path
	again._read()
	_check(again.has(&"x") and not again.has(&"y"), "HintStore round-trips through its json file")
	DirAccess.remove_absolute(tmp.path)


# =================================================================================================
# screenshot poses:  --selftest=tutorial_pose --pose=crew|crew2|repair|hold  (+ --phase=voyage --autobuild --tutstep=..)
# =================================================================================================
func _pose() -> void:
	if not _ensure_tutorial():
		return
	var pose: String = String(screen.params.get("pose", ""))
	if pose.begins_with("port_"):
		await _pose_port(pose)
		return
	var w: SimWorld = screen.world
	var inp: VoyageInput = screen.input
	var ctl: VoyageController = screen.ctl
	await _frames(20)
	match pose:
		"crew2":
			await _wait_until(func() -> bool: return _t.current_id() == &"crew" and _t.card_visible(), 6.0)
			var j: StaffMember = _t._janitor()
			if j != null:
				inp.select_staff(j.id)
		"repair":
			w.force_event(&"power_surge")
			await _wait_until(func() -> bool: return _t.current_id() == &"repair" and _t.card_visible(), 6.0)
		"hold":
			w.force_event(&"power_surge")
			await _wait_until(func() -> bool: return _t.current_id() == &"repair" and _t.card_visible(), 6.0)
			await _frames(40)
			var br: Array[RoomRuntime] = _t._broken_rooms()
			if not br.is_empty():
				inp.set_synthetic_hold(true)
				var rp: Vector2 = _room_click_point(br[0])
				await _hover(rp)
				_button(rp, true)
				await _frames(60)
	print("pose %s: step=%s paused=%s" % [pose, _t.current_id(), ctl.speed == 0])


## Port poses (real clicks): --pose=port_armed (cabin tool armed, pointer over the suggested spot),
## --pose=port_food (buffet step with the Food tab open)
func _pose_port(pose: String) -> void:
	var pp: PortPhase = screen._port_ui
	pp.swallow_real_pointer = true
	await _wait_until(func() -> bool: return _t.card_visible(), 10.0)
	await _frames(30)
	match pose:
		"port_armed":
			await _click(_center(pp.bar().card_for(&"cabin")))
			await _frames(30)
			await _hover(_t.tg.spot_rect(&"cabin").get_center())
			await _frames(30)
		"port_food":
			await _click(_center(pp.bar().card_for(&"cabin")))
			await _click(_t.tg.spot_rect(&"cabin").get_center())
			await _wait_until(func() -> bool: return _t.current_id() == &"buffet", 4.0)
			await _frames(30)
			await _click(_center(pp.bar().tab_button(&"food")))
			await _frames(40)
	print("pose %s: step=%s" % [pose, _t.current_id()])
