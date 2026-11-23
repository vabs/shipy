extends Control
## Dev screen that runs PortPhase standalone, replicating what LevelScreen does for the host side:
## SeaBackground + ShipView + ShipCamera (with insets) + HUD CanvasLayer + a fake top bar, and the
## ShipView refresh on port.changed.
##
##   godot --path . -- --scene=portdev --level=med_3 --shot=/abs/out.png --frames=60
##
## Params (all optional, "--key=value"):
##   level=<id>          level to build (default med_3)        campaign=<n>   override campaign index (unlocks)
##   budget=<n>          override the starting budget          unlock-all     everything unlocked
##   autobuild           pre-fill the ship with the sim's AutoBuilder
##   nopresets           skip the level's preset rooms/crew     coins=<n>      alias of budget
##   tab=<id>            rest|food|fun|health|transport|utility|crew|manifest
##   arm=<room_id>       arm the placement tool;  at=<deck>,<x>  put the (fake) mouse on that cell
##   hover=<deck>,<x>    fake the mouse over a cell without arming anything (stairs path hint, room hover)
##   carry=<room_id>     pick up the nth placed room of that id (nth=<k>)
##   select=<room_id>    open the popover on the nth placed room of that id
##   hover-card=<id>     show that card's tooltip           collapse     start with the bar collapsed
##   validate            press Set Sail (shows errors / warning dialog)
##   place=<id>@<d>,<x>  really place a room with real input events a few frames before the shot
##   disconnect          drop a cabin on an unreachable deck first (for the validation screenshots)
##   hire=<role>         hire a crew member via the crew tab
##   pose=<name>         hovercard|dragging|hoverroom|hoverstairs: real synthetic events for screenshots
##   selftest=build      run the scripted input self-test and quit with PASS/FAIL
##   zoom=<0|1|2>        camera zoom level
##   nobob               freeze the ship bob            bench   print fps / process ms after 360 frames

var params: Dictionary = {}
var level: LevelDef
var port: PortState
var view: ShipView
var cam: ShipCamera
var sea: SeaBackground
var phase: PortPhase
var money_pill: StatPill
var _frame: int = 0
var _mouse_set: bool = false
var _bench_ms: Array[float] = []
var _bench_draw: Array[float] = []


func setup(p: Dictionary) -> void:
	params = p


func _ready() -> void:
	theme = UITheme.build()
	var level_id: String = String(params.get("level", "med_3"))
	level = ContentStore.level(StringName(level_id))
	if level == null:
		push_error("portdev: unknown level '%s'" % level_id)
		get_tree().quit(1)
		return
	port = PortState.new(level, int(params.get("campaign", "-1")))
	if params.has("unlock-all"):
		port.grid.campaign_index = 99
	if params.has("nopresets"):
		port.layout.rooms.clear()
		port.preset_staff.clear()
		port.grid.invalidate_graph()
	if params.has("budget"):
		port.budget = int(params["budget"])
	if params.has("coins"):
		port.budget = int(params["coins"])
	if params.has("autobuild"):
		AutoBuilder.apply(port, {"budget": port.budget})
	# ---- host-side scene (what LevelScreen owns) ----
	sea = SeaBackground.attach_to(self)
	sea.set_destination(level.destination)
	view = ShipView.new()
	view.bob_enabled = not params.has("nobob")
	add_child(view)
	var hull: HullDef = port.hull
	view.set_hull(hull.width, hull.decks, hull.gangway_deck, level.destination)
	cam = ShipCamera.new()
	add_child(cam)
	cam.set_ship_rect(view.ship_rect())
	cam.set_insets(96.0, 300.0)
	sea.bind_camera(cam, ShipArt.WATERLINE_Y)
	port.changed.connect(_refresh_ship)
	_refresh_ship()
	_build_hud()
	phase = PortPhase.new()
	phase.top_inset = 96.0
	hud_root.add_child(phase)
	var t_setup: int = Time.get_ticks_usec()
	phase.setup(level, port, view, cam)
	if params.has("bench"):
		print("BENCH PortPhase.setup took %.1f ms" % (float(Time.get_ticks_usec() - t_setup) / 1000.0))
	phase.set_sail_requested.connect(func() -> void:
		print("PORTDEV set_sail_requested"))
	phase.exit_requested.connect(func() -> void:
		print("PORTDEV exit_requested"))
	if params.has("zoom"):
		cam.set_zoom_level(int(params["zoom"]))
	if params.has("pose"):
		var pt := PortSelfTest.new()
		add_child(pt)
		pt.run_pose(self, String(params["pose"]))
	if params.get("selftest", "") == "build":
		var st := PortSelfTest.new()
		add_child(st)
		st.run(self)


