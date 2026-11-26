class_name PerkCard
extends PanelContainer
## One Shipyard perk: badge icon, name, blurb, three level pips, "now / next level" effect plate and a Buy button
## (or a "Maxed" ribbon). The card tints its border: sun when you can afford the next level, mint when maxed.
##   setup(perk_id)            refresh(level, funds)            burst()   (sparkles after a purchase)
##   signal buy_pressed(perk_id)

signal buy_pressed(perk_id: StringName)

const CARD_W: float = 332.0

var perk_id: StringName = &""
var _level: int = 0
var _badge: PerkIcon
var _halo: _Halo
var _name: Label
var _blurb: Label
var _pips: _Pips
var _now_title: Label
var _now: Label
var _next_title: Label
var _next: Label
var _buy: Button
var _reason: Label
var _maxed: PanelContainer
var _sparks: _Sparks
var _tw: Tween


# ---------------------------------------------------------------------------------------------
class _Halo extends Control:
	var color: Color = Palette.SUN
	var strength: float = 0.0
	var _t: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(150, 124)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var pulse: float = 0.5 + 0.5 * sin(_t * 2.4)
		ArtUtil.circ(self, c, 62.0, Color(color.r, color.g, color.b, 0.16 + 0.1 * strength * pulse))
		ArtUtil.circ(self, c, 54.0, Color(color.r, color.g, color.b, 0.12 + 0.08 * strength * pulse))
		if strength > 0.0:
			ArtUtil.dashed_ring(self, c, 63.0, 63.0, Color(color.r, color.g, color.b, 0.6), 3.0, _t, 18)


class _Pips extends Control:
	var level: int = 0
	var maxed_color: Color = Palette.MINT_DARK

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(150, 36)

	func _draw() -> void:
		var gap: float = 46.0
		var c0: Vector2 = Vector2(size.x * 0.5 - gap, size.y * 0.5)
		for i in range(Perks.MAX_LEVEL):
			var c: Vector2 = c0 + Vector2(gap * float(i), 0.0)
			if i < level:
				IconArt.draw_icon(self, &"star", c, 36.0)
			else:
				ArtUtil.circ(self, c + Vector2(0, 1.5), 11.0, Color(0.1, 0.14, 0.26, 0.10))
				ArtUtil.circ(self, c, 11.0, Color("E7DABF"))
				ArtUtil.circ(self, c, 7.5, Color("F6EEDD"))


class _Sparks extends Control:
	var _parts: Array[Dictionary] = []
	var _rng := RandomNumberGenerator.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)
		_rng.seed = 777

	func burst(at: Vector2) -> void:
		var cols: Array[Color] = [Palette.SUN, Color.WHITE, Palette.MINT, Palette.CORAL_LIGHT, Palette.GOLD]
		for k in range(22):
			var a: float = _rng.randf() * TAU
			var sp: float = _rng.randf_range(110.0, 330.0)
			_parts.append({"p": at, "v": Vector2(cos(a), sin(a)) * sp, "age": 0.0, "life": _rng.randf_range(0.5, 0.95), "col": cols[k % cols.size()]})
		set_process(true)

	func _process(delta: float) -> void:
		for p in _parts:
			p["age"] = float(p["age"]) + delta
			p["v"] = (p["v"] as Vector2) * (1.0 - 2.4 * delta) + Vector2(0, 170.0) * delta
			p["p"] = (p["p"] as Vector2) + (p["v"] as Vector2) * delta
		_parts = _parts.filter(func(p: Dictionary) -> bool: return float(p["age"]) < float(p["life"]))
		queue_redraw()
		if _parts.is_empty():
			set_process(false)

	func _draw() -> void:
		for p in _parts:
			FxArt.draw_sparkle(self, p["p"], float(p["age"]) / float(p["life"]), p["col"])


