class_name PortDialog
extends Control
## Small modal confirm dialog used by the port phase ("Set sail anyway?", "Leave port?").
## Fully self-contained: dim backdrop, cream card, cancel + confirm buttons, Esc = cancel,
## Enter = confirm. Frees itself after emitting.

signal confirmed
signal cancelled

var _card: PanelContainer
var _done: bool = false


## Builds and shows a dialog under `host`. `lines` = Array[String] shown with a small icon each.
static func ask(host: Control, title: String, lines: Array, confirm_text: String, cancel_text: String,
		line_icon: StringName = &"warning", danger: bool = false) -> PortDialog:
	var d := PortDialog.new()
	d.name = "PortDialog"
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	d._build(title, lines, confirm_text, cancel_text, line_icon, danger)
	host.add_child(d)
	return d


func _build(title: String, lines: Array, confirm_text: String, cancel_text: String, line_icon: StringName, danger: bool) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.09, 0.17, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = UIKit.card()
	_card.custom_minimum_size = Vector2(560, 0)
	center.add_child(_card)
	var v := UIKit.vbox(14)
	_card.add_child(v)
	var head := UIKit.hbox(12)
	var ic := IconView.new()
	ic.icon = line_icon
	ic.icon_size = 40.0
	head.add_child(ic)
	var t := UIKit.header_label(title)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(t)
	v.add_child(head)
	for line in lines:
		var row := UIKit.hbox(10)
		var dot := IconView.new()
		dot.icon = &"mess" if line_icon == &"mess" else &"warning"
		dot.icon_size = 22.0
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(dot)
		var l := Label.new()
		l.text = String(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(440, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		v.add_child(row)
	var btns := UIKit.hbox(14)
	btns.alignment = BoxContainer.ALIGNMENT_END
	var cancel := UIKit.secondary_button(cancel_text)
	cancel.custom_minimum_size = Vector2(150, 54)
	cancel.pressed.connect(_cancel)
	btns.add_child(cancel)
	var ok: Button = UIKit.danger_button(confirm_text) if danger else UIKit.primary_button(confirm_text)
	ok.custom_minimum_size = Vector2(190, 54)
	ok.pressed.connect(_confirm)
	btns.add_child(ok)
	v.add_child(UIKit.v_spacer(4.0))
	v.add_child(btns)
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.14)
	_card.pivot_offset = Vector2(280, 120)
	_card.scale = Vector2(0.86, 0.86)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _confirm() -> void:
	if _done:
		return
	_done = true
	confirmed.emit()
	queue_free()


func _cancel() -> void:
	if _done:
		return
	_done = true
	cancelled.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed(&"cancel"):
		get_viewport().set_input_as_handled()
		_cancel()
	elif event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		_confirm()
