class_name PerkIcon
extends Control
## Control that draws a PerkArt badge (or bare glyph) centred in its rect.
##   perk: StringName (PerkArt id)   icon_size: float (px)   badge: bool (true = coloured badge, false = bare glyph)
##   glyph_color / accent: colours of a bare glyph   animate: bool (continuous time for the few animated details)

var perk: StringName = &"budget":
	set(v):
		perk = v
		queue_redraw()
var icon_size: float = 64.0:
	set(v):
		icon_size = v
		custom_minimum_size = Vector2(v, v)
		queue_redraw()
var badge: bool = true:
	set(v):
		badge = v
		queue_redraw()
var glyph_color: Color = Palette.CREAM:
	set(v):
		glyph_color = v
		queue_redraw()
var accent: Color = Palette.SUN:
	set(v):
		accent = v
		queue_redraw()
var animate: bool = false:
	set(v):
		animate = v
		set_process(v)
var _t: float = 0.0


func _init(id: StringName = &"budget", px: float = 64.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	perk = id
	icon_size = px


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	if badge:
		PerkArt.draw_badge(self, perk, size * 0.5, icon_size, _t)
	else:
		PerkArt.draw_glyph(self, perk, size * 0.5, icon_size, glyph_color, accent)
