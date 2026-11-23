class_name TutorialDirector
extends Node
## First-time walkthrough of level `med_1` (LevelDef.tutorial == true). Every step advances on a CONDITION
## (a room exists, a mess is gone, a room was repaired ...), never on a timer alone, and every step can be left:
## if the player already did it the step is skipped, if its target vanishes we move on, an action step that has
## been open for a while grows a "Continue" button, and "Skip tutorial" is always on screen.
##
## Hosted by LevelScreen (see the "TUTORIAL" blocks there):
##   var t := TutorialDirector.new(); add_child(t); t.setup(screen, hint_store)
##   t.on_port_started(port_phase)        t.on_voyage_started()        t.on_voyage_finished()
## Dev: `--tutstep=<step id>` jumps to that step of the current phase (screenshots).
##
## Port steps:   welcome, cabin, buffet, rooms (toilets + stairs info), fun, janitor, sail
## Voyage steps: board, mess (sim pauses), crew (sim pauses), repair (sim pauses), speed, meter, done

signal finished(skipped: bool)

enum State { IDLE, DELAY, WAIT, SHOW, PRAISE }

const PRAISE_TIME: float = 0.6
const DIM_PORT: float = 0.4
const DIM_VOYAGE: float = 0.52


class TStep extends RefCounted:
	var id: StringName = &""
	var text: String = ""
	var text_fn: Callable = Callable()   # () -> String, wording that follows the player's progress
	var next_label: String = ""          # "" = action step (advances on `done`), else informational + button
	var event: bool = false              # waits for something to happen; may be preempted by a later event step
	var pause: bool = false              # the sim is paused while this step is up
	var dim: float = 0.4
	var stuck_after: float = 30.0        # action steps: "Continue" appears after this many seconds
	var auto_after: float = -1.0         # informational: close by itself after n seconds of running game
	var needs_target: bool = false       # no targets for 1.5 s -> move on
	var trigger: Callable = Callable()   # () -> bool, step stays hidden until true
	var skip_if: Callable = Callable()   # () -> bool, already satisfied
	var done: Callable = Callable()      # () -> bool
	var targets: Callable = Callable()   # () -> Array[Dictionary]
	var on_enter: Callable = Callable()
	var on_exit: Callable = Callable()
	var force_delay: float = -1.0        # sim seconds of waiting after which `force` makes the trigger happen
	var force: Callable = Callable()
	var praise: bool = true


var screen: Node = null
var store: HintStore = null
var ui: TutorialUI = null
var tg: TutorialTargets = null
var port_ui: PortPhase = null
var active: bool = false
var mode: StringName = &""            # &"port" | &"voyage"
var steps: Array[TStep] = []
var idx: int = -1
var cur: TStep = null
var state: State = State.IDLE
## Ids of the steps that were shown / completed (for tests and dev).
var log_shown: Array[StringName] = []
var log_done: Array[StringName] = []
var log_skipped: Array[StringName] = []
var skipped_by_player: bool = false

var _t_step: float = 0.0
var _t_run: float = 0.0
var _t_run_game: float = 0.0
var _t_delay: float = 0.0
var _t_praise: float = 0.0
var _t_lost: float = 0.0
var _wait_world_t: float = 0.0
var _paused_by_me: bool = false
var _resume_speed: int = 1
var _speed_touched: bool = false
var _own_speed_change: bool = false
var _first_mess_id: int = -1
var _crew_mess_id: int = -1
var _crew_selected: bool = false
var _crew_assigned: bool = false
var _jump_to: StringName = &""
var _port_total: int = 0


func setup(p_screen: Node, p_store: HintStore) -> void:
	screen = p_screen
	store = p_store
	name = "TutorialDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS
	tg = TutorialTargets.new()
	tg.screen = screen
	ui = TutorialUI.new()
	screen.add_child(ui)
	ui.next_pressed.connect(_on_next)
	ui.skip_pressed.connect(_on_skip)
	ui.root.visible = true
	if not Settings.changed.is_connected(_on_settings):
		Settings.changed.connect(_on_settings)
	_jump_to = StringName(String(screen.params.get("tutstep", "")))
	active = true
	state = State.IDLE


