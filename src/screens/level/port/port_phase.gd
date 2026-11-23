class_name PortPhase
extends Control
## The calm half of a level: lay out the ship within a budget, hire crew, read the manifest, set sail.
##
## Host contract (LevelScreen):
##   var phase := PortPhase.new()
##   hud_layer.add_child(phase)
##   phase.setup(level, port_state, ship_view, ship_camera)   # after add_child
##   phase.set_sail_requested.connect(...); phase.exit_requested.connect(...)
##   phase.teardown()                                          # before freeing / starting the voyage
## The host owns PortState, ShipView (it must refresh rooms on port.changed), ShipCamera, the sea and the top
## bar. PortPhase adds a Node2D to ship_view's "overlay" layer and moves the camera's bottom inset to follow
## the (collapsible) build bar; the top inset is read from the camera at setup() (or set `top_inset`).
##
## Interaction summary
##   card press/drag  -> placement tool, ghost snaps to cells, click/drop places; Shift keeps the tool armed
##   click a room     -> popover (Move / Upgrade / Sell); drag a room to move it; right-click / Esc cancels
##   Ctrl/Cmd+Z       -> undo (place / move / sell / upgrade / hire / fire)     Tab / 1-8 -> switch tabs

signal set_sail_requested
signal exit_requested
## Generic hook for tutorials / analytics. kinds: placed, moved, sold, upgraded, hired, fired, undone,
## armed, cancelled, tab, selected, sail_blocked, sail_confirm.
signal port_action(kind: StringName, data: Dictionary)

enum Mode { IDLE, PLACING, CARRYING }

const U := preload("res://src/render/art/art_util.gd")
const DRAG_PX: float = 9.0
const CONFIRM_PATH: String = "res://src/ui/overlays/confirm_dialog.gd"

## Screen px (1080 base) covered by the host's top bar. Set before setup().
var top_inset: float = 96.0

var _level: LevelDef
var _port: PortState
var _view: ShipView
var _cam: ShipCamera
var _overlay: PortOverlay
var _bar: PortBuildBar
var _popover: PortPopover
var _tooltip: PortTooltip
var _tag: PanelContainer
var _tag_icon: IconView
var _tag_label: Label
var _hint_pill: PanelContainer
var _hint_label: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_icon: IconView
var _errors_card: PanelContainer
var _dialog: Node = null
var _undo: PortUndo = PortUndo.new()

var _mode: Mode = Mode.IDLE
var _tool_id: StringName = &""
var _carry_uid: int = -1
var _selected_uid: int = -1
var _hover_uid: int = -1
var _press: Dictionary = {}
var _tgt: Dictionary = {}
var _tgt_key: Vector3i = Vector3i(-99, -99, -99)
var _version: int = 0
var _hint_version: int = -1
var _bad_decks: Array[int] = []
var _hl: Dictionary = {}
var _tip_timer: SceneTreeTimer = null
var _hovered_card: PortRoomCard = null
var _toast_tween: Tween
var _tag_valid: bool = true
var _hint_pill_on: bool = false
var _last_inset: float = -1.0
var _mouse_override: Vector2 = Vector2(-1, -1)
var _errors_tween: Tween
var _active: bool = false
var _last_shift: bool = false
## Test hook: drop pointer events that do not come from InputEvent.DEVICE_ID_EMULATION so the OS cursor
## cannot interleave with scripted events (PortSelfTest turns this on). It also makes _pointer_over_ui ignore
## the real-cursor-driven hovered control.
var swallow_real_pointer: bool = false
## Dev metric: microseconds the last _process() of this node took (excludes children).
var process_usec: int = 0
## Last pointer position seen in _input (viewport px). Real and synthetic events both update it.
var _event_mouse: Vector2 = Vector2.ZERO
var _have_event_mouse: bool = false


# ================================================================================================
# host API
# ================================================================================================
func setup(level: LevelDef, port: PortState, ship_view: ShipView, camera: ShipCamera) -> void:
	_level = level
	_port = port
	_view = ship_view
	_cam = camera
	# follow whatever top inset the host chose for its top bar
	var host_top: Variant = camera.get("_inset_t")
	if host_top is float and float(host_top) > 0.0:
		top_inset = float(host_top)
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay = PortOverlay.new()
	_overlay.name = "PortOverlay"
	_overlay.port = port
	_view.get_layer(&"overlay").add_child(_overlay)
	_build_ui()
	_port.changed.connect(_on_port_changed)
	_active = true
	_on_port_changed()
	_apply_insets(true)
	set_process(true)


func teardown() -> void:
	_active = false
	if _port != null and _port.changed.is_connected(_on_port_changed):
		_port.changed.disconnect(_on_port_changed)
	_cancel_mode(false)
	_deselect()
	if _view != null:
		for uid in _hl.keys():
			_view.set_room_state(int(uid), {"highlight": 0})
		_hl.clear()
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	set_process(false)


## Bottom edge helper for hosts that want to know how much room the build bar takes.
func bottom_inset() -> float:
	return _bar.occupied_height() + 6.0 if _bar != null else 0.0


# ---- scripting / tutorial / dev API ----------------------------------------------------------
func bar() -> PortBuildBar:
	return _bar


func popover() -> PortPopover:
	return _popover


func overlay() -> PortOverlay:
	return _overlay


func dialog_node() -> Node:
	return _dialog if _dialog_open() else null


func armed_room() -> StringName:
	return _tool_id if _mode == Mode.PLACING else &""


func is_carrying() -> bool:
	return _mode == Mode.CARRYING


func selected_uid() -> int:
	return _selected_uid


func undo_steps() -> int:
	return _undo.steps()


## Current placement target {deck, x, valid, reason, floating, rect} while a tool is armed / a room carried.
func debug_target() -> Dictionary:
	return _tgt.duplicate()


func local_to_screen(p: Vector2) -> Vector2:
	return _overlay.get_global_transform_with_canvas() * p


func screen_to_ship_local(p: Vector2) -> Vector2:
	return _overlay.get_global_transform_with_canvas().affine_inverse() * p


