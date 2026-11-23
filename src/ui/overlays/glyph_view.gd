class_name GlyphView
extends Control
## Draws an IconArt icon OR a room badge (room ids) centred in its rect.
##   glyph: StringName (icon id like &"coin", or a room id like &"cinema"), glyph_size: float, colorblind: bool,
##   animate: bool (continuous time for animated icons).

var glyph: StringName = &"star":
	set(v):
		glyph = v
		queue_redraw()
var glyph_size: float = 32.0:
	set(v):
		glyph_size = v
		custom_minimum_size = Vector2(v, v)
		queue_redraw()
var colorblind: bool = false:
	set(v):
		colorblind = v
		queue_redraw()
var animate: bool = false:
	set(v):
		animate = v
		set_process(v)
var _t: float = 0.0


func _init(g: StringName = &"star", px: float = 32.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	colorblind = Settings.colorblind
	glyph = g
	glyph_size = px
	set_process(false)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	if glyph in IconArt.ROOM_ICONS:
		IconArt.draw_room_icon(self, glyph, size * 0.5, glyph_size)
	elif glyph != &"":
		IconArt.draw_icon(self, glyph, size * 0.5, glyph_size, _t, colorblind)
