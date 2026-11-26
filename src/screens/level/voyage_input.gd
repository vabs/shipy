class_name VoyageInput
extends Node
## Mouse interactions of the voyage (SPEC section 7):
##   left click mess = clean click   |  press-and-hold on a broken room = repair
##   click crew (ship or roster) then click a target = assign (dashed route preview, valid targets glow):
##     janitor -> spill | mechanic -> broken room | medic -> sick guest | warden -> ghost |
##     entertainer -> a room with a queue | chef -> buffet / restaurant | any crew -> crew quarters (rest)
##   click ghost = banish            |  click guest = pin its tooltip
##   right-click / Esc = cancel selection
## A full-rect PASS control (layer 6, under the HUD) receives the clicks so HUD panels block the world and
## wheel / middle-drag still reach ShipCamera. All picking goes through the ship-local transform, i.e.
## camera zoom/pan AND the bobbing of the ship are accounted for.

signal selection_changed

var enabled: bool = true
var world: SimWorld = null
var ctl: VoyageController = null
var renderer: VoyageRenderer = null
var view: ShipView = null
var cam: ShipCamera = null
var hud: Control = null

var selected_staff_id: int = -1
var pinned_guest_id: int = -1
var hover_kind: StringName = &""
var hover_id: int = -1
var mouse_screen: Vector2 = Vector2.ZERO
var over_world: bool = false
var catcher: Control = null

var _layer: CanvasLayer = null
var _hold_uid: int = -1
var _press_msec: int = 0
var _press_guest: int = -1
var _roster_hover: int = -1
var _path_key: String = ""
var _path_timer: float = 0.0
var _hold_fx_t: float = 0.0
var _screen: Node = null
var _last_paused_hint_msec: int = -100000


func setup(p_world: SimWorld, p_ctl: VoyageController, p_renderer: VoyageRenderer, p_view: ShipView, p_cam: ShipCamera, p_hud: Control, host: Node) -> void:
	world = p_world
	ctl = p_ctl
	renderer = p_renderer
	view = p_view
	cam = p_cam
	hud = p_hud
	_screen = host
	_layer = CanvasLayer.new()
	_layer.name = "WorldCatcherLayer"
	_layer.layer = 6
	host.add_child(_layer)
	catcher = Control.new()
	catcher.name = "WorldCatcher"
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_PASS
	catcher.focus_mode = Control.FOCUS_NONE
	catcher.gui_input.connect(_on_gui_input)
	catcher.mouse_entered.connect(func() -> void: over_world = true)
	catcher.mouse_exited.connect(func() -> void:
		over_world = false
		_stop_hold())
	_layer.add_child(catcher)


func _exit_tree() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()


# ---- coordinate mapping -----------------------------------------------------------------------
## Screen (viewport) position -> ship-local pixel position, including camera zoom/pan and the ship's bob.
func screen_to_local(p: Vector2) -> Vector2:
	var canvas_p: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * p
	var layer: Node2D = view.get_layer(&"overlay")
	return layer.get_global_transform().affine_inverse() * canvas_p


## Ship-local position -> screen (viewport) position. Inverse of screen_to_local().
func local_to_screen(p: Vector2) -> Vector2:
	var layer: Node2D = view.get_layer(&"overlay")
	var canvas_p: Vector2 = layer.get_global_transform() * p
	return get_viewport().get_canvas_transform() * canvas_p


# ---- selection --------------------------------------------------------------------------------
func has_selection() -> bool:
	return selected_staff_id >= 0 or pinned_guest_id >= 0


func select_staff(id: int) -> void:
	if id == selected_staff_id:
		return
	selected_staff_id = id
	pinned_guest_id = -1
	_sync_renderer()
	AudioManager.play_sfx(&"ui_click", 0.04, -2.0)
	selection_changed.emit()


func cancel() -> void:
	var had: bool = has_selection()
	selected_staff_id = -1
	pinned_guest_id = -1
	_path_key = ""
	_sync_renderer()
	if had:
		selection_changed.emit()


func set_roster_hover(id: int) -> void:
	_roster_hover = id


