extends Control
## Main menu: a living title scene (sunny sea + bobbing cruise ship with waving guests), a chunky hand-built
## logo and Continue / Play / Settings / Quit.
##
## Dev overlay previews (shown on top of the living scene, fake data, nothing is saved):
##   --scene=menu --overlay=results [--stars=0..3] [--mutiny] [--level=med_3] [--unlocks=0]
##   --scene=menu --overlay=pause [--settings]        --scene=menu --overlay=confirm
##   --scene=menu --overlay=banner                     --scene=menu --overlay=toast
## Screenshot after the intro: use --frames=150 (results reveal: --frames=260).

const BTN_W: float = 410.0

var _params: Dictionary = {}
var _sea: SeaBackground
var _stage: MenuStage
var _ui_layer: CanvasLayer
var _ui_root: Control
var _logo: MenuLogo
var _col: VBoxContainer
var _slots: Array[Control] = []
var _fade: ColorRect
var _leaving: bool = false
var _t: float = 0.0
var _enter_t: float = 0.0
var _next_level: LevelDef = null
var _star_pill: StarCounter
var _focus_btn: Button = null


func setup(params: Dictionary) -> void:
	_params = params
	OvUtil.dev_save(params)


func _ready() -> void:
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sea = SeaBackground.attach_to(self)
	_sea.set_destination(&"med")
	_sea.set_motion_scale(0.7)
	_stage = MenuStage.new()
	add_child(_stage)
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)
	_ui_root = Control.new()
	_ui_root.theme = UITheme.build()  # CanvasLayer breaks theme inheritance
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_ui_root)
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_intro()
	AudioManager.play_music(&"port")
	if _params.has("overlay"):
		_dev_overlay(String(_params["overlay"]))


# ================================================================================================
# UI
# ================================================================================================
func _find_next_level() -> LevelDef:
	var camp: Array[LevelDef] = ContentDB.campaign()
	var any_played: bool = false
	for lv in camp:
		if bool(SaveManager.best_for(lv.id)["played"]):
			any_played = true
			break
	if not any_played:
		return null
	for lv in camp:
		if SaveManager.is_level_unlocked(lv.id) and SaveManager.stars_for(lv.id) == 0:
			return lv
	for lv in camp:
		if SaveManager.is_level_unlocked(lv.id) and SaveManager.stars_for(lv.id) < 3:
			return lv
	return camp.back() if not camp.is_empty() else null


func _build_ui() -> void:
	_next_level = _find_next_level()
	_logo = MenuLogo.new()
	_ui_root.add_child(_logo)
	_col = UIKit.vbox(16)
	_ui_root.add_child(_col)
	var hero_is_continue: bool = _next_level != null
	if hero_is_continue:
		var cont := _hero_button("Continue", "Level %d  -  %s" % [_next_level.campaign_index, _next_level.display_name], UIKit.primary_button(""))
		cont.pressed.connect(func() -> void: _go("level", {"level": String(_next_level.id)}))
		_add_slot(cont, 100.0)
		_focus_btn = cont
	var play: Button
	if hero_is_continue:
		play = UIKit.secondary_button("Play")
		play.custom_minimum_size = Vector2(BTN_W, 74)
		OvUtil.set_font_px(play, 26)
	else:
		play = _hero_button("Play", "Set sail on a new adventure", UIKit.primary_button(""))
		_focus_btn = play
	OvUtil.focusable(play)
	play.pressed.connect(func() -> void: _go("map"))
	_add_slot(play, 100.0 if not hero_is_continue else 74.0)
	var sets := UIKit.sun_button("Settings")
	sets.custom_minimum_size = Vector2(BTN_W, 66)
	OvUtil.set_font_px(sets, 24)
	OvUtil.focusable(sets)
	sets.pressed.connect(func() -> void: _go("settings", {"back": "menu"}))
	_add_slot(sets, 66.0)
	if not OS.has_feature("web"):
		var quit := UIKit._btn("Quit", &"Button")
		quit.custom_minimum_size = Vector2(BTN_W, 62)
		OvUtil.set_font_px(quit, 22)
		OvUtil.focusable(quit)
		quit.pressed.connect(func() -> void: get_tree().quit())
		_add_slot(quit, 62.0)
	# star total (only once there is progress)
	if _next_level != null:
		_star_pill = StarCounter.new()
		_star_pill.set_count(SaveManager.total_stars(), maxi(ContentDB.campaign().size() * 3, 1))
		_ui_root.add_child(_star_pill)
	# credit line
	var ver := Label.new()
	ver.theme_type_variation = &"OnDarkSmall"
	ver.text = "Cruise Ship Manager  v0.1"
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	ver.add_theme_color_override("font_outline_color", Color(0.1, 0.16, 0.3, 0.6))
	ver.add_theme_constant_override("outline_size", 4)
	ver.name = "Version"
	_ui_root.add_child(ver)
	_fade = ColorRect.new()
	_fade.color = Color(0.08, 0.11, 0.2, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_fade)
	create_tween().tween_property(_fade, "modulate:a", 0.0, 0.35)