# ---------------------------------------------------------------------------------------------
func setup(id: StringName) -> void:
	perk_id = id
	custom_minimum_size = Vector2(CARD_W, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(5)
	add_child(UIKit.with_margin(v, 2))
	# badge with a soft halo
	var stage := CenterContainer.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(150, 124)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(holder)
	_halo = _Halo.new()
	_halo.position = Vector2.ZERO
	_halo.size = Vector2(150, 124)
	_halo.color = PerkArt.badge_color(id)
	holder.add_child(_halo)
	_badge = PerkIcon.new(id, 100.0)
	_badge.animate = true
	_badge.position = Vector2(25, 12)
	_badge.size = Vector2(100, 100)
	holder.add_child(_badge)
	v.add_child(stage)
	_name = UIKit.header_label(Perks.display_name(id))
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_name)
	_blurb = UIKit.small_label(Perks.blurb(id))
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(0, 48)
	v.add_child(_blurb)
	_pips = _Pips.new()
	v.add_child(_pips)
	# effect plate
	var plate := PanelContainer.new()
	plate.theme_type_variation = &"PlatePanel"
	var pv := UIKit.vbox(0)
	plate.add_child(pv)
	_now_title = UIKit.small_label("NOW")
	_now_title.add_theme_font_size_override("font_size", 15)
	pv.add_child(_now_title)
	_now = Label.new()
	_now.add_theme_font_override("font", UITheme.font_bold())
	_now.add_theme_font_size_override("font_size", 20)
	_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(_now)
	_next_title = UIKit.small_label("NEXT LEVEL")
	_next_title.add_theme_font_size_override("font_size", 15)
	pv.add_child(_next_title)
	_next = Label.new()
	_next.add_theme_font_size_override("font_size", 20)
	_next.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(_next)
	v.add_child(plate)
	v.add_child(UIKit.v_spacer(0, true))
	# buy row
	_buy = UIKit.primary_button("Buy")
	_buy.custom_minimum_size = Vector2(0, 58)
	OvUtil.focusable(_buy)
	_buy.pressed.connect(func() -> void: buy_pressed.emit(perk_id))
	v.add_child(_buy)
	_maxed = PanelContainer.new()
	var msb := UITheme.flat(Palette.MINT, 14, Palette.MINT_DARK, 0, Color(0, 0, 0, 0), 0, Vector2.ZERO, Vector4(10, 10, 10, 12))
	msb.border_width_bottom = 5
	msb.border_color = Palette.MINT_DARK
	_maxed.add_theme_stylebox_override("panel", msb)
	var mh := UIKit.hbox(8)
	mh.alignment = BoxContainer.ALIGNMENT_CENTER
	mh.add_child(GlyphView.new(&"star", 30.0))
	var ml := Label.new()
	ml.text = "Maxed out"
	ml.add_theme_font_override("font", UITheme.font_bold())
	ml.add_theme_font_size_override("font_size", 24)
	ml.add_theme_color_override("font_color", Color.WHITE)
	mh.add_child(ml)
	_maxed.add_child(mh)
	_maxed.custom_minimum_size = Vector2(0, 58)
	v.add_child(_maxed)
	_reason = UIKit.small_label("")
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.custom_minimum_size = Vector2(0, 26)
	v.add_child(_reason)
	_sparks = _Sparks.new()
	_sparks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_sparks)
	_sparks.top_level = false
	mouse_entered.connect(func() -> void: _hover(true))
	mouse_exited.connect(func() -> void: _hover(false))
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	refresh(0, 0)


func level() -> int:
	return _level


func buy_button() -> Button:
	return _buy


## Re-reads the numbers: `level` owned, `funds` available.
func refresh(level: int, funds: int) -> void:
	_level = level
	var maxed: bool = level >= Perks.MAX_LEVEL
	_pips.level = level
	_pips.queue_redraw()
	_now.text = Perks.effect_text(perk_id, level)
	_now.add_theme_color_override("font_color", UITheme.TEXT_INK if level > 0 else UITheme.TEXT_MUTED)
	if maxed:
		_next_title.text = "BEST POSSIBLE"
		_next.text = "Nothing left to buy"
	else:
		_next_title.text = "NEXT LEVEL"
		_next.text = Perks.effect_text(perk_id, level + 1)
	_buy.visible = not maxed
	_maxed.visible = maxed
	_reason.visible = not maxed
	var afford: bool = false
	if not maxed:
		var price: int = Perks.price(level + 1)
		afford = funds >= price
		_buy.text = "Buy  %s" % OvUtil.money(price)
		_buy.disabled = not afford
		_reason.text = "Ready to buy" if afford else "Need %s more" % OvUtil.money(price - funds)
		_reason.add_theme_color_override("font_color", Palette.MINT_DARK if afford else UITheme.TEXT_MUTED)
	else:
		_reason.text = ""
	_halo.strength = 1.0 if afford else 0.0
	_halo.set_process(true)
	var edge: Color = Color("EBDDC3")
	var bg: Color = UITheme.CARD
	if maxed:
		edge = Palette.MINT_DARK
		bg = Color("F3FBF1")
	elif afford:
		edge = Palette.SUN_DEEP
	var sb: StyleBoxFlat = UITheme.flat(bg, UITheme.R_CARD + 2, edge, 4 if (maxed or afford) else 2, Color(0.04, 0.07, 0.16, 0.3), 14, Vector2(0, 6), Vector4(16, 14, 16, 14))
	add_theme_stylebox_override("panel", sb)


## Pop + sparkles after a purchase.
func burst() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	pivot_offset = size * 0.5
	scale = Vector2(1.0, 1.0)
	_tw = create_tween()
	_tw.tween_property(self, "scale", Vector2(1.05, 1.05), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sparks.burst(Vector2(size.x * 0.5, 84.0))


func _hover(on: bool) -> void:
	if _tw != null and _tw.is_valid():
		return
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.015, 1.015) if on else Vector2.ONE, 0.12)
