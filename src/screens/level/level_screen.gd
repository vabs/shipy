extends Control
## Level screen: owns the whole level flow  intro -> port -> "Set sail!" -> voyage -> results.
##
## Params (Router / dev flags):
##   level=<id> (default med_1)   phase=port|voyage|results   autobuild   sim_seconds=<n>   seed=<n>
##   speed=<0..3>  zoom=<0..2>  focus=<x,deck>  autoplay[=active|passive]  selftest=clean|repair|assign|ghost|roster
##   port=<PortState>  (set by Retry: keeps the player's last layout)   report=<Dictionary>  (set by Retry: the last
##   voyage's VoyageTelemetry report, offered in port as a "Last voyage" heatmap toggle)
##   storm=<t>  (dev: a storm hits at second t of the voyage)   portstop=<t>  (dev: a mid-voyage port stop at second t, 40% of the guests
##   go ashore, 6 new ones board; add portname=<name> disembark=<0..1> board=<n>)   refitroom=<room id> (dev: arm that tool in the refit and hover
##   a free cell)   refitselect=<room id> (dev: open that room's popover)   castoff=<s> (dev: cast off by itself after s real seconds)   boltshot (dev: freeze a
##   lightning bolt)   stage=seasick (dev: a row of seasick guests, see _dev_stage_seasick)
##   heatmap[=traffic|unhappy|queue]  (dev, with phase=results: open the heatmap straight away)
##   showreport  (dev, with phase=results: open the Voyage report view straight away)
##   lastvoyage  (dev, with phase=port: run a quick voyage first so the port shows the "Last voyage" toggle)
##
## Scene tree:
##   SeaBackLayer(-10)  ShipView + ShipCamera  SeaFrontLayer(4)  WorldCatcher layer(6)  HUD layer(20)
## Port is delegated to PortPhase (src/screens/level/port/port_phase.gd) when it exists, otherwise a tiny
## fallback panel is used. Overlays (ResultsPanel / PauseMenu / Banner) are loaded dynamically from
## src/ui/overlays with minimal fallbacks so this screen never crashes while they are in progress.

const FallbackPort := preload("res://src/screens/level/fallback_port.gd")
const PORT_PHASE_PATH: String = "res://src/screens/level/port/port_phase.gd"
const TOP_INSET: float = 96.0
const BOTTOM_INSET: float = 214.0

enum Phase { INTRO, PORT, VOYAGE, RESULTS }

var params: Dictionary = {}
var level: LevelDef = null
var port: PortState = null
var world: SimWorld = null
var phase: Phase = Phase.INTRO

var sea: SeaBackground = null
var view: ShipView = null
var cam: ShipCamera = null
var hud_layer: CanvasLayer = null
var hud_root: Control = null
var ctl: VoyageController = null
var renderer: VoyageRenderer = null
var input: VoyageInput = null
var hud: VoyageHud = null

var _port_ui: Control = null
# --- storm / mid-voyage port stop (SPEC §13.7 / §13.8)
var _refit: RefitState = null
var _refit_ui: PortPhase = null
var _refit_prev_speed: int = 1
var _last_port_phase: StringName = &""
var _dock_inset_on: bool = false
const DOCK_LEFT_INSET: float = 470.0
var _seed: int = 1
var _intensity_t: float = 0.0
var _sea_motion: float = 0.2
var _sea_motion_target: float = 0.2
var _pause_menu: Control = null
var _menu_prev_speed: int = 1
var _results: Control = null
var _banner_script: Script = null
var _ended: bool = false
var _result: Dictionary = {}
var _selftest: Node = null
var _intro_banner: Node = null
var _menu_closed_frame: int = -1
# --- voyage report heatmap (SPEC §13.2)
var _heat: HeatmapOverlay = null
var _heat_hud: HeatmapHud = null
var _last_toggle: Button = null

# --- TUTORIAL INTEGRATION (src/screens/level/tutorial/**) -----------------------------------------
## med_1 walkthrough (null on every other level / when skipped / when Settings.show_tutorial_hints is off) and the
## contextual first-time hints for all levels. Both are plain child nodes with a few phase hooks below.
var tutorial: TutorialDirector = null
var hints: HintDirector = null
var hint_store: HintStore = null
# ---------------------------------------------------------------------------------------------------


func setup(p: Dictionary) -> void:
	params = p
	OvUtil.dev_save(p)   # --save=/abs/save.json loads a scratch save (dev phases never write the real one)


# =================================================================================================
# build
# =================================================================================================
func _ready() -> void:
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var level_id: StringName = StringName(String(params.get("level", "med_1")))
	level = ContentStore.level(level_id)
	if level == null:
		push_error("LevelScreen: unknown level '%s'" % String(level_id))
		_show_error("Unknown level: %s" % String(level_id))
		return
	_dev_guests()
	_seed = int(params.get("seed", int(Time.get_ticks_usec() & 0x7fffffff)))
	if String(params.get("phase", "port")) != "port" or params.has("selftest") or params.has("nosave"):
		# dev flags must never touch the player's real progress
		SaveManager.save_path = "user://dev_save.json"
	var hull: HullDef = ContentStore.hull(level.hull)
	# --- background, ship, camera
	sea = SeaBackground.attach_to(self)
	sea.set_destination(level.destination)
	sea.set_motion_scale(_sea_motion)
	view = ShipView.new()
	view.name = "ShipView"
	add_child(view)
	view.set_hull(hull.width, hull.decks, hull.gangway_deck, level.destination)
	cam = ShipCamera.new()
	cam.name = "ShipCamera"
	add_child(cam)
	cam.set_ship_rect(view.ship_rect())
	cam.set_insets(TOP_INSET, BOTTOM_INSET)
	cam.shake_enabled = Settings.screen_shake
	Settings.changed.connect(_on_settings_changed)
	sea.bind_camera(cam, ShipArt.WATERLINE_Y)
	# --- HUD layers
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HudLayer"
	hud_layer.layer = 20
	add_child(hud_layer)
	hud_root = Control.new()
	hud_root.name = "HudRoot"
	hud_root.theme = UITheme.build()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud_root)
	_tutorial_create()
	# --- phase
	var phase_arg: String = String(params.get("phase", "port"))
	if params.has("port") and params["port"] is PortState:
		port = params["port"]
	else:
		port = PortState.new(level, level.campaign_index)
		if params.has("autobuild") or phase_arg != "port":
			AutoBuilder.apply(port)
	_dev_crew()
	port.perks = SaveManager.perks()   # company perks from the Shipyard (budget bonus now, the rest at set sail)
	if phase_arg == "port" and params.has("lastvoyage") and not params.has("report"):
		params["report"] = _dev_last_voyage()
	if phase_arg == "port":
		_start_port(true)
		if params.has("tab") and _port_ui != null and _port_ui.has_method(&"select_tab"):
			_port_ui.call(&"select_tab", StringName(String(params["tab"])))
		if String(params.get("selftest", "")) == "flow":
			_spawn_selftest()
		elif String(params.get("selftest", "")).begins_with("tutorial"):
			_spawn_tutorial_selftest()
	else:
		_start_voyage(float(params.get("sim_seconds", 0.0)), phase_arg == "results")