func _sync_renderer() -> void:
	renderer.selected_staff_id = selected_staff_id
	renderer.pinned_guest_id = pinned_guest_id
	renderer.target_kind = &""
	renderer.rest_targets = false
	if selected_staff_id >= 0:
		var s: StaffMember = world.staff_by_id(selected_staff_id)
		if s != null:
			renderer.target_kind = s.job_kind() if s.job_kind() != &"" else s.aura_kind()
			renderer.rest_targets = not world.room_sim.crew_rooms.is_empty() and s.energy < 100.0
	if selected_staff_id < 0:
		renderer.path_points = PackedVector2Array()


# ---- events -----------------------------------------------------------------------------------
func _on_gui_input(event: InputEvent) -> void:
	if not enabled or world == null or world.finished:
		return
	if event is InputEventMouseMotion:
		mouse_screen = (event as InputEventMouseMotion).position
		over_world = true
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		mouse_screen = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(screen_to_local(mb.position))
			else:
				_on_release()
			catcher.accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel()
			catcher.accept_event()


func _on_press(local: Vector2) -> void:
	var pk: Dictionary = renderer.pick(local)
	var kind: StringName = pk["kind"]
	var id: int = pk["id"]
	_press_msec = Time.get_ticks_msec()
	_press_guest = -1
	if selected_staff_id >= 0:
		var s: StaffMember = world.staff_by_id(selected_staff_id)
		if s == null:
			cancel()
		else:
			if kind == &"staff":
				if id == selected_staff_id:
					cancel()
				else:
					select_staff(id)
				return
			var jk: StringName = s.job_kind()
			if kind == &"mess" and jk == &"mess":
				_assign(s, &"mess", id)
				return
			if kind == &"ghost" and jk == &"ghost":
				_assign(s, &"ghost", id)
				return
			if kind == &"guest" and jk == &"sick":
				var sg: Guest = world.guest_by_id(id)
				if sg != null and sg.is_ailing():
					_assign(s, &"sick", id)
					return
				_hint("Medics treat sick and seasick guests. Pick one with a green face!")
			if kind == &"mess" and jk != &"mess":
				_hint("Mechanics fix rooms. Send a janitor to the spill!" if jk == &"repair" else "%ss can't clean spills. Send a janitor!" % _role_name(s))
			var target_room: int = id if kind == &"room" else renderer.room_at(local)
			if target_room >= 0:
				var rr: RoomRuntime = world.room_by_uid(target_room)
				if rr != null:
					if rr.is_crew_quarters():
						_order_rest(s, rr)
						return
					if jk == &"repair" and rr.broken and kind != &"ghost" and kind != &"mess":
						_assign(s, &"repair", target_room)
						return
					if s.aura_kind() == &"perform" and rr.def.is_service_room() and rr.def.id != &"cabin":
						_assign(s, &"perform", target_room)
						return
					if s.aura_kind() == &"station":
						if rr.def.category == &"food":
							_assign(s, &"station", target_room)
							return
						_hint("Chefs work in the buffet or the restaurant.")
					if jk == &"mess" and rr.broken:
						_hint("Janitors clean spills. Send a mechanic to the broken room!")
			if kind == &"ghost" or kind == &"mess":
				pass  # fall through: banish / scrub even while a crew member is selected
			elif kind == &"room" and world.room_by_uid(id) != null and world.room_by_uid(id).broken:
				pass  # fall through: hold to repair
			else:
				cancel()
	match kind:
		&"ghost":
			if _paused_blocks(kind, id):
				_paused_hint()
				return
			world.player_banish_ghost(id)
			AudioManager.play_sfx(&"ui_click", 0.04, -2.0)
		&"mess":
			if _paused_blocks(kind, id):
				_paused_hint()
				return
			world.player_click_mess(id)
			AudioManager.play_sfx(&"ui_click", 0.15, -4.0)
			renderer.fx.scrub(id)
		&"staff":
			select_staff(id)
		&"guest", &"room":
			var broken_uid: int = -1
			var ruid: int = id if kind == &"room" else renderer.room_at(local)
			if ruid >= 0:
				var r: RoomRuntime = world.room_by_uid(ruid)
				if r != null and r.broken:
					broken_uid = ruid
			if broken_uid >= 0 and _paused_blocks(&"room", broken_uid):
				if kind == &"guest":
					_toggle_pin(id)   # paused: no repairing, but a guest in front can still be inspected
				else:
					_paused_hint()
			elif broken_uid >= 0:
				_start_hold(broken_uid)
				if kind == &"guest":
					_press_guest = id
			elif kind == &"guest":
				_toggle_pin(id)
			else:
				_unpin()
		_:
			_unpin()


