class_name IconView
extends Control
## Control that draws an IconArt icon centred in its rect.
##   icon: StringName (IconArt id, e.g. &"coin"), icon_size: float (px), colorblind: bool,
##   animate: bool (continuous animation time passed to IconArt).
## `colorblind` follows Settings.colorblind (live) until a caller assigns it explicitly.
## NOTE: use `icon_size`, not `size` (Control.size).

var icon: StringName = &"star":
	set(v):
		icon = v
		queue_redraw()
var icon_size: float = 32.0:
	set(v):
		icon_size = v
		custom_minimum_size = Vector2(v, v)
		queue_redraw()
var colorblind: bool = false:
	set(v):
		colorblind = v
		_cb_explicit = true
		queue_redraw()
var _cb_explicit: bool = false
var animate: bool = false:
	set(v):
		animate = v
		set_process(v)
		queue_redraw()
var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(icon_size, icon_size)
	set_process(false)
	colorblind = Settings.colorblind
	_cb_explicit = false


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting):
		Settings.changed.disconnect(_on_setting)


func _enter_tree() -> void:
	if not Settings.changed.is_connected(_on_setting):
		Settings.changed.connect(_on_setting)


func _on_setting(key: StringName) -> void:
	if key == &"colorblind" and not _cb_explicit:
		colorblind = Settings.colorblind
		_cb_explicit = false


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	IconArt.draw_icon(self, icon, size * 0.5, icon_size, _t, colorblind)