func _hero_button(title: String, sub: String, b: Button) -> Button:
	b.custom_minimum_size = Vector2(BTN_W, 100)
	OvUtil.focusable(b, Palette.SUN, 14)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_bottom = -6.0
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := Label.new()
	tl.text = title
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_override("font", UITheme.font_bold())
	tl.add_theme_font_size_override("font_size", 38)
	tl.add_theme_color_override("font_color", Color.WHITE)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tl)
	var sl := Label.new()
	sl.text = sub
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.add_theme_font_override("font", UITheme.font())
	sl.add_theme_font_size_override("font_size", 19)
	sl.add_theme_color_override("font_color", Color(1, 1, 1, 0.88))
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sl)
	b.add_child(v)
	return b


func _add_slot(btn: Button, h: float) -> void:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(BTN_W, h)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(btn)
	_col.add_child(slot)
	_slots.append(slot)


func _layout() -> void:
	var vs: Vector2 = get_viewport_rect().size
	var cx: float = clampf(vs.x * 0.255, 380.0, 560.0)
	var sc_logo: float = clampf(minf(vs.x * 0.46, 840.0) / 840.0, 0.6, 1.0)
	_logo.scale = Vector2(sc_logo, sc_logo)
	_logo.pivot_offset = Vector2(420, 0)
	_logo.position = Vector2(cx - 420.0, vs.y * 0.045)
	var col_top: float = _logo.position.y + 340.0 * sc_logo + 16.0
	_col.size = Vector2(BTN_W, 0)
	_col.position = Vector2(cx - BTN_W * 0.5, col_top)
	# ship
	var wl: float = vs.y * 0.83
	var rect: Rect2 = _stage.ship_rect if _stage.ship_rect.size.x > 10.0 else Rect2(-60, -520, 1400, 620)
	var k: float = minf((vs.x * 0.60) / rect.size.x, (vs.y * 0.58) / rect.size.y)
	_stage.scale = Vector2(k, k)
	_stage.set_meta(&"base_x", vs.x * 0.985 - rect.size.x * k - rect.position.x * k)
	_stage.position.y = wl - ShipArt.WATERLINE_Y * k
	_sea.set_waterline_y(wl)
	_sea.set_horizon_y(wl - vs.y * 0.17)
	if _star_pill != null:
		_star_pill.position = Vector2(vs.x - 20.0 - _star_pill.size.x, 20.0)
		_star_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_star_pill.offset_left = -190.0
		_star_pill.offset_right = -24.0
		_star_pill.offset_top = 22.0
		_star_pill.offset_bottom = 74.0
	var ver: Control = _ui_root.get_node_or_null("Version")
	if ver != null:
		ver.position = Vector2(26.0, vs.y - 44.0)


func _intro() -> void:
	_enter_t = 0.0
	for i in range(_slots.size()):
		var s: Control = _slots[i]
		var b: Control = s.get_child(0)
		b.modulate.a = 0.0
		b.position = Vector2(-90.0, 0.0)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(b, "modulate:a", 1.0, 0.3).set_delay(1.15 + 0.1 * float(i))
		tw.tween_property(b, "position:x", 0.0, 0.5).set_delay(1.15 + 0.1 * float(i)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _star_pill != null:
		OvUtil.fade_in(_star_pill, 1.6, 0.4)
	if _focus_btn != null:
		_focus_btn.call_deferred("grab_focus")


func _process(delta: float) -> void:
	_t += delta
	_enter_t += delta
	var base_x: float = float(_stage.get_meta(&"base_x", 0.0))
	# ship glides in from the right, then idles with a lazy drift
	var slide: float = 1.0 - ArtUtil.smooth(clampf(_enter_t / 2.2, 0.0, 1.0))
	_stage.position.x = base_x + slide * 900.0 + sin(_t * 0.17) * 18.0
	_sea.set_motion_scale(0.35 + 0.65 * (1.0 - slide))


func _go(screen: String, params: Dictionary = {}) -> void:
	if _leaving:
		return
	_leaving = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.22)
	tw.tween_callback(func() -> void: Router.goto(screen, params))


