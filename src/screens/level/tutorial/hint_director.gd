class_name HintDirector
extends Node
## Contextual "first time" tips for every level (after / instead of the med_1 walkthrough): the first sickness,
## ghost, queue anger, mutiny warning, each kind of event, first elevator / tier II / tier III availability and
## the first visit to the Arctic or Underworld (wording follows what is unlocked), and the v2 additions: a new crew role in port, VIPs,
## families, crew tiredness, storms, the port stop + Quick refit, company funds and the report / heatmap buttons on the first results.
## Each shows ONCE per save (HintStore), at most one at a time, never
## during the first 5 s of a voyage, never while the tutorial bubble is up, and only if Settings.show_tutorial_hints.
##
## Hosted by LevelScreen:  h.setup(screen, store);  h.on_port_started(port_phase);  h.on_voyage_started();
##                         h.on_voyage_finished();  h.on_results_shown(result, unlocks)
## Dev: `--hint=<id>` queues that hint right away (screenshots); ids are the keys of HINTS.

const MIN_VOYAGE_TIME: float = 5.0
const GAP_AFTER: float = 2.5
const STALE_AFTER: float = 30.0
## Design px kept free at the bottom of the results screen while a hint card is up.
const RESULTS_ROOM: float = 130.0

const HINTS: Dictionary = HintTexts.HINTS

var screen: Node = null
var store: HintStore = null
var layer: CanvasLayer = null
var card: HintCard = null
var shown_log: Array[StringName] = []
var suppress: bool = false           # set by LevelScreen while the tutorial bubble is up

var _queue: Array[Dictionary] = []
var _t: float = 0.0
var _gap: float = 0.0
var _world: SimWorld = null
var _port_ui: PortPhase = null
var _mode: StringName = &""


func setup(p_screen: Node, p_store: HintStore) -> void:
	screen = p_screen
	store = p_store
	name = "HintDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = CanvasLayer.new()
	layer.layer = 29
	layer.name = "HintLayer"
	screen.add_child(layer)
	if screen.params.has("hint"):
		request(StringName(String(screen.params["hint"])), 0.6, true)


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_settings):
		Settings.changed.disconnect(_on_settings)


func _on_settings(key: StringName) -> void:
	if key == &"show_tutorial_hints" and not Settings.show_tutorial_hints:
		_queue.clear()
		if card != null and is_instance_valid(card):
			card.close()


# ---- phase hooks ------------------------------------------------------------------------------
func on_port_started(pp: Node) -> void:
	_mode = &"port"
	_port_ui = pp as PortPhase
	if not Settings.changed.is_connected(_on_settings):
		Settings.changed.connect(_on_settings)
	var level: LevelDef = screen.level
	if level.destination == &"arctic":
		request(&"dest_arctic", 4.6)
	elif level.destination == &"underworld":
		request(&"dest_underworld", 4.6)
	var port: PortState = screen.port
	# v2 content, newest feature first (hints that cannot be shown within STALE_AFTER simply wait for the next level)
	for role in ContentStore.staff_available(level.campaign_index, level.destination):
		var def: StaffDef = role
		if def.unlock_level > 1:
			request(StringName("crew_" + String(def.id)), 5.0)
	if not level.vips.is_empty():
		request(&"vip_plan", 5.5)
	if level.group_ratio > 0.0:
		request(&"families", 6.0)
	if level.staff_fatigue:
		request(&"fatigue", 6.5)
	if not level.port_stop.is_empty():
		request(&"portstop_plan", 7.0)
	if port.grid.room_lock_reason(&"elevator") == "" and level.campaign_index >= 7:
		request(&"elevator", 7.5)
	if level.campaign_index >= SimConst.TIER3_UNLOCK_LEVEL:
		request(&"tier3", 9.0)
	elif level.campaign_index >= SimConst.TIER2_UNLOCK_LEVEL:
		request(&"tier2", 8.0)


func on_voyage_started() -> void:
	_mode = &"voyage"
	_port_ui = null
	var w: SimWorld = screen.world
	_world = w
	if not Settings.changed.is_connected(_on_settings):
		Settings.changed.connect(_on_settings)
	w.guest_got_sick.connect(func(_g: int) -> void:
		if w.has_room_type(&"medbay"):
			request(&"sick_have", 1.2)
		else:
			request(&"sick" if _medbay_open() else &"sick_locked", 1.2))
	w.ghost_spawned.connect(func(_g: int) -> void: request(&"ghost", 1.5))
	w.guest_patience_out.connect(func(_g: int, _r: int) -> void:
		request(&"queue_anger" if _upgrades_open() else &"queue_anger_basic", 1.0))
	w.mutiny_warning.connect(func(_s: float) -> void: request(&"mutiny", 0.5))
	w.vip_boarded.connect(func(_g: int, kind: StringName) -> void: request(StringName("vip_" + String(kind)), 1.4))
	w.staff_tired.connect(func(_s: int) -> void: request(&"tired" if w.has_room_type(&"crew_quarters") else &"tired_none", 1.5))
	w.port_stop_started.connect(func(_n: String) -> void: request(&"portstop", 1.2))
	w.port_stop_ready.connect(func() -> void: request(&"refit", 0.5))
	w.event_started.connect(func(id: StringName) -> void:
		if id == &"food_poisoning" or id == &"haunting":
			var hid: StringName = StringName("event_" + String(id))
			if id == &"food_poisoning" and not w.has_room_type(&"medbay") and not _medbay_open():
				hid = &"event_food_poisoning_locked"
			request(hid, 3.2)
		else:
			request(StringName("event_" + String(id)), 2.8))


