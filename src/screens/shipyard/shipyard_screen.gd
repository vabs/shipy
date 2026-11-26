extends Control
## The Shipyard (docs/SPEC.md §13.1): spend company funds (best payout on every level, see SaveManager) on five permanent
## perks. A harbour scene up top (your flagship at the pier, a crane lowering a perk crate), a navy bar underneath with one
## cream card per perk, a funds header and "Refund all".
##
## Reached from the map ("Shipyard" button). Esc / Back returns to the map.
## Dev: --scene=shipyard [--save=/abs/save.json] [--buy=crew] [--refund]

const SEA_TOP_GAP: float = 40.0

var _params: Dictionary = {}
var _sea: SeaBackground
var _stage: MenuStage
var _dock: ShipyardDock
var _ui_layer: CanvasLayer
var _ui_root: Control
var _bar: PanelContainer
var _cards: Dictionary = {}
var _funds_label: Label
var _funds_sub: Label
var _next_label: Label
var _mini: Dictionary = {}
var _refund: Button
var _fade: ColorRect
var _leaving: bool = false
var _t: float = 0.0
var _enter_t: float = 0.0
var _funds_shown: float = -1.0
var _funds_tw: Tween
var _first_focus: Button = null
var _flash_active: bool = false
var _flash_tw: Tween


func setup(params: Dictionary) -> void:
	_params = params
	OvUtil.dev_save(params)


func _ready() -> void:
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sea = SeaBackground.attach_to(self)
	_sea.set_destination(&"med")
	_sea.set_motion_scale(0.25)
	_stage = MenuStage.new()
	add_child(_stage)
	_dock = ShipyardDock.new()
	add_child(_dock)
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)
	_ui_root = Control.new()
	_ui_root.theme = UITheme.build()  # CanvasLayer breaks theme inheritance
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_ui_root)
	_build_ui()
	SaveManager.progress_changed.connect(_refresh)
	get_viewport().size_changed.connect(_layout)
	_refresh()
	await get_tree().process_frame
	_layout()
	_enter()
	AudioManager.play_music(&"port")
	# dev previews: --buy=<perk id> buys after a moment (sparkles + toast), --refund opens the confirm dialog
	if _params.has("buy"):
		get_tree().create_timer(0.9).timeout.connect(func() -> void: _on_buy(StringName(String(_params["buy"]))))
	if _params.has("refund"):
		get_tree().create_timer(0.9).timeout.connect(_on_refund)


# ================================================================================================
# construction
# ================================================================================================
func _outlined(l: Label, color: Color = Color.WHITE) -> void:
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.14, 0.3, 0.7))
	l.add_theme_constant_override("outline_size", 8)


