class_name VoyageProgress
extends Control
## Voyage progress bar: a little ship sails along a water trough towards a flag.
##   value: float 0..1. Animated (bobbing ship, waving flag, wake foam). Min size 420x46.

const U := preload("res://src/render/art/art_util.gd")

var value: float = 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(420, 46)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var th := 16.0
	var ty := h - th - 5.0
	var x0 := 6.0
	var x1 := w - 34.0
	var trough := Rect2(x0, ty, w - x0 * 2.0, th)
	U.rr(self, trough.grow(2.0), th * 0.5 + 2.0, Color(1, 1, 1, 0.16))
	U.rr(self, trough, th * 0.5, Color(0.04, 0.07, 0.13, 0.78))
	var sx: float = lerpf(x0 + 20.0, x1 - 6.0, value)
	# water fill
	var fw := sx - x0 + 6.0
	if fw > th:
		U.rr(self, Rect2(x0, ty, fw, th), th * 0.5, Palette.TEAL_DARK)
		U.rr(self, Rect2(x0, ty, fw, th - 3.0), th * 0.5 - 1.0, Palette.TEAL)
		U.rr(self, Rect2(x0 + 4.0, ty + 2.0, maxf(fw - 8.0, 2.0), 3.0), 1.5, Color(1, 1, 1, 0.28))
		# little wave ticks moving left
		var n := int(fw / 22.0)
		for i in range(n):
			var wx := x0 + 10.0 + fposmod(float(i) * 22.0 - _t * 14.0, maxf(fw - 20.0, 22.0))
			U.arc(self, Vector2(wx, ty + th * 0.62), 3.5, PI * 1.1, PI * 1.9, Color(1, 1, 1, 0.45), 1.4, 6)
	# tick marks for milestones
	for i in range(1, 4):
		var mx := lerpf(x0 + 20.0, x1 - 6.0, float(i) / 4.0)
		U.circ(self, Vector2(mx, ty + th * 0.5), 1.6, Color(1, 1, 1, 0.35))
	# flag at the end
	var fx := w - 20.0
	var fy := ty + th * 0.5
	U.circ(self, Vector2(fx, fy), 4.0, Palette.CREAM)
	U.rr(self, Rect2(fx - 1.2, fy - 30.0, 2.4, 30.0), 1.0, Palette.CREAM)
	var wave := sin(_t * 5.0) * 2.0
	var flag := PackedVector2Array([Vector2(fx + 1.2, fy - 30.0), Vector2(fx + 18.0, fy - 26.0 + wave), Vector2(fx + 1.2, fy - 18.0)])
	U.poly(self, flag, Palette.CORAL)
	U.circ(self, Vector2(fx, fy - 31.0), 2.4, Palette.SUN)
	# wake foam
	var bob := sin(_t * 2.6) * 1.5
	for i in range(4):
		var f := fposmod(_t * 1.1 + float(i) * 0.25, 1.0)
		var fxp := sx - 16.0 - f * 26.0
		var a := (1.0 - f) * 0.7
		U.circ(self, Vector2(fxp, ty + th * 0.55 + sin(f * 6.0 + float(i)) * 1.2), 2.8 * (1.0 - f * 0.5), Color(1, 1, 1, a))
	_ship(Vector2(sx, ty + th * 0.35 + bob), _t)


func _ship(p: Vector2, t: float) -> void:
	# smoke
	for i in range(3):
		var f := fposmod(t * 0.7 + float(i) / 3.0, 1.0)
		U.circ(self, p + Vector2(-5.0 - f * 14.0, -26.0 - f * 12.0), 2.0 + f * 3.0, Color(1, 1, 1, (1.0 - f) * 0.55))
	U.xf(self, p, sin(t * 2.6) * 0.04)
	# hull
	var hull := PackedVector2Array([Vector2(-18, -7), Vector2(19, -7), Vector2(14, 5), Vector2(-14, 5)])
	U.poly(self, hull, Palette.NAVY)
	U.rr(self, Rect2(-20, -9, 41, 4), 2.0, Palette.HULL_WHITE)
	U.rect(self, Rect2(-16, -2, 31, 2.2), Palette.CORAL)
	# cabin
	U.rr(self, Rect2(-11, -19, 20, 11), 3.0, Palette.HULL_WHITE)
	U.rr(self, Rect2(-8, -16, 4, 4), 1.6, Palette.TEAL)
	U.rr(self, Rect2(-2, -16, 4, 4), 1.6, Palette.TEAL)
	U.rr(self, Rect2(4, -16, 3, 4), 1.6, Palette.TEAL)
	# funnel
	U.rr(self, Rect2(-5, -28, 8, 10), 2.0, Palette.CORAL)
	U.rect(self, Rect2(-5, -24.5, 8, 2.4), Palette.SUN)
	U.xf_end(self)
