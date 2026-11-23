class_name Toast
extends PanelContainer
## Small pill that slides up from the bottom of `host`, stays a moment and fades.
##   Toast.show_toast(host, "Progress reset", &"star", 2.2) -> Toast


static func show_toast(host: Control, text: String, icon: StringName = &"", seconds: float = 2.2) -> Toast:
	var t := Toast.new()
	t._build(text, icon)
	host.add_child(t)
	t._run(seconds)
	return t


func _build(text: String, icon: StringName) -> void:
	theme = UITheme.build()
	theme_type_variation = &"PillPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200
	top_level = true  # never laid out by a container host
	var hb := UIKit.hbox(10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hb)
	if icon != &"":
		hb.add_child(GlyphView.new(icon, 30.0))
	var l := Label.new()
	l.theme_type_variation = &"PillLabel"
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	hb.add_child(l)
	# a more opaque pill than the default so it reads over busy scenes
	var sb: StyleBoxFlat = (UITheme.build().get_stylebox("panel", "PillPanel") as StyleBoxFlat).duplicate()
	sb.bg_color = Color(0.1, 0.14, 0.24, 0.94)
	sb.content_margin_left = 22
	sb.content_margin_right = 26
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", sb)


func _run(seconds: float) -> void:
	modulate.a = 0.0
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var host_size: Vector2 = get_viewport_rect().size
	var x: float = (host_size.x - size.x) * 0.5
	var y_end: float = host_size.y - size.y - 56.0
	position = Vector2(x, y_end + 36.0)
	var tw := create_tween()
	tw.tween_property(self, "position:y", y_end, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "modulate:a", 1.0, 0.2)
	tw.tween_interval(seconds)
	tw.tween_property(self, "position:y", y_end - 18.0, 0.3).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