## Screen centre of a ship cell (deck, x) - handy for tutorials and tests.
func cell_to_screen(deck: int, x: float) -> Vector2:
	return local_to_screen(Vector2(x * SimConst.CELL_W, -(float(deck) + 0.5) * SimConst.DECK_H))


## Dev/test: pretend the mouse is here (screen px); (-1,-1) = use the real mouse.
func set_mouse_override(p: Vector2) -> void:
	_mouse_override = p


func select_tab(id: StringName) -> void:
	_bar.select_tab(id)


func arm_tool(room_id: StringName) -> bool:
	var def: RoomDef = ContentStore.room(room_id)
	if def == null:
		return false
	_arm(room_id)
	return _mode == Mode.PLACING


func select_room(uid: int) -> void:
	_select(uid)


func request_set_sail() -> void:
	_on_sail_pressed()


func request_back() -> void:
	_on_back_pressed()


func show_card_tooltip(room_id: StringName) -> void:
	var card: PortRoomCard = _bar.card_for(room_id)
	if card != null:
		_bar.select_tab(_bar.tab_of(room_id), false)
		_show_tooltip(card)


func set_bar_collapsed(c: bool) -> void:
	_bar.set_collapsed(c)


func show_toast(text: String, icon: StringName = &"star", color: Color = Palette.SUN) -> void:
	_toast_label.text = text
	_toast_icon.icon = icon
	_toast_label.add_theme_color_override("font_color", color)
	_toast.reset_size()
	_toast.visible = true
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_toast.pivot_offset = _toast.size * 0.5
	_toast.scale = Vector2(0.8, 0.8)
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.12)
	_toast_tween.parallel().tween_property(_toast, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


# ================================================================================================
# UI construction
# ================================================================================================
func _build_ui() -> void:
	_bar = PortBuildBar.new()
	_bar.name = "BuildBar"
	add_child(_bar)
	_bar.setup(_port)
	_bar.tab_changed.connect(func(t: StringName) -> void:
		_hide_tooltip()
		port_action.emit(&"tab", {"tab": t}))
	_bar.card_pressed.connect(_on_card_pressed)
	_bar.card_blocked.connect(_on_card_blocked)
	_bar.card_hovered.connect(_on_card_hovered)
	_bar.card_unhovered.connect(_on_card_unhovered)
	_bar.sail_pressed.connect(_on_sail_pressed)
	_bar.back_pressed.connect(_on_back_pressed)
	_bar.undo_pressed.connect(_do_undo)
	_bar.hire_requested.connect(_do_hire)
	_bar.fire_requested.connect(_do_fire)
	_bar.collapse_changed.connect(func(_c: bool) -> void: _hide_tooltip())

	# floating helpers (never block the mouse)
	_hint_pill = PanelContainer.new()
	_hint_pill.theme_type_variation = &"PillPanel"
	_hint_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"PillLabel"
	_hint_label.add_theme_font_size_override("font_size", 19)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_pill.add_child(_hint_label)
	_hint_pill.modulate.a = 0.0
	_hint_pill.visible = false
	add_child(_hint_pill)

	_tag = PanelContainer.new()
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.z_index = 60
	var th := UIKit.hbox(7)
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_icon = IconView.new()
	_tag_icon.icon = &"coin"
	_tag_icon.icon_size = 24.0
	th.add_child(_tag_icon)
	_tag_label = Label.new()
	_tag_label.add_theme_font_size_override("font_size", 20)
	_tag_label.add_theme_font_override("font", UITheme.font_bold())
	_tag_label.add_theme_color_override("font_color", Color.WHITE)
	_tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.add_child(_tag_label)
	_tag.add_child(th)
	_tag.visible = false
	add_child(_tag)
	_style_tag(true)

	_toast = PanelContainer.new()
	_toast.theme_type_variation = &"PillPanel"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tt := UIKit.hbox(8)
	tt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_icon = IconView.new()
	_toast_icon.icon_size = 26.0
	tt.add_child(_toast_icon)
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 21)
	_toast_label.add_theme_font_override("font", UITheme.font_bold())
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tt.add_child(_toast_label)
	_toast.add_child(tt)
	_toast.visible = false
	add_child(_toast)

	_errors_card = UIKit.card()
	_errors_card.visible = false
	_errors_card.z_index = 45
	_errors_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_errors_card.gui_input.connect(func(ev: InputEvent) -> void:
		var mbe := ev as InputEventMouseButton
		if mbe != null and mbe.pressed:
			_hide_errors())
	add_child(_errors_card)

	_popover = PortPopover.new()
	add_child(_popover)
	_popover.move_requested.connect(func(uid: int) -> void: _begin_carry(uid))
	_popover.upgrade_requested.connect(_do_upgrade)
	_popover.sell_requested.connect(_do_sell)

	_tooltip = PortTooltip.new()
	add_child(_tooltip)


func _style_tag(valid: bool) -> void:
	_tag_valid = valid
	var bg: Color = Color(0.12, 0.17, 0.27, 0.92) if valid else Palette.CORAL
	var edge: Color = Color(1, 1, 1, 0.18) if valid else Palette.CORAL_DARK
	_tag.add_theme_stylebox_override("panel", UITheme.flat(bg, 20, edge, 2, Color(0, 0, 0, 0.28), 8, Vector2(0, 3), Vector4(12, 6, 16, 7)))


# ================================================================================================
# per-frame
# ================================================================================================
func _mouse_screen() -> Vector2:
	if _mouse_override.x >= 0.0:
		return _mouse_override
	if _have_event_mouse:
		return _event_mouse
	return get_viewport().get_mouse_position()


func _mouse_local() -> Vector2:
	return screen_to_ship_local(_mouse_screen())


func _process(delta: float) -> void:
	if not _active:
		return
	var t0: int = Time.get_ticks_usec()
	_process_impl(delta)
	process_usec = Time.get_ticks_usec() - t0


