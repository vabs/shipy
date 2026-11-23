class_name TutorialPointer
extends Control
## Pulsing ring + bouncing arrow around the spotlight windows. Mouse transparent.
##
##   rects / radii / arrows   parallel arrays set every frame by TutorialUI (screen-space viewport px, already padded)
##   avoid: Rect2             area the arrows must not cover (the hint card)
##   active: bool             draw nothing when false

const U := preload("res://src/render/art/art_util.gd")
const ARROW_LEN: float = 62.0
const GAP: float = 10.0

var rects: Array[Rect2] = []
var radii: Array[float] = []
var arrows: Array[bool] = []
var avoid: Rect2 = Rect2()
var active: bool = true
var _t: float = 0.0
var _fade: float = 0.0
var _flash: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 2


## Mint burst around the windows when a step was completed.
func flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(_flash - delta * 2.2, 0.0)
	_fade = move_toward(_fade, 1.0 if (active and not rects.is_empty()) else 0.0, delta * 4.0)
	visible = _fade > 0.01
	if visible:
		queue_redraw()


func _draw() -> void:
	var vp: Vector2 = size
	for i in rects.size():
		var r: Rect2 = rects[i]
		_ring(r, radii[i] if i < radii.size() else 18.0)
	for i in rects.size():
		if i < arrows.size() and arrows[i]:
			_arrow(rects[i], vp)


func _ring(r: Rect2, rad: float) -> void:
	var k: float = _fade
	var beat: float = 0.5 + 0.5 * sin(_t * 4.2)
	# steady glow ring
	U.rr_outline(self, r.grow(2.0), rad + 2.0, Color(Palette.SUN.r, Palette.SUN.g, Palette.SUN.b, (0.55 + 0.4 * beat) * k), 4.0)
	U.rr_outline(self, r.grow(-1.0), maxf(rad - 1.0, 2.0), Color(1, 1, 1, 0.75 * k), 2.0)
	# sonar ripple
	var ph: float = fmod(_t * 0.85, 1.0)
	var grow: float = 6.0 + 26.0 * ph
	U.rr_outline(self, r.grow(grow), rad + grow, Color(Palette.SUN.r, Palette.SUN.g, Palette.SUN.b, 0.5 * (1.0 - ph) * k), 3.0)
	if _flash > 0.0:
		var fg: float = 4.0 + 60.0 * (1.0 - _flash)
		U.rr_outline(self, r.grow(fg), rad + fg, Color(Palette.MINT.r, Palette.MINT.g, Palette.MINT.b, _flash * 0.9), 6.0)


## Picks a side of the target with room for the arrow (and clear of the hint card).
func _arrow(r: Rect2, vp: Vector2) -> void:
	var c: Vector2 = r.get_center()
	var prefer_below: bool = c.y < vp.y * 0.28
	var order: Array[Vector2] = [Vector2.DOWN, Vector2.UP, Vector2.RIGHT, Vector2.LEFT]
	if prefer_below:
		order = [Vector2.UP, Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT]
	var chosen: Vector2 = order[0]
	for d in order:
		var tip: Vector2 = _tip_for(r, d)
		var box: Rect2 = _arrow_box(tip, d)
		if not Rect2(Vector2(6, 6), vp - Vector2(12, 12)).encloses(box):
			continue
		if avoid.size.x > 0.0 and avoid.grow(10.0).intersects(box):
			continue
		chosen = d
		break
	var tip2: Vector2 = _tip_for(r, chosen)
	var bounce: float = (0.5 + 0.5 * sin(_t * 5.6)) * 12.0
	tip2 -= chosen * bounce
	_draw_arrow(tip2, chosen)


## `d` is the direction the arrow POINTS (DOWN = arrow sits above the target).
func _tip_for(r: Rect2, d: Vector2) -> Vector2:
	var c: Vector2 = r.get_center()
	if d == Vector2.DOWN:
		return Vector2(c.x, r.position.y - GAP)
	if d == Vector2.UP:
		return Vector2(c.x, r.end.y + GAP)
	if d == Vector2.RIGHT:
		return Vector2(r.position.x - GAP, c.y)
	return Vector2(r.end.x + GAP, c.y)


func _arrow_box(tip: Vector2, d: Vector2) -> Rect2:
	var back: Vector2 = tip - d * (ARROW_LEN + 12.0)
	var half: float = 28.0
	var a: Vector2 = tip - d.orthogonal() * half
	var b: Vector2 = back + d.orthogonal() * half
	var tl := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var br := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(tl, br - tl)


func _draw_arrow(tip: Vector2, d: Vector2) -> void:
	var rot: float = d.angle() - PI * 0.5   # shape below points DOWN (+y)
	var pts := PackedVector2Array([
		Vector2(0, 0), Vector2(-25, -27), Vector2(-10, -27), Vector2(-10, -ARROW_LEN),
		Vector2(10, -ARROW_LEN), Vector2(10, -27), Vector2(25, -27),
	])
	var xf := Transform2D(rot, tip)
	var world := PackedVector2Array()
	for p in pts:
		world.append(xf * p)
	var k: float = _fade
	var shadow := PackedVector2Array()
	for p in world:
		shadow.append(p + Vector2(2, 5))
	draw_colored_polygon(shadow, Color(0.05, 0.08, 0.16, 0.28 * k))
	var closed := world.duplicate()
	closed.append(world[0])
	draw_polyline(closed, Color(1, 1, 1, k), 9.0, true)
	draw_colored_polygon(world, Color(Palette.CORAL.r, Palette.CORAL.g, Palette.CORAL.b, k))
	# lighter left half for a toy-like bevel
	var hi := PackedVector2Array([xf * Vector2(0, -2), xf * Vector2(-18, -27), xf * Vector2(-6, -27), xf * Vector2(-6, -ARROW_LEN + 4), xf * Vector2(0, -ARROW_LEN + 4)])
	draw_colored_polygon(hi, Color(1, 1, 1, 0.22 * k))
	draw_polyline(closed, Color(Palette.CORAL_DARK.r, Palette.CORAL_DARK.g, Palette.CORAL_DARK.b, k), 2.5, true)