func is_active() -> bool:
	return active


func current_id() -> StringName:
	return cur.id if cur != null and active else &""


## VoyageInput asks this while the sim is paused (normally the world is look-only then). The tutorial pauses on
## purpose, so it unlocks exactly what the current step asks for: its spill, or a broken room to hold.
func allows_paused_action(kind: StringName, id: int) -> bool:
	if not active or cur == null or not cur.pause or not _paused_by_me or state != State.SHOW:
		return false
	match cur.id:
		&"mess":
			return kind == &"mess" and id == _first_mess_id
		&"repair":
			if kind != &"room":
				return false
			var r: RoomRuntime = _w().room_by_uid(id)
			return r != null and r.broken
	return false


func card_visible() -> bool:
	return active and ui != null and ui.card_shown and state in [State.SHOW, State.PRAISE]


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_settings):
		Settings.changed.disconnect(_on_settings)


func _on_settings(key: StringName) -> void:
	if key == &"show_tutorial_hints" and not Settings.show_tutorial_hints and active:
		_finish(true, false)


# =================================================================================================
# phase hooks (called by LevelScreen)
# =================================================================================================
func on_port_started(pp: Node) -> void:
	if not active:
		return
	if not (pp is PortPhase):
		_finish(true, false)   # fallback port UI has no tutorial hooks
		return
	port_ui = pp
	tg.port_ui = port_ui
	tg.voyage = false
	mode = &"port"
	port_ui.port_action.connect(func(_k: StringName, _d: Dictionary) -> void: tg.bump())
	var port: PortState = screen.port
	port.changed.connect(func() -> void: tg.bump())
	_set_bounds_port()
	steps = _port_steps()
	_port_total = steps.size()
	_t_delay = 0.0
	state = State.DELAY   # wait for the level intro banner to leave


func on_voyage_started() -> void:
	if not active:
		return
	if mode == &"port":
		_leave_current()
	mode = &"voyage"
	tg.voyage = true
	tg.port_ui = null
	port_ui = null
	_speed_touched = false
	var ctl: VoyageController = screen.ctl
	ctl.speed_changed.connect(func(_s: int) -> void:
		if not _own_speed_change:
			_speed_touched = true)
	var inp: VoyageInput = screen.input
	inp.selection_changed.connect(_on_selection_changed)
	_set_bounds_voyage()
	steps = _voyage_steps()
	_begin_list()


func on_voyage_finished() -> void:
	if active:
		_finish(false, true)


func _begin_list() -> void:
	idx = -1
	cur = null
	if _jump_to != &"":
		for i in steps.size():
			if steps[i].id == _jump_to:
				idx = i - 1
				for k in i:
					log_skipped.append(steps[k].id)
				break
		_jump_to = &""
	_advance()


# =================================================================================================
# state machine
# =================================================================================================
func _process(delta: float) -> void:
	if not active:
		return
	_t_run += delta
	if screen == null or not is_instance_valid(screen):
		return
	_hide_for_dialogs()
	if mode != &"":
		_process_bounds()
	match state:
		State.DELAY:
			_tick_delay(delta)
		State.WAIT:
			_tick_wait(delta)
		State.SHOW:
			_tick_show(delta)
		State.PRAISE:
			_tick_praise(delta)


func _hide_for_dialogs() -> void:
	var hide: bool = false
	if mode == &"port" and port_ui != null and is_instance_valid(port_ui) and port_ui.dialog_node() != null:
		hide = true
	if mode == &"voyage" and screen._pause_menu != null:
		hide = true
	ui.root.visible = not hide


func _tick_delay(delta: float) -> void:
	_t_delay += delta
	var banner: Variant = screen._intro_banner
	var banner_gone: bool = banner == null or not is_instance_valid(banner)
	if _jump_to != &"" or (banner_gone and _t_delay >= 0.5) or _t_delay >= 4.4:
		_begin_list()