func _process_impl(delta: float) -> void:
	_apply_insets(false)
	_overlay.zoom = _cam.zoom.x
	var m: Vector2 = _mouse_screen()
	var over_ui: bool = _pointer_over_ui(m)
	# drag detection
	if not _press.is_empty() and not bool(_press["dragging"]):
		if m.distance_to(_press["start"]) > DRAG_PX:
			_press["dragging"] = true
			if _press["src"] == &"room":
				var uid: int = int(_press["uid"])
				var room: PlacedRoom = _port.layout.get_room(uid)
				if room != null and room.locked:
					_buzz()
					show_toast("That room is part of the ship", &"lock", Palette.SUN)
					_press.clear()
				elif room != null:
					_begin_carry(uid)
	match _mode:
		Mode.PLACING, Mode.CARRYING:
			_update_placement(m, over_ui)
		_:
			_update_hover(m, over_ui)
	_update_floaters(m)
	_update_popover_position()
	_update_tooltip_position()


func _apply_insets(force: bool) -> void:
	var inset: float = bottom_inset()
	if force or absf(inset - _last_inset) > 0.5:
		_last_inset = inset
		_cam.set_insets(top_inset, inset)


func _pointer_over_ui(m: Vector2) -> bool:
	if _bar.get_global_rect().has_point(m):
		return true
	if _popover.visible and _popover.get_global_rect().has_point(m):
		return true
	if _errors_card.visible and _errors_card.get_global_rect().has_point(m):
		return true
	# gui_get_hovered_control() follows the real OS cursor. Harnesses (mouse override / swallowed real pointer)
	# drive the port with synthetic events instead, so for them only the geometric checks above count.
	if _mouse_override.x < 0.0 and not swallow_real_pointer:
		var hc: Control = get_viewport().gui_get_hovered_control()
		if hc != null and hc.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
	return false


func _dialog_open() -> bool:
	return _dialog != null and is_instance_valid(_dialog)


# ---- idle hover ----------------------------------------------------------------------------
func _room_under(local: Vector2) -> PlacedRoom:
	var cell: Vector2i = _view.cell_at_local(local)
	if cell.x < 0:
		return null
	return _port.layout.room_at(cell.y, cell.x)


func _update_hover(m: Vector2, over_ui: bool) -> void:
	var hov: int = -1
	var local: Vector2 = _mouse_local()
	if not over_ui and not _dialog_open() and (_press.is_empty() or not bool(_press["dragging"])):
		var r: PlacedRoom = _room_under(local)
		if r != null:
			hov = r.uid
	if hov != _hover_uid:
		if _hover_uid >= 0:
			_set_hl(_hover_uid, 2 if _hover_uid == _selected_uid else 0)
		_hover_uid = hov
		if hov >= 0 and hov != _selected_uid:
			_set_hl(hov, 1)
		_update_path_hint()
	_overlay.ghost_on = false
	_overlay.hints = []
	_overlay.origin_rect = Rect2()
	var lock_rect := Rect2()
	if _hover_uid >= 0:
		var hr: PlacedRoom = _port.layout.get_room(_hover_uid)
		if hr != null and hr.locked:
			lock_rect = SimConst.room_rect(hr.first_deck(), hr.x, hr.def.width, hr.decks_tall(_port.hull.decks))
	_overlay.hover_lock_rect = lock_rect
	if over_ui or _dialog_open():
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	elif _hover_uid >= 0:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _update_path_hint() -> void:
	_overlay.path_points = PackedVector2Array()
	if _hover_uid < 0 or _mode != Mode.IDLE:
		return
	var r: PlacedRoom = _port.layout.get_room(_hover_uid)
	if r == null or not r.is_stairs():
		return
	# faint route a guest would take from the gangway to the top of these stairs
	var g: WalkGraph = _port.grid.graph
	var gw: int = _port.hull.gangway_deck
	var a: int = g.node(gw, 0)
	var b: int = g.node(r.deck + 1, r.x)
	if not g.reachable(a, b):
		return
	var route: Array = g.route(a, b)
	var pts := PackedVector2Array()
	pts.append(SimConst.to_px(SimConst.GANGWAY_X, float(gw)) + Vector2(0, -6))
	for wp in route:
		var d: Dictionary = wp
		pts.append(SimConst.to_px(float(d["x"]), float(d["deck"])) + Vector2(0, -6))
	_overlay.path_points = pts


# ---- placement / carrying --------------------------------------------------------------------
func _current_def() -> RoomDef:
	if _mode == Mode.CARRYING:
		var r: PlacedRoom = _port.layout.get_room(_carry_uid)
		return r.def if r != null else null
	return ContentStore.room(_tool_id)


func _check(def: RoomDef, deck: int, x: int) -> Dictionary:
	if _mode == Mode.CARRYING:
		return _port.grid.can_move(_carry_uid, deck, x)
	return _port.can_place(def.id, deck, x)


func _compute_target(def: RoomDef, local: Vector2) -> Dictionary:
	var hull: HullDef = _port.hull
	var w: int = def.width
	var tall: int = def.decks_tall(hull.decks)
	var top: int = hull.decks - 1
	var deck_f: float = -local.y / SimConst.DECK_H
	var cx: float = local.x / SimConst.CELL_W
	var in_x: bool = cx > -1.5 and cx < float(hull.width) + 1.5
	var in_y: bool = deck_f > -0.7 and deck_f < float(hull.decks) + 0.7
	var size_v := Vector2(float(w) * SimConst.CELL_W, float(tall) * SimConst.DECK_H)
	if not (in_x and in_y):
		return {"floating": true, "valid": false, "reason": "", "deck": 0, "x": 0,
				"rect": Rect2(local - size_v * 0.5, size_v)}
	var x: int = clampi(roundi(cx - float(w) * 0.5), 0, hull.width - w)
	var deck: int = 0
	if def.is_elevator():
		deck = 0
	elif def.is_stairs():
		deck = clampi(roundi(deck_f - 1.0), 0, maxi(top - 1, 0))
	else:
		deck = clampi(floori(deck_f), 0, top)
	var res: Dictionary = _check(def, deck, x)
	var rect: Rect2 = SimConst.room_rect(deck, x, w, tall)
	return {"floating": false, "valid": bool(res["ok"]), "reason": String(res["reason"]), "deck": deck, "x": x, "rect": rect}


