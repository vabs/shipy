extends Control
## Settings screen: a SettingsPanel centred over the sunny sea. Back -> params.back (default "menu").
## Dev: --scene=settings --tab=0..4

var _back: String = "menu"
var _tab: int = 0
var _panel: SettingsPanel
var _fade: ColorRect
var _leaving: bool = false


func setup(params: Dictionary) -> void:
	OvUtil.dev_save(params)
	_back = String(params.get("back", "menu"))
	_tab = int(params.get("tab", 0))


func _ready() -> void:
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sea := SeaBackground.attach_to(self)
	sea.set_destination(&"med")
	sea.set_motion_scale(0.35)
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	# soft veil so the card pops against the scenery
	var veil := ColorRect.new()
	veil.color = Color(0.1, 0.16, 0.3, 0.28)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = SettingsPanel.new()
	_panel.back_text = "Back"
	_panel.closed.connect(_leave)
	center.add_child(_panel)
	_panel.show_tab(_tab)
	_panel.focus_first()
	_fade = ColorRect.new()
	_fade.color = Color(0.08, 0.11, 0.2, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	create_tween().tween_property(_fade, "modulate:a", 0.0, 0.25)
	# entrance
	await get_tree().process_frame
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.94, 0.94)
	_panel.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)
	AudioManager.play_music(&"port")


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.2)
	tw.tween_callback(func() -> void: Router.goto(_back))
