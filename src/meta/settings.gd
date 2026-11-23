extends Node
## Settings autoload ("Settings") — see docs/SPEC.md §9.
##
## * Registers every gameplay input action in code (defaults below) so they exist before any
##   screen loads, and applies the player's saved remaps on top.
## * Holds the player preferences (volumes, colourblind, fullscreen, screen shake, tutorial hints).
##   Each property setter emits `changed(key)` (key = property name as StringName).
##
## PERSISTENCE: preferences and key bindings are stored in their own JSON file at
## `user://settings.json` (NOT in save.json) so "Reset progress" never wipes them and the
## settings screen has no dependency on SaveManager. Writes are atomic (tmp + rename), debounced
## (0.4 s after the last change) and flushed on exit; `save_now()` forces a write. A missing or
## corrupt file silently falls back to the defaults.
##
## Remapping API: get_bindings / rebind / clear_binding / reset_bindings / action_display_name /
## event_display_text / find_conflicts. Key events are stored by *physical* keycode (layout
## independent) except for the zoom keys, which are logical (`=` / `-` / numpad).

signal changed(key: StringName)

## Every action the game defines, in the order the remap list should show them.
const ACTIONS: Array[StringName] = [
	&"pause", &"speed_1", &"speed_2", &"speed_3",
	&"zoom_in", &"zoom_out",
	&"pan_left", &"pan_right", &"pan_up", &"pan_down",
	&"cancel", &"toggle_fullscreen",
]

const ACTION_NAMES: Dictionary = {
	&"pause": "Pause / resume",
	&"speed_1": "Speed 1x",
	&"speed_2": "Speed 2x",
	&"speed_3": "Speed 3x",
	&"zoom_in": "Zoom in",
	&"zoom_out": "Zoom out",
	&"pan_left": "Pan left",
	&"pan_right": "Pan right",
	&"pan_up": "Pan up",
	&"pan_down": "Pan down",
	&"cancel": "Cancel / deselect",
	&"toggle_fullscreen": "Toggle fullscreen",
}

## Keys of the preference values (also the `changed` keys).
const VALUE_KEYS: Array[StringName] = [
	&"master_volume", &"music_volume", &"sfx_volume",
	&"colorblind", &"fullscreen", &"screen_shake", &"show_tutorial_hints",
]

const SAVE_DELAY: float = 0.4
const MAX_SLOTS: int = 2

## Where the config is written. Tests override this before the node enters the tree.
var settings_path: String = "user://settings.json"

var master_volume: float = 0.8: set = set_master_volume
var music_volume: float = 0.7: set = set_music_volume
var sfx_volume: float = 0.9: set = set_sfx_volume
var colorblind: bool = false: set = set_colorblind
var fullscreen: bool = false: set = set_fullscreen
var screen_shake: bool = true: set = set_screen_shake
var show_tutorial_hints: bool = true: set = set_show_tutorial_hints

## action -> Array[InputEvent] (current bindings, max MAX_SLOTS).
var _bindings: Dictionary = {}
var _dirty: bool = false
var _save_timer: float = 0.0
var _loading: bool = false


func _ready() -> void:
	setup()
	set_process(false)


## Registers actions, loads the config file, applies everything. Called from _ready; safe to call
## again (tests do, after changing `settings_path`).
func setup() -> void:
	_loading = true
	_bindings.clear()
	_register_actions()
	load_settings()
	_loading = false
	_apply_all_bindings()
	if fullscreen:
		_apply_fullscreen()


func _process(delta: float) -> void:
	if _dirty:
		_save_timer -= delta
		if _save_timer <= 0.0:
			save_now()
	else:
		set_process(false)


func _exit_tree() -> void:
	if _dirty:
		save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _dirty:
		save_now()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen") and not event.is_echo():
		fullscreen = not fullscreen
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------------------------
# Values
# ---------------------------------------------------------------------------------------------

func set_master_volume(v: float) -> void:
	var nv: float = clampf(v, 0.0, 1.0)
	if is_equal_approx(master_volume, nv):
		return
	master_volume = nv
	_notify(&"master_volume")


func set_music_volume(v: float) -> void:
	var nv: float = clampf(v, 0.0, 1.0)
	if is_equal_approx(music_volume, nv):
		return
	music_volume = nv
	_notify(&"music_volume")