## Dev: plays a quick headless voyage on the current port so the port can show its "Last voyage" heatmap toggle.
func _dev_last_voyage() -> Dictionary:
	var w: SimWorld = port.create_world(_seed)
	var ap := AutoPlayer.new(w, &"human", _seed)
	while not w.finished:
		w.tick(SimConst.TICK)
		ap.tick(SimConst.TICK)
	return w.result.get("report", {})


func _spawn_selftest() -> void:
	_selftest = VoyageSelfTest.new()
	_selftest.name = "SelfTest"
	add_child(_selftest)
	_selftest.call(&"setup", self, String(params["selftest"]))


func _show_error(msg: String) -> void:
	var l := Label.new()
	l.text = msg
	l.position = Vector2(40, 40)
	add_child(l)


func _on_settings_changed(key: StringName) -> void:
	if key == &"screen_shake" and cam != null:
		cam.shake_enabled = Settings.screen_shake


# =================================================================================================
# TUTORIAL INTEGRATION (everything the tutorial needs from this screen; logic lives in tutorial/**)
# =================================================================================================
func _tutorial_create() -> void:
	hint_store = HintStore.for_params(params)
	if not Settings.show_tutorial_hints:
		return
	if HintStore.is_dev(params) and not HintStore.asked_for(params):
		return   # dev launches (--phase / --autobuild / --selftest ...) stay free of tutorial overlays unless they ask
	if level.tutorial and not hint_store.has(&"tutorial") and not params.has("notutorial"):
		tutorial = TutorialDirector.new()
		add_child(tutorial)
		tutorial.setup(self, hint_store)
	hints = HintDirector.new()
	add_child(hints)
	hints.setup(self, hint_store)


func _tutorial_port_started() -> void:
	if tutorial != null:
		tutorial.on_port_started(_port_ui)
	if hints != null:
		hints.on_port_started(_port_ui)


func _tutorial_voyage_started() -> void:
	if tutorial != null:
		tutorial.on_voyage_started()
	if hints != null:
		hints.on_voyage_started()


func _tutorial_voyage_finished() -> void:
	if tutorial != null:
		tutorial.on_voyage_finished()
	if hints != null:
		hints.on_voyage_finished()


func _spawn_tutorial_selftest() -> void:
	_selftest = TutorialSelfTest.new()
	_selftest.name = "TutorialSelfTest"
	add_child(_selftest)
	_selftest.call(&"setup", self, String(params["selftest"]))


# =================================================================================================
# dynamic overlay helpers (MENUS agent classes may not exist yet)
# =================================================================================================
static func script_for_class(cls: String, fallback_path: String = "") -> Script:
	for d in ProjectSettings.get_global_class_list():
		if String(d.get("class", "")) == cls:
			var path: String = String(d.get("path", ""))
			if path != "" and ResourceLoader.exists(path):
				return load(path)
	if fallback_path != "" and ResourceLoader.exists(fallback_path):
		return load(fallback_path)
	return null


func show_banner(title: String, subtitle: String = "", icon: StringName = &"event", color: Color = Palette.TEAL, seconds: float = 2.6) -> Node:
	if _banner_script == null:
		_banner_script = script_for_class("Banner", "res://src/ui/overlays/banner.gd")
	if _banner_script != null and _banner_script.has_method("show_banner"):
		return _banner_script.call("show_banner", hud_root, title, subtitle, icon, color, seconds)
	return VoyageBanner.show_banner(hud_root, title, subtitle, icon, color, seconds)


var _toast_script: Script = null
var _last_toast_msec: int = 0


## Small hint pill at the bottom of the screen (rate limited); uses the shared Toast overlay when present.
func toast(text: String, icon: StringName = &"warning", seconds: float = 2.0) -> void:
	if Time.get_ticks_msec() - _last_toast_msec < 1500:
		return
	_last_toast_msec = Time.get_ticks_msec()
	if _toast_script == null:
		_toast_script = script_for_class("Toast", "res://src/ui/overlays/toast.gd")
	if _toast_script != null and _toast_script.has_method("show_toast"):
		_toast_script.call("show_toast", hud_root, text, icon, seconds)


# =================================================================================================
# port
# =================================================================================================
func _start_port(with_intro: bool) -> void:
	phase = Phase.PORT
	_sea_motion_target = 0.15
	view.bob_enabled = true
	view.set_rooms(LayoutBridge.rooms_from_layout(port.layout))
	if not port.changed.is_connected(_on_port_changed):
		port.changed.connect(_on_port_changed)
	cam.set_insets(TOP_INSET, 260.0)
	cam.fit()
	AudioManager.play_music(&"port")
	var pp: Script = null
	if ResourceLoader.exists(PORT_PHASE_PATH):
		pp = load(PORT_PHASE_PATH)
	if pp != null:
		_port_ui = pp.new()
	else:
		_port_ui = FallbackPort.new()
	_port_ui.name = "PortPhase"
	hud_root.add_child(_port_ui)
	_port_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_port_ui.connect(&"set_sail_requested", _on_set_sail)
	_port_ui.connect(&"exit_requested", _to_map)
	_port_ui.call(&"setup", level, port, view, cam)
	_build_last_voyage_toggle()
	_tutorial_port_started()
	if params.has("autosail"):
		get_tree().create_timer(float(params["autosail"])).timeout.connect(_on_set_sail)
	if with_intro:
		var dest: DestinationDef = ContentStore.destination(level.destination)
		var sub: String = level.blurb
		if dest != null and dest.twist_text != "":
			sub += "\n" + dest.twist_text
		var col: Color = Palette.TEAL
		match level.destination:
			&"arctic": col = Palette.TEAL_DARK
			&"underworld": col = Palette.LILAC_DARK
		# short and tucked against the top edge: the ship (funnel, top deck) and the tutorial card stay clear
		_intro_banner = show_banner(level.display_name, sub, &"event", col, 2.2)
		if _intro_banner != null:
			_intro_banner.set(&"top_y", 4.0)


