class_name ShipCamera
extends Camera2D
## Camera for the ship scene (port + voyage). The ship lives in world coordinates (ShipView at origin).
##
## API
##   set_ship_rect(r: Rect2)                       # ship-local bounds incl. hull + superstructure
##   set_insets(top, bottom, left := 0, right := 0) # screen px (1080 base) covered by HUD
##   fit() / zoom_in() / zoom_out() / set_zoom_level(i: int)    # level 0 = fit whole ship, 1, 2 = closer
##   var zoom_level: int
##   focus_on(local_pos: Vector2, level := -1)     # smooth pan (and optional zoom level)
##   local_to_screen(p: Vector2) -> Vector2 / screen_to_local(p: Vector2) -> Vector2
##   shake(amount := 3.0, duration := 0.25)        # tiny camera shake (breakdowns)
##   var shake_enabled: bool
##   signal view_changed
## Input: mouse wheel (zoom to cursor), +/- keys (or zoom_in/zoom_out actions if they exist), middle-drag pan,
## pan_left/right/up/down actions if they exist. Uses _unhandled_input so UI gets events first.

signal view_changed

const MAX_ZOOM: float = 3.5
const MARGIN_PX: float = 28.0
const KEY_PAN_SPEED: float = 760.0

var zoom_level: int = 0
var shake_enabled: bool = true

var _ship_rect: Rect2 = Rect2(-60, -480, 1400, 620)
var _inset_t: float = 100.0
var _inset_b: float = 220.0
var _inset_l: float = 0.0
var _inset_r: float = 0.0
var _focus_target: Vector2 = Vector2.ZERO     # ship-local point shown at the centre of the free area
var _focus_cur: Vector2 = Vector2.ZERO
var _zoom_target: float = 1.0
var _zoom_cur: float = 1.0
var _snap: bool = true
var _dragging: bool = false
var _shake_t: float = 0.0
var _shake_dur: float = 0.0
var _shake_amp: float = 0.0
var _last_view: Vector4 = Vector4.ZERO


func _ready() -> void:
	position_smoothing_enabled = false
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	make_current()
	get_viewport().size_changed.connect(_on_resized)
	_recompute(true)


func _on_resized() -> void:
	_recompute(false)


# ---- public API ---------------------------------------------------------------------------------
func set_ship_rect(r: Rect2) -> void:
	_ship_rect = r
	_recompute(false)


func set_insets(top: float, bottom: float, left: float = 0.0, right: float = 0.0) -> void:
	_inset_t = top
	_inset_b = bottom
	_inset_l = left
	_inset_r = right
	_recompute(false)


func fit() -> void:
	set_zoom_level(0)


func zoom_in() -> void:
	set_zoom_level(zoom_level + 1)


func zoom_out() -> void:
	set_zoom_level(zoom_level - 1)


func set_zoom_level(i: int) -> void:
	zoom_level = clampi(i, 0, 2)
	_zoom_target = _level_zoom(zoom_level)
	_focus_target = _clamp_focus(_focus_target, _zoom_target)
	_emit_if_changed()


func focus_on(local_pos: Vector2, level: int = -1) -> void:
	if level >= 0:
		zoom_level = clampi(level, 0, 2)
		_zoom_target = _level_zoom(zoom_level)
	_focus_target = _clamp_focus(local_pos, _zoom_target)


func local_to_screen(p: Vector2) -> Vector2:
	return (p - (position + offset)) * zoom.x + _view_size() * 0.5


func screen_to_local(p: Vector2) -> Vector2:
	return (p - _view_size() * 0.5) / zoom.x + position + offset


func shake(amount: float = 3.0, duration: float = 0.25) -> void:
	if not shake_enabled:
		return
	_shake_amp = maxf(_shake_amp * clampf(_shake_t / maxf(_shake_dur, 0.01), 0.0, 1.0), amount)
	_shake_dur = duration
	_shake_t = duration


# ---- layout math --------------------------------------------------------------------------------
func _view_size() -> Vector2:
	return get_viewport_rect().size


func _free_area() -> Rect2:
	var v: Vector2 = _view_size()
	return Rect2(_inset_l, _inset_t, maxf(v.x - _inset_l - _inset_r, 100.0), maxf(v.y - _inset_t - _inset_b, 100.0))


func _fit_zoom() -> float:
	var a: Rect2 = _free_area()
	var zx: float = (a.size.x - MARGIN_PX * 2.0) / maxf(_ship_rect.size.x, 1.0)
	var zy: float = (a.size.y - MARGIN_PX * 2.0) / maxf(_ship_rect.size.y, 1.0)
	return clampf(minf(zx, zy), 0.2, MAX_ZOOM * 0.6)


func _level_zoom(level: int) -> float:
	var f: float = _fit_zoom()
	var z1: float = maxf(f * 1.7, 1.0)
	var z2: float = minf(maxf(z1 * 1.7, 2.0), MAX_ZOOM)
	if z2 < z1 * 1.6:
		z1 = z2 / 1.7
	if level <= 0:
		return f
	if level == 1:
		return z1
	return z2


