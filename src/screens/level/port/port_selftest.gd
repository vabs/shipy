class_name PortSelfTest
extends Node
## Scripted end-to-end check of the build UI. Drives REAL InputEvents (pushed into the viewport so they
## travel the normal _input -> GUI -> _unhandled_input path) through the camera + ship bob mapping:
## drag a card onto a cell, click a room, press Upgrade / Sell, undo, drag-move, hire crew, set sail.
## Run:  godot --path . -- --scene=portdev --level=med_3 --selftest=build
## Prints PASS / FAIL per check and exits with code 0 (all pass) or 1.

var _dev: Node
var _phase: PortPhase
var _port: PortState
var _cam: ShipCamera
var _passed: int = 0
var _failed: int = 0
var _last: Vector2 = Vector2.ZERO
var _sail_requested: bool = false
var _exit_requested: bool = false


func run(dev: Node) -> void:
	_dev = dev
	_phase = dev.phase
	_port = dev.port
	_cam = dev.cam
	Input.use_accumulated_input = false
	_phase.swallow_real_pointer = true      # the OS cursor must not interleave with the scripted events
	_phase.set_sail_requested.connect(func() -> void: _sail_requested = true)
	_phase.exit_requested.connect(func() -> void: _exit_requested = true)
	await _frames(12)
	await _test_mapping()
	await _test_card_drag_place()
	await _test_invalid_and_shift_paint()
	await _test_cancel()
	await _test_popover_upgrade_sell_undo()
	await _test_drag_move()
	await _test_crew()
	await _test_set_sail()
	await _test_back_and_teardown()
	print("SELFTEST build: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


## Scripted poses for screenshots, driven by real events (so hover / drag visuals are the real ones):
##   --pose=hovercard (pointer rests on the cabin card)   --pose=dragging (mid-drag from a card, held)
##   --pose=hoverroom (pointer over a placed room)        --pose=hoverstairs (pointer over placed stairs)
func run_pose(dev: Node, pose: String) -> void:
	_dev = dev
	_phase = dev.phase
	_port = dev.port
	_cam = dev.cam
	_phase.swallow_real_pointer = true
	await _frames(12)
	match pose:
		"hovercard":
			await _hover(_card_pos(&"cabin") + Vector2(-70, -10))
			await _hover(_card_pos(&"cabin"))
		"dragging":
			var a: Vector2 = _card_pos(&"cabin")
			await _hover(a)
			_button(a, true)
			await _frames(1)
			var b: Vector2 = _cell(1, 9.0)
			for i in range(1, 11):
				_motion(a.lerp(b, float(i) / 10.0), 1)
				await get_tree().process_frame
		"hoverroom":
			for r in _port.layout.rooms:
				if r.def.id == &"buffet":
					await _hover(_cell(r.deck, float(r.x) + 2.0))
					break
		"hoverstairs":
			for r in _port.layout.rooms:
				if r.def.id == &"stairs":
					await _hover(_cell(r.deck, float(r.x) + 0.5))
					break


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


func _button(p: Vector2, pressed: bool, idx: MouseButton = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	var e := InputEventMouseButton.new()
	e.device = InputEvent.DEVICE_ID_EMULATION
	e.position = p
	e.global_position = p
	e.button_index = idx
	e.pressed = pressed
	e.shift_pressed = shift
	e.button_mask = (1 << (idx - 1)) if pressed else 0
	get_viewport().push_input(e, true)


func _key(code: Key, ctrl: bool = false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		e.meta_pressed = ctrl
		get_viewport().push_input(e, true)
		await get_tree().process_frame


func _hover(p: Vector2) -> void:
	_motion(p)
	await _frames(2)


func _click(p: Vector2, shift: bool = false, idx: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await _hover(p)
	_button(p, true, idx, shift)
	await _frames(2)
	_button(p, false, idx, shift)
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


func _cell(deck: int, x_center: float) -> Vector2:
	return _phase.cell_to_screen(deck, x_center)


func _card_pos(room_id: StringName) -> Vector2:
	var card: PortRoomCard = _phase.bar().card_for(room_id)
	return card.get_global_rect().get_center()


func _room_at(room_id: StringName, deck: int, x: int) -> PlacedRoom:
	for r in _port.layout.rooms:
		if r.def.id == room_id and r.deck == deck and r.x == x:
			return r
	return null


func _count(room_id: StringName) -> int:
	return _port.layout.count_of(room_id)


# ---- tests -----------------------------------------------------------------------------------
func _test_mapping() -> void:
	print("-- mouse -> cell mapping through camera + bob")
	_phase.bar().select_tab(&"rest")
	_phase.arm_tool(&"cabin")
	for zoom_level in [0, 1]:
		_cam.set_zoom_level(zoom_level)
		await _frames(50)
		for spec in [[0, 3], [1, 12], [2, 8], [2, 18]]:
			var deck: int = spec[0]
			var x: int = spec[1]
			var p: Vector2 = _cell(deck, float(x) + 1.0)
			var local: Vector2 = Vector2((float(x) + 1.0) * SimConst.CELL_W, -(float(deck) + 0.5) * SimConst.DECK_H)
			var cam_p: Vector2 = _cam.local_to_screen(local)
			var inside: bool = p.y > 100.0 and p.y < _phase.bar().global_position.y - 10.0 and p.x > 10.0 and p.x < 1910.0
			if not inside:
				print("  (skip off-screen cell deck %d x %d at zoom %d)" % [deck, x, zoom_level])
				continue
			await _hover(p)
			var t: Dictionary = _phase.debug_target()
			_check(not t.is_empty() and int(t["deck"]) == deck and int(t["x"]) == x, "zoom %d: mouse on deck %d x %d -> ghost on (%d, %d)" % [zoom_level, deck, x, int(t.get("deck", -1)), int(t.get("x", -1))])
			# the camera ignores the ship's bob (+-3 px) and tilt (+-0.5 deg about the waterline), so allow ~1 cell/3
			_check(p.distance_to(cam_p) < 14.0, "zoom %d: ShipCamera.local_to_screen agrees within the bob margin (%.1f px)" % [zoom_level, p.distance_to(cam_p)])
	_cam.set_zoom_level(0)
	await _frames(50)
	await _key(KEY_ESCAPE)
	_check(_phase.armed_room() == &"", "Esc disarms the tool")


func _test_card_drag_place() -> void:
	print("-- drag a card onto the ship")
	var before: int = _port.budget
	await _drag(_card_pos(&"cabin"), _cell(0, 3.0))
	var r: PlacedRoom = _room_at(&"cabin", 0, 2)
	_check(r != null, "cabin placed on deck 0 at x=2 by dragging its card")
	_check(_port.budget == before - ContentStore.room(&"cabin").cost, "budget dropped by the cabin cost (%d -> %d)" % [before, _port.budget])
	_check(_phase.armed_room() == &"", "tool disarmed after a plain drop")
	_check(_phase.undo_steps() == 1, "placement recorded for undo")


func _test_invalid_and_shift_paint() -> void:
	print("-- invalid cells, shift painting")
	await _click(_card_pos(&"cabin"))
	_check(_phase.armed_room() == &"cabin", "clicking a card arms the tool")
	var money: int = _port.budget
	var count: int = _count(&"cabin")
	await _hover(_cell(0, 3.0))
	var t: Dictionary = _phase.debug_target()
	_check(t.has("valid") and not bool(t["valid"]) and String(t["reason"]).begins_with("Overlaps"), "ghost over the cabin is invalid: '%s'" % String(t.get("reason", "no ghost")))
	await _click(_cell(0, 3.0))
	_check(_count(&"cabin") == count and _port.budget == money, "clicking an invalid cell places nothing")
	_check(_phase.armed_room() == &"cabin", "tool stays armed after an invalid click")
	await _click(_cell(0, 7.0), true)
	await _click(_cell(0, 9.0), true)
	_check(_count(&"cabin") == count + 2, "shift-click painted two more cabins")
	_check(_phase.armed_room() == &"cabin", "tool still armed after shift-clicks")
	await _click(_cell(0, 11.0))
	_check(_count(&"cabin") == count + 3 and _phase.armed_room() == &"", "plain click places one more and disarms")
	# top-deck-only rule
	_phase.bar().select_tab(&"food")
	await _frames(2)
	_phase.arm_tool(&"pool")
	await _hover(_cell(1, 5.0))
	t = _phase.debug_target()
	_check(t.has("valid") and not bool(t["valid"]) and String(t["reason"]) == "Top deck only", "pool on an interior deck: '%s'" % String(t.get("reason", "no ghost")))
	await _key(KEY_ESCAPE)


func _test_cancel() -> void:
	print("-- cancel")
	_phase.bar().select_tab(&"rest")
	await _click(_card_pos(&"cabin"))
	_check(_phase.armed_room() == &"cabin", "armed")
	await _click(_cell(2, 6.0), false, MOUSE_BUTTON_RIGHT)
	_check(_phase.armed_room() == &"", "right-click cancels the tool")
	await _click(_card_pos(&"cabin"))
	await _click(_card_pos(&"cabin"))
	_check(_phase.armed_room() == &"", "clicking the armed card again disarms it")


func _popover_click(btn: Button) -> void:
	await _click(btn.get_global_rect().get_center())


func _test_popover_upgrade_sell_undo() -> void:
	print("-- popover: upgrade, sell, undo")
	var room: PlacedRoom = _room_at(&"cabin", 0, 2)
	await _click(_cell(0, 3.0))
	_check(_phase.popover().is_open() and _phase.selected_uid() == room.uid, "clicking a room opens its popover")
	await _frames(20)
	var up: Button = _phase.popover().upgrade_button
	_check(up != null and up.disabled, "Upgrade is disabled at campaign level %d (tier II needs level %d)" % [_port.grid.campaign_index, SimConst.TIER2_UNLOCK_LEVEL])
	var money: int = _port.budget
	await _popover_click(up)
	_check(room.tier == 0 and _port.budget == money, "pressing a disabled Upgrade does nothing")
	# pretend the player progressed, then reopen
	_port.grid.campaign_index = 5
	await _click(_cell(2, 14.0))      # empty space deselects
	_check(not _phase.popover().is_open(), "clicking empty ship closes the popover")
	await _click(_cell(0, 3.0))
	await _frames(20)
	up = _phase.popover().upgrade_button
	_check(up != null and not up.disabled, "Upgrade enabled once tier II is unlocked")
	var cost: int = ContentStore.room(&"cabin").upgrade_cost(0)
	money = _port.budget
	await _popover_click(up)
	_check(room.tier == 1 and _port.budget == money - cost, "Upgrade pressed: cabin is tier II, budget -$%d" % cost)
	if room.tier != 1:
		print("  DEBUG tier=%d budget=%d money=%d btn=%s disabled=%s popover_open=%s pos=%s size=%s vp=%s campaign=%d" % [room.tier, _port.budget, money, str(up.get_global_rect()), str(up.disabled), str(_phase.popover().is_open()), str(_phase.popover().position), str(_phase.popover().size), str(get_viewport().get_visible_rect().size), _port.grid.campaign_index])
	await _frames(20)
	var sell: Button = _phase.popover().sell_button
	var refund: int = _port.grid.refund_for(room.uid)
	money = _port.budget
	var uid: int = room.uid
	await _popover_click(sell)
	_check(_port.layout.get_room(uid) == null and _port.budget == money + refund, "Sell pressed: room gone, +$%d refunded" % refund)
	await _key(KEY_Z, true)
	var back: PlacedRoom = _port.layout.get_room(uid)
	_check(back != null and back.tier == 1 and _port.budget == money, "Ctrl/Cmd+Z restores the sold tier II cabin and the budget")
	await _key(KEY_Z, true)
	_check(back != null and _port.layout.get_room(uid).tier == 0, "second undo reverts the upgrade")


func _test_drag_move() -> void:
	print("-- drag a placed room to move it")
	var room: PlacedRoom = _room_at(&"cabin", 0, 2)
	var money: int = _port.budget
	await _drag(_cell(0, 3.0), _cell(2, 10.0))
	_check(room.deck == 2 and room.x == 9, "dragged cabin moved to deck 2, x=9 (now %d, %d)" % [room.deck, room.x])
	_check(_port.budget == money, "moving is free")
	# invalid drop snaps back
	var ox: int = room.x
	await _drag(_cell(2, 10.0), _cell(0, 8.0))   # deck 0 x=7..8 is occupied by a painted cabin
	_check(room.deck == 2 and room.x == ox, "dropping on an occupied cell leaves the room where it was")
	# move via popover button
	await _click(_cell(2, 10.0))
	await _frames(20)
	await _popover_click(_phase.popover().move_button)
	_check(_phase.is_carrying(), "popover Move picks the room up")
	await _click(_cell(2, 15.0))
	_check(room.deck == 2 and room.x == 14 and not _phase.is_carrying(), "click drops it at x=14 (now %d)" % room.x)
	await _click(_cell(3, 1.0))
	await _key(KEY_ESCAPE)


func _test_crew() -> void:
	print("-- crew")
	var bar: PortBuildBar = _phase.bar()
	await _click(bar.tab_button(&"crew").get_global_rect().get_center())
	_check(bar.current_tab == &"crew", "Crew tab opens")
	var money: int = _port.budget
	var jan: int = int(_port.hired[&"janitor"])
	await _click(bar.crew_panel.hire_button(&"janitor").get_global_rect().get_center())
	_check(int(_port.hired[&"janitor"]) == jan + 1 and _port.budget == money - ContentStore.staff_role(&"janitor").wage, "Hire janitor: +1 crew, -wage")
	await _click(bar.crew_panel.fire_button(&"janitor").get_global_rect().get_center())
	_check(int(_port.hired[&"janitor"]) == jan and _port.budget == money, "Fire janitor refunds the wage")
	await _key(KEY_Z, true)
	_check(int(_port.hired[&"janitor"]) == jan + 1, "undo brings the janitor back")
	await _key(KEY_Z, true)
	await _click(bar.tab_button(&"rest").get_global_rect().get_center())


func _find_button(root: Node, text: String) -> Button:
	for n in root.find_children("*", "Button", true, false):
		if (n as Button).text == text:
			return n as Button
	return null


func _test_set_sail() -> void:
	print("-- set sail validation")
	var bar: PortBuildBar = _phase.bar()
	await _click(bar.sail_button.get_global_rect().get_center())
	_check(not _sail_requested, "disconnected decks block Set Sail (errors)")
	_check(not _phase.overlay().bad_decks.is_empty(), "offending decks are marked on the ship (%s)" % str(_phase.overlay().bad_decks))
	# connect decks with stairs: (0,14) joins decks 0-1, (1,16) joins decks 1-2
	await _click(bar.tab_button(&"transport").get_global_rect().get_center())
	await _drag(_card_pos(&"stairs"), _phase.local_to_screen(Vector2(14.5 * SimConst.CELL_W, -1.0 * SimConst.DECK_H)))
	_check(_room_at(&"stairs", 0, 14) != null, "stairs placed at deck 0/1 (x=14)")
	await _drag(_card_pos(&"stairs"), _phase.local_to_screen(Vector2(16.5 * SimConst.CELL_W, -2.0 * SimConst.DECK_H)))
	_check(_room_at(&"stairs", 1, 16) != null, "stairs placed at deck 1/2 (x=16)")
	_check(_phase.overlay().bad_decks.is_empty(), "no deck is marked disconnected any more")
	await _click(bar.sail_button.get_global_rect().get_center())
	await _frames(10)
	await _frames(15)
	var dlg: Node = _phase.dialog_node()
	_check(dlg != null and not _sail_requested, "warnings (beds / food / crew...) ask 'Set sail anyway?'")
	var keep: Button = _find_button(dlg, "Keep building") if dlg != null else null
	if keep != null:
		await _click(keep.get_global_rect().get_center())
		await _frames(25)
	_check(not _sail_requested and _phase.dialog_node() == null, "'Keep building' dismisses the dialog without sailing")
	await _click(bar.sail_button.get_global_rect().get_center())
	await _frames(25)
	dlg = _phase.dialog_node()
	var ok: Button = _find_button(dlg, "Set sail") if dlg != null else null
	if ok != null:
		await _click(ok.get_global_rect().get_center())
		await _frames(25)
	_check(_sail_requested, "confirming emits set_sail_requested")


func _test_back_and_teardown() -> void:
	print("-- back to map, teardown")
	var bar: PortBuildBar = _phase.bar()
	await _click(bar.back_button.get_global_rect().get_center())
	await _frames(25)
	var dlg: Node = _phase.dialog_node()
	_check(dlg != null and not _exit_requested, "Back with changes asks for confirmation")
	var stay: Button = _find_button(dlg, "Stay") if dlg != null else null
	if stay != null:
		await _click(stay.get_global_rect().get_center())
		await _frames(25)
	_check(not _exit_requested, "'Stay' keeps the player in port")
	await _click(bar.back_button.get_global_rect().get_center())
	await _frames(25)
	dlg = _phase.dialog_node()
	var leave: Button = _find_button(dlg, "Leave") if dlg != null else null
	if leave != null:
		await _click(leave.get_global_rect().get_center())
		await _frames(25)
	_check(_exit_requested, "'Leave' emits exit_requested")
	var layer: Node = _dev.view.get_layer(&"overlay")
	var before: int = layer.get_child_count()
	_phase.teardown()
	await _frames(3)
	_check(layer.get_child_count() == before - 1, "teardown removes the overlay from the ship_view layer")
