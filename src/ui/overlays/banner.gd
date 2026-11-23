class_name Banner
extends Control
## Big sliding event banner ("Film Night!", level intro cards, "Set sail!").
##
##   Banner.show_banner(host: Control, title: String, subtitle := "", icon: StringName = &"event",
##                      color: Color = Palette.CORAL, seconds := 3.0) -> Banner
## `icon` is any IconArt id or a room id (cinema, pool ...). Banners on the same host stack downwards.
## The band slides in from the left, holds, then leaves to the right. Mouse transparent.
## Big full-width bands are for moments where play is NOT running (level intro, "Set sail!", results). Use
## Banner.show_compact(...) (a small pill that drops in under the top bar and shrinks into its event chip) for
## announcements during the voyage.

# preload (not the CompactBanner global class) so a stale class cache can never break this script
const _COMPACT := preload("res://src/ui/overlays/compact_banner.gd")
const BAND_H: float = 132.0
const SLOT_GAP: float = 12.0
const TOP_Y: float = 150.0

var color: Color = Palette.CORAL
## y of the first slot (default TOP_Y). The port's level intro hugs the top edge so it never covers the ship.
var top_y: float = TOP_Y:
	set(v):
		top_y = v
		if is_node_ready():
			_place()
var _title: String = ""
var _subtitle: String = ""
var _icon: StringName = &"event"
var _seconds: float = 3.0
var _slot: int = 0
var _t: float = 0.0
var _content: Control
var _medal: GlyphView


static func show_banner(host: Control, title: String, subtitle: String = "", icon: StringName = &"event",
		color: Color = Palette.CORAL, seconds: float = 3.0) -> Banner:
	var b := Banner.new()
	b._title = title
	b._subtitle = subtitle
	b._icon = icon
	b.color = color
	b._seconds = seconds
	var used: Array = host.get_meta(&"_banner_slots", [])
	var slot: int = 0
	while slot in used:
		slot += 1
	used.append(slot)
	host.set_meta(&"_banner_slots", used)
	b._slot = slot
	b.tree_exiting.connect(func() -> void:
		if is_instance_valid(host):
			var u: Array = host.get_meta(&"_banner_slots", [])
			u.erase(slot)
			host.set_meta(&"_banner_slots", u))
	host.add_child(b)
	return b


## Compact in-voyage announcement (see CompactBanner). `origin` is the pill's top-left in `host` px.
static func show_compact(host: Control, title: String, subtitle: String = "", icon: StringName = &"event",
		color: Color = Palette.CORAL, seconds: float = 2.5, origin: Vector2 = Vector2(24, 150),
		dock: Callable = Callable()) -> Control:
	return _COMPACT.show_compact(host, title, subtitle, icon, color, seconds, origin, dock)


func _init() -> void:
	theme = UITheme.build()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 150
	top_level = true  # anchored to the viewport; never laid out by a container host
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, BAND_H)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_left = 0.0
	offset_right = 0.0
	_place()
	_content = HBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("separation", 22)
	add_child(_content)
	_medal = GlyphView.new(_icon, 84.0)
	_medal.custom_minimum_size = Vector2(112, 112)
	_content.add_child(_medal)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(v)
	var tl := Label.new()
	tl.text = _title
	tl.add_theme_font_override("font", UITheme.font_bold())
	tl.add_theme_font_size_override("font_size", 56)
	tl.add_theme_color_override("font_color", Color.WHITE)
	tl.add_theme_color_override("font_outline_color", Palette.shade(color, 0.7))
	tl.add_theme_constant_override("outline_size", 12)
	tl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.25))
	tl.add_theme_constant_override("shadow_offset_y", 4)
	v.add_child(tl)
	if _subtitle != "":
		var sl := Label.new()
		sl.text = _subtitle
		sl.add_theme_font_override("font", UITheme.font())
		sl.add_theme_font_size_override("font_size", 24)
		sl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		sl.add_theme_color_override("font_outline_color", Palette.shade(color, 0.6))
		sl.add_theme_constant_override("outline_size", 6)
		v.add_child(sl)
	# centre the content once it has its size
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_content.size = _content.get_combined_minimum_size()
	_content.position = Vector2((size.x - _content.size.x) * 0.5, (BAND_H - _content.size.y) * 0.5)
	_play()


func _place() -> void:
	offset_top = top_y + float(_slot) * (BAND_H + SLOT_GAP)
	offset_bottom = offset_top + BAND_H


func _play() -> void:
	var w: float = maxf(size.x, 600.0)
	position.x = -w
	_content.pivot_offset = _content.size * 0.5
	_content.scale = Vector2(0.6, 0.6)
	_content.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "position:x", 0.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_content, "scale", Vector2.ONE, 0.45).set_delay(0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_content, "modulate:a", 1.0, 0.25).set_delay(0.18)
	tw.tween_interval(maxf(_seconds - 0.9, 0.2))
	tw.tween_property(self, "position:x", w, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = BAND_H
	var lite: Color = Palette.tint(color, 0.28)
	var dark: Color = Palette.shade(color, 0.45)
	# shadow
	var pts_shadow := PackedVector2Array([Vector2(-20, 10), Vector2(w + 20, 10), Vector2(w + 20, h + 12), Vector2(-20, h + 12)])
	draw_colored_polygon(pts_shadow, Color(0.05, 0.08, 0.16, 0.22))
	# ribbon band, slanted ends
	var band := PackedVector2Array([Vector2(-30, 0), Vector2(w + 30, 0), Vector2(w + 30, h), Vector2(-30, h)])
	draw_colored_polygon(band, color)
	# lighter upper half + bottom lip
	draw_rect(Rect2(-30, 0, w + 60, h * 0.5), Color(lite.r, lite.g, lite.b, 0.55))
	draw_rect(Rect2(-30, h - 9, w + 60, 9), dark)
	draw_rect(Rect2(-30, 0, w + 60, 5), Color(1, 1, 1, 0.5))
	# drifting diagonal stripes for texture
	var off: float = fmod(_t * 28.0, 64.0)
	var x: float = -64.0 + off
	while x < w + 64.0:
		var stripe := PackedVector2Array([Vector2(x, 0), Vector2(x + 22, 0), Vector2(x - 14, h - 9), Vector2(x - 36, h - 9)])
		draw_colored_polygon(stripe, Color(1, 1, 1, 0.07))
		x += 64.0
	# sparkles near the medal
	if _content != null and _content.modulate.a > 0.5:
		var cx: float = _content.position.x + 56.0
		for i in range(5):
			var ph: float = fmod(_t * 0.8 + float(i) * 0.37, 1.0)
			var ang: float = float(i) * 1.7 + 0.6
			var p := Vector2(cx, h * 0.5) + Vector2(cos(ang), sin(ang)) * (60.0 + 26.0 * ph)
			FxArt.draw_sparkle(self, p, ph, Color.WHITE)