func _tick_wait(_delta: float) -> void:
	if cur == null:
		return
	if cur.skip_if.is_valid() and bool(cur.skip_if.call()):
		log_skipped.append(cur.id)
		_advance()
		return
	if cur.trigger.is_valid() and bool(cur.trigger.call()):
		_show_current()
		return
	if _preempt():
		return
	var w: SimWorld = screen.world
	if cur.force_delay >= 0.0 and w != null and not w.finished and w.time - _wait_world_t >= cur.force_delay and cur.force.is_valid():
		cur.force_delay = -1.0
		cur.force.call()


## A later event step (e.g. the power surge) may overtake a step that never got its trigger.
func _preempt() -> bool:
	for j in range(idx + 1, steps.size()):
		var s: TStep = steps[j]
		if s.event and s.trigger.is_valid() and bool(s.trigger.call()):
			_leave_current()
			for k in range(idx, j):
				log_skipped.append(steps[k].id)
			idx = j - 1
			_advance()
			return true
	return false


func _tick_show(delta: float) -> void:
	_t_step += delta
	if _running_game():
		_t_run_game += delta
	if cur.auto_after > 0.0 and _preempt():
		return
	var ts: Array = cur.targets.call() if cur.targets.is_valid() else []
	ui.set_targets(ts)
	if cur.text_fn.is_valid():
		ui.card.set_text(String(cur.text_fn.call()))
	if cur.done.is_valid() and bool(cur.done.call()):
		_complete()
		return
	if cur.next_label == "" and _t_step >= cur.stuck_after:
		ui.card.enable_stuck_skip()
	if cur.auto_after > 0.0 and _t_run_game >= cur.auto_after:
		_leave_current()
		log_done.append(cur.id)
		_advance()
		return
	if cur.needs_target:
		if ts.is_empty():
			_t_lost += delta
			if _t_lost > 1.5:
				_leave_current()
				log_skipped.append(cur.id)
				_advance()
				return
		else:
			_t_lost = 0.0


func _running_game() -> bool:
	if mode != &"voyage":
		return true
	var ctl: VoyageController = screen.ctl
	return ctl != null and ctl.speed > 0 and ctl.start_delay <= 0.0


func _tick_praise(delta: float) -> void:
	_t_praise -= delta
	var ts: Array = cur.targets.call() if cur.targets.is_valid() else []
	ui.set_targets(ts)
	if _t_praise <= 0.0:
		_advance()


func _advance() -> void:
	while true:
		idx += 1
		if idx >= steps.size():
			cur = null
			_end_list()
			return
		cur = steps[idx]
		if cur.skip_if.is_valid() and bool(cur.skip_if.call()):
			log_skipped.append(cur.id)
			continue
		break
	_t_step = 0.0
	_t_run_game = 0.0
	_t_lost = 0.0
	var w: SimWorld = screen.world
	_wait_world_t = w.time if (w != null and mode == &"voyage") else 0.0
	if cur.trigger.is_valid() and not bool(cur.trigger.call()):
		state = State.WAIT
		ui.hide_step()
		return
	_show_current()


func _show_current() -> void:
	_t_step = 0.0
	_t_run_game = 0.0
	_t_lost = 0.0
	if cur.on_enter.is_valid():
		cur.on_enter.call()
	if cur.pause:
		_pause_game()
	var txt: String = String(cur.text_fn.call()) if cur.text_fn.is_valid() else cur.text
	var total: int = _port_total if mode == &"port" else steps.size()
	ui.set_dim(cur.dim)
	ui.show_step(txt, idx, total, cur.next_label)
	state = State.SHOW
	log_shown.append(cur.id)
	if cur.targets.is_valid():
		ui.set_targets(cur.targets.call())


func _complete() -> void:
	_leave_current()
	log_done.append(cur.id)
	if cur.praise:
		ui.celebrate()
		state = State.PRAISE
		_t_praise = PRAISE_TIME
	else:
		_advance()


