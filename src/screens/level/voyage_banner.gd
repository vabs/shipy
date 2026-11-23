class_name VoyageBanner
extends PanelContainer
## Minimal slide-in banner (title + subtitle + icon) used when the shared Banner overlay is unavailable.

static func show_banner(host: Control, title: String, subtitle: String = "", icon: StringName = &"event", color: Color = Palette.TEAL, seconds: float = 2.6) -> VoyageBanner:
	var b := VoyageBanner.new()
	host.add_child(b)
	b.build(title, subtitle, icon, color, seconds)
	return b


func build(title: String, subtitle: String, icon: StringName, color: Color, seconds: float) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.flat(Color(color.r * 0.82, color.g * 0.82, color.b * 0.82, 0.96), 22, Color(1, 1, 1, 0.55), 3, Color(0, 0, 0, 0.3), 14, Vector2(0, 5), Vector4(26, 14, 34, 16))
	add_theme_stylebox_override("panel", sb)
	var row := UIKit.hbox(14)
	var iv := IconView.new()
	iv.icon = icon
	iv.icon_size = 46.0
	row.add_child(iv)
	var col := UIKit.vbox(0)
	var t := UIKit.title_label(title)
	t.theme_type_variation = &"OnDarkTitle"
	col.add_child(t)
	if subtitle != "":
		var s := UIKit.small_label(subtitle)
		s.theme_type_variation = &"OnDarkSmall"
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size = Vector2(520, 0)
		col.add_child(s)
	row.add_child(col)
	add_child(row)
	# layout: top centre, slides down from above
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var y_rest: float = 112.0
	position.x = (get_viewport_rect().size.x - size.x) * 0.5
	position.y = -size.y - 20.0
	pivot_offset = size * 0.5
	var tw := create_tween()
	tw.tween_property(self, "position:y", y_rest, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(seconds - 0.9, 0.3))
	tw.tween_property(self, "position:y", -size.y - 30.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
