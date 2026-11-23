class_name ConfirmDialog
extends Control
## Modal yes/no dialog on a dimmed backdrop.
##
##   var d := ConfirmDialog.present(host, "Reset progress?", "This cannot be undone.", "Reset", "Keep", true)
##   d.confirmed.connect(func(ok: bool) -> void: ...)
## or manually: add a ConfirmDialog as a full-screen child and call ask(...).
## `present()` wraps the dialog in a CanvasLayer (layer 100) so it always covers the whole screen, and frees
## it afterwards. Esc / cancel = "no". Focus starts on the safe button (cancel when `danger`).

signal confirmed(ok: bool)

var _title_l: Label
var _body_l: Label
var _yes: Button
var _no: Button
var _card: PanelContainer
var _backdrop: ColorRect
var _done: bool = false
var _danger: bool = false
var _opened_ms: int = 0
var _wrapper: Node = null


static func present(host: Node, title: String, body: String, confirm_text: String = "Yes",
		cancel_text: String = "Cancel", danger: bool = false) -> ConfirmDialog:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var d := ConfirmDialog.new()
	d._wrapper = layer
	layer.add_child(d)
	d.ask(title, body, confirm_text, cancel_text, danger)
	return d


func _init() -> void:
	theme = UITheme.build()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop = OvUtil.make_backdrop(0.62)
	add_child(_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = UIKit.card()
	_card.custom_minimum_size = Vector2(620, 0)
	center.add_child(_card)
	var v := UIKit.vbox(14)
	_card.add_child(UIKit.with_margin(v, 14))
	_title_l = UIKit.title_label("")
	_title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title_l)
	_body_l = Label.new()
	_body_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_l.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_body_l.custom_minimum_size = Vector2(540, 0)
	v.add_child(_body_l)
	v.add_child(UIKit.v_spacer(6))
	var row := UIKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	_no = UIKit.secondary_button("Cancel")
	_no.custom_minimum_size = Vector2(220, 60)
	OvUtil.focusable(_no)
	_no.pressed.connect(_finish.bind(false))
	row.add_child(_no)
	_yes = UIKit.primary_button("Yes")
	_yes.custom_minimum_size = Vector2(220, 60)
	OvUtil.focusable(_yes)
	_yes.pressed.connect(_finish.bind(true))
	row.add_child(_yes)


func ask(title: String, body: String, confirm_text: String = "Yes", cancel_text: String = "Cancel",
		danger: bool = false) -> void:
	_title_l.text = title
	_body_l.text = body
	_yes.text = confirm_text
	_no.text = cancel_text
	_danger = danger
	_yes.theme_type_variation = &"DangerButton" if danger else &"PrimaryButton"
	_no.theme_type_variation = &"SecondaryButton"
	_done = false
	if is_inside_tree():
		_play_in()
	else:
		ready.connect(_play_in, CONNECT_ONE_SHOT)


func _play_in() -> void:
	_opened_ms = Time.get_ticks_msec()
	_backdrop.modulate.a = 0.0
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.86, 0.86)
	_card.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_backdrop, "modulate:a", 1.0, 0.18)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "modulate:a", 1.0, 0.16)
	(_no if _danger else _yes).call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if _done or event is InputEventMouseButton:
		return
	if Time.get_ticks_msec() - _opened_ms < 150:
		return
	if event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish(false)


func _finish(ok: bool) -> void:
	if _done:
		return
	_done = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_card, "scale", Vector2(0.92, 0.92), 0.14)
	tw.tween_property(self, "modulate:a", 0.0, 0.14)
	tw.chain().tween_callback(func() -> void:
		confirmed.emit(ok)
		if _wrapper != null and is_instance_valid(_wrapper):
			_wrapper.queue_free()
		else:
			queue_free())