# ---- "Last voyage" heatmap in port (after Retry) ----------------------------------------------------
func _build_last_voyage_toggle() -> void:
	var rep: Variant = params.get("report", null)
	if not (rep is Dictionary) or (rep as Dictionary).is_empty():
		return
	_last_toggle = UIKit.secondary_button("Last voyage")
	_last_toggle.toggle_mode = true
	_last_toggle.custom_minimum_size = Vector2(230, 54)
	_last_toggle.tooltip_text = "Show where guests walked, waited and got unhappy last time"
	_last_toggle.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_last_toggle.offset_left = -254.0
	_last_toggle.offset_right = -24.0
	_last_toggle.offset_top = 20.0
	_last_toggle.offset_bottom = 74.0
	_last_toggle.z_index = 20
	var ic := PerkIcon.new(&"heatmap", 28.0)
	ic.badge = false
	ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	ic.offset_left = 14.0
	ic.offset_right = 42.0
	ic.offset_top = -16.0
	ic.offset_bottom = 12.0
	_last_toggle.add_child(ic)
	_last_toggle.toggled.connect(_on_last_voyage_toggled)
	hud_root.add_child(_last_toggle)
	if String(params.get("lastvoyage", "")) == "on":
		_last_toggle.button_pressed = true   # dev: start with the heatmap showing


func _on_last_voyage_toggled(on: bool) -> void:
	if phase != Phase.PORT:
		return
	if on:
		_last_toggle.text = "Hide heatmap"
		_open_heatmap(params["report"], "", false)
	else:
		_last_toggle.text = "Last voyage"
		_close_heatmap(false)


## Shows the heatmap of `report` over the ship. `back_text` != "" adds the HUD's back button (results flow: the results
## panel hides meanwhile and `_close_heatmap` brings it back).
func _open_heatmap(report: Dictionary, back_text: String, hide_results: bool, mode: StringName = &"traffic") -> void:
	if _heat != null or report.is_empty():
		return
	if hide_results and _results != null:
		_results.visible = false
	_heat = HeatmapOverlay.new()
	_heat.name = "Heatmap"
	var layer: Node2D = view.get_layer(&"overlay")
	layer.add_child(_heat)
	if not hide_results:
		layer.move_child(_heat, 0)   # port: stay under the placement ghost / hints
	_heat.setup(report, Settings.colorblind or params.has("cb"), view.ship_rect())
	_heat.set_mode(mode)
	_heat_hud = HeatmapHud.new()
	_heat_hud.name = "HeatmapHud"
	hud_root.add_child(_heat_hud)
	_heat_hud.setup(_heat, back_text)
	_heat_hud.closed.connect(func() -> void: _close_heatmap(true))
	if hide_results:
		cam.set_insets(110.0, 150.0)
		cam.fit()


func _close_heatmap(restore_results: bool) -> void:
	if _heat_hud != null and is_instance_valid(_heat_hud):
		_heat_hud.queue_free()
	if _heat != null and is_instance_valid(_heat):
		_heat.queue_free()
	_heat_hud = null
	_heat = null
	if restore_results and _results != null and is_instance_valid(_results):
		_results.visible = true
		cam.set_insets(TOP_INSET, BOTTOM_INSET)
		cam.fit()
	if _last_toggle != null and not restore_results:
		pass
	elif _last_toggle != null and _last_toggle.button_pressed:
		_last_toggle.set_pressed_no_signal(false)
		_last_toggle.text = "Last voyage"


func _on_port_changed() -> void:
	if phase == Phase.PORT:
		view.set_rooms(LayoutBridge.rooms_from_layout(port.layout))


func _teardown_port() -> void:
	if _port_ui != null and is_instance_valid(_port_ui):
		if _port_ui.has_method(&"teardown"):
			_port_ui.call(&"teardown")
		_port_ui.queue_free()
	_port_ui = null
	# the "Last voyage" heatmap and its toggle belong to the port: neither may outlive it (the results' own heatmap needs `_heat` free)
	_close_heatmap(false)
	if _last_toggle != null and is_instance_valid(_last_toggle):
		_last_toggle.queue_free()
	_last_toggle = null
	if port != null and port.changed.is_connected(_on_port_changed):
		port.changed.disconnect(_on_port_changed)


func _on_set_sail() -> void:
	if phase != Phase.PORT:
		return
	AudioManager.play_sfx(&"set_sail_horn")
	if _intro_banner != null and is_instance_valid(_intro_banner):
		_intro_banner.queue_free()
	_intro_banner = null
	_teardown_port()
	show_banner("Set sail!", level.display_name, &"event", Palette.CORAL, 2.0)
	_start_voyage(0.0, false, true)