## Runs the step's on_exit and gives the game back (if the step had paused it).
func _leave_current() -> void:
	if cur == null:
		return
	if cur.on_exit.is_valid():
		cur.on_exit.call()
	if cur.pause:
		_resume_game()


func _end_list() -> void:
	if mode == &"voyage":
		_finish(false, true)
	else:
		# port list finished (the player is about to sail): keep the chip, hide the bubble
		state = State.IDLE
		ui.hide_step()


func _on_next() -> void:
	if not active or state != State.SHOW or cur == null:
		return
	_leave_current()
	if cur.next_label != "":
		log_done.append(cur.id)
	else:
		log_skipped.append(cur.id)
	ui.set_targets([])
	_advance()


func _on_skip() -> void:
	skipped_by_player = true
	_finish(true, true)


func _finish(skipped: bool, mark_done: bool) -> void:
	if not active:
		return
	active = false
	if _paused_by_me:
		_resume_game()
	if mark_done and store != null:
		store.mark(&"tutorial")
	state = State.IDLE
	if ui != null and is_instance_valid(ui):
		ui.set_targets([])
		var tw := ui.root.create_tween()
		tw.tween_property(ui.root, "modulate:a", 0.0, 0.3)
		tw.tween_callback(ui.queue_free)
	finished.emit(skipped)


# =================================================================================================
# pausing
# =================================================================================================
func _pause_game() -> void:
	var ctl: VoyageController = screen.ctl
	if ctl == null:
		return
	if ctl.speed > 0:
		_resume_speed = ctl.speed
	if ctl.speed != 0:
		_own_speed_change = true
		ctl.set_speed(0)
		_own_speed_change = false
	_paused_by_me = true


func _resume_game() -> void:
	if not _paused_by_me:
		return
	_paused_by_me = false
	var ctl: VoyageController = screen.ctl
	if ctl != null and ctl.speed == 0 and screen._pause_menu == null and not (screen.world != null and screen.world.finished):
		_own_speed_change = true
		ctl.set_speed(maxi(_resume_speed, 1))
		_own_speed_change = false


func _set_bounds_port() -> void:
	ui.set_bounds(104.0, ui.root.size.y - 380.0)


func _set_bounds_voyage() -> void:
	ui.set_bounds(104.0, ui.root.size.y - VoyageHud.BOTTOM_H)


func _process_bounds() -> void:
	if mode == &"port" and port_ui != null and is_instance_valid(port_ui) and port_ui.bar() != null:
		ui.set_bounds(104.0, port_ui.bar().global_position.y)
	elif mode == &"voyage":
		ui.set_bounds(104.0, ui.root.size.y - VoyageHud.BOTTOM_H)


# =================================================================================================
# helpers shared by the step definitions
# =================================================================================================
func _mk(id: StringName, text: String, next_label: String = "") -> TStep:
	var s := TStep.new()
	s.id = id
	s.text = text
	s.next_label = next_label
	s.dim = DIM_PORT if mode == &"port" else DIM_VOYAGE
	return s


func _w() -> SimWorld:
	return screen.world


func _count(room_id: StringName) -> int:
	var port: PortState = screen.port
	return port.layout.count_of(room_id)


func _beds_ok() -> bool:
	var port: PortState = screen.port
	var m: Dictionary = port.manifest()
	return int(m["beds"]) >= int(m["guests"])


func _has_fun() -> bool:
	var port: PortState = screen.port
	for r in port.layout.rooms:
		if r.def.satisfies.has(&"fun") and r.def.category == &"fun":
			return true
	return false


func _broken_rooms() -> Array[RoomRuntime]:
	var out: Array[RoomRuntime] = []
	var w: SimWorld = _w()
	for r in w.rooms:
		if r.broken:
			out.append(r)
	return out


func _janitor() -> StaffMember:
	var w: SimWorld = _w()
	for s in w.staff:
		if s.role == &"janitor":
			return s
	return null


func _on_screen(r: Rect2) -> bool:
	return r.size.x > 0.0 and Rect2(Vector2(8, 96), Vector2(1904, 780)).intersects(r)