func _update_placement(m: Vector2, over_ui: bool) -> void:
	var def: RoomDef = _current_def()
	if def == null:
		_cancel_mode()
		return
	var local: Vector2 = _mouse_local()
	var hide_ghost: bool = over_ui or _dialog_open()
	if _hint_version != _version:
		_overlay.hints = _compute_hints(def)
		_hint_version = _version
		_tgt_key = Vector3i(-99, -99, -99)
	if hide_ghost:
		_overlay.ghost_on = false
		_tgt = {}
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	var key := Vector3i(floori(local.x / SimConst.CELL_W * 2.0), floori(-local.y / SimConst.DECK_H * 2.0), _version)
	var t: Dictionary = _compute_target(def, local)
	if bool(t["floating"]) or key != _tgt_key or _tgt.is_empty():
		_tgt = t
		_tgt_key = key
	else:
		# same snapped cell: keep the cached validity
		_tgt = t
	_overlay.ghost_on = true
	_overlay.ghost_room_id = def.id
	_overlay.ghost_tier = 1
	if _mode == Mode.CARRYING:
		var cr: PlacedRoom = _port.layout.get_room(_carry_uid)
		if cr != null:
			_overlay.ghost_tier = cr.tier + 1
			_overlay.origin_rect = SimConst.room_rect(cr.first_deck(), cr.x, cr.def.width, cr.decks_tall(_port.hull.decks))
	_overlay.ghost_rect = _tgt["rect"]
	_overlay.ghost_valid = bool(_tgt["valid"])
	_overlay.ghost_floating = bool(_tgt["floating"])
	_overlay.hover_lock_rect = Rect2()
	_overlay.path_points = PackedVector2Array()
	if bool(_tgt["floating"]):
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	elif bool(_tgt["valid"]):
		Input.set_default_cursor_shape(Input.CURSOR_CAN_DROP)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)


func _compute_hints(def: RoomDef) -> Array[Rect2]:
	var hull: HullDef = _port.hull
	var w: int = def.width
	var tall: int = def.decks_tall(hull.decks)
	var covered: Array[PackedByteArray] = []
	for d in hull.decks:
		var row := PackedByteArray()
		row.resize(hull.width)
		covered.append(row)
	var decks_to_try: Array[int] = []
	if def.is_elevator():
		decks_to_try.append(0)
	else:
		for d in hull.decks:
			decks_to_try.append(d)
	for d in decks_to_try:
		for x in range(0, hull.width - w + 1):
			if not bool(_check(def, d, x)["ok"]):
				continue
			for row in range(d, mini(d + tall, hull.decks)):
				for c in range(x, x + w):
					covered[row][c] = 1
	var out: Array[Rect2] = []
	for d in hull.decks:
		var c: int = 0
		while c < hull.width:
			if covered[d][c] != 0:
				var s: int = c
				while c < hull.width and covered[d][c] != 0:
					c += 1
				out.append(Rect2(float(s) * SimConst.CELL_W, -float(d + 1) * SimConst.DECK_H, float(c - s) * SimConst.CELL_W, SimConst.DECK_H))
			else:
				c += 1
	return out


# ---- floating helpers ------------------------------------------------------------------------
func _update_floaters(m: Vector2) -> void:
	var vp: Vector2 = get_viewport_rect().size
	# cursor tag
	var show_tag: bool = (_mode != Mode.IDLE) and _overlay.ghost_on and not _dialog_open()
	_tag.visible = show_tag
	if show_tag:
		var def: RoomDef = _current_def()
		var floating: bool = _overlay.ghost_floating
		var valid: bool = _overlay.ghost_valid
		if floating:
			_style_tag(true)
			_tag_icon.icon = &"guest"
			_tag_label.text = "Drop it on the ship"
		elif valid:
			_style_tag(true)
			if _mode == Mode.CARRYING:
				_tag_icon.icon = &"star"
				_tag_label.text = "Move here"
			else:
				_tag_icon.icon = &"coin"
				_tag_label.text = "$%d" % def.cost
		else:
			_style_tag(false)
			_tag_icon.icon = &"warning"
			_tag_label.text = String(_tgt.get("reason", "Can't go here"))
		_tag.reset_size()
		var tp: Vector2 = m + Vector2(26, 24)
		if tp.x + _tag.size.x > vp.x - 8.0:
			tp.x = m.x - 26.0 - _tag.size.x
		tp.y = clampf(tp.y, 8.0, vp.y - _tag.size.y - 8.0)
		_tag.position = tp
	# hint pill
	var want_pill: bool = _mode != Mode.IDLE
	if want_pill != _hint_pill_on:
		_hint_pill_on = want_pill
		var tw := create_tween()
		if want_pill:
			_hint_pill.visible = true
			tw.tween_property(_hint_pill, "modulate:a", 1.0, 0.18)
		else:
			tw.tween_property(_hint_pill, "modulate:a", 0.0, 0.14)
			tw.tween_callback(func() -> void:
				if not _hint_pill_on:
					_hint_pill.visible = false)
	if _hint_pill.visible:
		if _mode == Mode.CARRYING:
			_hint_label.text = "Click to drop it here     Right-click or Esc to put it back"
		else:
			_hint_label.text = "Click to place     Shift to keep building     Right-click or Esc to cancel"
		_hint_pill.reset_size()
		_hint_pill.position = Vector2((vp.x - _hint_pill.size.x) * 0.5, _bar.global_position.y - _hint_pill.size.y - 16.0)
	# toast
	if _toast.visible:
		_toast.position = Vector2((vp.x - _toast.size.x) * 0.5, top_inset + 14.0)
	# errors card sits above the sail button
	if _errors_card.visible:
		_errors_card.reset_size()
		var r: Rect2 = _bar.sail_button.get_global_rect()
		_errors_card.position = Vector2(clampf(r.end.x - _errors_card.size.x, 8.0, vp.x - _errors_card.size.x - 8.0), _bar.global_position.y - _errors_card.size.y - 14.0)


