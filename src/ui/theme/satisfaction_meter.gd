class_name SatisfactionMeter
extends Control
## Ship rating meter: gradient red -> yellow -> green fill with three star threshold marks that light up.
##   value: float 0..100;  star_thresholds: Array[float] (default 40/65/85, 0..3 marks are fine);  show_face: bool.
## Below `danger_below` (20) the trough pulses red (mutiny warning).

const U := preload("res://src/render/art/art_util.gd")

var value: float = 50.0:
	set(v):
		value = clampf(v, 0.0, 100.0)
		_check_pops()
		queue_redraw()
var star_thresholds: Array[float] = [40.0, 65.0, 85.0]:
	set(v):
		star_thresholds = v
		_lit.clear()
		queue_redraw()
var show_face: bool = true:
	set(v):
		show_face = v
		queue_redraw()
var danger_below: float = 20.0
var _lit: Array[bool] = []
var _pop: Array[float] = []
var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(380, 40)


func _check_pops() -> void:
	if _lit.size() != star_thresholds.size():
		_lit.clear()
		_pop.clear()
		for th in star_thresholds:
			_lit.append(value >= th)
			_pop.append(1.0)
		return
	for i in range(star_thresholds.size()):
		var on := value >= star_thresholds[i]
		if on != _lit[i]:
			_lit[i] = on
			_pop[i] = 0.0 if on else 1.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	for i in range(_pop.size()):
		_pop[i] = minf(_pop[i] + delta * 2.2, 1.0)
	queue_redraw()


static func color_at(f: float) -> Color:
	f = clampf(f, 0.0, 1.0)
	if f < 0.5:
		return Palette.CORAL.lerp(Palette.SUN, f * 2.0)
	return Palette.SUN.lerp(Palette.MINT, (f - 0.5) * 2.0)


func face_icon() -> StringName:
	# mood bands follow the marks when there are two or more; fewer marks (0..1) fall back to sane defaults
	var n := star_thresholds.size()
	var hi: float = star_thresholds[1] if n >= 2 else (star_thresholds[0] if n == 1 else 65.0)
	var lo: float = star_thresholds[0] if n >= 2 else minf(40.0, hi)
	if value >= hi:
		return &"smile"
	if value >= lo:
		return &"meh"
	return &"frown"


func _draw() -> void:
	if _lit.size() != star_thresholds.size():
		_check_pops()
	var w := size.x
	var h := size.y
	var bh := 18.0
	var by := h * 0.5 - bh * 0.5 + 2.0
	var bx := 44.0 if show_face else 8.0
	var bw := w - bx - 16.0
	var danger := value < danger_below
	if show_face:
		var fc := Vector2(20.0, h * 0.5)
		U.circ(self, fc + Vector2(0, 2), 17.0, Color(0, 0, 0, 0.18))
		U.circ(self, fc, 17.0, Color(0.1686, 0.2275, 0.3333, 0.9))
		IconArt.draw_icon(self, &"angry" if danger else face_icon(), fc, 26.0, _t, false)
	var trough := Rect2(bx, by, bw, bh)
	if danger:
		var pa := 0.25 + 0.35 * U.pulse(_t, 1.6)
		U.rr(self, trough.grow(4.0), bh * 0.5 + 4.0, Color(Palette.CORAL.r, Palette.CORAL.g, Palette.CORAL.b, pa))
	U.rr(self, trough.grow(2.0), bh * 0.5 + 2.0, Color(1, 1, 1, 0.12))
	U.rr(self, trough, bh * 0.5, Color(0.07, 0.10, 0.18, 0.6))
	# gradient fill (absolute colour positions: left red .. right green)
	var f := value / 100.0
	var fw := bw * f
	var r := bh * 0.5
	if fw > 1.0:
		if fw < bh:
			U.rr(self, Rect2(bx, by, fw, bh), minf(r, fw * 0.5), color_at(0.0))
		else:
			var slices := maxi(int(fw / 10.0), 4)
			var x_a := bx + r
			var x_b := bx + fw - r
			U.circ(self, Vector2(bx + r, by + r), r, color_at(0.0))
			U.circ(self, Vector2(bx + fw - r, by + r), r, color_at(f))
			var sw := (x_b - x_a) / float(slices)
			for i in range(slices):
				var cx := x_a + sw * float(i)
				var cf := (cx - bx + sw * 0.5) / bw
				U.rect(self, Rect2(cx, by, sw + 0.7, bh), color_at(cf))
			U.rr(self, Rect2(bx + 5.0, by + 2.5, maxf(fw - 10.0, 1.0), 3.5), 1.7, Color(1, 1, 1, 0.30))
	# star marks
	for i in range(star_thresholds.size()):
		var x := bx + bw * star_thresholds[i] / 100.0
		var cy := by + bh * 0.5
		var lit := _lit[i]
		var k := 1.0
		if lit:
			k = U.ease_out_back(clampf(_pop[i], 0.0, 1.0)) * 1.0
			k = clampf(k, 0.0, 1.35)
		var kb := k if lit else 1.0
		# round badge behind each star so it reads on any part of the gradient
		U.circ(self, Vector2(x, cy + 1.5), 15.0 * kb, Color(0, 0, 0, 0.22))
		U.circ(self, Vector2(x, cy), 15.0 * kb, Color(1, 1, 1, 0.95) if lit else Color(0.12, 0.17, 0.27, 0.95))
		U.circ(self, Vector2(x, cy), 12.6 * kb, Color(0.16, 0.22, 0.34, 1.0) if lit else Color(0.2, 0.27, 0.4, 1.0))
		IconArt.draw_icon(self, &"star" if lit else &"star_empty", Vector2(x, cy + 0.5), 20.0 * kb, _t, false)