func _ensure_visible(local_pos: Vector2) -> void:
	if local_pos == Vector2.INF:
		return
	var inp: VoyageInput = screen.input
	var sp: Vector2 = inp.local_to_screen(local_pos)
	if not Rect2(Vector2(60, 130), Vector2(1800, 680)).has_point(sp):
		var cam: ShipCamera = screen.cam
		cam.focus_on(local_pos, cam.zoom_level)


# =================================================================================================
# PORT steps
# =================================================================================================
func _port_steps() -> Array[TStep]:
	var out: Array[TStep] = []
	# 1) welcome ----------------------------------------------------------------------------------
	var s := _mk(&"welcome", "Welcome aboard, Captain! Let's **build your ship** and set sail.", "Let's go!")
	s.targets = func() -> Array:
		return []
	out.append(s)
	# 2) cabin ------------------------------------------------------------------------------------
	s = _mk(&"cabin", "Guests need beds! **Place a Cabin** on the ship.")
	s.skip_if = func() -> bool: return _beds_ok()
	s.done = func() -> bool: return _beds_ok()
	s.targets = _place_targets.bind(&"cabin")
	s.text_fn = _place_text.bind(&"cabin", "Guests need beds! **Place a Cabin** on the ship.")
	s.on_enter = _uncollapse
	out.append(s)
	# 3) buffet -----------------------------------------------------------------------------------
	s = _mk(&"buffet", "Hungry guests need food. **Place a Buffet**.")
	s.skip_if = func() -> bool: return _count(&"buffet") + _count(&"restaurant") > 0
	s.done = func() -> bool: return _count(&"buffet") + _count(&"restaurant") > 0
	s.targets = _place_targets.bind(&"buffet")
	s.text_fn = _place_text.bind(&"buffet", "Hungry guests need food. **Place a Buffet**.")
	s.on_enter = _uncollapse
	out.append(s)
	# 4) toilets + stairs (already built) ---------------------------------------------------------
	s = _mk(&"rooms", "Toilets and **Stairs** are already built. Stairs link the decks.", "Got it")
	s.skip_if = func() -> bool: return _count(&"toilets") == 0 or _count(&"stairs") == 0
	s.targets = _info_targets
	out.append(s)
	# 5) fun --------------------------------------------------------------------------------------
	s = _mk(&"fun", "Guests want fun too! **Place a Bar** upstairs, by the Stairs.")
	s.skip_if = func() -> bool: return _has_fun()
	s.done = func() -> bool: return _has_fun()
	s.targets = _place_targets.bind(&"bar")
	s.text_fn = _place_text.bind(&"bar", "Guests want fun too! **Place a Bar** upstairs, by the Stairs.")
	s.on_enter = _uncollapse
	out.append(s)
	# 6) janitor ----------------------------------------------------------------------------------
	s = _mk(&"janitor", "Spills happen! **Hire a Janitor** from the Crew tab.")
	s.skip_if = func() -> bool: return (screen.port as PortState).staff_total() > 0
	s.done = func() -> bool: return (screen.port as PortState).staff_total() > 0
	s.targets = _janitor_targets
	s.on_enter = _uncollapse
	out.append(s)
	# 7) set sail ---------------------------------------------------------------------------------
	s = _mk(&"sail", "All set! Press **Set Sail** when you're ready.")
	s.text_fn = _sail_text
	s.targets = _sail_targets
	s.on_enter = _uncollapse
	out.append(s)
	return out


func _uncollapse() -> void:
	if port_ui != null and is_instance_valid(port_ui) and port_ui.bar() != null and port_ui.bar().collapsed:
		port_ui.set_bar_collapsed(false)


func _place_text(room_id: StringName, base: String) -> String:
	if port_ui != null and port_ui.armed_room() == room_id:
		return "Now **click the ship** to put it down."
	return base