# =================================================================================================
# voyage
# =================================================================================================
func _start_voyage(ff_seconds: float, run_to_end: bool, from_port: bool = false) -> void:
	phase = Phase.VOYAGE
	_ended = false
	world = port.create_world(_seed)
	world.refit_manual = not run_to_end   # (a fast-forward to the end has nobody to cast off: the sim does it by itself)
	view.set_rooms(LayoutBridge.rooms_from_world(world))
	view.bob_enabled = true
	ctl = VoyageController.new()
	ctl.name = "VoyageController"
	add_child(ctl)
	ctl.setup(world)
	if params.has("autoplay"):
		var mode: StringName = &"passive" if String(params["autoplay"]) == "passive" else &"active"
		ctl.autoplayer = AutoPlayer.new(world, mode, _seed + 11)
	ctl.set_speed(int(params.get("speed", 1)))
	_dev_tired()
	if from_port:
		ctl.start_delay = 1.1
	ctl.finished.connect(_on_voyage_finished)
	# fast-forward first (nothing is bound yet, so no signal spam)
	if run_to_end:
		ctl.fast_forward(world.duration + 5.0)
	elif ff_seconds > 0.0:
		ctl.fast_forward(ff_seconds)
	_dev_incidents()
	if params.has("force_rating"):
		# dev: crush every guest's satisfaction so the mutiny warning / vignette can be screenshotted
		for g in world.guests:
			g.satisfaction = float(params["force_rating"])
		ctl.fast_forward(3.0)
	# renderer / input / hud
	renderer = VoyageRenderer.new()
	renderer.name = "VoyageRenderer"
	add_child(renderer)
	renderer.attach(view, world, ctl)
	renderer.fx.camera = cam
	renderer.fx.bind(world)
	input = VoyageInput.new()
	input.name = "VoyageInput"
	add_child(input)
	hud = VoyageHud.new()
	hud.name = "VoyageHud"
	hud_root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.setup(level, world, ctl, renderer)
	input.setup(world, ctl, renderer, view, cam, hud, self)
	hud.input = input
	hud.focus_requested.connect(_on_focus_requested)
	hud.banner_requested.connect(show_banner)
	_bind_weather_and_port()
	_tutorial_voyage_started()
	# camera
	cam.set_insets(TOP_INSET, BOTTOM_INSET, DOCK_LEFT_INSET if _dock_inset_on else 0.0)
	cam.fit()
	if params.has("zoom"):
		cam.set_zoom_level(int(params["zoom"]))
	if params.has("focus"):
		var parts: PackedStringArray = String(params["focus"]).split(",")
		if parts.size() >= 2:
			cam.focus_on(SimConst.to_px(float(parts[0]), float(parts[1]) + 0.5), int(params.get("zoom", cam.zoom_level)))
	AudioManager.bind_sim(world)
	AudioManager.play_music(&"voyage")
	_sea_motion_target = 1.0
	renderer.update(0.0)
	hud.refresh(0.0)
	_dev_stage_vips_overlay()
	if params.has("selftest") and String(params["selftest"]) != "flow" and not from_port:
		if String(params["selftest"]).begins_with("tutorial"):
			_spawn_tutorial_selftest()
		elif String(params["selftest"]) == "portstop":
			_selftest = PortStopSelfTest.new()
			_selftest.name = "PortStopSelfTest"
			add_child(_selftest)
			_selftest.call(&"setup", self, "portstop")
		else:
			_spawn_selftest()
	if world.finished:
		_on_voyage_finished(world.result)


## Dev flags --vips=critic:20,celebrity:40,inspector:60 (kind:boarding second) and --groups=<0..1> (share of every wave that
## travels as couples / families): play a private copy of the level with VIPs / groups switched on (the content is untouched).
func _dev_guests() -> void:
	if not params.has("vips") and not params.has("groups") and not params.has("storm") and not params.has("portstop"):
		return
	level = level.duplicate(true)
	if params.has("storm"):
		var evs: Array[Dictionary] = []
		for e in level.scheduled_events:
			evs.append(e)
		evs.append({"t": float(params["storm"]), "event": &"storm"})
		level.scheduled_events = evs
	if params.has("portstop"):
		level.port_stop = {"t": float(params["portstop"]), "name": String(params.get("portname", _dev_port_name(level.destination))),
				"disembark": float(params.get("disembark", 0.4)), "board": int(params.get("board", 6))}
	if params.has("vips"):
		var list: Array[Dictionary] = []
		for part in String(params["vips"]).split(","):
			var kv: PackedStringArray = part.split(":")
			if kv.size() >= 1 and kv[0] != "":
				list.append({"t": float(kv[1]) if kv.size() > 1 else 10.0, "kind": StringName(kv[0])})
		level.vips = list
	if params.has("groups"):
		level.group_ratio = clampf(float(params["groups"]), 0.0, 1.0)


static func _dev_port_name(dest: StringName) -> String:
	match dest:
		&"arctic": return "Tromso Cove"
		&"underworld": return "Cinder Quay"
	return "Santorini"


## Dev flag --crew=janitor:2,medic:1,...: replaces the crew with exactly this (free preset crew, ignores unlocks).
func _dev_crew() -> void:
	if not params.has("crew"):
		return
	var counts: Dictionary = {}
	for part in String(params["crew"]).split(","):
		var kv: PackedStringArray = part.split(":")
		if kv.size() >= 1 and kv[0] != "":
			counts[StringName(kv[0])] = int(kv[1]) if kv.size() > 1 else 1
	port.preset_staff = counts
	for k in port.hired.keys():
		port.hired[k] = 0
	port.changed.emit()


## Dev flag --tired=<energy>: crew start the voyage worn out (every third one with double / a fraction of that energy).
func _dev_tired() -> void:
	if not params.has("tired"):
		return
	var e: float = float(params["tired"])
	for i in world.staff.size():
		world.staff[i].energy = clampf(e * [1.0, 2.0, 0.4][i % 3], 0.0, 100.0)


## Dev flags --sicken=<n> / --ghosts=<n>: n guests fall ill / n ghosts appear right after the fast-forward.
func _dev_incidents() -> void:
	if params.has("sicken"):
		var n: int = int(params["sicken"])
		for g in world.guests:
			if n <= 0:
				break
			if g.mode != Guest.GONE and not g.sick:
				world.problems.infect(world, g)
				n -= 1
	if params.has("ghosts"):
		for i in int(params["ghosts"]):
			world.problems.spawn_ghost(world)
	if params.has("jam"):
		_dev_jam(StringName(String(params["jam"])))
	if String(params.get("stage", "")) == "seasick":
		_dev_stage_seasick()
	if String(params.get("stage", "")) == "crew":
		_dev_stage_crew()
	if String(params.get("stage", "")) == "vips":
		_dev_stage_vips()
	if params.has("wait"):
		ctl.fast_forward(float(params["wait"]))