func _update_popover_position() -> void:
	if not _popover.is_open():
		return
	var room: PlacedRoom = _port.layout.get_room(_popover.uid)
	if room == null:
		_popover.close()
		return
	var rect: Rect2 = SimConst.room_rect(room.first_deck(), room.x, room.def.width, room.decks_tall(_port.hull.decks))
	var top: Vector2 = local_to_screen(Vector2(rect.get_center().x, rect.position.y))
	var bottom: Vector2 = local_to_screen(Vector2(rect.get_center().x, rect.end.y))
	var vp: Vector2 = get_viewport_rect().size
	var ps: Vector2 = _popover.size
	var x: float = clampf(top.x - ps.x * 0.5, 10.0, vp.x - ps.x - 10.0)
	var above_y: float = top.y - ps.y - 6.0
	var bar_top: float = _bar.global_position.y
	var flip: bool = above_y < top_inset + 4.0
	var y: float = above_y
	if flip:
		y = bottom.y + 6.0
		if y + ps.y > bar_top - 4.0:
			# nowhere to go: sit over the room's top edge but stay on screen
			flip = false
			y = clampf(above_y, top_inset + 4.0, bar_top - ps.y - 4.0)
	_popover.set_flipped(flip)
	_popover.set_tail_x(top.x - x)
	_popover.position = Vector2(x, y)


# ================================================================================================
# selection / highlight
# ================================================================================================
func _set_hl(uid: int, level: int) -> void:
	if int(_hl.get(uid, 0)) == level:
		return
	_hl[uid] = level
	_view.set_room_state(uid, {"highlight": level})


func _select(uid: int) -> void:
	_hide_errors()
	if _selected_uid >= 0 and _selected_uid != uid:
		_set_hl(_selected_uid, 0)
	var room: PlacedRoom = _port.layout.get_room(uid)
	if room == null:
		_deselect()
		return
	_selected_uid = uid
	_set_hl(uid, 2)
	_popover.open_for(_port, uid)
	port_action.emit(&"selected", {"uid": uid, "room_id": room.def.id})


func _deselect() -> void:
	if _selected_uid >= 0:
		_set_hl(_selected_uid, 1 if _hover_uid == _selected_uid else 0)
	_selected_uid = -1
	if _popover != null:
		_popover.close()


# ================================================================================================
# tool state
# ================================================================================================
func _arm(room_id: StringName) -> void:
	_deselect()
	_hide_tooltip()
	_hide_errors()
	if _mode == Mode.CARRYING:
		_cancel_mode(false)
	_mode = Mode.PLACING
	_tool_id = room_id
	_carry_uid = -1
	_hint_version = -1
	var tab: StringName = _bar.tab_of(room_id)
	if _bar.current_tab != tab:
		_bar.select_tab(tab, false)
	_bar.set_armed(room_id)
	_update_preview()
	port_action.emit(&"armed", {"room_id": room_id})


func _begin_carry(uid: int) -> void:
	var room: PlacedRoom = _port.layout.get_room(uid)
	if room == null:
		return
	if room.locked:
		_buzz()
		return
	_hide_errors()
	_cancel_mode(false)
	_deselect()
	_mode = Mode.CARRYING
	_carry_uid = uid
	_tool_id = room.def.id
	_hint_version = -1
	_bar.set_armed(&"")
	_bar.set_preview(0, 0)
	AudioManager.play_sfx(&"ui_click")


func _cancel_mode(emit_signal: bool = true) -> void:
	var was: Mode = _mode
	_mode = Mode.IDLE
	_tool_id = &""
	_carry_uid = -1
	_tgt = {}
	_hint_version = -1
	if _overlay != null:
		_overlay.ghost_on = false
		_overlay.hints = []
		_overlay.origin_rect = Rect2()
	if _bar != null:
		_bar.set_armed(&"")
		_update_preview()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if emit_signal and was != Mode.IDLE:
		port_action.emit(&"cancelled", {})


func _update_preview() -> void:
	var def: RoomDef = null
	if _mode == Mode.PLACING:
		def = ContentStore.room(_tool_id)
	elif _hovered_card != null:
		def = _hovered_card.def
	var pcard: PortRoomCard = _bar.card_for(def.id) if def != null else null   # null: not in this level's catalog
	if pcard != null and not pcard.is_locked():
		_bar.set_preview(def.power, def.water)
	else:
		_bar.set_preview(0, 0)


# ================================================================================================
# cards
# ================================================================================================
func _on_card_pressed(room_id: StringName) -> void:
	_hide_tooltip()
	var was_same: bool = _mode == Mode.PLACING and _tool_id == room_id
	_press = {"src": &"card", "id": room_id, "start": _mouse_screen(), "dragging": false, "was_same": was_same}
	if not was_same:
		_arm(room_id)
		AudioManager.play_sfx(&"ui_click")
		var card: PortRoomCard = _bar.card_for(room_id)
		if card != null:
			card.pop()


func _on_card_blocked(room_id: StringName, reason: String) -> void:
	_buzz()
	_show_tooltip(_bar.card_for(room_id))
	if reason == "Not enough money":
		show_toast("Not enough money", &"coin", Palette.CORAL_LIGHT)
	else:
		show_toast(reason, &"lock", Palette.SUN)


func _on_card_hovered(card: PortRoomCard) -> void:
	_hovered_card = card
	if _mode == Mode.IDLE or _tool_id != card.def.id:
		AudioManager.play_sfx(&"ui_hover")
	_update_preview()
	if _tip_timer != null:
		_tip_timer.timeout.disconnect(_on_tip_timer)
	_tip_timer = get_tree().create_timer(0.22)
	_tip_timer.timeout.connect(_on_tip_timer)


func _on_card_unhovered(card: PortRoomCard) -> void:
	if _hovered_card == card:
		_hovered_card = null
	_update_preview()
	_hide_tooltip()