func _place_targets(room_id: StringName) -> Array:
	_process_bounds()
	var out: Array = []
	if port_ui == null or not is_instance_valid(port_ui):
		return out
	var bar: PortBuildBar = port_ui.bar()
	if bar.collapsed:
		_uncollapse()
	var tab: StringName = bar.tab_of(room_id)
	if port_ui.armed_room() == room_id:
		var spot: Rect2 = tg.spot_rect(room_id)
		if spot.size.x > 0.0:
			out.append({"rect": spot, "radius": 10.0, "pad": 4.0})
		return out
	if bar.current_tab != tab:
		var tb: Rect2 = TutorialTargets.ctrl(bar.tab_button(tab))
		if tb.size.x > 0.0:
			out.append({"rect": tb, "radius": 22.0, "pad": 6.0})
		return out
	var card: Rect2 = TutorialTargets.ctrl(bar.card_for(room_id))
	if card.size.x > 0.0:
		out.append({"rect": card, "radius": 20.0, "pad": 6.0})
	var spot2: Rect2 = tg.spot_rect(room_id)
	if spot2.size.x > 0.0:
		out.append({"rect": spot2, "radius": 10.0, "pad": 4.0})
	return out


func _info_targets() -> Array:
	_process_bounds()
	var out: Array = []
	if port_ui == null or not is_instance_valid(port_ui):
		return out
	var t: Rect2 = tg.placed_rect_of(&"toilets")
	var st: Rect2 = tg.placed_rect_of(&"stairs")
	if t.size.x > 0.0:
		out.append({"rect": t, "radius": 10.0, "pad": 4.0})
	if st.size.x > 0.0:
		out.append({"rect": st, "radius": 10.0, "pad": 4.0})
	return out


func _janitor_targets() -> Array:
	_process_bounds()
	var out: Array = []
	if port_ui == null or not is_instance_valid(port_ui):
		return out
	var bar: PortBuildBar = port_ui.bar()
	if bar.current_tab != &"crew":
		var tb: Rect2 = TutorialTargets.ctrl(bar.tab_button(&"crew"))
		if tb.size.x > 0.0:
			out.append({"rect": tb, "radius": 22.0, "pad": 6.0})
		return out
	var hb: Button = bar.crew_panel.hire_button(&"janitor")
	var r: Rect2 = TutorialTargets.ctrl(hb)
	if r.size.x > 0.0:
		out.append({"rect": r, "radius": 20.0, "pad": 6.0})
	return out


func _sail_targets() -> Array:
	_process_bounds()
	var out: Array = []
	if port_ui == null or not is_instance_valid(port_ui):
		return out
	var r: Rect2 = TutorialTargets.ctrl(port_ui.bar().sail_button)
	if r.size.x > 0.0:
		out.append({"rect": r, "radius": 26.0, "pad": 8.0})
	return out


func _sail_text() -> String:
	var port: PortState = screen.port
	var v: Dictionary = port.validate()
	if (v["errors"] as Array).size() > 0:
		return "Some rooms are cut off! Link every deck with **Stairs**."
	return "All set! Press **Set Sail** when you're ready."