## Dev flag --stage=crew (use with --speed=0 and --crew=...): freezes a showcase on one deck: the entertainer juggling
## at a queue, the chef cooking at the food room, the medic treating a sick guest, the warden channelling at a ghost
## and the janitor scrubbing a spill. Poses are set directly, nothing ticks while paused.
func _dev_stage_crew() -> void:
	var food: RoomRuntime = null
	for r in world.room_sim.service_rooms:
		if r.def.category == &"food":
			food = r
			break
	if food == null:
		return
	_dev_jam(food.def.id)
	var deck: int = food.deck
	var spare: Array[Guest] = []
	for g in world.guests:
		if g.mode == Guest.WANDER or g.mode == Guest.WALK:
			spare.append(g)
	for s in world.staff:
		match s.role:
			&"entertainer":
				s.set_position(deck, world.room_sim.queue_spot_x(world, food, food.queue.size() / 2))
				s.state = &"perform"
				s.aura_uid = food.uid
				s.facing = -1
			&"chef":
				s.set_position(deck, food.door_x + 0.8)
				s.state = &"station"
				s.aura_uid = food.uid
				s.facing = -1
				food.chef_on = true
			&"medic":
				if not spare.is_empty():
					var sg: Guest = spare.pop_back()
					sg.clear_route()
					sg.mode = Guest.WANDER
					sg.state = Guest.WANDER
					sg.set_position(deck, food.door_x + 3.6)
					world.problems.infect(world, sg)
					sg.hold_until = 1.0e6
					var sj: Job = world.staff_sim.jobs.find(&"sick", sg.id)
					if sj != null:
						sj.claimed_by = s.id
						s.job = sj
						s.work_kind = &"sick"
						s.work_target_id = sg.id
					s.set_position(deck, sg.x - 0.8)
					s.state = &"work"
					s.facing = 1
			&"warden":
				var gh: Ghost = world.problems.spawn_ghost(world)
				gh.deck = deck
				gh.deck_f = float(deck)
				gh.prev_deck_f = gh.deck_f
				gh.x = food.door_x + 6.6
				gh.prev_x = gh.x
				gh.age = 5.0
				var gj: Job = world.staff_sim.jobs.find(&"ghost", gh.id)
				if gj != null:
					gj.claimed_by = s.id
					s.job = gj
					s.work_kind = &"ghost"
					s.work_target_id = gh.id
				s.set_position(deck, gh.x - 1.2)
				s.state = &"work"
				s.facing = 1
			&"janitor":
				var m: Mess = world.problems.spawn_mess(world, food)
				if m != null:
					s.set_position(deck, m.x + 0.7)
					s.state = &"work"
					s.work_kind = &"mess"
					s.facing = -1
			&"mechanic":
				s.set_position(deck, food.door_x + 9.0)
				s.state = &"walk"


## Dev flag --stage=seasick (use with --storm, --speed=0 and --zoom=3 --focus=<x>,<deck>): a row of guests on one deck in front of the first
## food room: a normal one, three seasick ones (one treated by the medic if there is one) and, for contrast, a food-sick one.
func _dev_stage_seasick() -> void:
	var food: RoomRuntime = null
	for r in world.room_sim.service_rooms:
		if r.def.category == &"food":
			food = r
			break
	if food == null:
		return
	var deck: int = food.deck
	var spare: Array[Guest] = []
	for g in world.guests:
		if g.is_aboard() and g.mode != Guest.BOARDING:
			spare.append(g)
	var x0: float = food.door_x - 2.0
	for i in mini(5, spare.size()):
		var g: Guest = spare[i]
		g.clear_route()
		g.mode = Guest.WANDER
		g.state = Guest.WANDER
		g.set_position(deck, x0 + 1.15 * float(i))
		g.facing = 1 if i % 2 == 0 else -1
		g.wander_pause = 1.0e6
		g.eval_timer = 1.0e6
		g.hold_until = 1.0e6
		match i:
			1, 2, 3:
				world.guest_sim.make_seasick(world, g, 999.0)
			4:
				world.problems.infect(world, g)
	print("STAGE seasick: staged on deck %d, x %.1f" % [deck, x0])


var _stage_pin: int = -1
var _stage_verdicts: Array[Array] = []


## Dev flag --stage=vips (use with --speed=0, --vips=critic:..,celebrity:..,inspector:.. and --groups=...): freezes a showcase in front
## of the kids' club: a family (the kid in the ball pit), the three VIPs in the corridor, the first family member pinned (tooltip),
## a spill next to the inspector, and a verdict plate over the critic. Poses are set directly, nothing ticks while paused.
func _dev_stage_vips() -> void:
	var club: RoomRuntime = null
	for r in world.room_sim.service_rooms:
		if r.def.id == &"kids_club":
			club = r
			break
	if club == null:
		for r in world.room_sim.service_rooms:
			if r.def.category == &"fun":
				club = r
				break
	if club == null:
		return
	var deck: int = club.deck
	var base: float = club.door_x
	for r in world.rooms:
		if r.broken:
			world.room_sim.repair_room(world, r)   # a clean showcase: nothing is out of order
	print("STAGE vips: staged in front of the %s on deck %d, door x %.1f" % [club.def.display_name, deck, base])
	var fam: GuestGroup = null
	for grp in world.groups:
		if grp.kids > 0:
			fam = grp
			break
	if fam != null:
		var kid_n: int = 0
		for i in fam.members.size():
			var g: Guest = world.guest_by_id(fam.members[i])
			g.clear_route()
			if g.is_kid() and kid_n < 2 and club.def.id == &"kids_club":
				world.guest_sim.start_use(world, g, club)
				g.use_timer = g.use_dur * 0.6
				kid_n += 1
			else:
				g.mode = Guest.WANDER
				g.state = Guest.WANDER
				g.set_position(deck, base - 2.6 - 1.0 * float(i))
				g.facing = 1
				g.wander_pause = 1.0e6
				g.eval_timer = 1.0e6
		_stage_pin = fam.members[0]
		# a second family member close behind, so the link between them reads
	var spots: Dictionary = {&"critic": 3.2, &"celebrity": 5.6, &"inspector": 8.2}
	var pos_x: Dictionary = {}
	for v in world.vip_sim.members:
		var x: float = float(spots.get(v.vip_kind, 5.0)) + base
		x = clampf(x, 1.0, float(world.grid.hull.width) - 1.5)
		v.clear_route()
		v.set_position(deck, x)
		v.facing = -1 if v.vip_kind != &"inspector" else 1
		v.mode = Guest.WANDER
		v.state = Guest.WANDER
		v.wander_pause = 1.0e6
		v.eval_timer = 1.0e6
		pos_x[v.vip_kind] = x
		if v.vip_kind == &"inspector":
			v.mode = Guest.INSPECT
			v.state = Guest.INSPECT
			v.vip_score = 2.0
		elif v.vip_kind == &"critic":
			v.vip_score = 40.0
			v.vip_n = 1
	if pos_x.has(&"inspector"):
		var m: Mess = world.problems.spawn_mess(world, club)
		if m != null:
			m.x = float(pos_x[&"inspector"]) + 1.1
			world.problems.mess_cells.clear()
			world.problems.mess_cells[world.problems.cell_key(m.deck, int(m.x))] = m.id
	if String(params.get("verdict", "")) != "":
		for part in String(params["verdict"]).split(","):
			var kv: PackedStringArray = part.split(":")
			if kv.size() == 2:
				_stage_verdicts.append([StringName(kv[0]), StringName(kv[1])])


