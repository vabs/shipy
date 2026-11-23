class_name StatPill
extends PanelContainer
## Rounded pill with an icon + value text (money, guests, power...). Dark navy by default, `set_light(true)` for cream.
##   set_text(s: String, pop := true)   -- pops when the text changes
##   set_icon(icon: StringName)

var _icon: IconView
var _label: Label
var _tween: Tween


func _init(icon_id: StringName = &"coin", text_value: String = "") -> void:
	theme_type_variation = &"PillPanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hb)
	_icon = IconView.new()
	_icon.icon = icon_id
	_icon.icon_size = 28.0
	hb.add_child(_icon)
	_label = Label.new()
	_label.theme_type_variation = &"PillLabel"
	_label.text = text_value
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_label)


func set_text(s: String, pop: bool = true) -> void:
	if _label.text == s:
		return
	_label.text = s
	if pop and is_inside_tree():
		_label.pivot_offset = _label.size * 0.5
		if _tween != null:
			_tween.kill()
		_tween = create_tween()
		_label.scale = Vector2(1.25, 1.25)
		_tween.tween_property(_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func get_text() -> String:
	return _label.text


func set_icon(icon_id: StringName) -> void:
	_icon.icon = icon_id


func set_light(light: bool) -> void:
	theme_type_variation = &"PillPanelLight" if light else &"PillPanel"
	_label.theme_type_variation = &"HeaderLabel" if light else &"PillLabel"
