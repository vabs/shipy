class_name HintDirector
extends Node
## Contextual "first time" tips for every level (after / instead of the med_1 walkthrough): the first sickness,
## ghost, queue anger, mutiny warning, each kind of event, first elevator / tier II / tier III availability and
## the first visit to the Arctic or Underworld (wording follows what is unlocked). Each shows ONCE per save (HintStore), at most one at a time, never
## during the first 5 s of a voyage, never while the tutorial bubble is up, and only if Settings.show_tutorial_hints.
##
## Hosted by LevelScreen:  h.setup(screen, store);  h.on_port_started(port_phase);  h.on_voyage_started();
##                         h.on_voyage_finished()
## Dev: `--hint=<id>` queues that hint right away (screenshots); ids are the keys of HINTS.

const MIN_VOYAGE_TIME: float = 5.0
const GAP_AFTER: float = 2.5
const STALE_AFTER: float = 30.0

const HINTS: Dictionary = {
	&"sick": {"icon": &"sick", "text": "Sick guests need a **Medbay**. Build one in port to cure them."},
	&"sick_locked": {"icon": &"sick", "text": "Sick guests recover slowly. The **Medbay** unlocks soon!"},
	&"sick_have": {"icon": &"sick", "text": "A guest is sick! They will head to the **Medbay** to get cured."},
	&"ghost": {"icon": &"ghost", "text": "Click ghosts to **banish** them! They scare guests."},
	&"queue_anger": {"icon": &"angry", "text": "Guests leave long queues. **Add another room** or upgrade it!"},
	&"queue_anger_basic": {"icon": &"angry", "text": "Guests leave long queues. **Add another room** to share the load!"},
	&"mutiny": {"icon": &"warning", "text": "Guests are furious! **Fix problems fast** or they take over the ship."},
	&"elevator": {"icon": &"elevator", "text": "**Elevators** are unlocked! One shaft links every deck at once."},
	&"tier2": {"icon": &"star", "text": "**Upgrades** are open! Click a room, then Upgrade for more space and speed."},
	&"tier3": {"icon": &"star", "text": "**Tier III** upgrades are open! Your busiest rooms can go even faster."},
	&"dest_arctic": {"icon": &"ice_rink", "text": "Brr! Guests lose cheer on the **top deck** here. Keep the fun indoors."},
	&"dest_underworld": {"icon": &"ghost", "text": "Spooky! **Ghosts** drift through the decks. Click them before they scare guests."},
	&"event_lunch_rush": {"icon": &"buffet", "text": "Lunch rush! Everyone is hungry, so **food rooms** get busy."},
	&"event_power_surge": {"icon": &"breakdown", "text": "Power surge! Machines break. **Hold** on a broken room to repair it."},
	&"event_film_night": {"icon": &"cinema", "text": "Film night! The **cinema** is extra popular for a while."},
	&"event_pool_party": {"icon": &"pool", "text": "Pool party! The **pool** draws a crowd, and crowds make messes."},
	&"event_food_poisoning": {"icon": &"sick", "text": "Food poisoning! Sick guests need a **Medbay**."},
	&"event_food_poisoning_locked": {"icon": &"sick", "text": "Food poisoning! Sick guests recover slowly until the **Medbay** unlocks."},
	&"event_captains_dinner": {"icon": &"restaurant", "text": "Captain's dinner! The **restaurant** is packed and pays well."},
	&"event_heat_wave": {"icon": &"pool", "text": "Heat wave! Sweaty guests keep **toilets and the pool** busy."},
	&"event_northern_lights": {"icon": &"star", "text": "Northern lights! Guests rush to the **top deck** to watch."},
	&"event_haunting": {"icon": &"ghost", "text": "Haunting! Ghosts are aboard. **Click them** away!"},
}

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
	if port.grid.room_lock_reason(&"elevator") == "" and level.campaign_index >= 7:
		request(&"elevator", 6.5)
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
	card.closed.connect(func() -> void:
		card = null
		_gap = GAP_AFTER)
	_place_card()
	card.play()
	AudioManager.play_sfx(&"alert", 0.0, -9.0)


func _place_card() -> void:
	if card == null or not is_instance_valid(card):
		return
	var bottom: float = screen.get_viewport().get_visible_rect().size.y - 210.0
	if _mode == &"voyage" and screen.hud != null:
		var bb: Control = (screen.hud as VoyageHud).bottom_bar
		if bb != null:
			bottom = bb.global_position.y
	elif _mode == &"port" and _port_ui != null and is_instance_valid(_port_ui) and _port_ui.bar() != null:
		bottom = _port_ui.bar().global_position.y
	card.reset_size()
	card.position = Vector2(24.0, bottom - card.size.y - 14.0)