## After the renderer / input exist: pin the staged guest's tooltip and drop the requested verdict plates (--verdict=critic:great,...).
func _dev_stage_vips_overlay() -> void:
	if String(params.get("stage", "")) != "vips":
		return
	if params.has("pin"):
		_stage_pin = int(params["pin"])
	if _stage_pin >= 0 and not params.has("nopin"):
		input.pinned_guest_id = _stage_pin
		renderer.pinned_guest_id = _stage_pin
	for e in _stage_verdicts:
		for v in world.vip_sim.members:
			if v.vip_kind == e[0]:
				renderer.fx._on_vip_verdict(v.id, v.vip_kind, e[1])
				hud._on_vip_verdict(v.id, v.vip_kind, e[1])
				hud.alerts._on_vip_verdict(v.id, v.vip_kind, e[1])
	for fx_e in renderer.fx._fx:
		fx_e["t0"] = float(fx_e["t0"]) - 0.55


## Dev flag --jam=<room id>: that room is "full" and six guests queue up outside it (to show the entertainer's show).
func _dev_jam(room_id: StringName) -> void:
	var room: RoomRuntime = null
	for r in world.rooms:
		if r.def.id == room_id and r.def.is_service_room():
			room = r
			break
	if room == null:
		return
	var fid: int = 900000
	while room.users.size() < room.capacity():
		room.users.append(fid)   # fake occupants keep the line from moving
		fid += 1
	var n: int = 0
	for g in world.guests:
		if n >= 6:
			break
		if g.mode == Guest.GONE or g.mode == Guest.STORM_OFF or g.mode == Guest.BOARDING:
			continue
		g.clear_route()
		g.mode = Guest.QUEUE
		g.state = Guest.QUEUE
		g.target_uid = room.uid
		g.patience = 28.0
		room.queue.append(g.id)
		g.queue_index = n
		g.queue_x = world.room_sim.queue_spot_x(world, room, n)
		g.set_position(room.deck, g.queue_x)
		n += 1


var _bench_frames: int = 0
var _bench_acc: float = 0.0
var _bench_draw: float = 0.0


func _bench_tick() -> void:
	_bench_frames += 1
	if _bench_frames > 120:
		_bench_acc += Performance.get_monitor(Performance.TIME_PROCESS)
		_bench_draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	if _bench_frames == 420:
		var n: float = 300.0
		print("BENCH fps=%.1f process_ms=%.2f draw_calls=%.0f guests=%d messes=%d" % [Engine.get_frames_per_second(), _bench_acc / n * 1000.0, _bench_draw / n, world.guests.size(), world.messes.size()])
		get_tree().quit()


func _process(delta: float) -> void:
	if params.has("bench") and world != null:
		_bench_tick()
	if sea != null:
		var tgt: float = _sea_motion_target
		if phase == Phase.VOYAGE and ctl != null:
			tgt = [0.0, 1.0, 1.7, 2.4][clampi(ctl.speed, 0, 3)] if not _ended else 0.35
			if world != null:
				tgt *= 1.0 - world.port_stop.dock_progress   # the sea scroll eases to a stop as the ship glides up to the quay
		_sea_motion = lerpf(_sea_motion, tgt, clampf(delta * 2.5, 0.0, 1.0))
		sea.set_motion_scale(_sea_motion)
		if phase == Phase.VOYAGE and world != null:
			_update_weather_and_dock()
	if phase == Phase.VOYAGE and world != null and ctl != null:
		if view != null:
			view.anim_speed = float(ctl.speed) if ctl.speed > 0 else 0.0
		renderer.update(delta)
		hud.refresh(delta)
		_intensity_t -= delta
		if _intensity_t <= 0.0:
			_intensity_t = 0.5
			_update_music_intensity()


func _update_music_intensity() -> void:
	var st: Dictionary = world.stats()
	var rating: float = float(st["rating"])
	var problems: float = float(st["problems"])
	var i: float = 0.25 + clampf((70.0 - rating) / 50.0, 0.0, 1.0) * 0.45 + clampf(problems / 10.0, 0.0, 1.0) * 0.3
	if world.mutiny_active:
		i = 1.0
	AudioManager.set_music_intensity(clampf(i, 0.0, 1.0))


func _on_focus_requested(local_pos: Vector2) -> void:
	cam.focus_on(local_pos, maxi(cam.zoom_level, 1))