func set_sfx_volume(v: float) -> void:
	var nv: float = clampf(v, 0.0, 1.0)
	if is_equal_approx(sfx_volume, nv):
		return
	sfx_volume = nv
	_notify(&"sfx_volume")


func set_colorblind(v: bool) -> void:
	if colorblind == v:
		return
	colorblind = v
	_notify(&"colorblind")


func set_fullscreen(v: bool) -> void:
	if fullscreen == v:
		return
	fullscreen = v
	if not _loading:
		_apply_fullscreen()
	_notify(&"fullscreen")


func set_screen_shake(v: bool) -> void:
	if screen_shake == v:
		return
	screen_shake = v
	_notify(&"screen_shake")


func set_show_tutorial_hints(v: bool) -> void:
	if show_tutorial_hints == v:
		return
	show_tutorial_hints = v
	_notify(&"show_tutorial_hints")


## Generic getter by key (see VALUE_KEYS).
func get_value(key: StringName) -> Variant:
	if key in VALUE_KEYS:
		return get(key)
	return null


## Generic setter by key (see VALUE_KEYS). Returns false for unknown keys.
func set_value(key: StringName, value: Variant) -> bool:
	if key not in VALUE_KEYS:
		return false
	set(key, value)
	return true


## Restores every preference (not the key bindings) to its default.
func reset_values() -> void:
	master_volume = 0.8
	music_volume = 0.7
	sfx_volume = 0.9
	colorblind = false
	fullscreen = false
	screen_shake = true
	show_tutorial_hints = true


func _notify(key: StringName) -> void:
	if _loading:
		return
	changed.emit(key)
	_mark_dirty()


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


# ---------------------------------------------------------------------------------------------
# Input actions & remapping
# ---------------------------------------------------------------------------------------------

