extends Control
## Level screen: owns the whole level flow  intro -> port -> "Set sail!" -> voyage -> results.
##
## Params (Router / dev flags):
##   level=<id> (default med_1)   phase=port|voyage|results   autobuild   sim_seconds=<n>   seed=<n>
##   speed=<0..3>  zoom=<0..2>  focus=<x,deck>  autoplay[=active|passive]  selftest=clean|repair|assign|ghost|roster
##   port=<PortState>  (set by Retry: keeps the player's last layout)
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

# --- TUTORIAL INTEGRATION (src/screens/level/tutorial/**) -----------------------------------------
## med_1 walkthrough (null on every other level / when skipped / when Settings.show_tutorial_hints is off) and the
## contextual first-time hints for all levels. Both are plain child nodes with a few phase hooks below.
var tutorial: TutorialDirector = null
var hints: HintDirector = null
var hint_store: HintStore = null
# ---------------------------------------------------------------------------------------------------


func setup(p: Dictionary) -> void:
	params = p


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
	if phase_arg == "port":
		_start_port(true)
		if String(params.get("selftest", "")) == "flow":
			_spawn_selftest()
		elif String(params.get("selftest", "")).begins_with("tutorial"):
			_spawn_tutorial_selftest()
	else:
		_start_voyage(float(params.get("sim_seconds", 0.0)), phase_arg == "results")


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


func _on_port_changed() -> void:
	if phase == Phase.PORT:
		view.set_rooms(LayoutBridge.rooms_from_layout(port.layout))


func _teardown_port() -> void:
	if _port_ui != null and is_instance_valid(_port_ui):
		if _port_ui.has_method(&"teardown"):
			_port_ui.call(&"teardown")
		_port_ui.queue_free()
	_port_ui = null
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
	if from_port:
		ctl.start_delay = 1.1
	ctl.finished.connect(_on_voyage_finished)
	# fast-forward first (nothing is bound yet, so no signal spam)
	if run_to_end:
		ctl.fast_forward(world.duration + 5.0)
	elif ff_seconds > 0.0:
		ctl.fast_forward(ff_seconds)
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
	_tutorial_voyage_started()
	# camera
	cam.set_insets(TOP_INSET, BOTTOM_INSET)
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
	if params.has("selftest") and String(params["selftest"]) != "flow" and not from_port:
		if String(params["selftest"]).begins_with("tutorial"):
			_spawn_tutorial_selftest()
		else:
			_spawn_selftest()
	if world.finished:
		_on_voyage_finished(world.result)


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
		_sea_motion = lerpf(_sea_motion, tgt, clampf(delta * 2.5, 0.0, 1.0))
		sea.set_motion_scale(_sea_motion)
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
	Router.goto("level", {"level": String(level.id), "port": port})


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
	AudioManager.unbind_sim()
	if Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)