func _build_ui() -> void:
	# --- hero (floating over the scene)
	var back := UIKit.secondary_button("Map")
	back.custom_minimum_size = Vector2(150, 54)
	OvUtil.focusable(back)
	back.pressed.connect(func() -> void: _go("map"))
	back.position = Vector2(28, 24)
	back.name = "BackButton"
	_ui_root.add_child(back)
	var hero := UIKit.vbox(10)
	hero.name = "Hero"
	hero.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hero.offset_left = -900.0
	hero.offset_right = -44.0
	hero.offset_top = 26.0
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(hero)
	var title := Label.new()
	title.text = "Shipyard"
	title.add_theme_font_override("font", UITheme.font_bold())
	title.add_theme_font_size_override("font_size", 84)
	_outlined(title)
	hero.add_child(title)
	var sub_pill := PanelContainer.new()
	sub_pill.theme_type_variation = &"PillPanel"
	sub_pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sub := Label.new()
	sub.theme_type_variation = &"PillLabel"
	sub.text = "Spend your company funds on permanent perks for every voyage."
	sub.add_theme_font_size_override("font_size", 22)
	sub_pill.add_child(sub)
	hero.add_child(sub_pill)
	hero.add_child(UIKit.v_spacer(4))
	# funds card
	var fc := UIKit.card()
	fc.custom_minimum_size = Vector2(0, 0)
	var fh := UIKit.hbox(20)
	fc.add_child(UIKit.with_margin(fh, 6))
	var coin := GlyphView.new(&"coin", 92.0)
	coin.animate = true
	coin.custom_minimum_size = Vector2(100, 100)
	fh.add_child(coin)
	var fv := UIKit.vbox(0)
	fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fv.alignment = BoxContainer.ALIGNMENT_CENTER
	fv.add_child(UIKit.small_label("COMPANY FUNDS"))
	_funds_label = Label.new()
	_funds_label.add_theme_font_override("font", UITheme.font_bold())
	_funds_label.add_theme_font_size_override("font_size", 68)
	_funds_label.text = "$0"
	fv.add_child(_funds_label)
	_funds_sub = UIKit.small_label("")
	fv.add_child(_funds_sub)
	fh.add_child(fv)
	# what is switched on right now, at a glance
	var av := UIKit.vbox(4)
	av.alignment = BoxContainer.ALIGNMENT_CENTER
	var at := UIKit.small_label("ACTIVE PERKS")
	at.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(at)
	var ar := UIKit.hbox(10)
	for id in Perks.IDS:
		var item := UIKit.vbox(0)
		item.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := PerkIcon.new(id, 46.0)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		item.add_child(ic)
		var lv := Label.new()
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.add_theme_font_override("font", UITheme.font_bold())
		lv.add_theme_font_size_override("font_size", 18)
		item.add_child(lv)
		ar.add_child(item)
		_mini[id] = {"icon": ic, "label": lv}
	av.add_child(ar)
	fh.add_child(av)
	hero.add_child(fc)
	var next_pill := PanelContainer.new()
	next_pill.theme_type_variation = &"PillPanel"
	next_pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_next_label = Label.new()
	_next_label.theme_type_variation = &"MoneyLabel"
	_next_label.add_theme_font_size_override("font_size", 21)
	next_pill.add_child(_next_label)
	hero.add_child(next_pill)

	# --- bottom bar with the cards
	_bar = UIKit.navy_bar_bottom()
	_bar.name = "PerkBar"
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui_root.add_child(_bar)
	var v := UIKit.vbox(12)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_child(v)
	_bar.add_child(pad)
	var head := UIKit.hbox(18)
	head.custom_minimum_size = Vector2(0, 58)
	v.add_child(head)
	var ht := Label.new()
	ht.theme_type_variation = &"OnDarkTitle"
	ht.add_theme_font_size_override("font_size", 38)
	ht.text = "Perks"
	ht.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ht)
	var hs := Label.new()
	hs.theme_type_variation = &"OnDarkSmall"
	hs.add_theme_font_size_override("font_size", 20)
	hs.text = "Each level stacks on top of the last. Refund any time for the full price."
	hs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hs)
	_refund = UIKit.danger_button("Refund all")
	_refund.custom_minimum_size = Vector2(210, 52)
	_refund.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	OvUtil.focusable(_refund)
	_refund.pressed.connect(_on_refund)
	head.add_child(_refund)
	var row := UIKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	for id in Perks.IDS:
		var c := PerkCard.new()
		row.add_child(c)
		c.setup(id)
		c.buy_pressed.connect(_on_buy)
		_cards[id] = c
	_fade = ColorRect.new()
	_fade.color = Color(0.08, 0.11, 0.2, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_fade)


# ================================================================================================
# layout / animation
# ================================================================================================
func _layout() -> void:
	if _stage == null or _bar == null:
		return
	var vs: Vector2 = get_viewport_rect().size
	var bar_top: float = _bar.global_position.y
	if bar_top <= 1.0:
		bar_top = vs.y - 560.0
	var wl: float = bar_top - 26.0
	var rect: Rect2 = _stage.ship_rect if _stage.ship_rect.size.x > 10.0 else Rect2(-60, -520, 1400, 620)
	var up: float = -rect.position.y + ShipArt.WATERLINE_Y
	var k: float = minf((wl - SEA_TOP_GAP - 20.0) / up, 740.0 / rect.size.x)
	var left: float = maxf(250.0, (vs.x - 1920.0) * 0.5 + 250.0)
	_stage.scale = Vector2(k, k)
	_stage.position = Vector2(left - rect.position.x * k, wl - ShipArt.WATERLINE_Y * k)
	_sea.set_waterline_y(wl)
	_sea.set_horizon_y(wl - vs.y * 0.16)
	_dock.setup(left, left + rect.size.x * k, wl, k)


func _enter() -> void:
	_enter_t = 0.0
	create_tween().tween_property(_fade, "modulate:a", 0.0, 0.35)
	var i: int = 0
	for id in Perks.IDS:
		var c: PerkCard = _cards[id]
		c.modulate.a = 0.0
		c.position.y += 0.0
		var tw := create_tween()
		tw.tween_interval(0.18 + 0.08 * float(i))
		tw.tween_property(c, "modulate:a", 1.0, 0.25)
		i += 1
	_grab_focus.call_deferred()


func _grab_focus() -> void:
	for id in Perks.IDS:
		var c: PerkCard = _cards[id]
		if not c.buy_button().disabled and c.buy_button().visible:
			c.buy_button().grab_focus()
			return
	var back: Control = _ui_root.get_node_or_null("BackButton")
	if back != null:
		back.grab_focus()


