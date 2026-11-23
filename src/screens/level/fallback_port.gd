extends Control
## Tiny stand-in for PortPhase (used only while src/screens/level/port/port_phase.gd does not exist).
## Same contract: signals set_sail_requested / exit_requested, setup(level, port, view, camera), teardown().

signal set_sail_requested
signal exit_requested

var _port: PortState = null
var _info: Label = null


func setup(level: LevelDef, port: PortState, _view: ShipView, _camera: ShipCamera) -> void:
	_port = port
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := UIKit.navy_bar_bottom()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.custom_minimum_size = Vector2(0, 120)
	bar.offset_top = -120
	var row := UIKit.hbox(18)
	_info = UIKit.header_label("")
	_info.theme_type_variation = &"OnDarkTitle"
	row.add_child(_info)
	row.add_child(UIKit.h_spacer())
	var back := UIKit.ghost_button("Back")
	back.pressed.connect(func() -> void: exit_requested.emit())
	row.add_child(back)
	var auto := UIKit.secondary_button("Auto-build")
	auto.pressed.connect(func() -> void:
		AutoBuilder.apply(_port)
		_port.changed.emit()
		_refresh())
	row.add_child(auto)
	var sail := UIKit.primary_button("Set sail!")
	sail.pressed.connect(func() -> void: set_sail_requested.emit())
	row.add_child(sail)
	bar.add_child(UIKit.with_margin(row, 16))
	add_child(bar)
	var title := UIKit.title_label(level.display_name)
	title.theme_type_variation = &"OnDarkTitle"
	title.position = Vector2(40, 24)
	add_child(title)
	_refresh()


func _refresh() -> void:
	if _info != null and _port != null:
		_info.text = "Budget $%d   Crew %d/%d" % [_port.budget, _port.staff_total(), _port.max_staff()]


func teardown() -> void:
	pass