func _on_release() -> void:
	if _press_guest >= 0 and Time.get_ticks_msec() - _press_msec < 260:
		_toggle_pin(_press_guest)
	_press_guest = -1
	_stop_hold()


func _hint(text: String) -> void:
	if _screen != null and _screen.has_method(&"toast"):
		_screen.call(&"toast", text, &"warning", 2.2)
	AudioManager.play_sfx(&"error_buzz", 0.02, -8.0)


## While the voyage is paused the world is look-only: scrubbing, repairing and banishing are blocked (planning
## orders, selecting crew, tooltips and the camera still work). The tutorial pauses on purpose and unlocks exactly
## the spill / broken room it is asking about.
func _paused_blocks(kind: StringName, id: int) -> bool:
	if ctl == null or ctl.speed > 0:
		return false
	var tut: Variant = _screen.get(&"tutorial") if _screen != null else null
	if tut is TutorialDirector and (tut as TutorialDirector).allows_paused_action(kind, id):
		return false
	return true


func _paused_hint() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_paused_hint_msec < 2200:
		return
	_last_paused_hint_msec = now
	if _screen != null and _screen.has_method(&"toast"):
		_screen.call(&"toast", "Unpause to act!", &"pause", 1.6)
	AudioManager.play_sfx(&"error_buzz", 0.02, -10.0)


func _toggle_pin(gid: int) -> void:
	pinned_guest_id = -1 if pinned_guest_id == gid else gid
	selected_staff_id = -1
	_sync_renderer()
	selection_changed.emit()


func _unpin() -> void:
	if pinned_guest_id >= 0:
		pinned_guest_id = -1
		_sync_renderer()
		selection_changed.emit()


func _role_name(s: StaffMember) -> String:
	return s.def.display_name


## Sends crew to a crew quarters bunk, with a helpful hint when it can't.
func _order_rest(s: StaffMember, q: RoomRuntime) -> void:
	if s.energy >= 100.0:
		_hint("%s is fully rested." % _role_name(s))
		return
	if q.free_bunks() <= 0 and s.rest_uid != q.uid:
		_hint("All bunks are taken.")
		return
	_assign(s, &"rest", q.uid)


func _assign(s: StaffMember, kind: StringName, target_id: int) -> void:
	if world.assign_staff(s.id, kind, target_id):
		AudioManager.play_sfx(&"ui_click", 0.04, 0.0)
		cancel()
	else:
		AudioManager.play_sfx(&"error_buzz", 0.02, -4.0)


func _start_hold(uid: int) -> void:
	_hold_uid = uid
	ctl.hold_room_uid = uid
	ctl.paused_hold_ok = ctl.speed == 0   # only reachable while paused when the tutorial allowed it
	renderer.hold_room_uid = uid


func _stop_hold() -> void:
	if _hold_uid < 0:
		return
	_hold_uid = -1
	ctl.hold_room_uid = -1
	ctl.paused_hold_ok = false
	renderer.hold_room_uid = -1


# ---- per frame --------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if world == null or renderer == null:
		return
	if not enabled or world.finished:
		hover_kind = &""
		hover_id = -1
		_stop_hold()
		_push_hover()
		return
	if _hold_uid >= 0 and ctl.speed == 0:
		# paused mid-hold (Space): the repair stops, except for the tutorial's own hold
		ctl.paused_hold_ok = not _paused_blocks(&"room", _hold_uid)
		if not ctl.paused_hold_ok:
			_stop_hold()
	if _hold_uid >= 0:
		_hold_fx_t -= delta
		if _hold_fx_t <= 0.0 and not world.finished:
			_hold_fx_t = 0.3
			AudioManager.play_sfx(&"ui_click", 0.25, -9.0)
			var rc: Rect2 = renderer.room_rect(_hold_uid)
			renderer.fx.spawn(&"sparkle", rc.get_center() + Vector2(randf_range(-26.0, 26.0), randf_range(-16.0, 14.0)), 0.55, {"color": Palette.MINT})
		var r: RoomRuntime = world.room_by_uid(_hold_uid)
		var local: Vector2 = screen_to_local(mouse_screen)
		if r == null or not r.broken or renderer.room_at(local) != _hold_uid or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _synthetic_hold:
			_stop_hold()
	if selected_staff_id >= 0 and world.staff_by_id(selected_staff_id) == null:
		cancel()
	if pinned_guest_id >= 0:
		var pg: Guest = world.guest_by_id(pinned_guest_id)
		if pg == null or pg.state == Guest.GONE:
			_unpin()
	if over_world:
		var pk: Dictionary = renderer.pick(screen_to_local(mouse_screen))
		hover_kind = pk["kind"]
		hover_id = pk["id"]
	else:
		hover_kind = &""
		hover_id = -1
	if _roster_hover >= 0 and not over_world:
		hover_kind = &"staff"
		hover_id = _roster_hover
	_push_hover()
	_update_cursor()
	_update_path(delta)


