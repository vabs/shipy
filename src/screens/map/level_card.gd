class_name LevelCard
extends PanelContainer
## One level on the map: number badge, name, blurb, guests / hull / duration chips, the three star goals,
## earned stars, best rating and a Play button (or the lock reason). One focus stop per card; Enter / click plays.
##   signal play_requested(level_id)   signal locked_pressed(level_id, reason)
##   set_level(def, accent)            recommended: bool  ("NEXT UP" pill)

signal play_requested(level_id: StringName)
signal locked_pressed(level_id: StringName, reason: String)

var level_id: StringName = &""
var is_locked: bool = false
var recommended: bool = false:
	set(v):
		recommended = v
		if _next_pill != null:
			_next_pill.visible = v

var _badge: _Badge
var _stars: StarRow
var _next_pill: PanelContainer
var _name: Label
var _blurb: Label
var _chip_guests: Label
var _chip_hull: Label
var _hull_glyph: _HullGlyph
var _chip_time: Label
var _goal_icons: Array[GlyphView] = []
var _goal_labels: Array[Label] = []
var _best: Label
var _reason: Label
var _play: Button
var _info: Control
var _style_normal: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _style_focus: StyleBoxFlat
var _style_locked: StyleBoxFlat
var _hover: bool = false
var _scale_tw: Tween
var _shake_tw: Tween


class _Badge extends Control:
	var number: int = 1
	var color: Color = Palette.SUN
	var locked: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(50, 50)

	func _draw() -> void:
		var c := size * 0.5
		ArtUtil.circ(self, c + Vector2(0, 3), 23.0, Color(0.1, 0.14, 0.26, 0.22))
		var col: Color = color if not locked else Color("A9B0C2")
		ArtUtil.circ(self, c, 23.0, Palette.shade(col, 0.4))
		ArtUtil.circ(self, c + Vector2(0, -1.5), 21.0, col)
		ArtUtil.circ(self, c + Vector2(-6, -9), 8.0, Color(1, 1, 1, 0.22))
		ArtUtil.text(self, str(number), Vector2(0, c.y + 11.0), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)


class _HullGlyph extends Control:
	var hull: StringName = &"small"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(38, 26)

	func _draw() -> void:
		var decks: int = 2
		var w: float = 26.0
		match hull:
			&"medium":
				decks = 3
				w = 34.0
			&"large":
				decks = 4
				w = 42.0
		var base_y: float = size.y - 6.0
		var x0: float = (size.x - w) * 0.5
		ArtUtil.poly(self, PackedVector2Array([Vector2(x0 - 2, base_y), Vector2(x0 + w + 2, base_y), Vector2(x0 + w - 2, base_y + 6), Vector2(x0 + 3, base_y + 6)]), Palette.NAVY)
		for i in range(decks):
			ArtUtil.rr(self, Rect2(x0 + float(i) * 1.5, base_y - 5.0 * float(i + 1), w - float(i) * 3.0, 4.2), 1.5, Palette.TEAL if i % 2 == 0 else Palette.CORAL)
		ArtUtil.rect(self, Rect2(x0 + w * 0.3, base_y - 5.0 * float(decks) - 5.0, 4.0, 5.0), Palette.CORAL_DARK)


func _init() -> void:
	theme_type_variation = &"CardPanel"
	custom_minimum_size = Vector2(250, 476)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_make_styles()
	add_theme_stylebox_override("panel", _style_normal)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	focus_entered.connect(_restyle)
	focus_exited.connect(_restyle)
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	_build()


func _make_styles() -> void:
	var base: StyleBoxFlat = (UITheme.build().get_stylebox("panel", "CardPanel") as StyleBoxFlat).duplicate()
	base.content_margin_left = 16
	base.content_margin_right = 16
	base.content_margin_top = 12
	base.content_margin_bottom = 12
	_style_normal = base
	_style_hover = base.duplicate()
	_style_hover.border_color = Palette.SUN
	_style_hover.set_border_width_all(3)
	_style_hover.shadow_size = 20
	_style_focus = base.duplicate()
	_style_focus.border_color = Palette.SUN_DEEP
	_style_focus.set_border_width_all(4)
	_style_focus.shadow_size = 22
	_style_locked = base.duplicate()
	_style_locked.bg_color = Color("F3EEE2")
	_style_locked.border_color = Color("E3DAC6")


func _chip(icon: Control, label: Label) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("F5E9D3")
	sb.set_corner_radius_all(11)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UIKit.hbox(4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon)
	label.add_theme_font_override("font", UITheme.font_bold())
	label.add_theme_font_size_override("font_size", 16)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(label)
	p.add_child(h)
	return p