# =================================================================================================
# VOYAGE steps
# =================================================================================================
func _voyage_steps() -> Array[TStep]:
	var out: Array[TStep] = []
	# 1) board ------------------------------------------------------------------------------------
	var s := _mk(&"board", "Guests are boarding! The **bubbles** over their heads show what they need.", "Got it")
	s.auto_after = 7.0
	s.dim = 0.0
	s.targets = func() -> Array:
		return []
	out.append(s)
	# 2) first mess: the sim pauses ---------------------------------------------------------------
	s = _mk(&"mess", "Oops, a spill! **Click it 3 times** to scrub it clean.")
	s.event = true
	s.pause = true
	s.needs_target = false
	s.trigger = func() -> bool: return not _w().messes.is_empty()
	s.skip_if = func() -> bool: return int(_w().metrics["cleaned"]) >= 1 and _first_mess_id < 0
	s.force_delay = 40.0
	s.force = _force_mess
	s.on_enter = func() -> void:
		var m: Mess = _w().messes[0] if not _w().messes.is_empty() else null
		_first_mess_id = m.id if m != null else -1
		if m != null:
			_ensure_visible((screen.renderer as VoyageRenderer).local_pos_of(&"mess", m.id))
	s.done = func() -> bool: return _first_mess_id < 0 or _w().mess_by_id(_first_mess_id) == null
	s.text_fn = _mess_text
	s.targets = func() -> Array:
		var r: Rect2 = tg.mess_rect(_first_mess_id)
		return [{"rect": r, "radius": 30.0, "pad": 10.0}] if r.size.x > 0.0 else []
	out.append(s)
	# 3) send the janitor: the sim pauses ---------------------------------------------------------
	s = _mk(&"crew", "Your janitor cleans too. **Click them**, then click a spill.")
	s.event = true
	s.pause = true
	s.skip_if = func() -> bool: return _janitor() == null
	s.trigger = func() -> bool: return (log_done.has(&"mess") or log_skipped.has(&"mess")) and _janitor() != null and _fresh_mess() != null
	s.force_delay = 28.0
	s.force = _force_mess
	s.on_enter = func() -> void:
		var m: Mess = _fresh_mess()
		_crew_mess_id = m.id if m != null else -1
		_crew_selected = false
		_crew_assigned = false
		if m != null:
			_ensure_visible((screen.renderer as VoyageRenderer).local_pos_of(&"mess", m.id))
	s.done = func() -> bool: return _crew_assigned or _crew_mess_id < 0 or _w().mess_by_id(_crew_mess_id) == null
	s.text_fn = _crew_text
	s.targets = _crew_targets
	out.append(s)
	# 4) repair by holding: the sim pauses --------------------------------------------------------
	s = _mk(&"repair", "Power surge! **Press and hold** on a broken room to repair it.")
	s.event = true
	s.pause = true
	s.skip_if = func() -> bool: return int(_w().metrics["repairs"]) >= 1 and _broken_rooms().is_empty()
	s.trigger = func() -> bool: return not _broken_rooms().is_empty()
	s.force_delay = 60.0
	s.force = _force_surge
	s.on_enter = func() -> void:
		var rooms: Array[RoomRuntime] = _broken_rooms()
		if not rooms.is_empty():
			_ensure_visible((screen.renderer as VoyageRenderer).room_rect(rooms[0].uid).get_center())
	s.done = func() -> bool: return _broken_rooms().is_empty()
	s.on_exit = func() -> void: store.mark(&"event_power_surge")
	s.text_fn = _repair_text
	s.targets = _repair_targets
	out.append(s)
	# 5) pause and speed ---------------------------------------------------------------------------
	s = _mk(&"speed", "**Space** pauses the game. **1, 2 and 3** change its speed.", "Got it")
	s.on_enter = func() -> void: _speed_touched = false
	s.done = func() -> bool: return _speed_touched
	s.targets = _speed_targets
	s.stuck_after = 9999.0
	s.dim = 0.36
	out.append(s)
	# 6) rating meter ------------------------------------------------------------------------------
	s = _mk(&"meter", "Keep guests happy to earn **stars**. Watch the meter up here!", "Got it")
	s.targets = _meter_targets
	s.dim = 0.36
	out.append(s)
	# 7) finish ------------------------------------------------------------------------------------
	s = _mk(&"done", "That's all you need, Captain. **Good luck** out there!", "Aye aye!")
	s.targets = func() -> Array:
		return []
	out.append(s)
	return out


func _fresh_mess() -> Mess:
	var w: SimWorld = _w()
	for m in w.messes:
		if m.id != _first_mess_id:
			return m
	return null


func _force_mess() -> void:
	var w: SimWorld = _w()
	for r in w.room_sim.service_rooms:
		if r.def.id == &"cabin":
			continue
		var m: Mess = w.problems.spawn_mess(w, r)
		if m != null:
			return


func _force_surge() -> void:
	var w: SimWorld = _w()
	w.force_event(&"power_surge")
	if _broken_rooms().is_empty():
		for r in w.room_sim.service_rooms:
			if r.is_breakable() and not r.broken:
				w.room_sim.break_room(w, r)
				break


