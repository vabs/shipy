class_name CompactBanner
extends Control
## Small event announcement used DURING the voyage (the full-width Banner would cover the top deck while
## play is running). A coloured pill drops in under the top bar, in the free sky area at the top left,
## holds ~1.8 s and then shrinks into its event chip (or just fades when there is no chip to fly to).
##
##   CompactBanner.show_compact(host: Control, title, subtitle := "", icon := &"event", color := Palette.CORAL,
##                              seconds := 2.5, origin := Vector2(24, 150), dock := Callable()) -> CompactBanner
##
## `dock` (optional) returns the screen centre (host-local px) the pill should shrink into, or Vector2.INF.
## Pills on the same host stack downwards. Mouse transparent. signal docked fires when the pill has landed.

signal docked

const PAD_X: float = 18.0
const PAD_Y: float = 9.0
const MEDAL: float = 46.0
const SLOT_GAP: float = 8.0

var color: Color = Palette.CORAL
var _title: String = ""
var _subtitle: String = ""
var _icon: StringName = &"event"
var _seconds: float = 2.5
var _origin: Vector2 = Vector2(24, 150)
var _dock: Callable = Callable()
var _slot: int = 0
var _medal: GlyphView
var _panel: PanelContainer


static func show_compact(host: Control, title: String, subtitle: String = "", icon: StringName = &"event",
		p_color: Color = Palette.CORAL, seconds: float = 2.5, origin: Vector2 = Vector2(24, 150),
		dock: Callable = Callable()) -> CompactBanner:
	var b := CompactBanner.new()
	b._title = title
	b._subtitle = subtitle
	b._icon = icon
	b.color = p_color
	b._seconds = seconds
	b._origin = origin
	b._dock = dock
	var used: Array = host.get_meta(&"_compact_slots", [])
	var slot: int = 0
	while slot in used:
		slot += 1
	used.append(slot)
	host.set_meta(&"_compact_slots", used)
	b._slot = slot
	b.tree_exiting.connect(func() -> void:
		if is_instance_valid(host):
			var u: Array = host.get_meta(&"_compact_slots", [])
			u.erase(slot)
			host.set_meta(&"_compact_slots", u))
	host.add_child(b)
	return b


func _init() -> void:
	theme = UITheme.build()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 140


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dark: Color = Palette.shade(color, 0.35)
	_panel.add_theme_stylebox_override("panel", UITheme.flat(color, 30, Color(1, 1, 1, 0.55), 3,
			Color(0.05, 0.08, 0.16, 0.38), 12, Vector2(0, 5), Vector4(10, PAD_Y, PAD_X, PAD_Y)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(hb)
	var medal_holder := Panel.new()
	medal_holder.custom_minimum_size = Vector2(MEDAL, MEDAL)
	medal_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal_holder.add_theme_stylebox_override("panel", UITheme.flat(Color(1, 1, 1, 0.94), int(MEDAL * 0.5), Palette.shade(color, 0.3), 2))
	hb.add_child(medal_holder)
	_medal = GlyphView.new(_icon, MEDAL - 10.0)
	_medal.animate = true
	_medal.position = Vector2(5, 5)
	_medal.custom_minimum_size = Vector2(MEDAL - 10.0, MEDAL - 10.0)
	medal_holder.add_child(_medal)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(v)
	var tl := Label.new()
	tl.text = _title
	tl.add_theme_font_override("font", UITheme.font_bold())
	tl.add_theme_font_size_override("font_size", 28)
	tl.add_theme_color_override("font_color", Color.WHITE)
	tl.add_theme_color_override("font_outline_color", dark)
	tl.add_theme_constant_override("outline_size", 7)
	tl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.22))
	tl.add_theme_constant_override("shadow_offset_y", 2)
	v.add_child(tl)
	if _subtitle != "":
		var sl := Label.new()
		sl.text = _subtitle
		sl.add_theme_font_override("font", UITheme.font())
		sl.add_theme_font_size_override("font_size", 17)
		sl.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
		sl.add_theme_color_override("font_outline_color", dark)
		sl.add_theme_constant_override("outline_size", 4)
		v.add_child(sl)
	add_child(_panel)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_panel.size = _panel.get_combined_minimum_size()
	size = _panel.size
	_play()


func _target_pos() -> Vector2:
	return _origin + Vector2(0.0, float(_slot) * (size.y + SLOT_GAP))


func _play() -> void:
	var tgt: Vector2 = _target_pos()
	pivot_offset = Vector2(40.0, size.y * 0.5)
	position = tgt + Vector2(0.0, -size.y - 30.0)
	scale = Vector2(0.9, 0.9)
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "position", tgt, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_interval(maxf(_seconds - 0.4 - 0.45, 0.3))
	tw.tween_callback(_shrink)


func _shrink() -> void:
	var dest: Vector2 = Vector2.INF
	if _dock.is_valid():
		var d: Variant = _dock.call()
		if d is Vector2:
			dest = d
	var tw := create_tween()
	if dest != Vector2.INF:
		# fly into the chip: keep the pill's own pivot at its centre so the shrink lands on `dest`
		pivot_offset = size * 0.5
		var landing: Vector2 = dest - size * 0.5
		tw.tween_property(self, "position", landing, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(self, "scale", Vector2(0.28, 0.28), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(self, "modulate:a", 0.0, 0.14).set_delay(0.3)
	else:
		tw.tween_property(self, "position:y", position.y - 24.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void:
		docked.emit()
		queue_free())