## Self-tests inject events without a real pressed button; they set this so the hold is not cancelled.
var _synthetic_hold: bool = false

func set_synthetic_hold(v: bool) -> void:
	_synthetic_hold = v


func _push_hover() -> void:
	renderer.hover_kind = hover_kind
	renderer.hover_id = hover_id


func _update_cursor() -> void:
	var hand: bool = false
	match hover_kind:
		&"ghost", &"mess", &"staff", &"guest":
			hand = true
		&"room":
			var r: RoomRuntime = world.room_by_uid(hover_id)
			hand = r != null and r.broken
	if selected_staff_id >= 0 and hover_kind == &"":
		hand = false
	catcher.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hand else Control.CURSOR_ARROW


func _update_path(delta: float) -> void:
	if selected_staff_id < 0:
		return
	var s: StaffMember = world.staff_by_id(selected_staff_id)
	if s == null:
		return
	var td: int = -1
	var tx: float = 0.0
	var jk: StringName = s.job_kind()
	match hover_kind:
		&"mess":
			var m: Mess = world.mess_by_id(hover_id)
			if m != null and jk == &"mess":
				td = m.deck
				tx = m.x
		&"guest":
			var g: Guest = world.guest_by_id(hover_id)
			if g != null and g.is_ailing() and jk == &"sick":
				td = g.deck
				tx = g.x
		&"ghost":
			var gh: Ghost = world.ghost_by_id(hover_id)
			if gh != null and jk == &"ghost":
				td = gh.deck
				tx = clampf(gh.x, 0.5, float(world.grid.hull.width) - 0.5)
		&"room":
			var r: RoomRuntime = world.room_by_uid(hover_id)
			if r != null:
				var ok: bool = r.is_crew_quarters() and s.energy < 100.0 and r.free_bunks() > 0
				ok = ok or (jk == &"repair" and r.broken)
				ok = ok or (s.aura_kind() == &"perform" and r.def.is_service_room() and r.def.id != &"cabin")
				ok = ok or (s.aura_kind() == &"station" and r.def.category == &"food")
				if ok:
					td = r.deck
					tx = r.door_x
	_path_timer -= delta
	if td < 0:
		if _path_key != "":
			_path_key = ""
			renderer.path_points = PackedVector2Array()
		return
	var key: String = "%d:%d:%d" % [s.id, td, int(tx * 2.0)]
	if key == _path_key and _path_timer > 0.0:
		return
	_path_key = key
	_path_timer = 0.35
	renderer.path_points = _route_points(s, td, tx)


func _route_points(s: StaffMember, td: int, tx: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var off := Vector2(0, -7)
	var start_deck: int = int(round(s.deck_f))
	var w := Walker.new()
	w.set_position(start_deck, s.x)
	pts.append(SimConst.to_px(s.x, s.deck_f) + off)
	if not w.plan_route(world.grid, td, tx):
		pts.append(SimConst.to_px(tx, float(td)) + off)
		return pts
	var cur: int = start_deck
	for i in w.wp_mode.size():
		var wx: float = w.wp_x[i]
		var wd: int = w.wp_deck[i]
		pts.append(SimConst.to_px(wx, float(cur)) + off)
		if w.wp_mode[i] != 0 and wd != cur:
			pts.append(SimConst.to_px(wx, float(wd)) + off)
			cur = wd
	return pts