func _process(delta: float) -> void:
	_t += delta
	_enter_t += delta
	if _stage != null:
		_stage.position.x += sin(_t * 0.2) * 3.0 * delta  # a lazy drift
	if _sea != null:
		_sea.set_motion_scale(0.25)


# ================================================================================================
# state
# ================================================================================================
func _refresh() -> void:
	var funds: int = SaveManager.funds()
	for id in Perks.IDS:
		(_cards[id] as PerkCard).refresh(SaveManager.perk_level(id), funds)
	_funds_sub.text = "Earned %s  -  Spent %s" % [OvUtil.money(SaveManager.funds_earned()), OvUtil.money(SaveManager.funds_spent())]
	for id in Perks.IDS:
		var lv: int = SaveManager.perk_level(id)
		var m: Dictionary = _mini[id]
		(m["icon"] as PerkIcon).modulate.a = 1.0 if lv > 0 else 0.32
		var ml: Label = m["label"]
		ml.text = "L%d" % lv if lv > 0 else "-"
		ml.add_theme_color_override("font_color", UITheme.TEXT_INK if lv > 0 else UITheme.TEXT_MUTED)
	_refund.disabled = SaveManager.perks().is_empty()
	_refund.tooltip_text = "Get back %s" % OvUtil.money(SaveManager.funds_spent()) if not _refund.disabled else "Nothing to refund yet"
	_show_funds(funds)
	# what the next purchase looks like
	var cheapest: int = -1
	for id in Perks.IDS:
		var lv: int = SaveManager.perk_level(id)
		if lv < Perks.MAX_LEVEL:
			var p: int = Perks.price(lv + 1)
			if cheapest < 0 or p < cheapest:
				cheapest = p
	if _flash_active:
		return
	if cheapest < 0:
		_next_label.text = "Every perk is maxed out. Smooth sailing!"
	elif funds >= cheapest:
		_next_label.text = "You can afford an upgrade. Pick a card below!"
	else:
		_next_label.text = "Next upgrade at %s. Beat your best payout on any level to earn more." % OvUtil.money(cheapest)


## Shows `text` in the hero pill for a couple of seconds (purchase / refund feedback), then the usual hint returns.
func _flash(text: String) -> void:
	_flash_active = true
	_next_label.text = text
	var pill: Control = _next_label.get_parent()
	pill.pivot_offset = Vector2(40.0, pill.size.y * 0.5)
	pill.scale = Vector2(1.12, 1.12)
	create_tween().tween_property(pill, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _flash_tw != null and _flash_tw.is_valid():
		_flash_tw.kill()
	_flash_tw = create_tween()
	_flash_tw.tween_interval(2.6)
	_flash_tw.tween_callback(func() -> void:
		_flash_active = false
		_refresh())


func _show_funds(target: int) -> void:
	if _funds_shown < 0.0:
		_funds_shown = float(target)
		_funds_label.text = OvUtil.money(target)
		return
	if _funds_tw != null and _funds_tw.is_valid():
		_funds_tw.kill()
	_funds_tw = create_tween()
	_funds_tw.tween_method(func(v: float) -> void:
		_funds_shown = v
		_funds_label.text = OvUtil.money(int(round(v))), _funds_shown, float(target), 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_funds_label.pivot_offset = Vector2(0, _funds_label.size.y * 0.5)
	_funds_label.scale = Vector2(1.08, 1.08)
	_funds_tw.parallel().tween_property(_funds_label, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ================================================================================================
# actions
# ================================================================================================
func _on_buy(perk_id: StringName) -> void:
	if SaveManager.buy_perk(perk_id):
		AudioManager.play_sfx(&"upgrade")
		AudioManager.play_sfx(&"coin")
		var c: PerkCard = _cards[perk_id]
		c.burst()
		_flash("%s is now level %d!" % [Perks.display_name(perk_id), SaveManager.perk_level(perk_id)])
		_grab_focus.call_deferred()
	else:
		AudioManager.play_sfx(&"error_buzz")


func _on_refund() -> void:
	var value: int = SaveManager.funds_spent()
	if value <= 0:
		return
	var d := ConfirmDialog.present(_ui_root, "Refund every perk?",
			"You get all %s back and the perks switch off. You can buy them again any time." % OvUtil.money(value), "Refund all", "Keep perks", true)
	d.confirmed.connect(func(ok: bool) -> void:
		if not ok:
			return
		var back: int = SaveManager.refund_perks()
		AudioManager.play_sfx(&"sell")
		_flash("Refunded %s. Spend it again whenever you like." % OvUtil.money(back))
		_grab_focus.call_deferred())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		return
	if event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_go("map")


func _go(screen: String, params: Dictionary = {}) -> void:
	if _leaving:
		return
	_leaving = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.22)
	tw.tween_callback(func() -> void: Router.goto(screen, params))
