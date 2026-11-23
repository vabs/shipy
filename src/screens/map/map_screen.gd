extends Control
## Voyage map: a stylised sea chart with the three destinations (Mediterranean, Arctic, Underworld), a dotted route
## and a little ship; selecting a destination shows its six level cards in the bottom bar.
##
## params: dest (med|arctic|underworld) preselects a destination, level (level id) preselects its destination
## and highlights that card. Defaults to the destination of the next unfinished level.
## Keyboard / controller: left / right browse destinations, Down jumps to the level cards, Esc goes back.
## Dev: --scene=map [--dest=arctic] [--unlock-all]

const DESTS: Array[StringName] = [&"med", &"arctic", &"underworld"]
const ACCENTS: Dictionary = {
	&"med": Color("F2A93B"),
	&"arctic": Color("3AA0C8"),
	&"underworld": Color("8A72BD"),
}

var _params: Dictionary = {}
var _canvas: MapCanvas
var _top: PanelContainer
var _bottom: PanelContainer
var _cards: Array[LevelCard] = []
var _dest_title: Label
var _dest_twist: Label
var _dest_pill: StatPill
var _room_chip: HBoxContainer
var _room_icon: GlyphView
var _room_label: Label
var _lock_banner: PanelContainer
var _lock_label: Label
var _star_counter: StarCounter
var _selected: StringName = &""
var _recommended: StringName = &""
var _focus_level: StringName = &""
var _fade: ColorRect
var _leaving: bool = false


func setup(params: Dictionary) -> void:
	_params = params
	OvUtil.dev_save(params)


func _ready() -> void:
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas = MapCanvas.new()
	add_child(_canvas)
	_canvas.setup(DESTS)
	_canvas.dest_chosen.connect(_select)
	var ui := VBoxContainer.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_theme_constant_override("separation", 0)
	add_child(ui)
	_top = _build_top()
	ui.add_child(_top)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(gap)
	_bottom = _build_bottom()
	ui.add_child(_bottom)
	_fade = ColorRect.new()
	_fade.color = Color(0.08, 0.11, 0.2, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_top.resized.connect(_sync_insets)
	_bottom.resized.connect(_sync_insets)
	SaveManager.progress_changed.connect(_refresh_all)
	_pick_initial()
	await get_tree().process_frame
	_sync_insets()
	_canvas.set_ship_dest(_ship_target(), false)
	_enter()
	AudioManager.play_music(&"port")


func _sync_insets() -> void:
	if _canvas == null:
		return
	_canvas.set_insets(_top.size.y + 6.0, _bottom.size.y + 4.0)
	_canvas.set_ship_dest(_ship_target(), false)


# ================================================================================================
# construction
# ================================================================================================
func _build_top() -> PanelContainer:
	var bar := UIKit.navy_bar()
	bar.custom_minimum_size = Vector2(0, 84)
	var h := UIKit.hbox(18)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(h)
	var back := UIKit.secondary_button("Back")
	back.custom_minimum_size = Vector2(150, 52)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	OvUtil.focusable(back)
	back.pressed.connect(func() -> void: _go("menu"))
	h.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"OnDarkTitle"
	title.text = "Choose your voyage"
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(title)
	h.add_child(UIKit.h_spacer())
	_star_counter = StarCounter.new()
	_star_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_star_counter)
	return bar