func _mess_text() -> String:
	var m: Mess = _w().mess_by_id(_first_mess_id)
	if m != null and m.clean_progress > 0.01:
		var left: int = maxi(int(ceil((1.0 - m.clean_progress) / SimConst.PLAYER_MESS_CLICK - 0.001)), 1)
		return "Keep **clicking**! %d more." % left
	return "Oops, a spill! **Click it 3 times** to scrub it clean."


## True when clicking the janitor on the ship really hits the janitor (not a spill / ghost standing on top of them).
func _janitor_pickable(j: StaffMember) -> bool:
	var sr: Rect2 = tg.staff_rect(j.id)
	if not _on_screen(sr):
		return false
	var inp: VoyageInput = screen.input
	var rend: VoyageRenderer = screen.renderer
	var pk: Dictionary = rend.pick(inp.screen_to_local(sr.get_center()))
	return pk["kind"] == &"staff" and int(pk["id"]) == j.id


func _crew_text() -> String:
	var inp: VoyageInput = screen.input
	if inp.selected_staff_id >= 0:
		return "Now **click the spill** to send your janitor there."
	var j: StaffMember = _janitor()
	if j != null and not _janitor_pickable(j):
		return "Your janitor cleans too. **Click their card**, then click a spill."
	return "Your janitor cleans too. **Click them**, then click a spill."


func _crew_targets() -> Array:
	var out: Array = []
	var inp: VoyageInput = screen.input
	var mr: Rect2 = tg.mess_rect(_crew_mess_id)
	if inp.selected_staff_id >= 0:
		if mr.size.x > 0.0:
			out.append({"rect": mr, "radius": 30.0, "pad": 10.0})
		return out
	var j: StaffMember = _janitor()
	if j != null:
		var on_ship: bool = _janitor_pickable(j)
		if on_ship:
			out.append({"rect": tg.staff_rect(j.id), "radius": 24.0, "pad": 8.0})
		var cr: Rect2 = tg.roster_card_rect(j.id)
		if cr.size.x > 0.0:
			out.append({"rect": cr, "radius": 18.0, "pad": 6.0, "arrow": not on_ship})
	if mr.size.x > 0.0:
		out.append({"rect": mr, "radius": 30.0, "pad": 6.0, "arrow": false})
	return out


func _repair_text() -> String:
	var ctl: VoyageController = screen.ctl
	if ctl.hold_room_uid >= 0:
		return "Keep **holding**..."
	return "Power surge! **Press and hold** on a broken room to repair it."


func _repair_targets() -> Array:
	var out: Array = []
	for r in _broken_rooms():
		var rr: Rect2 = tg.room_rt_rect(r.uid)
		if rr.size.x > 0.0:
			out.append({"rect": rr, "radius": 12.0, "pad": 6.0})
		if out.size() >= 3:
			break
	return out


func _speed_targets() -> Array:
	var hud: VoyageHud = screen.hud
	var rects: Array = []
	for b in hud.speed_buttons:
		rects.append(TutorialTargets.ctrl(b))
	var u: Rect2 = TutorialTargets.union(rects)
	return [{"rect": u, "radius": 26.0, "pad": 8.0}] if u.size.x > 0.0 else []


func _meter_targets() -> Array:
	var hud: VoyageHud = screen.hud
	var u: Rect2 = TutorialTargets.union([TutorialTargets.ctrl(hud.meter), TutorialTargets.ctrl(hud.pct_label), TutorialTargets.ctrl(hud.stars)])
	return [{"rect": u, "radius": 24.0, "pad": 10.0}] if u.size.x > 0.0 else []


func _on_selection_changed() -> void:
	var inp: VoyageInput = screen.input
	if inp.selected_staff_id >= 0:
		_crew_selected = true
		return
	if not _crew_selected or cur == null or cur.id != &"crew":
		return
	# the selection was cleared: either the player assigned the janitor to a spill or cancelled
	_crew_selected = false
	for s in _w().staff:
		if s.role == &"janitor" and s.job != null and s.job.kind == &"mess":
			_crew_assigned = true
			return