func _build() -> void:
	var v := UIKit.vbox(7)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	# header
	var head := UIKit.hbox(6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge = _Badge.new()
	head.add_child(_badge)
	_next_pill = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Palette.CORAL
	psb.set_corner_radius_all(10)
	psb.content_margin_left = 8
	psb.content_margin_right = 8
	psb.content_margin_top = 1
	psb.content_margin_bottom = 2
	_next_pill.add_theme_stylebox_override("panel", psb)
	var npl := Label.new()
	npl.text = "NEXT UP"
	npl.add_theme_font_override("font", UITheme.font_bold())
	npl.add_theme_font_size_override("font_size", 14)
	npl.add_theme_color_override("font_color", Color.WHITE)
	_next_pill.add_child(npl)
	_next_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_next_pill.visible = false
	_next_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_next_pill)
	head.add_child(UIKit.h_spacer())
	_stars = UIKit.star_row(0, 30.0)
	_stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_stars)
	v.add_child(head)
	# info block (dimmed when locked)
	var info := UIKit.vbox(7)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info = info
	v.add_child(info)
	_name = Label.new()
	_name.add_theme_font_override("font", UITheme.font_bold())
	_name.add_theme_font_size_override("font_size", 25)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.custom_minimum_size = Vector2(0, 68)
	_name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_name)
	_blurb = UIKit.small_label("")
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.max_lines_visible = 3
	_blurb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_blurb.custom_minimum_size = Vector2(0, 66)
	_blurb.add_theme_font_size_override("font_size", 17)
	_blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_blurb)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 5)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_guests = Label.new()
	chips.add_child(_chip(GlyphView.new(&"guest", 22.0), _chip_guests))
	_hull_glyph = _HullGlyph.new()
	_chip_hull = Label.new()
	chips.add_child(_chip(_hull_glyph, _chip_hull))
	_chip_time = Label.new()
	chips.add_child(_chip(GlyphView.new(&"clock", 22.0), _chip_time))
	info.add_child(chips)
	var goals := UIKit.vbox(3)
	goals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(3):
		var gh := UIKit.hbox(7)
		gh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gi := GlyphView.new(&"star", 22.0)
		gh.add_child(gi)
		var gl := Label.new()
		gl.add_theme_font_size_override("font_size", 17)
		gl.add_theme_font_override("font", UITheme.font_bold())
		gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gh.add_child(gl)
		goals.add_child(gh)
		_goal_icons.append(gi)
		_goal_labels.append(gl)
	info.add_child(goals)
	_best = UIKit.small_label("")
	_best.add_theme_font_size_override("font_size", 16)
	_best.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_best)
	v.add_child(UIKit.v_spacer(0, true))
	_reason = Label.new()
	_reason.theme_type_variation = &"WarningLabel"
	_reason.add_theme_font_size_override("font_size", 16)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.custom_minimum_size = Vector2(0, 40)
	_reason.visible = false
	_reason.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_reason)
	_play = UIKit.primary_button("Play")
	_play.custom_minimum_size = Vector2(0, 54)
	_play.focus_mode = Control.FOCUS_NONE
	_play.pressed.connect(_activate)
	v.add_child(_play)


func set_level(def: LevelDef, accent: Color) -> void:
	level_id = def.id
	is_locked = not SaveManager.is_level_unlocked(def.id)
	var best: Dictionary = SaveManager.best_for(def.id)
	_badge.number = def.index
	_badge.color = accent
	_badge.locked = is_locked
	_badge.queue_redraw()
	_stars.value = int(best["stars"])
	_name.text = def.display_name
	_blurb.text = def.blurb
	_chip_guests.text = "%d" % def.total_guests()
	var hd: HullDef = ContentDB.hull(def.hull)
	_chip_hull.text = String(def.hull).capitalize()
	if hd != null:
		_chip_hull.tooltip_text = hd.display_name
	_hull_glyph.hull = def.hull
	_hull_glyph.queue_redraw()
	_chip_time.text = OvUtil.time_text(def.duration)
	for i in range(3):
		if i < def.star_goals.size():
			_goal_icons[i].glyph = GoalText.icon(def.star_goals[i])
			_goal_labels[i].text = GoalText.describe(def.star_goals[i])
			_goal_icons[i].get_parent().visible = true
		else:
			_goal_icons[i].get_parent().visible = false
	if bool(best["played"]):
		_best.text = "Best: %d%% rating  -  %s" % [int(round(float(best["best_rating"]))), OvUtil.money(int(best["best_profit"]))]
	else:
		_best.text = "Not played yet"
	_reason.visible = is_locked
	_reason.text = SaveManager.level_lock_reason(def.id) if is_locked else ""
	_play.disabled = is_locked
	_play.text = "Locked" if is_locked else ("Play" if int(best["stars"]) == 0 and not bool(best["played"]) else "Play again")
	_info.modulate = Color(0.82, 0.85, 0.92, 0.62) if is_locked else Color.WHITE
	focus_mode = Control.FOCUS_ALL
	tooltip_text = _reason.text
	_restyle()


func _restyle() -> void:
	var sb: StyleBoxFlat = _style_normal
	if is_locked:
		sb = _style_locked
	if has_focus():
		sb = _style_focus
	elif _hover and not is_locked:
		sb = _style_hover
	add_theme_stylebox_override("panel", sb)


func _on_hover(on: bool) -> void:
	_hover = on
	_restyle()
	_tween_scale(1.025 if (on and not is_locked) else 1.0)


func _tween_scale(s: float) -> void:
	if _scale_tw != null and _scale_tw.is_valid():
		_scale_tw.kill()
	_scale_tw = create_tween()
	_scale_tw.tween_property(self, "scale", Vector2(s, s), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			_activate()
			accept_event()
	elif event.is_action_pressed(&"ui_accept"):
		_activate()
		accept_event()


func _activate() -> void:
	if level_id == &"":
		return
	if is_locked:
		_shake()
		locked_pressed.emit(level_id, _reason.text)
		AudioManager.play_sfx(&"error_buzz", 0.0, 0.0)
		return
	play_requested.emit(level_id)


func _shake() -> void:
	if _shake_tw != null and _shake_tw.is_valid():
		_shake_tw.kill()
	rotation = 0.0
	_shake_tw = create_tween()
	for a in [0.025, -0.025, 0.018, -0.012, 0.0]:
		_shake_tw.tween_property(self, "rotation", a, 0.05)


func pop(delay: float) -> void:
	modulate.a = 0.0
	scale = Vector2(0.9, 0.9)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.25).set_delay(delay)
	tw.tween_property(self, "scale", Vector2.ONE, 0.4).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