## Hint wording must never point at content the player cannot use yet (see the *_locked / *_basic variants).
func _medbay_open() -> bool:
	var port: PortState = screen.port
	return port != null and port.grid.room_lock_reason(&"medbay") == ""


func _upgrades_open() -> bool:
	var port: PortState = screen.port
	return port != null and port.grid.campaign_index >= port.grid.tier_unlock_level(1)


func on_voyage_finished() -> void:
	_queue.clear()
	_world = null
	if card != null and is_instance_valid(card):
		card.close()


## The results panel is up: explain the company funds and the report / heatmap buttons the first time they show.
func on_results_shown(result: Dictionary, unlocks: Dictionary) -> void:
	_mode = &"results"
	_queue.clear()
	if int(unlocks.get("funds_earned", 0)) > 0 or int(result.get("payout", 0)) > 0:
		request(&"funds", 2.6)
	if result.has("report") and not (result["report"] as Dictionary).is_empty():
		request(&"report", 2.6)


# ---- queue ------------------------------------------------------------------------------------
## Queues a hint (once per save). `delay` seconds from now before it may appear.
func request(id: StringName, delay: float = 0.0, force: bool = false) -> void:
	if not Settings.show_tutorial_hints:
		return
	if not HINTS.has(id):
		return
	if store.has(id) and not force:
		return
	for q in _queue:
		if q["id"] == id:
			return
	_queue.append({"id": id, "ready": _t + delay, "expire": _t + delay + STALE_AFTER, "force": force})


func _process(delta: float) -> void:
	_t += delta
	if _gap > 0.0:
		_gap -= delta
	if not Settings.show_tutorial_hints:
		return
	var showing: bool = card != null and is_instance_valid(card)
	if showing:
		_place_card()
		var hide: bool = _blocked_by_ui()
		card.visible = not hide
		return
	if _queue.is_empty() or _gap > 0.0 or _blocked():
		return
	for i in _queue.size():
		var q: Dictionary = _queue[i]
		if _t > float(q["expire"]):
			continue
		if float(q["ready"]) <= _t:
			_queue.remove_at(i)
			_show(StringName(q["id"]), bool(q["force"]))
			break
	# drop stale entries
	_queue = _queue.filter(func(q: Dictionary) -> bool: return _t <= float(q["expire"]))


func _blocked() -> bool:
	if suppress:
		return true
	var tut: Variant = screen.get("tutorial")
	if tut != null and is_instance_valid(tut) and (tut as TutorialDirector).is_active():
		return true
	if _blocked_by_ui():
		return true
	if _mode == &"voyage":
		if _world == null or _world.finished or _world.time < MIN_VOYAGE_TIME:
			return true
		var ctl: VoyageController = screen.ctl
		if ctl == null or ctl.start_delay > 0.0:
			return true
	if _mode == &"" or (_mode == &"port" and screen.phase != 1):
		return true
	if _mode == &"results":
		var res: Variant = screen.get("_results")
		return res == null or not is_instance_valid(res) or not (res as Control).visible
	return false


func _blocked_by_ui() -> bool:
	if _mode == &"voyage" and screen._pause_menu != null:
		return true
	if _mode == &"port" and _port_ui != null and is_instance_valid(_port_ui) and _port_ui.dialog_node() != null:
		return true
	return false


func _show(id: StringName, force: bool) -> void:
	if store.has(id) and not force:
		return
	store.mark(id)
	shown_log.append(id)
	var d: Dictionary = HINTS[id]
	card = HintCard.make(String(d["text"]), StringName(d["icon"]), 7.5)
	layer.add_child(card)
	_results_room(true)
	card.closed.connect(func() -> void:
		card = null
		_gap = GAP_AFTER
		_results_room(false))
	_place_card()
	card.play()
	AudioManager.play_sfx(&"alert", 0.0, -9.0)


## On the results screen the panel fills the middle: make it leave room at the bottom for the card while one is up.
func _results_room(on: bool) -> void:
	if _mode != &"results":
		return
	var res: Variant = screen.get("_results")
	if res != null and is_instance_valid(res) and (res as Object).has_method(&"reserve_bottom"):
		(res as Object).call(&"reserve_bottom", RESULTS_ROOM if on else 0.0)


func _place_card() -> void:
	if card == null or not is_instance_valid(card):
		return
	var bottom: float = screen.get_viewport().get_visible_rect().size.y - 210.0
	var refit_ui: Variant = screen.get("_refit_ui")
	if _mode == &"voyage" and refit_ui != null and is_instance_valid(refit_ui) and (refit_ui as PortPhase).bar() != null:
		bottom = (refit_ui as PortPhase).bar().global_position.y
	elif _mode == &"results":
		# bottom centre, just under the results buttons (the panel fills the middle of the screen)
		var vp: Vector2 = screen.get_viewport().get_visible_rect().size
		card.reset_size()
		card.position = Vector2((vp.x - card.size.x) * 0.5, vp.y - card.size.y - 14.0)
		return
	elif _mode == &"voyage" and screen.hud != null:
		var bb: Control = (screen.hud as VoyageHud).bottom_bar
		if bb != null:
			bottom = bb.global_position.y
	elif _mode == &"port" and _port_ui != null and is_instance_valid(_port_ui) and _port_ui.bar() != null:
		bottom = _port_ui.bar().global_position.y
	card.reset_size()
	card.position = Vector2(24.0, bottom - card.size.y - 14.0)
