class_name HintCard
extends PanelContainer
## Compact "first time" tip: icon + one or two short sentences (**word** = sun-yellow bold). Slides in, stays a few
## seconds, fades out; a click dismisses it early.
##   HintCard.make(text, icon, seconds) -> HintCard      (add to a CanvasLayer / Control, then position it)
## Signals: closed

signal closed

const MAX_W: float = 640.0

var seconds: float = 7.0
var _tween: Tween
var _closing: bool = false
var _label: RichTextLabel


static func make(text: String, icon: StringName, p_seconds: float = 7.0) -> HintCard:
	var c := HintCard.new()
	c.seconds = p_seconds
	c._build(text, icon)
	return c


func _build(text: String, icon: StringName) -> void:
	theme = UITheme.build()
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sb: StyleBoxFlat = UITheme.flat(Color(0.1, 0.14, 0.24, 0.95), 22, Palette.SUN, 2, Color(0, 0, 0, 0.32), 12, Vector2(0, 4), Vector4(14, 10, 22, 10))
	add_theme_stylebox_override("panel", sb)
	var hb := UIKit.hbox(12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hb)
	var plate := Control.new()
	plate.custom_minimum_size = Vector2(52, 52)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.draw.connect(func() -> void: ArtUtil.circ(plate, Vector2(26, 26), 25.0, Color(1, 1, 1, 0.12)))
	var gv := GlyphView.new(icon, 40.0)
	gv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gv.animate = true
	plate.add_child(gv)
	hb.add_child(plate)
	var v := UIKit.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var tag := Label.new()
	tag.text = "TIP"
	tag.add_theme_font_override("font", UITheme.font_bold())
	tag.add_theme_font_size_override("font_size", 15)
	tag.add_theme_color_override("font_color", Palette.SUN)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tag)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(MAX_W - 110.0, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 23)
	_label.add_theme_font_size_override("bold_font_size", 23)
	_label.add_theme_color_override("default_color", UITheme.TEXT_ON_DARK)
	_label.text = format(text)
	v.add_child(_label)
	hb.add_child(v)
	modulate.a = 0.0


func play() -> void:
	_closing = false
	await get_tree().process_frame
	if not is_inside_tree():
		return
	pivot_offset = Vector2(40.0, size.y)
	scale = Vector2(0.9, 0.9)
	modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(seconds)
	_tween.tween_callback(close)


func close() -> void:
	if _closing:
		return
	_closing = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		AudioManager.play_sfx(&"ui_click")
		close()


static func format(s: String) -> String:
	var out: String = ""
	var parts: PackedStringArray = s.split("**")
	for i in parts.size():
		if i % 2 == 1:
			out += "[b][color=#%s]%s[/color][/b]" % [Palette.SUN.to_html(false), parts[i]]
		else:
			out += parts[i]
	return out
