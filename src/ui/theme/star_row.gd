class_name StarRow
extends Control
## Row of stars (e.g. level result 0..3). value: int, max_stars: int (3), star_size: float (28).
## Newly lit stars pop in.

var value: int = 0:
	set(v):
		v = clampi(v, 0, max_stars)
		if v > value:
			_pop_idx = v - 1
			_pop = 0.0
			set_process(true)
		value = v
		queue_redraw()
var max_stars: int = 3:
	set(v):
		max_stars = v
		_update_min()
		queue_redraw()
var star_size: float = 28.0:
	set(v):
		star_size = v
		_update_min()
		queue_redraw()
var spacing: float = 4.0
var _pop_idx: int = -1
var _pop: float = 1.0
var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_min()
	set_process(false)


func _update_min() -> void:
	custom_minimum_size = Vector2((star_size + spacing) * max_stars, star_size + 6.0)


func _process(delta: float) -> void:
	_t += delta
	_pop = minf(_pop + delta * 2.4, 1.0)
	queue_redraw()
	if _pop >= 1.0:
		set_process(false)


func _draw() -> void:
	var total := (star_size + spacing) * max_stars - spacing
	var x0 := (size.x - total) * 0.5
	for i in range(max_stars):
		var c := Vector2(x0 + star_size * 0.5 + (star_size + spacing) * i, size.y * 0.5)
		var lit := i < value
		var k := 1.0
		if lit and i == _pop_idx and _pop < 1.0:
			k = clampf(ArtUtil.ease_out_back(_pop), 0.0, 1.4)
			c.y -= sin(_pop * PI) * 4.0
		IconArt.draw_icon(self, &"star" if lit else &"star_empty", c, star_size * k, _t, false)