func _clamp_focus(f: Vector2, z: float) -> Vector2:
	var a: Rect2 = _free_area()
	var vis: Vector2 = a.size / z
	var r: Rect2 = _ship_rect.grow(MARGIN_PX / z)
	var out := f
	if vis.x >= r.size.x:
		out.x = r.get_center().x
	else:
		out.x = clampf(f.x, r.position.x + vis.x * 0.5, r.end.x - vis.x * 0.5)
	if vis.y >= r.size.y:
		out.y = r.get_center().y
	else:
		out.y = clampf(f.y, r.position.y + vis.y * 0.5, r.end.y - vis.y * 0.5)
	return out


## offset between the free-area centre and the viewport centre, in screen px
func _area_shift() -> Vector2:
	var a: Rect2 = _free_area()
	return a.get_center() - _view_size() * 0.5


func _recompute(snap: bool) -> void:
	_zoom_target = _level_zoom(zoom_level)
	_focus_target = _clamp_focus(_focus_target if not snap else _ship_rect.get_center(), _zoom_target)
	if snap or _snap:
		_snap = false
		_zoom_cur = _zoom_target
		_focus_cur = _focus_target
		_apply()


func _apply() -> void:
	zoom = Vector2(_zoom_cur, _zoom_cur)
	position = _focus_cur - _area_shift() / _zoom_cur
	_emit_if_changed()


func _emit_if_changed() -> void:
	var v := Vector4(position.x, position.y, zoom.x, 0.0)
	if not v.is_equal_approx(_last_view):
		_last_view = v
		view_changed.emit()


# ---- per frame ----------------------------------------------------------------------------------
func _process(dt: float) -> void:
	# keyboard pan via InputMap actions (only if they exist)
	var pan := Vector2.ZERO
	if InputMap.has_action(&"pan_left") and Input.is_action_pressed(&"pan_left"):
		pan.x -= 1.0
	if InputMap.has_action(&"pan_right") and Input.is_action_pressed(&"pan_right"):
		pan.x += 1.0
	if InputMap.has_action(&"pan_up") and Input.is_action_pressed(&"pan_up"):
		pan.y -= 1.0
	if InputMap.has_action(&"pan_down") and Input.is_action_pressed(&"pan_down"):
		pan.y += 1.0
	if pan != Vector2.ZERO:
		_focus_target = _clamp_focus(_focus_target + pan.normalized() * KEY_PAN_SPEED * dt / _zoom_cur, _zoom_target)
	# smoothing (exponential, frame-rate independent)
	var kz: float = 1.0 - exp(-dt * 9.0)
	var kp: float = 1.0 - exp(-dt * 10.0)
	_zoom_cur = exp(lerpf(log(_zoom_cur), log(_zoom_target), kz))
	if absf(_zoom_cur - _zoom_target) < 0.0004:
		_zoom_cur = _zoom_target
	_focus_cur = _focus_cur.lerp(_focus_target, kp)
	if _focus_cur.distance_squared_to(_focus_target) < 0.01:
		_focus_cur = _focus_target
	_apply()
	# shake
	if _shake_t > 0.0:
		_shake_t = maxf(0.0, _shake_t - dt)
		var k: float = _shake_t / maxf(_shake_dur, 0.01)
		var tt: float = Time.get_ticks_msec() * 0.001
		offset = Vector2(sin(tt * 61.0), cos(tt * 53.0)) * _shake_amp * k * k
		if _shake_t <= 0.0:
			offset = Vector2.ZERO
			_shake_amp = 0.0


# ---- input --------------------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_step(1, mb.position)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_step(-1, mb.position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event
		_focus_target = _clamp_focus(_focus_target - mm.relative / _zoom_target, _zoom_target)
		_focus_cur = _focus_target
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var ke: InputEventKey = event
		if not ke.pressed or ke.echo:
			return
		var has_actions: bool = InputMap.has_action(&"zoom_in") and InputMap.has_action(&"zoom_out")
		if has_actions:
			if event.is_action_pressed(&"zoom_in"):
				_zoom_step(1, _view_size() * 0.5)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed(&"zoom_out"):
				_zoom_step(-1, _view_size() * 0.5)
				get_viewport().set_input_as_handled()
		else:
			match ke.keycode:
				KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
					_zoom_step(1, _view_size() * 0.5)
					get_viewport().set_input_as_handled()
				KEY_MINUS, KEY_KP_SUBTRACT:
					_zoom_step(-1, _view_size() * 0.5)
					get_viewport().set_input_as_handled()


## Change zoom level keeping the ship-local point under `screen_pos` fixed (zoom to cursor).
func _zoom_step(dir: int, screen_pos: Vector2) -> void:
	var nl: int = clampi(zoom_level + dir, 0, 2)
	if nl == zoom_level:
		return
	# local point under cursor given the TARGET view
	var a_shift: Vector2 = _area_shift()
	var cam_pos: Vector2 = _focus_target - a_shift / _zoom_target
	var local_pt: Vector2 = (screen_pos - _view_size() * 0.5) / _zoom_target + cam_pos
	zoom_level = nl
	_zoom_target = _level_zoom(nl)
	# focus such that local_pt stays at screen_pos
	var new_cam: Vector2 = local_pt - (screen_pos - _view_size() * 0.5) / _zoom_target
	_focus_target = _clamp_focus(new_cam + _area_shift() / _zoom_target, _zoom_target)
	_emit_if_changed()