func _on_tip_timer() -> void:
	_tip_timer = null
	if _hovered_card != null and _press.is_empty():
		_show_tooltip(_hovered_card)


func _show_tooltip(card: PortRoomCard) -> void:
	if card == null:
		return
	_tooltip.fill(card.def, card.lock_reason, _port.hull.decks)
	_tooltip.set_meta(&"card", card)
	_update_tooltip_position()


func _hide_tooltip() -> void:
	if _tip_timer != null:
		if _tip_timer.timeout.is_connected(_on_tip_timer):
			_tip_timer.timeout.disconnect(_on_tip_timer)
		_tip_timer = null
	_tooltip.hide_tip()


func _update_tooltip_position() -> void:
	if not _tooltip.visible:
		return
	var card: PortRoomCard = _tooltip.get_meta(&"card", null) as PortRoomCard
	if card == null or not is_instance_valid(card):
		_tooltip.hide_tip()
		return
	var r: Rect2 = card.get_global_rect()
	var vp: Vector2 = get_viewport_rect().size
	var ts: Vector2 = _tooltip.size
	var x: float = clampf(r.get_center().x - ts.x * 0.5, 10.0, vp.x - ts.x - 10.0)
	var y: float = _bar.global_position.y - ts.y - 10.0
	if y < top_inset:
		y = top_inset
	_tooltip.position = Vector2(x, y)


# ================================================================================================
# input
# ================================================================================================
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not swallow_real_pointer:
		_press.clear()


func _input(event: InputEvent) -> void:
	var em := event as InputEventMouse
	if swallow_real_pointer and em != null and em.device != InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()
		return
	if em != null:
		_event_mouse = em.position
		_have_event_mouse = true
	if not _active or _dialog_open():
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if _mode != Mode.IDLE:
			_cancel_mode()
			_press.clear()
			get_viewport().set_input_as_handled()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not _press.is_empty():
		_finish_press(mb)


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _dialog_open():
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_on_ship_press(mb)
		return
	var ke := event as InputEventKey
	if ke != null and ke.pressed and not ke.echo:
		if ke.keycode == KEY_Z and ke.is_command_or_control_pressed() and not ke.shift_pressed:
			_do_undo()
			get_viewport().set_input_as_handled()
			return
		if ke.keycode == KEY_TAB:
			_bar.set_collapsed(false)
			_bar.cycle_tab(-1 if ke.shift_pressed else 1)
			get_viewport().set_input_as_handled()
			return
		if ke.keycode >= KEY_1 and ke.keycode <= KEY_8 and not ke.ctrl_pressed and not ke.meta_pressed and not ke.alt_pressed:
			var idx: int = ke.keycode - KEY_1
			if idx < PortBuildBar.TABS.size():
				_bar.set_collapsed(false)
				_bar.select_tab(PortBuildBar.TABS[idx]["id"])
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed(&"cancel"):
		if _mode != Mode.IDLE:
			_cancel_mode()
			_press.clear()
			get_viewport().set_input_as_handled()
		elif _popover.is_open():
			_deselect()
			get_viewport().set_input_as_handled()
		elif _errors_card.visible:
			_hide_errors()
			get_viewport().set_input_as_handled()


