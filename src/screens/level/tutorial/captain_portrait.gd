class_name CaptainPortrait
extends Control
## The tutorial narrator: a cream bean with a navy captain's cap, framed in the same round plate as BeanPortrait.
##   portrait_size: float (px, square)      nod() -> little hop when a new hint appears

const U := preload("res://src/render/art/art_util.gd")

var portrait_size: float = 92.0:
	set(v):
		portrait_size = v
		custom_minimum_size = Vector2(v, v)
		queue_redraw()
var plate_color: Color = Color("CDEFFB")
var _t: float = 0.0
var _nod: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(portrait_size, portrait_size)


func nod() -> void:
	_nod = 1.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_nod = maxf(_nod - delta * 3.2, 0.0)
	queue_redraw()


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var c := Vector2(size.x * 0.5, size.y * 0.5)
	var r: float = s * 0.5 - 2.0
	U.circ(self, c + Vector2(0, 2), r, Color(0.1, 0.14, 0.26, 0.2))
	U.circ(self, c, r, plate_color)
	U.circ(self, c + Vector2(0, r * 0.55), r * 0.62, plate_color.lerp(Color.WHITE, 0.35))
	var k: float = s / 33.0
	var hop: float = sin(clampf(_nod, 0.0, 1.0) * PI) * 3.0
	U.begin_scaled(self, c + Vector2(0, r * 0.66 - hop), k)
	var o: Dictionary = {"prop": &"", "body_color": Color("F7F4EC"), "facing": 1, "walk_phase": 0.0, "pose": &"stand",
			"sick": false, "t": _t, "highlight": 0, "scale": 1.0}
	GuestArt.draw_guest(self, Vector2.ZERO, o)
	# captain's cap (guest space: head top is y = -21.5, body half-width ~7)
	var top: float = -21.5
	U.ellipse(self, Vector2(0.5, top + 2.6), 9.6, 2.6, Palette.NAVY_DARK)                 # brim
	U.rr(self, Rect2(-6.8, top - 4.6, 14.6, 7.0), 3.4, Palette.NAVY)                      # crown
	U.rr(self, Rect2(-6.8, top - 4.6, 14.6, 2.4), 1.8, Color(1, 1, 1, 0.16))             # crown sheen
	U.rr(self, Rect2(-6.8, top - 0.6, 14.6, 2.0), 0.8, Palette.HULL_WHITE)               # band
	U.circ(self, Vector2(0.5, top - 2.0), 2.1, Palette.SUN)                               # badge
	U.circ(self, Vector2(0.5, top - 2.0), 1.0, Palette.SUN_DEEP)
	U.end_scaled(self)
	U.arc(self, c, r, 0.0, TAU, Color(1, 1, 1, 0.92), 3.0, 40)
