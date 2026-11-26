class_name HeatmapOverlay
extends Node2D
## Tints the ship's cells by how much guests used them during the last voyage (docs/SPEC.md §13.2). Lives in a ShipView
## layer (usually "overlay"), so it bobs with the ship. Smooth horizontal bands per deck, strongest along the floor
## where guests walk: transparent -> sun yellow -> coral (colour-blind palette: blue -> orange).
##
##   var h := HeatmapOverlay.new(); view.get_layer(&"overlay").add_child(h)
##   h.setup(report: Dictionary, colorblind: bool, ship_rect: Rect2)   # report = VoyageTelemetry.report()
##   h.set_mode(&"traffic" | &"unhappy" | &"queue")      h.mode
##   h.peak() -> float                 largest (smoothed) cell value of the current mode, in guest-seconds
##   h.hottest() -> Dictionary         {deck, x, value} of that cell ({} when the mode is empty)
##   HeatmapOverlay.ramp(t, colorblind) -> Color      t 0..1 (alpha rises with t)

const MODES: Array[StringName] = [&"traffic", &"unhappy", &"queue"]
const MODE_NAMES: Dictionary = {&"traffic": "Traffic", &"unhappy": "Unhappy", &"queue": "Queues"}
const MODE_CAPTIONS: Dictionary = {
	&"traffic": "Where guests walked and waited",
	&"unhappy": "Where guests were unhappy (satisfaction under 40)",
	&"queue": "Where guests stood in line",
}
const CELL_W: float = SimConst.CELL_W
const DECK_H: float = SimConst.DECK_H

var mode: StringName = &"traffic"
var colorblind: bool = false

var _decks: int = 0
var _width: int = 0
var _grids: Dictionary = {}      # mode -> Array[PackedFloat32Array] (smoothed)
var _peaks: Dictionary = {}      # mode -> float
var _hot: Dictionary = {}        # mode -> {deck, x, value}
var _rect: Rect2 = Rect2()
var _marker: _Marker = null


class _Marker extends Node2D:
	var owner_overlay: HeatmapOverlay
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var hot: Dictionary = owner_overlay.hottest()
		if hot.is_empty():
			return
		var c: Vector2 = SimConst.to_px(float(hot["x"]) + 0.5, float(hot["deck"])) + Vector2(0, -16.0)
		var k: float = 0.5 + 0.5 * sin(_t * 3.2)
		var col: Color = Color.WHITE
		ArtUtil.ring(self, c, 26.0 + 5.0 * k, Color(col.r, col.g, col.b, 0.9 - 0.4 * k), 4.0)
		ArtUtil.ring(self, c, 18.0, Color(0.1, 0.14, 0.26, 0.55), 3.0)
		var txt: String = "%ds" % int(round(float(hot["value"])))
		ArtUtil.text_outlined(self, txt, c + Vector2(-30.0, -38.0), 22, Color.WHITE, Color(0.1, 0.14, 0.26, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 60.0)


func setup(report: Dictionary, cb: bool, ship_rect: Rect2) -> void:
	colorblind = cb
	_rect = ship_rect
	_decks = int(report.get("decks", 0))
	_width = int(report.get("width", 0))
	var grids: Dictionary = report.get("grids", {})
	_grids.clear()
	_peaks.clear()
	_hot.clear()
	for m in MODES:
		var raw: Array = grids.get(m, [])
		var sm: Array[PackedFloat32Array] = []
		var peak: float = 0.0
		var hot: Dictionary = {}
		for d in range(_decks):
			var row := PackedFloat32Array()
			row.resize(_width)
			row.fill(0.0)
			if d < raw.size():
				var src: PackedFloat32Array = raw[d]
				row = _smooth(_smooth(src))
			sm.append(row)
			for i in range(row.size()):
				if row[i] > peak:
					peak = row[i]
					hot = {"deck": d, "x": i, "value": row[i]}
		_grids[m] = sm
		_peaks[m] = peak
		_hot[m] = hot
	if _marker == null:
		_marker = _Marker.new()
		_marker.owner_overlay = self
		add_child(_marker)
	queue_redraw()


func set_mode(m: StringName) -> void:
	if m not in MODES or m == mode:
		return
	mode = m
	queue_redraw()
	if _marker != null:
		_marker.queue_redraw()


func set_colorblind(cb: bool) -> void:
	if cb == colorblind:
		return
	colorblind = cb
	queue_redraw()


func peak() -> float:
	return float(_peaks.get(mode, 0.0))


func hottest() -> Dictionary:
	var h: Dictionary = _hot.get(mode, {})
	if h.is_empty() or float(h.get("value", 0.0)) < 1.0:
		return {}
	return h


## 1-2-1 smoothing along x so a handful of queue cells blends into a believable hot patch.
static func _smooth(src: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = src.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var a: float = src[maxi(i - 1, 0)]
		var b: float = src[i]
		var c: float = src[mini(i + 1, n - 1)]
		out[i] = (a + 2.0 * b + c) * 0.25
	return out


## Heat colour for t in 0..1: transparent -> sun yellow -> coral, or transparent -> blue -> orange for colour-blind mode.
static func ramp(t: float, cb: bool = false) -> Color:
	t = clampf(t, 0.0, 1.0)
	var lo: Color = Color("FFD866")
	var mid: Color = Color("FFB347")
	var hi: Color = Palette.CORAL
	if cb:
		# blue (cool) -> orange (hot); both stay distinguishable for the common colour-vision types
		lo = Color("56B4E9")
		mid = Color("3F6FD0")
		hi = Color("F59B00")
	var c: Color
	if t < 0.5:
		c = lo.lerp(mid, t * 2.0)
	else:
		c = mid.lerp(hi, (t - 0.5) * 2.0)
	c.a = clampf(t * 2.2, 0.0, 1.0) * 0.82
	return c


func _draw() -> void:
	# dim the interior decks a little so the heat reads (not the open top deck or the sky around the ship)
	if _decks > 1 and _width > 0:
		ArtUtil.rect(self, Rect2(0.0, -float(_decks - 1) * DECK_H, float(_width) * CELL_W, float(_decks - 1) * DECK_H), Color(0.1, 0.14, 0.26, 0.26))
	var grid: Array = _grids.get(mode, [])
	var pk: float = float(_peaks.get(mode, 0.0))
	if pk <= 0.0001:
		return
	for d in range(grid.size()):
		var row: PackedFloat32Array = grid[d]
		var y_floor: float = -float(d) * DECK_H
		var y_top: float = y_floor - DECK_H
		var cols := PackedColorArray()
		for i in range(row.size()):
			cols.append(ramp(pow(row[i] / pk, 0.75), colorblind))
		# one quad between neighbouring cell centres, solid on the floor and fading up the wall
		for i in range(-1, row.size()):
			var i0: int = maxi(i, 0)
			var i1: int = mini(i + 1, row.size() - 1)
			var c0: Color = cols[i0]
			var c1: Color = cols[i1]
			if c0.a < 0.01 and c1.a < 0.01:
				continue
			var x0: float = maxf((float(i) + 0.5) * CELL_W, 0.0)
			var x1: float = minf((float(i + 1) + 0.5) * CELL_W, float(row.size()) * CELL_W)
			var t0 := Color(c0.r, c0.g, c0.b, c0.a * 0.28)
			var t1 := Color(c1.r, c1.g, c1.b, c1.a * 0.28)
			draw_primitive(PackedVector2Array([Vector2(x0, y_top), Vector2(x1, y_top), Vector2(x1, y_floor), Vector2(x0, y_floor)]),
					PackedColorArray([t0, t1, c1, c0]), PackedVector2Array())