func _on_ship_press(mb: InputEventMouseButton) -> void:
	_last_shift = mb.shift_pressed
	_hide_errors()
	if _mode != Mode.IDLE:
		if _tgt.is_empty():
			return
		_commit_current(mb.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	var r: PlacedRoom = _room_under(_mouse_local())
	if r != null:
		_press = {"src": &"room", "uid": r.uid, "start": _mouse_screen(), "dragging": false}
		get_viewport().set_input_as_handled()
	else:
		_deselect()


func _finish_press(mb: InputEventMouseButton) -> void:
	var p: Dictionary = _press
	_press = {}
	var over_ui: bool = _pointer_over_ui(_mouse_screen())
	if p["src"] == &"card":
		if bool(p["dragging"]):
			if over_ui or _tgt.is_empty():
				_cancel_mode()
			elif not _commit_current(mb.shift_pressed, true):
				_cancel_mode()
		elif bool(p["was_same"]):
			_cancel_mode()
	elif p["src"] == &"room":
		if bool(p["dragging"]) and _mode == Mode.CARRYING:
			if over_ui or _tgt.is_empty():
				_cancel_mode()
			elif not _commit_current(false, true):
				_cancel_mode()
		elif not bool(p["dragging"]):
			var uid: int = int(p["uid"])
			if uid == _selected_uid:
				_deselect()
			else:
				_select(uid)


# ================================================================================================
# actions
# ================================================================================================
func _commit_current(keep_armed: bool, from_drag: bool = false) -> bool:
	if _tgt.is_empty() or bool(_tgt["floating"]) or not bool(_tgt["valid"]):
		_buzz()
		return false
	var deck: int = int(_tgt["deck"])
	var x: int = int(_tgt["x"])
	if _mode == Mode.PLACING:
		var id: StringName = _tool_id
		var ok: bool = _do_place(id, deck, x)
		if ok:
			if keep_armed:
				var def: RoomDef = ContentStore.room(id)
				if def.cost > _port.budget:
					_cancel_mode(false)
					show_toast("Out of budget", &"coin", Palette.CORAL_LIGHT)
					port_action.emit(&"cancelled", {})
				else:
					_hint_version = -1
			else:
				_cancel_mode(false)
		return ok
	elif _mode == Mode.CARRYING:
		var uid: int = _carry_uid
		var ok2: bool = _do_move(uid, deck, x)
		if ok2:
			_cancel_mode(false)
			if not from_drag:
				_select(uid)
		return ok2
	return false


func _room_rect_of(r: PlacedRoom) -> Rect2:
	return SimConst.room_rect(r.first_deck(), r.x, r.def.width, r.decks_tall(_port.hull.decks))


func _do_place(room_id: StringName, deck: int, x: int) -> bool:
	var def: RoomDef = ContentStore.room(room_id)
	_undo.push(_port, "Place %s" % def.display_name)
	var r: PlacedRoom = _port.place(room_id, deck, x)
	if r == null:
		_undo.drop_last()
		_buzz()
		return false
	AudioManager.play_sfx(&"place")
	var rect: Rect2 = _room_rect_of(r)
	_overlay.fx_place(rect)
	_overlay.fx_text(Vector2(rect.get_center().x, rect.position.y + 14.0), "-$%d" % def.cost, Palette.SUN)
	_overlay.fx_coin(Vector2(rect.get_center().x + 26.0, rect.position.y + 22.0))
	_pop_room(r.uid, 1.0)
	_cam.shake(1.4, 0.14)
	port_action.emit(&"placed", {"room_id": room_id, "uid": r.uid, "deck": deck, "x": x})
	return true


func _do_move(uid: int, deck: int, x: int) -> bool:
	var room: PlacedRoom = _port.layout.get_room(uid)
	if room == null:
		return false
	_undo.push(_port, "Move %s" % room.def.display_name)
	if not _port.move(uid, deck, x):
		_undo.drop_last()
		_buzz()
		return false
	AudioManager.play_sfx(&"place")
	var rect: Rect2 = _room_rect_of(room)
	_overlay.fx_place(rect)
	_pop_room(uid, 0.8)
	port_action.emit(&"moved", {"uid": uid, "room_id": room.def.id, "deck": deck, "x": x})
	return true


func _do_sell(uid: int) -> void:
	var room: PlacedRoom = _port.layout.get_room(uid)
	if room == null:
		return
	var rect: Rect2 = _room_rect_of(room)
	var name_s: String = room.def.display_name
	var id: StringName = room.def.id
	_undo.push(_port, "Sell %s" % name_s)
	var refund: int = _port.sell(uid)
	if refund < 0:
		_undo.drop_last()
		_buzz()
		return
	_deselect()
	_hl.erase(uid)
	AudioManager.play_sfx(&"sell")
	_overlay.fx_poof(rect)
	_overlay.fx_text(Vector2(rect.get_center().x, rect.position.y + 14.0), "+$%d" % refund, Palette.MINT)
	port_action.emit(&"sold", {"uid": uid, "room_id": id, "refund": refund})


func _do_upgrade(uid: int) -> void:
	var room: PlacedRoom = _port.layout.get_room(uid)
	if room == null:
		return
	var cost: int = _port.grid.upgrade_cost(uid)
	var chk: Dictionary = _port.grid.can_upgrade(uid)
	if not bool(chk["ok"]):
		_buzz()
		show_toast(String(chk["reason"]), &"lock", Palette.SUN)
		return
	_undo.push(_port, "Upgrade %s" % room.def.display_name)
	if not _port.upgrade(uid):
		_undo.drop_last()
		_buzz()
		return
	AudioManager.play_sfx(&"upgrade")
	var rect: Rect2 = _room_rect_of(room)
	_overlay.fx_upgrade(rect)
	_overlay.fx_text(Vector2(rect.get_center().x, rect.position.y + 14.0), "-$%d" % cost, Palette.SUN)
	_pop_room(uid, 1.1)
	_cam.shake(1.8, 0.16)
	port_action.emit(&"upgraded", {"uid": uid, "room_id": room.def.id, "tier": room.tier})


func _do_hire(role: StringName) -> void:
	var chk: Dictionary = _port.can_hire(role)
	if not bool(chk["ok"]):
		_buzz()
		show_toast(String(chk["reason"]), &"staff", Palette.CORAL_LIGHT)
		return
	_undo.push(_port, "Hire %s" % ContentStore.staff_role(role).display_name)
	if _port.hire(role):
		AudioManager.play_sfx(&"hire")
		port_action.emit(&"hired", {"role": role})
	else:
		_undo.drop_last()
		_buzz()


func _do_fire(role: StringName) -> void:
	if int(_port.hired.get(role, 0)) <= 0:
		_buzz()
		return
	_undo.push(_port, "Dismiss %s" % ContentStore.staff_role(role).display_name)
	if _port.fire(role):
		AudioManager.play_sfx(&"sell")
		port_action.emit(&"fired", {"role": role})
	else:
		_undo.drop_last()


func _do_undo() -> void:
	if not _undo.can_undo():
		_buzz()
		show_toast("Nothing to undo", &"clock", Palette.SUN)
		return
	_cancel_mode(false)
	_deselect()
	var label: String = _undo.undo(_port)
	AudioManager.play_sfx(&"ui_click")
	show_toast("Undid: %s" % label, &"clock", Palette.CREAM)
	port_action.emit(&"undone", {"label": label})


func _buzz() -> void:
	AudioManager.play_sfx(&"error_buzz")


## Squash-and-stretch "thunk" on a freshly placed / moved / upgraded room.
func _pop_room(uid: int, strength: float) -> void:
	await get_tree().process_frame
	if not _active or _view == null:
		return
	var rect: Rect2 = _view.room_rect(uid)
	if rect.size.x <= 0.0:
		return
	var nodes: Array[Node2D] = []
	for layer in [&"rooms_back", &"rooms_front"]:
		for c in _view.get_layer(layer).get_children():
			var n := c as Node2D
			if n != null and n.get("rect") == rect:
				nodes.append(n)
	if nodes.is_empty():
		return
	var pivot := Vector2(rect.get_center().x, rect.end.y)
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		var e: float = exp(-5.5 * k) * cos(k * 10.5)
		var s := Vector2(1.0 + 0.09 * e * strength, 1.0 - 0.20 * e * strength)
		for n2 in nodes:
			if is_instance_valid(n2):
				n2.scale = s
				n2.position = pivot - Vector2(pivot.x * s.x, pivot.y * s.y)
		, 0.0, 1.0, 0.5)
	tw.tween_callback(func() -> void:
		for n3 in nodes:
			if is_instance_valid(n3):
				n3.scale = Vector2.ONE
				n3.position = Vector2.ZERO)