# =================================================================================================
# end of voyage
# =================================================================================================
func _on_voyage_finished(result: Dictionary) -> void:
	if _ended:
		return
	_ended = true
	_result = result
	_close_refit()
	AudioManager.set_ambience(&"rain", 0.0)
	_tutorial_voyage_finished()
	ctl.set_speed(0)
	if input != null:
		input.enabled = false
	var mutiny: bool = bool(result.get("mutiny", false))
	if mutiny:
		show_banner("Mutiny!", "The guests have taken over the ship...", &"angry", Palette.CORAL_DARK, 2.4)
		cam.shake(5.0, 0.6)
	else:
		show_banner("Voyage complete!", level.display_name, &"star", Palette.MINT_DARK, 2.0)
	var unlocks: Dictionary = SaveManager.record_result(result)
	var delay: float = 0.4 if bool(params.get("phase", "") == "results") else 1.8
	get_tree().create_timer(delay).timeout.connect(func() -> void: _show_results(result, unlocks))


func _show_results(result: Dictionary, unlocks: Dictionary) -> void:
	if not is_inside_tree():
		return
	phase = Phase.RESULTS
	if hud != null:
		hud.visible = false
	if hints != null:
		hints.on_results_shown(result, unlocks)
	var rp: Script = script_for_class("ResultsPanel", "res://src/ui/overlays/results_panel.gd")
	if rp != null:
		_results = rp.new()
		hud_root.add_child(_results)
		_results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if _results.has_method(&"show_result"):
			_results.call(&"show_result", result, unlocks, level)
		for pair in [[&"retry_pressed", _retry], [&"next_pressed", _next], [&"map_pressed", _to_map]]:
			if _results.has_signal(pair[0]):
				_results.connect(pair[0], pair[1])
		if _results.has_signal(&"heatmap_pressed"):
			_results.connect(&"heatmap_pressed", func() -> void: _open_heatmap(result.get("report", {}), "Back to results", true))
		if params.has("showreport") and _results.has_method(&"show_report"):
			_results.call_deferred(&"show_report")
		if params.has("heatmap"):
			var hm_mode: StringName = StringName(String(params["heatmap"])) if String(params["heatmap"]) in ["traffic", "unhappy", "queue"] else &"traffic"
			_open_heatmap.call_deferred(result.get("report", {}), "Back to results", true, hm_mode)
	else:
		_results = VoyageResultsFallback.new()
		hud_root.add_child(_results)
		_results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_results.call(&"show_result", result, unlocks, level)
		_results.connect(&"retry_pressed", _retry)
		_results.connect(&"next_pressed", _next)
		_results.connect(&"map_pressed", _to_map)
	if params.has("selftest") and _selftest != null:
		pass


func _retry() -> void:
	var p: Dictionary = {"level": String(level.id), "port": port}
	var rep: Variant = _result.get("report", null)
	if rep is Dictionary and not (rep as Dictionary).is_empty():
		p["report"] = rep   # the port offers it as a "Last voyage" heatmap toggle
	Router.goto("level", p)


func _next() -> void:
	var nxt: StringName = SaveManager.next_level_id(level.id)
	if nxt == &"" or not SaveManager.is_level_unlocked(nxt):
		_to_map()
	else:
		Router.goto("level", {"level": String(nxt)})


func _to_map() -> void:
	if ResourceLoader.exists("res://src/screens/map/map_screen.gd"):
		Router.goto("map")
	else:
		Router.goto("menu")


# =================================================================================================
# pause / keys
# =================================================================================================
func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.VOYAGE or ctl == null or _ended:
		return
	if _pause_menu != null:
		return  # the menu owns the keyboard while it is open
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if event.is_action_pressed(&"pause"):
			ctl.toggle_pause()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"speed_1"):
			ctl.set_speed(1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"speed_2"):
			ctl.set_speed(2)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"speed_3"):
			ctl.set_speed(3)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"cancel"):
			if Engine.get_process_frames() == _menu_closed_frame:
				return
			if input != null and input.has_selection():
				input.cancel()
			else:
				open_pause_menu()
			get_viewport().set_input_as_handled()


func open_pause_menu() -> void:
	if _pause_menu != null or phase != Phase.VOYAGE:
		return
	_menu_prev_speed = ctl.speed
	ctl.set_speed(0)
	var pm: Script = script_for_class("PauseMenu", "res://src/ui/overlays/pause_menu.gd")
	if pm != null:
		_pause_menu = pm.new()
	else:
		_pause_menu = VoyagePauseFallback.new()
	if _pause_menu.has_method(&"set_level"):
		_pause_menu.call(&"set_level", level)
	hud_root.add_child(_pause_menu)
	_pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _pause_menu.has_signal(&"resume_pressed"):
		_pause_menu.connect(&"resume_pressed", _resume_from_menu)
	if _pause_menu.has_signal(&"restart_pressed"):
		_pause_menu.connect(&"restart_pressed", _retry)
	if _pause_menu.has_signal(&"quit_pressed"):
		_pause_menu.connect(&"quit_pressed", _to_map)


func _resume_from_menu() -> void:
	_menu_closed_frame = Engine.get_process_frames()
	if _pause_menu != null:
		_pause_menu.queue_free()
		_pause_menu = null
	if ctl != null and ctl.speed == 0:
		ctl.set_speed(maxi(_menu_prev_speed, 1))


func _exit_tree() -> void:
	AudioManager.set_ambience(&"rain", 0.0)
	AudioManager.unbind_sim()
	_close_refit()
	if Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)


# =================================================================================================
# storms (SPEC §13.7) and the mid-voyage port stop (SPEC §13.8)
# =================================================================================================
func _bind_weather_and_port() -> void:
	world.refit_manual = true   # the player casts off (the sim holds still until then)
	world.port_stop_started.connect(_on_port_stop_started)
	world.port_stop_ready.connect(_on_port_stop_ready)
	world.port_stop_ended.connect(_on_port_stop_ended)
	world.room_added.connect(_on_refit_rooms_changed.unbind(1))
	world.room_upgraded.connect(_on_refit_rooms_changed.unbind(1))
	sea.lightning.connect(_on_lightning)
	sea.dev_hold_bolt = params.has("boltshot")
	if world.port_stop.configured:
		var gd: int = world.grid.hull.gangway_deck
		sea.set_dock_anchor(Vector2(-84.0, -float(gd) * SimConst.DECK_H + 18.0))
	_last_port_phase = world.port_stop.phase
	if world.port_stop.is_ready():
		_on_port_stop_ready()   # (a dev fast-forward can end right at the quay)
	elif world.port_stop.is_active():
		_dock_inset_on = true