static func _key(code: Key, physical: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	if physical:
		e.physical_keycode = code
	else:
		e.keycode = code
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


## Factory defaults (fresh event instances each call).
static func default_bindings() -> Dictionary:
	return {
		&"pause": [_key(KEY_SPACE), _key(KEY_P)],
		&"speed_1": [_key(KEY_1), _key(KEY_KP_1)],
		&"speed_2": [_key(KEY_2), _key(KEY_KP_2)],
		&"speed_3": [_key(KEY_3), _key(KEY_KP_3)],
		&"zoom_in": [_key(KEY_EQUAL, false), _key(KEY_KP_ADD, false)],
		&"zoom_out": [_key(KEY_MINUS, false), _key(KEY_KP_SUBTRACT, false)],
		&"pan_left": [_key(KEY_A), _key(KEY_LEFT)],
		&"pan_right": [_key(KEY_D), _key(KEY_RIGHT)],
		&"pan_up": [_key(KEY_W), _key(KEY_UP)],
		&"pan_down": [_key(KEY_S), _key(KEY_DOWN)],
		&"cancel": [_key(KEY_ESCAPE), _mouse(MOUSE_BUTTON_RIGHT)],
		&"toggle_fullscreen": [_key(KEY_F11)],
	}


func _register_actions() -> void:
	var defaults := default_bindings()
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		_bindings[action] = defaults[action]


func _apply_all_bindings() -> void:
	for action: StringName in ACTIONS:
		_apply_binding(action)


func _apply_binding(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.5)
	InputMap.action_erase_events(action)
	for e: InputEvent in _bindings[action]:
		InputMap.action_add_event(action, e)


## Current bindings of an action (copies; slot 0 = primary, slot 1 = alternate).
func get_bindings(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if _bindings.has(action):
		for e: InputEvent in _bindings[action]:
			out.append(e.duplicate())
	return out


## Sets the binding in `slot` (appends if the slot is past the end). Only key and mouse-button
## events are accepted. Returns false if rejected.
func rebind(action: StringName, event: InputEvent, slot: int = 0) -> bool:
	if not _bindings.has(action) or slot < 0 or slot >= MAX_SLOTS:
		return false
	var ev: InputEvent = _normalize_event(event)
	if ev == null:
		return false
	var list: Array = _bindings[action]
	# The same event in the other slot is removed so an action never lists a key twice.
	for i in range(list.size() - 1, -1, -1):
		if i != slot and events_equal(list[i], ev):
			list.remove_at(i)
			if i < slot:
				slot -= 1
	if slot >= list.size():
		list.append(ev)
	else:
		list[slot] = ev
	_bindings[action] = list
	_apply_binding(action)
	_after_bindings_changed()
	return true


## Removes the binding in `slot` (the action keeps its other binding, if any).
func clear_binding(action: StringName, slot: int = 0) -> bool:
	if not _bindings.has(action):
		return false
	var list: Array = _bindings[action]
	if slot < 0 or slot >= list.size():
		return false
	list.remove_at(slot)
	_apply_binding(action)
	_after_bindings_changed()
	return true


## Restores every key binding to its default.
func reset_bindings() -> void:
	_bindings.clear()
	var defaults := default_bindings()
	for action: StringName in ACTIONS:
		_bindings[action] = defaults[action]
	_apply_all_bindings()
	_after_bindings_changed()


## Other actions currently using an equivalent event (for "already bound to X" warnings).
func find_conflicts(event: InputEvent, except_action: StringName = &"") -> Array[StringName]:
	var out: Array[StringName] = []
	var ev: InputEvent = _normalize_event(event)
	if ev == null:
		return out
	for action: StringName in ACTIONS:
		if action == except_action:
			continue
		for e: InputEvent in _bindings[action]:
			if events_equal(e, ev):
				out.append(action)
				break
	return out


func action_display_name(action: StringName) -> String:
	return String(ACTION_NAMES.get(action, String(action).capitalize()))


## Short human text for a key / mouse event ("Space", "Esc", "Num +", "Right Click").
func event_display_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var k: InputEventKey = event
		var mods := ""
		if k.ctrl_pressed:
			mods += "Ctrl+"
		if k.alt_pressed:
			mods += "Alt+"
		if k.shift_pressed:
			mods += "Shift+"
		if k.meta_pressed:
			mods += "Cmd+"
		var code: Key = k.keycode
		if code == KEY_NONE and k.physical_keycode != KEY_NONE:
			code = k.physical_keycode
			if DisplayServer.get_name() != "headless":
				# Show the label this physical key has on the player's layout (AZERTY etc.).
				var logical: Key = DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
				if logical != KEY_NONE:
					code = logical
		return mods + _key_text(code)
	if event is InputEventMouseButton:
		var m: InputEventMouseButton = event
		match m.button_index:
			MOUSE_BUTTON_LEFT: return "Left Click"
			MOUSE_BUTTON_RIGHT: return "Right Click"
			MOUSE_BUTTON_MIDDLE: return "Middle Click"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
			_: return "Mouse %d" % m.button_index
	if event == null:
		return "-"
	return event.as_text()


static func _key_text(code: Key) -> String:
	match code:
		KEY_ESCAPE: return "Esc"
		KEY_KP_ADD: return "Num +"
		KEY_KP_SUBTRACT: return "Num -"
		KEY_KP_1: return "Num 1"
		KEY_KP_2: return "Num 2"
		KEY_KP_3: return "Num 3"
		KEY_EQUAL: return "="
		KEY_MINUS: return "-"
		KEY_PLUS: return "+"
		KEY_SPACE: return "Space"
		KEY_NONE: return "?"
	return OS.get_keycode_string(code)


## True when two events would trigger on the same physical/logical input with the same modifiers.
static func events_equal(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka: InputEventKey = a
		var kb: InputEventKey = b
		if ka.shift_pressed != kb.shift_pressed or ka.ctrl_pressed != kb.ctrl_pressed \
				or ka.alt_pressed != kb.alt_pressed or ka.meta_pressed != kb.meta_pressed:
			return false
		if ka.physical_keycode != KEY_NONE and kb.physical_keycode != KEY_NONE:
			return ka.physical_keycode == kb.physical_keycode
		if ka.keycode != KEY_NONE and kb.keycode != KEY_NONE:
			return ka.keycode == kb.keycode
		return false
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


## Strips transient fields (pressed state, echo, device) so a captured event becomes a clean
## binding. Returns null for unsupported event types.
static func _normalize_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var src: InputEventKey = event
		var e := InputEventKey.new()
		if src.physical_keycode != KEY_NONE:
			e.physical_keycode = src.physical_keycode
		elif src.keycode != KEY_NONE:
			e.keycode = src.keycode
		else:
			return null
		e.shift_pressed = src.shift_pressed
		e.ctrl_pressed = src.ctrl_pressed
		e.alt_pressed = src.alt_pressed
		e.meta_pressed = src.meta_pressed
		return e
	if event is InputEventMouseButton:
		var m: InputEventMouseButton = event
		if m.button_index == MOUSE_BUTTON_NONE:
			return null
		var e2 := InputEventMouseButton.new()
		e2.button_index = m.button_index
		return e2
	return null


func _after_bindings_changed() -> void:
	if not _loading:
		changed.emit(&"bindings")
		_mark_dirty()


# ---------------------------------------------------------------------------------------------
# Persistence (JSON at settings_path)
# ---------------------------------------------------------------------------------------------

func _mark_dirty() -> void:
	_dirty = true
	_save_timer = SAVE_DELAY
	if is_inside_tree():
		set_process(true)


## Writes the settings file immediately (atomic: tmp file, then rename).
func save_now() -> bool:
	_dirty = false
	var values: Dictionary = {}
	for key: StringName in VALUE_KEYS:
		values[String(key)] = get(key)
	var bindings: Dictionary = {}
	for action: StringName in ACTIONS:
		var arr: Array = []
		for e: InputEvent in _bindings[action]:
			arr.append(_event_to_dict(e))
		bindings[String(action)] = arr
	var data: Dictionary = {"version": 1, "values": values, "bindings": bindings}
	var tmp: String = settings_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Settings: could not write %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var err: Error = DirAccess.rename_absolute(tmp, settings_path)
	if err != OK:
		DirAccess.remove_absolute(settings_path)  # platforms that refuse to rename over a file
		err = DirAccess.rename_absolute(tmp, settings_path)
		if err != OK:
			push_warning("Settings: could not move %s into place (error %d)" % [tmp, err])
			return false
	return true


## Re-reads the settings file (missing / unreadable / corrupt file keeps the current values).
func load_settings() -> void:
	if not FileAccess.file_exists(settings_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(settings_path)) != OK or not (json.data is Dictionary):
		push_warning("Settings: %s is unreadable; using defaults" % settings_path)
		return
	var data: Dictionary = json.data
	var was_loading := _loading
	_loading = true
	var values: Variant = data.get("values", {})
	if values is Dictionary:
		for key: StringName in VALUE_KEYS:
			if not (values as Dictionary).has(String(key)):
				continue
			var v: Variant = values[String(key)]
			if get(key) is bool and v is bool:
				set(key, v)
			elif get(key) is float and (v is float or v is int):
				set(key, clampf(float(v), 0.0, 1.0))
	var defaults := default_bindings()
	var saved: Variant = data.get("bindings", {})
	if saved is Dictionary:
		for action: StringName in ACTIONS:
			if not (saved as Dictionary).has(String(action)):
				continue
			var raw: Variant = saved[String(action)]
			if raw is Array:
				var list: Array = []
				for item: Variant in raw:
					if item is Dictionary:
						var e: InputEvent = _event_from_dict(item)
						if e != null and list.size() < MAX_SLOTS:
							list.append(e)
				if list.is_empty() and not (raw as Array).is_empty():
					list = defaults[action]  # entries present but all unreadable
				_bindings[action] = list
	_loading = was_loading


static func _event_to_dict(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		var k: InputEventKey = e
		return {
			"t": "key", "pc": int(k.physical_keycode), "kc": int(k.keycode),
			"shift": k.shift_pressed, "ctrl": k.ctrl_pressed, "alt": k.alt_pressed, "meta": k.meta_pressed,
		}
	if e is InputEventMouseButton:
		return {"t": "mouse", "b": int((e as InputEventMouseButton).button_index)}
	return {}


static func _event_from_dict(d: Dictionary) -> InputEvent:
	match String(d.get("t", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("pc", 0)) as Key
			k.keycode = int(d.get("kc", 0)) as Key
			if k.physical_keycode == KEY_NONE and k.keycode == KEY_NONE:
				return null
			k.shift_pressed = bool(d.get("shift", false))
			k.ctrl_pressed = bool(d.get("ctrl", false))
			k.alt_pressed = bool(d.get("alt", false))
			k.meta_pressed = bool(d.get("meta", false))
			return k
		"mouse":
			var b: int = int(d.get("b", 0))
			if b <= 0:
				return null
			var m := InputEventMouseButton.new()
			m.button_index = b as MouseButton
			return m
	return null