var hud_root: Control


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	hud_root = Control.new()
	hud_root.theme = UITheme.build()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud_root)
	var top := UIKit.navy_bar()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 88.0
	hud_root.add_child(top)
	var hb := UIKit.hbox(22)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(hb)
	money_pill = UIKit.stat_pill(&"coin", PortBuildBar.fmt_money(port.budget))
	money_pill.custom_minimum_size = Vector2(190, 48)
	hb.add_child(money_pill)
	var lv := UIKit.vbox(0)
	var l1 := Label.new()
	l1.text = level.display_name
	l1.theme_type_variation = &"OnDarkTitle"
	l1.add_theme_font_size_override("font_size", 28)
	lv.add_child(l1)
	var l2 := Label.new()
	l2.text = "%s  -  Port  (portdev)" % String(level.destination).capitalize()
	l2.theme_type_variation = &"OnDarkSmall"
	lv.add_child(l2)
	hb.add_child(lv)
	hb.add_child(UIKit.h_spacer())
	port.changed.connect(func() -> void: money_pill.set_text(PortBuildBar.fmt_money(port.budget)))


func _refresh_ship() -> void:
	view.set_rooms(LayoutBridge.rooms_from_layout(port.layout))


func _process(_delta: float) -> void:
	_frame += 1
	if phase == null:
		return
	if _frame == 4:
		_run_demo()
	if params.has("bench"):
		if _frame > 60:
			_bench_ms.append(float(phase.process_usec) / 1000.0)
			_bench_draw.append(float(phase.overlay().draw_usec) / 1000.0)
		if _frame == 360:
			_bench_ms.sort()
			_bench_draw.sort()
			print("BENCH PortPhase._process ms median=%.3f max=%.3f | overlay._draw ms median=%.3f max=%.3f" % [_bench_ms[_bench_ms.size() / 2], _bench_ms[-1], _bench_draw[_bench_draw.size() / 2], _bench_draw[-1]])
			get_tree().quit()
	if _frame == 8 and params.has("sizes"):
		var b: PortBuildBar = phase.bar()
		print("SIZES bar=", b.size, " min=", b.get_combined_minimum_size())
		for n in b.find_children("*", "Button", true, false):
			var bt := n as Button
			print("  btn '%s' w=%.0f" % [bt.text, bt.size.x])
	if _mouse_set and params.has("at"):
		_place_fake_mouse()


func _first_room(room_id: StringName, nth: int) -> PlacedRoom:
	var k: int = 0
	for r in port.layout.rooms:
		if r.def.id == room_id:
			if k == nth:
				return r
			k += 1
	return null


func _place_fake_mouse() -> void:
	var parts: PackedStringArray = String(params["at"]).split(",")
	var deck: int = int(parts[0])
	var x: float = float(parts[1]) + (float(parts[2]) if parts.size() > 2 else 0.5)
	phase.set_mouse_override(phase.cell_to_screen(deck, x))


func _run_demo() -> void:
	if params.has("collapse"):
		phase.set_bar_collapsed(true)
	if params.has("tab"):
		phase.select_tab(StringName(String(params["tab"])))
	if params.has("disconnect"):
		var deck: int = port.hull.decks - 2
		port.place(&"cabin", deck, 4)
		port.place(&"cabin", deck, 6)
	if params.has("hire"):
		phase.bar().select_tab(&"crew")
		port.hire(StringName(String(params["hire"])))
	if params.has("hover") and not params.has("at"):
		params["at"] = params["hover"]
		_mouse_set = true
	if params.has("arm"):
		phase.arm_tool(StringName(String(params["arm"])))
		_mouse_set = params.has("at")
	if params.has("carry"):
		var r: PlacedRoom = _first_room(StringName(String(params["carry"])), int(params.get("nth", "0")))
		if r != null:
			phase.select_room(r.uid)
			phase.popover().move_requested.emit(r.uid)
			_mouse_set = params.has("at")
	if params.has("select"):
		var r2: PlacedRoom = _first_room(StringName(String(params["select"])), int(params.get("nth", "0")))
		if r2 != null:
			phase.select_room(r2.uid)
	if params.has("hover-card"):
		phase.show_card_tooltip(StringName(String(params["hover-card"])))
	if params.has("place"):
		var spec: PackedStringArray = String(params["place"]).split("@")
		var cell: PackedStringArray = spec[1].split(",")
		phase.arm_tool(StringName(spec[0]))
		phase.set_mouse_override(phase.cell_to_screen(int(cell[0]), float(cell[1]) + 0.5 * float(ContentStore.room(StringName(spec[0])).width)))
		await get_tree().process_frame
		await get_tree().process_frame
		var p: Vector2 = phase.get_viewport().get_mouse_position()
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = true
		mb.position = phase._mouse_screen()
		phase.get_viewport().push_input(mb, true)
		_mouse_set = false
		phase.set_mouse_override(Vector2(-1, -1))
		if p.x < 0.0:
			return
	if params.has("validate"):
		phase.request_set_sail()