# ================================================================================================
# state refresh
# ================================================================================================
func _on_port_changed() -> void:
	if not _active:
		return
	_version += 1
	_bar.refresh()
	_popover.refresh()
	if _selected_uid >= 0 and _port.layout.get_room(_selected_uid) == null:
		_selected_uid = -1
		_popover.close()
	if _hover_uid >= 0 and _port.layout.get_room(_hover_uid) == null:
		_hover_uid = -1
	for uid in _hl.keys():
		if _port.layout.get_room(int(uid)) == null:
			_hl.erase(uid)
	if _mode == Mode.CARRYING and _port.layout.get_room(_carry_uid) == null:
		_cancel_mode(false)
	_recompute_bad_decks()
	_update_status()
	_bar.set_undo_enabled(_undo.can_undo())
	_update_preview()


func _recompute_bad_decks() -> void:
	var reach: Array[int] = _port.grid.graph.reachable_decks(_port.hull.gangway_deck)
	var bad: Array[int] = []
	for r in _port.layout.rooms:
		if r.is_transport():
			continue
		if not reach.has(r.deck) and not bad.has(r.deck):
			bad.append(r.deck)
	bad.sort()
	_bad_decks = bad
	if _overlay != null:
		_overlay.bad_decks = bad


static func _short(msg: String) -> String:
	var cut: int = msg.length()
	for ch in [":", "."]:
		var i: int = msg.find(ch)
		if i >= 0:
			cut = mini(cut, i)
	return msg.substr(0, cut)


func _update_status() -> void:
	var v: Dictionary = _port.validate()
	var errors: Array = v["errors"]
	var warnings: Array = v["warnings"]
	if errors.size() > 0:
		var extra: String = "" if errors.size() == 1 else " · +%d more error%s" % [errors.size() - 1, "" if errors.size() == 2 else "s"]
		_bar.set_status(_short(String(errors[0])) + extra, Palette.CORAL_LIGHT)
	elif warnings.size() > 0:
		var extra2: String = "" if warnings.size() == 1 else " · +%d more warning%s" % [warnings.size() - 1, "" if warnings.size() == 2 else "s"]
		_bar.set_status(_short(String(warnings[0])) + extra2, Palette.SUN)
	else:
		_bar.set_status("All set. Ready to sail!", Palette.MINT)


# ================================================================================================
# set sail / back
# ================================================================================================
func _on_sail_pressed() -> void:
	if _mode != Mode.IDLE:
		_cancel_mode()
	_deselect()
	var v: Dictionary = _port.validate()
	var errors: Array = v["errors"]
	var warnings: Array = v["warnings"]
	if errors.size() > 0:
		_buzz()
		_bar.shake_sail()
		_show_errors(errors)
		_overlay.flash_decks = _bad_decks.duplicate()
		_overlay.flash_time = 4.0
		port_action.emit(&"sail_blocked", {"errors": errors})
		return
	if warnings.size() > 0:
		_ask("Set sail anyway?", warnings, "Set sail", "Keep building", false, _do_sail)
		return
	_do_sail()


## The host plays the horn and runs the transition; we only announce the decision.
func _do_sail() -> void:
	port_action.emit(&"sail_confirm", {})
	set_sail_requested.emit()


func _on_back_pressed() -> void:
	if _mode != Mode.IDLE:
		_cancel_mode()
	if _undo.can_undo():
		_ask("Leave port?", ["Your changes to the ship will be lost."], "Leave", "Stay", true, func() -> void: exit_requested.emit())
	else:
		exit_requested.emit()


## Confirm dialog: the shared ConfirmDialog (src/ui/overlays) when present, else our own PortDialog.
func _ask(title: String, lines: Array, confirm_text: String, cancel_text: String, danger: bool, on_yes: Callable) -> void:
	var script: Script = null
	if ResourceLoader.exists(CONFIRM_PATH):
		script = load(CONFIRM_PATH)
	if script != null and script.has_method(&"present"):
		var body: String = "\n".join(PackedStringArray(lines))
		var d: Node = script.call(&"present", self, title, body, confirm_text, cancel_text, danger)
		_dialog = d
		d.connect(&"confirmed", func(ok: bool) -> void:
			_dialog = null
			if ok:
				on_yes.call())
		return
	var pd: PortDialog = PortDialog.ask(self, title, lines, confirm_text, cancel_text, &"warning", danger)
	_dialog = pd
	pd.confirmed.connect(func() -> void:
		_dialog = null
		on_yes.call())
	pd.cancelled.connect(func() -> void: _dialog = null)


func _show_errors(errors: Array) -> void:
	for c in _errors_card.get_children():
		_errors_card.remove_child(c)
		c.queue_free()
	var v := UIKit.vbox(8)
	_errors_card.add_child(v)
	var head := UIKit.hbox(10)
	var ic := IconView.new()
	ic.icon = &"warning"
	ic.icon_size = 34.0
	ic.animate = true
	head.add_child(ic)
	head.add_child(UIKit.header_label("Can't set sail yet"))
	v.add_child(head)
	for e in errors:
		var l := Label.new()
		l.text = String(e)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(380, 0)
		l.add_theme_color_override("font_color", Palette.CORAL_DARK)
		l.add_theme_font_size_override("font_size", 20)
		v.add_child(l)
	_errors_card.reset_size()
	_errors_card.visible = true
	_errors_card.pivot_offset = Vector2(_errors_card.size.x * 0.8, _errors_card.size.y)
	_errors_card.modulate.a = 0.0
	_errors_card.scale = Vector2(0.85, 0.85)
	if _errors_tween != null and _errors_tween.is_valid():
		_errors_tween.kill()
	_errors_tween = create_tween()
	_errors_tween.tween_property(_errors_card, "modulate:a", 1.0, 0.12)
	_errors_tween.parallel().tween_property(_errors_card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_errors_tween.tween_interval(6.0)
	_errors_tween.tween_property(_errors_card, "modulate:a", 0.0, 0.3)
	_errors_tween.tween_callback(func() -> void: _errors_card.visible = false)


func _hide_errors() -> void:
	if _errors_card != null and _errors_card.visible:
		if _errors_tween != null and _errors_tween.is_valid():
			_errors_tween.kill()
		_errors_card.visible = false