func _update_weather_and_dock() -> void:
	var storm: float = world.weather_intensity
	sea.set_weather(storm)
	view.weather = storm
	if not _ended:
		AudioManager.set_ambience(&"rain", storm)
	var ps: PortStop = world.port_stop
	sea.set_dock(ps.dock_progress, ps.stop_name)
	if ps.phase != _last_port_phase:
		if ps.phase == PortStop.EXCURSION and ps.excursion_count > 0:
			Banner.show_compact(hud, "Shore leave!", "%d guest%s heading ashore" % [ps.excursion_count, "" if ps.excursion_count == 1 else "s"],
					&"guest", Palette.TEAL_DARK, 3.4, Vector2(24.0, VoyageHud.TOP_H + 14.0 + 50.0))
		elif ps.phase == PortStop.DONE and _dock_inset_on:
			_dock_inset_on = false
			cam.set_insets(TOP_INSET, BOTTOM_INSET)
			cam.fit()
		_last_port_phase = ps.phase


func _on_lightning(strength: float) -> void:
	if _ended or phase != Phase.VOYAGE:
		return
	# the light comes first; the thunder rolls in a beat later and the ship shudders a little
	var delay: float = 0.25 + randf() * 0.5
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if is_inside_tree() and not _ended:
			AudioManager.play_sfx(&"thunder", 0.05, -6.0 + 5.0 * strength)
			if cam != null:
				cam.shake(2.2 * strength, 0.35))


func _on_port_stop_started(stop_name: String) -> void:
	show_banner("Docking at %s" % stop_name, "Hold on tight: we are pulling into port", &"event", Palette.TEAL_DARK, 3.4)
	sea.set_dock(0.0, stop_name)
	_dock_inset_on = true
	cam.set_insets(TOP_INSET, BOTTOM_INSET, DOCK_LEFT_INSET)
	cam.fit()


## The excursion is over and the sim holds still: pause, hide the crew bar and open the Quick refit panel.
func _on_port_stop_ready() -> void:
	if _refit_ui != null or _ended:
		return
	_refit_prev_speed = ctl.speed if ctl.speed > 0 else maxi(ctl.last_speed, 1)
	ctl.set_speed(0)
	ctl.locked = true
	if input != null:
		input.cancel()
		input.enabled = false
	hud.set_refit_mode(true)
	_refit = RefitState.new(world)
	_refit_ui = PortPhase.new()
	_refit_ui.name = "RefitPhase"
	_refit_ui.left_inset = DOCK_LEFT_INSET
	hud_root.add_child(_refit_ui)
	_refit_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refit_ui.connect(&"set_sail_requested", _on_cast_off)
	_refit_ui.setup(level, _refit, view, cam)
	_refit.changed.connect(_on_refit_rooms_changed)
	AudioManager.play_sfx(&"alert", 0.0, -8.0)
	if params.has("refitroom") or params.has("refitselect"):
		get_tree().create_timer(1.2).timeout.connect(_dev_refit_pose)
	if params.has("castoff"):
		get_tree().create_timer(float(params["castoff"])).timeout.connect(_on_cast_off)   # dev: cast off by itself after n real seconds


## Dev flags --refitroom=<room id> (arm that tool and hover a free cell: the placement ghost) and --refitselect=<room id> (open the popover
## of the first such room), for screenshots of the Quick refit.
func _dev_refit_pose() -> void:
	if _refit_ui == null or world == null:
		return
	if params.has("refitselect"):
		for r in world.rooms:
			if r.def.id == StringName(String(params["refitselect"])):
				_refit_ui.select_room(r.uid)
				break
	if params.has("refitroom"):
		var rid: StringName = StringName(String(params["refitroom"]).split(":")[0])
		_refit_ui.select_tab(_refit_ui.bar().tab_of(rid))
		_refit_ui.arm_tool(rid)
		var spot: Vector2i = Vector2i(-1, -1)
		var def: RoomDef = ContentStore.room(rid)
		for d in range(world.grid.hull.decks - 1, -1, -1):
			for x in range(world.grid.hull.width - def.width, -1, -1):
				if bool(world.can_add_room(rid, d, x)["ok"]):
					var p: Vector2 = _refit_ui.cell_to_screen(d, float(x) + float(def.width) * 0.5)
					if p.y > 140.0 and p.y < _refit_ui.bar().global_position.y - 30.0 and p.x > 560.0 and p.x < 1700.0:
						spot = Vector2i(x, d)
						break
			if spot.x >= 0:
				break
		if spot.x >= 0:
			_refit_ui.set_mouse_override(_refit_ui.cell_to_screen(spot.y, float(spot.x) + float(def.width) * 0.5))


func _on_refit_rooms_changed() -> void:
	if view == null or world == null:
		return
	view.set_rooms(LayoutBridge.rooms_from_world(world))
	if renderer != null:
		renderer.refresh_rooms()


func _on_cast_off() -> void:
	if _refit_ui == null:
		return
	_close_refit()
	world.cast_off()
	if hud != null:
		hud.set_refit_mode(false)
	if input != null:
		input.enabled = true
	ctl.locked = false
	ctl.set_speed(maxi(_refit_prev_speed, 1))
	cam.set_insets(TOP_INSET, BOTTOM_INSET, DOCK_LEFT_INSET if _dock_inset_on else 0.0)
	cam.fit()


func _on_port_stop_ended() -> void:
	var n: int = world.port_stop.board
	show_banner("Cast off!", "%d new guest%s coming aboard" % [n, "" if n == 1 else "s"] if n > 0 else "Next stop: the horizon", &"event", Palette.CORAL, 2.4)


## Tears the Quick refit panel down and hands the grid back to the sim.
func _close_refit() -> void:
	if _refit_ui != null and is_instance_valid(_refit_ui):
		_refit_ui.teardown()
		_refit_ui.queue_free()
	_refit_ui = null
	if _refit != null:
		if _refit.changed.is_connected(_on_refit_rooms_changed):
			_refit.changed.disconnect(_on_refit_rooms_changed)
		_refit.close()
	_refit = null
