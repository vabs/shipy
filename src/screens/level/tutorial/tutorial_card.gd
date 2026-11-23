class_name TutorialCard
extends HBoxContainer
## The captain's speech bubble: portrait, short rich text (**word** = coral bold action verb), step dots,
## "Skip tutorial" and (informational steps only) a Next button.
##
##   show_step(text, index, count, next_label)   next_label "" hides the Next button
##   set_text(text)      update the wording of the current step without replaying the intro
##   praise(word)        brief "Nice!" flash when the step's condition was met
##   enable_stuck_skip() reveal a "Continue" button on an action step that is taking too long
##   next_button / skip_button   (for tests)
## Signals: next_pressed, skip_pressed

signal next_pressed
signal skip_pressed

const TEXT_W: float = 430.0

var portrait: CaptainPortrait
var next_button: Button
var skip_button: Button
var text_label: RichTextLabel

var _panel: PanelContainer
var _dots: _Dots
var _tween: Tween
var _text_tween: Tween
var _raw: String = ""
var _next_label: String = ""
var _stuck: bool = false
var _praising: bool = false


## Step dots: filled mint = done, coral = current, sand = to come.
class _Dots extends Control:
	var index: int = 0
	var count: int = 1
	var _t: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(120, 24)

	func set_progress(i: int, n: int) -> void:
		index = i
		count = maxi(n, 1)
		custom_minimum_size = Vector2(float(count) * 17.0 + 4.0, 24)
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var cy: float = size.y * 0.5
		for i in count:
			var p := Vector2(10.0 + float(i) * 17.0, cy)
			if i < index:
				ArtUtil.circ(self, p, 5.0, Palette.MINT_DARK)
			elif i == index:
				var pulse: float = 1.0 + 0.18 * sin(_t * 5.0)
				ArtUtil.circ(self, p, 7.0 * pulse, Color(Palette.CORAL.r, Palette.CORAL.g, Palette.CORAL.b, 0.28))
				ArtUtil.circ(self, p, 5.4, Palette.CORAL)
			else:
				ArtUtil.circ(self, p, 4.2, UITheme.CARD_EDGE.darkened(0.08))


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	theme = UITheme.build()
	_build()


func _build() -> void:
	# portrait column (drawn above the bubble so it overlaps the bubble's edge)
	var left := Control.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.custom_minimum_size = Vector2(88, 0)
	left.z_index = 1
	add_child(left)
	portrait = CaptainPortrait.new()
	portrait.portrait_size = 92.0
	portrait.position = Vector2(-4, 10)
	left.add_child(portrait)
	var tail := _Tail.new()
	tail.position = Vector2(86, 52)
	left.add_child(tail)
	# bubble
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb: StyleBoxFlat = UITheme.flat(UITheme.CARD, 24, Palette.SUN, 3, Color(0.06, 0.1, 0.2, 0.34), 22, Vector2(0, 7), Vector4(24, 16, 22, 14))
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := UIKit.vbox(8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(v)
	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(TEXT_W, 0)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.add_theme_font_size_override("normal_font_size", 27)
	text_label.add_theme_font_size_override("bold_font_size", 27)
	text_label.add_theme_color_override("default_color", UITheme.TEXT_INK)
	v.add_child(text_label)
	var row := UIKit.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots = _Dots.new()
	row.add_child(_dots)
	row.add_child(UIKit.h_spacer())
	skip_button = Button.new()
	skip_button.text = "Skip tutorial"
	skip_button.flat = true
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	skip_button.add_theme_font_override("font", UITheme.font_bold())
	skip_button.add_theme_font_size_override("font_size", 18)
	skip_button.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	skip_button.add_theme_color_override("font_hover_color", Palette.CORAL_DARK)
	skip_button.add_theme_color_override("font_pressed_color", Palette.CORAL_DARK)
	for st in ["normal", "hover", "pressed", "focus"]:
		skip_button.add_theme_stylebox_override(st, UITheme.empty(Vector4(8, 6, 8, 6)))
	skip_button.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"ui_click")
		skip_pressed.emit())
	row.add_child(skip_button)
	next_button = UIKit.primary_button("Next")
	next_button.custom_minimum_size = Vector2(124, 50)
	next_button.add_theme_font_size_override("font_size", 24)
	next_button.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"ui_click")
		next_pressed.emit())
	row.add_child(next_button)
	v.add_child(row)
	next_button.visible = false


class _Tail extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		# a small speech tail pointing back at the captain, sitting on the bubble's left border
		var tri := PackedVector2Array([Vector2(8, -12), Vector2(-9, 2), Vector2(8, 12)])
		draw_colored_polygon(tri, UITheme.CARD)
		draw_polyline(tri, Palette.SUN, 3.0, true)
		draw_line(Vector2(9, -9), Vector2(9, 11), UITheme.CARD, 5.0)


func show_step(text: String, index: int, count: int, next_label: String) -> void:
	_stuck = false
	_praising = false
	_next_label = next_label
	_raw = text
	_dots.set_progress(index, count)
	text_label.text = _format(text)
	next_button.text = next_label if next_label != "" else "Next"
	next_button.visible = next_label != ""
	skip_button.visible = true
	reset_size()
	portrait.nod()
	if _text_tween != null and _text_tween.is_valid():
		_text_tween.kill()
	text_label.visible_ratio = 0.0
	_text_tween = create_tween()
	_text_tween.tween_property(text_label, "visible_ratio", 1.0, clampf(float(text.length()) * 0.011, 0.25, 0.8))
	appear()


func set_text(text: String) -> void:
	if text == _raw or _praising:
		return
	_raw = text
	text_label.text = _format(text)
	text_label.visible_ratio = 1.0
	reset_size()


func enable_stuck_skip() -> void:
	if _stuck or next_button.visible:
		return
	_stuck = true
	next_button.text = "Continue"
	next_button.visible = true
	UIKit.tween_pop(next_button)


func praise(word: String) -> void:
	_praising = true
	_stuck = false
	text_label.text = "[b][color=#%s]%s[/color][/b]" % [Palette.MINT_DARK.to_html(false), word]
	text_label.visible_ratio = 1.0
	next_button.visible = false
	portrait.nod()
	_panel.pivot_offset = _panel.size * 0.5
	var tw := create_tween()
	tw.tween_property(_panel, "scale", Vector2(1.04, 1.04), 0.08)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func appear() -> void:
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	pivot_offset = Vector2(40, size.y * 0.5)
	modulate.a = 0.0
	scale = Vector2(0.9, 0.9)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.18)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func disappear() -> void:
	if not visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.14)
	_tween.tween_callback(func() -> void: visible = false)


## `**word**` becomes coral bold; everything else is escaped-safe plain text.
static func _format(s: String) -> String:
	var out: String = ""
	var parts: PackedStringArray = s.split("**")
	for i in parts.size():
		if i % 2 == 1:
			out += "[b][color=#%s]%s[/color][/b]" % [Palette.CORAL_DARK.to_html(false), parts[i]]
		else:
			out += parts[i]
	return out