# ================================================================================================
# dev overlay previews
# ================================================================================================
func _dev_overlay(kind: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var host := Control.new()
	host.theme = UITheme.build()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(host)
	var level: LevelDef = ContentDB.level(StringName(String(_params.get("level", "med_3"))))
	match kind:
		"results":
			var mutiny: bool = _params.has("mutiny")
			var stars: int = int(_params.get("stars", 3))
			var rp := ResultsPanel.new()
			host.add_child(rp)
			rp.show_result(_fake_result(stars, mutiny, level), _fake_unlocks(stars, mutiny, level), level)
		"pause":
			var pm := PauseMenu.new()
			pm.set_level(level)
			host.add_child(pm)
			if _params.has("settings"):
				pm._show_settings()
		"confirm":
			ConfirmDialog.present(host, "Reset all progress?", "Every star and unlock will be erased. Your settings stay.", "Reset everything", "Keep my stars", true)
		"banner":
			Banner.show_banner(host, "Film Night!", "The cinema is packed. Keep the popcorn coming.", &"cinema", Palette.LILAC_DARK, 30.0)
			Banner.show_banner(host, "Set sail!", "Level 3  -  Lido Rush Hour", &"event", Palette.TEAL, 30.0)
		"toast":
			Toast.show_toast(host, "Progress reset", &"star", 30.0)


func _fake_result(stars: int, mutiny: bool, level: LevelDef) -> Dictionary:
	var goals: Array[Dictionary] = []
	var defs: Array[Dictionary] = level.star_goals if level != null else [{"type": "rating", "value": 58}, {"type": "profit", "value": 550}, {"type": "no_lost_guests"}]
	for i in range(defs.size()):
		goals.append({"text": GoalText.describe(defs[i]), "met": (not mutiny) and i < stars})
	var lost: int = 0 if stars >= 3 else (2 if stars == 2 else 5)
	var total: int = 28
	if mutiny:
		lost = 17
	var rating: float = [38.0, 61.0, 74.0, 91.0][stars]
	if mutiny:
		rating = 14.0
	# like the real thing: profit = tickets + spending - upkeep - hires (wages are paid in port, shown separately)
	var ledger: Dictionary = {"tickets": [1000, 1900, 2640, 3100][stars], "spending": [450, 900, 1210, 1500][stars], "upkeep": [1280, 820, 640, 600][stars],
			"wages": 380, "hires": 60 if stars < 2 else 0}
	if mutiny:
		ledger = {"tickets": 900, "spending": 300, "upkeep": 1500, "wages": 380, "hires": 60}
	var profit: int = int(ledger["tickets"]) + int(ledger["spending"]) - int(ledger["upkeep"]) - int(ledger["hires"])
	return {
		"stars": 0 if mutiny else stars, "goals": goals, "rating": rating, "profit": profit,
		"ledger": ledger,
		"guests_total": total, "guests_lost": lost, "served": total - lost if not mutiny else 11, "mutiny": mutiny,
		"level_id": String(level.id) if level != null else "med_3",
	}


func _fake_unlocks(stars: int, mutiny: bool, _level: LevelDef) -> Dictionary:
	var out: Dictionary = {"new_stars": stars, "total_stars": 12, "best_stars": stars, "newly_unlocked_levels": [], "newly_unlocked_destinations": [],
			"newly_unlocked_rooms": [], "newly_unlocked_features": []}
	if mutiny or int(_params.get("unlocks", "1")) == 0:
		return out
	if stars >= 1:
		out["newly_unlocked_levels"] = [&"med_4"]
	if stars >= 2:
		out["newly_unlocked_rooms"] = [&"gym", &"medbay"]
		out["newly_unlocked_features"] = [&"tier_2"]
	if stars >= 3:
		out["newly_unlocked_destinations"] = [&"arctic"]
	return out