func _build_bottom() -> PanelContainer:
	var bar := UIKit.navy_bar_bottom()
	var v := UIKit.vbox(10)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_bottom", 10)
	pad.add_child(v)
	bar.add_child(pad)
	# header row
	var head := UIKit.hbox(18)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.custom_minimum_size = Vector2(0, 58)
	v.add_child(head)
	_dest_title = Label.new()
	_dest_title.theme_type_variation = &"OnDarkTitle"
	_dest_title.add_theme_font_size_override("font_size", 38)
	_dest_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_dest_title)
	_dest_pill = UIKit.stat_pill(&"star", "0 / 18")
	_dest_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_dest_pill)
	_dest_twist = Label.new()
	_dest_twist.theme_type_variation = &"OnDarkSmall"
	_dest_twist.add_theme_font_size_override("font_size", 19)
	_dest_twist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dest_twist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dest_twist.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dest_twist.custom_minimum_size = Vector2(300, 0)
	head.add_child(_dest_twist)
	_room_chip = UIKit.hbox(8)
	_room_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rc := PanelContainer.new()
	rc.theme_type_variation = &"PillPanel"
	var rh := UIKit.hbox(8)
	rc.add_child(rh)
	_room_icon = GlyphView.new(&"cabin", 30.0)
	rh.add_child(_room_icon)
	_room_label = Label.new()
	_room_label.theme_type_variation = &"PillLabel"
	_room_label.add_theme_font_size_override("font_size", 19)
	rh.add_child(_room_label)
	_room_chip.add_child(rc)
	head.add_child(_room_chip)
	_lock_banner = PanelContainer.new()
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Palette.CORAL
	lsb.set_corner_radius_all(18)
	lsb.content_margin_left = 16
	lsb.content_margin_right = 18
	lsb.content_margin_top = 7
	lsb.content_margin_bottom = 8
	lsb.anti_aliasing = true
	_lock_banner.add_theme_stylebox_override("panel", lsb)
	var lh := UIKit.hbox(8)
	_lock_banner.add_child(lh)
	lh.add_child(GlyphView.new(&"lock", 28.0))
	_lock_label = Label.new()
	_lock_label.add_theme_font_override("font", UITheme.font_bold())
	_lock_label.add_theme_color_override("font_color", Color.WHITE)
	_lock_label.add_theme_font_size_override("font_size", 20)
	lh.add_child(_lock_label)
	_lock_banner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_lock_banner)
	# cards
	var row := UIKit.hbox(14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	for i in range(6):
		var card := LevelCard.new()
		card.play_requested.connect(_on_play)
		card.locked_pressed.connect(_on_locked)
		row.add_child(card)
		_cards.append(card)
	return bar


# ================================================================================================
# state
# ================================================================================================
func _pick_initial() -> void:
	# recommended level = first unlocked level with no stars (campaign order)
	_recommended = &""
	for lv in ContentDB.campaign():
		if SaveManager.is_level_unlocked(lv.id) and SaveManager.stars_for(lv.id) == 0:
			_recommended = lv.id
			break
	var dest: StringName = &"med"
	if _params.has("level"):
		var lv0: LevelDef = ContentDB.level(StringName(String(_params["level"])))
		if lv0 != null:
			dest = lv0.destination
			_focus_level = lv0.id
	elif _params.has("dest"):
		dest = StringName(String(_params["dest"]))
	elif _recommended != &"":
		dest = ContentDB.level(_recommended).destination
	if dest not in DESTS:
		dest = &"med"
	_select(dest, true)


func _ship_target() -> StringName:
	if _selected != &"" and SaveManager.is_destination_unlocked(_selected):
		return _selected
	# stay at the farthest unlocked destination before the selected one
	var best: StringName = &"med"
	for d in DESTS:
		if SaveManager.is_destination_unlocked(d):
			best = d
		if d == _selected:
			break
	return best


func _refresh_all() -> void:
	for n in _canvas.nodes:
		n.refresh()
	_star_counter.set_count(SaveManager.total_stars(), maxi(ContentDB.campaign().size() * 3, 1))
	if _selected != &"":
		_populate(_selected, false)


func _select(dest: StringName, first: bool = false) -> void:
	if dest == _selected and not first:
		return
	_selected = dest
	for n in _canvas.nodes:
		n.selected = n.dest == dest
	_star_counter.set_count(SaveManager.total_stars(), maxi(ContentDB.campaign().size() * 3, 1))
	_populate(dest, true)
	_canvas.set_ship_dest(_ship_target(), not first)


func _populate(dest: StringName, animate: bool) -> void:
	var def: DestinationDef = ContentDB.destination(dest)
	var levels: Array[LevelDef] = ContentDB.levels_for(dest)
	var accent: Color = ACCENTS.get(dest, Palette.SUN)
	_dest_title.text = def.display_name if def != null else String(dest)
	var unlocked: bool = SaveManager.is_destination_unlocked(dest)
	_dest_pill.set_text("%d / %d" % [SaveManager.stars_in_destination(dest), levels.size() * 3], false)
	_dest_twist.text = def.twist_text if def != null and def.twist_text != "" else ""
	var new_room: StringName = def.new_room if def != null else &""
	_room_chip.visible = new_room != &""
	if new_room != &"":
		var rd: RoomDef = ContentDB.room(new_room)
		_room_icon.glyph = new_room
		_room_label.text = "New room: %s" % (rd.display_name if rd != null else String(new_room))
	_lock_banner.visible = not unlocked
	if not unlocked:
		_lock_label.text = "%d stars needed  (you have %d)" % [SaveManager.stars_required(dest), SaveManager.total_stars()]
	for i in range(_cards.size()):
		var c: LevelCard = _cards[i]
		if i < levels.size():
			c.visible = true
			c.set_level(levels[i], accent)
			c.recommended = levels[i].id == _recommended
			if animate:
				c.pop(0.04 * float(i))
		else:
			c.visible = false
	_wire_focus()


func _wire_focus() -> void:
	var first_playable: LevelCard = null
	for c in _cards:
		if c.visible and not c.is_locked:
			if c.level_id == _focus_level or c.recommended:
				first_playable = c
				break
			if first_playable == null:
				first_playable = c
	var node: DestNode = _canvas.node_for(_selected)
	for c in _cards:
		c.focus_neighbor_top = c.get_path_to(node) if node != null else NodePath()
	var nn: Array[DestNode] = _canvas.nodes
	for i in range(nn.size()):
		nn[i].focus_neighbor_left = nn[i].get_path_to(nn[maxi(i - 1, 0)])
		nn[i].focus_neighbor_right = nn[i].get_path_to(nn[mini(i + 1, nn.size() - 1)])
	for n in _canvas.nodes:
		var target: Control = first_playable if first_playable != null else (_cards[0] if not _cards.is_empty() else null)
		if target != null:
			n.focus_neighbor_bottom = n.get_path_to(target)


func _enter() -> void:
	create_tween().tween_property(_fade, "modulate:a", 0.0, 0.3)
	for i in range(_canvas.nodes.size()):
		_canvas.nodes[i].pop(0.12 + 0.12 * float(i))
	_top.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_top, "modulate:a", 1.0, 0.3).set_delay(0.1)
	# focus the recommended level so Enter plays it
	_grab_default_focus.call_deferred()


func _grab_default_focus() -> void:
	for c in _cards:
		if c.visible and c.level_id == _focus_level and not c.is_locked:
			c.grab_focus()
			return
	for c in _cards:
		if c.visible and c.recommended and not c.is_locked:
			c.grab_focus()
			return
	for c in _cards:
		if c.visible and not c.is_locked:
			c.grab_focus()
			return


# ================================================================================================
# actions
# ================================================================================================
func _on_play(level_id: StringName) -> void:
	_go("level", {"level": String(level_id)})


func _on_locked(_level_id: StringName, reason: String) -> void:
	if reason != "":
		Toast.show_toast(self, reason, &"lock", 2.4)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		return
	if event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_go("menu")


func _go(screen: String, params: Dictionary = {}) -> void:
	if _leaving:
		return
	_leaving = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.22)
	tw.tween_callback(func() -> void: Router.goto(screen, params))
