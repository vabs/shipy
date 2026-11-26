class_name VoyageTooltip
extends Control
## Hover / pinned tooltip card, drawn by hand (cream card, soft shadow) so bars and icons can be animated
## every frame without rebuilding Controls.
##
## model keys: title: String, icon: StringName (optional), tag: String (small caption right of the title),
##   lines: Array[String], bars: Array[{icon, label, value 0..1, color}], hint: String, pinned: bool, accent: Color,
##   review: {value 0..1, caption, detail, grade} (a VIP's review meter: gold-edged bar under the lines)

const U := preload("res://src/render/art/art_util.gd")
const PAD: float = 14.0
const MIN_W: float = 230.0
const REVIEW_H: float = 76.0

var model: Dictionary = {}
var _size_px: Vector2 = Vector2(MIN_W, 80)
var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 100


func hide_tip() -> void:
	if visible:
		visible = false


## Shows `m` with its card anchored near `anchor` (screen px); the card stays inside the viewport.
func show_model(m: Dictionary, anchor: Vector2, offset: Vector2 = Vector2(22, 18)) -> void:
	model = m
	_size_px = _measure()
	var vp: Vector2 = get_viewport_rect().size
	var p: Vector2 = anchor + offset
	if p.x + _size_px.x > vp.x - 8.0:
		p.x = anchor.x - offset.x - _size_px.x
	if p.y + _size_px.y > vp.y - 8.0:
		p.y = anchor.y - offset.y - _size_px.y
	p.x = clampf(p.x, 8.0, maxf(vp.x - _size_px.x - 8.0, 8.0))
	p.y = clampf(p.y, 8.0, maxf(vp.y - _size_px.y - 8.0, 8.0))
	position = p
	size = _size_px
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _measure() -> Vector2:
	var f: Font = UITheme.font_bold()
	var fr: Font = UITheme.font()
	var w: float = MIN_W
	var title: String = String(model.get("title", ""))
	var tag: String = String(model.get("tag", ""))
	var tw: float = f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + (34.0 if (model.has("icon") or model.has("room")) else 0.0)
	if tag != "":
		tw += fr.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 12.0
	w = maxf(w, tw + PAD * 2.0)
	var h: float = PAD + 28.0
	for l in model.get("lines", []):
		if l is Dictionary:
			w = maxf(w, fr.get_string_size(String(l["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + PAD * 2.0 + 30.0)
			h += 27.0
		else:
			w = maxf(w, fr.get_string_size(String(l), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + PAD * 2.0)
			h += 23.0
	var review: Dictionary = model.get("review", {})
	if not review.is_empty():
		h += REVIEW_H
		w = maxf(w, fr.get_string_size(String(review.get("detail", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + PAD * 2.0)
	var bars: Array = model.get("bars", [])
	if not bars.is_empty():
		h += 6.0 + 25.0 * float(bars.size())
	var hint: String = String(model.get("hint", ""))
	if hint != "":
		w = maxf(w, fr.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + PAD * 2.0)
		h += 24.0
	h += PAD - 2.0
	return Vector2(minf(w, 380.0), h)


func _draw() -> void:
	if model.is_empty():
		return
	var f: Font = UITheme.font_bold()
	var fr: Font = UITheme.font()
	var r := Rect2(Vector2.ZERO, _size_px)
	var accent: Color = model.get("accent", Palette.TEAL)
	U.rr_shadow(self, r, 16.0, Color("FFF8EC"), Color(0.1, 0.14, 0.26, 0.38), 10.0, Vector2(0, 5))
	U.rr_outline(self, r, 16.0, UITheme.CARD_EDGE, 2.0)
	# accent strip
	U.rr_ex(self, Rect2(2.0, 2.0, r.size.x - 4.0, 5.0), 14.0, 14.0, 0.0, 0.0, accent)
	var y: float = PAD + 12.0
	var x: float = PAD
	if model.has("room"):
		IconArt.draw_room_icon(self, model["room"], Vector2(x + 12.0, y + 2.0), 26.0)
		x += 34.0
	elif model.has("icon"):
		IconArt.draw_icon(self, model["icon"], Vector2(x + 12.0, y + 2.0), 26.0, _t, Settings.colorblind)
		x += 34.0
	U.text(self, String(model.get("title", "")), Vector2(x, y + 9.0), 22, UITheme.TEXT_INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f)
	var tag: String = String(model.get("tag", ""))
	if tag != "":
		_right_text(tag, Vector2(r.size.x - PAD, y + 8.0), fr)
	y += 20.0
	for l in model.get("lines", []):
		if l is Dictionary:
			IconArt.draw_icon(self, l["icon"], Vector2(PAD + 11.0, y + 11.0), 22.0, _t, Settings.colorblind)
			var col: Color = UITheme.TEXT_INK if l.get("on", true) else UITheme.TEXT_MUTED
			U.text(self, String(l["text"]), Vector2(PAD + 30.0, y + 16.0), 18, col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fr)
			y += 27.0
		else:
			U.text(self, String(l), Vector2(PAD, y + 12.0), 18, UITheme.TEXT_MUTED.darkened(0.15), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fr)
			y += 23.0
	var review: Dictionary = model.get("review", {})
	if not review.is_empty():
		_draw_review(review, y + 4.0, r.size.x, fr, f)
		y += REVIEW_H
	var bars: Array = model.get("bars", [])
	if not bars.is_empty():
		y += 6.0
		for b in bars:
			var bx: float = PAD
			IconArt.draw_icon(self, b.get("icon", &"star"), Vector2(bx + 10.0, y + 10.0), 20.0, _t, Settings.colorblind)
			var label: String = String(b.get("label", ""))
			var track := Rect2(bx + 30.0, y + 5.0, r.size.x - PAD * 2.0 - 30.0 - 44.0, 11.0)
			U.rr(self, track, 5.5, Color(0.17, 0.23, 0.36, 0.16))
			var v: float = clampf(float(b.get("value", 0.0)), 0.0, 1.0)
			if v > 0.01:
				var col: Color = b.get("color", Palette.MINT)
				U.rr(self, Rect2(track.position, Vector2(maxf(track.size.y, track.size.x * v), track.size.y)), 5.5, col)
				U.rr(self, Rect2(track.position + Vector2(3, 1.8), Vector2(maxf(track.size.x * v - 6.0, 2.0), 2.6)), 1.3, Color(1, 1, 1, 0.35))
			U.text(self, label, Vector2(r.size.x - PAD - 42.0, y + 15.5), 16, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 42.0, fr)
			y += 25.0
	var hint: String = String(model.get("hint", ""))
	if hint != "":
		y += 4.0
		U.text(self, hint, Vector2(PAD, y + 14.0), 16, Palette.CORAL_DARK if not model.get("pinned", false) else UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fr)


## A VIP's review meter: a gold-edged plate with the standing, a caption ("1/2 meals") and a one-line summary.
func _draw_review(rv: Dictionary, y: float, width: float, fr: Font, fb: Font) -> void:
	var plate := Rect2(PAD, y, width - PAD * 2.0, REVIEW_H - 8.0)
	U.rr(self, plate, 12.0, Color("FFF3CC"))
	U.rr_outline(self, plate, 12.0, Palette.VIP_GOLD_DARK, 2.0)
	IconArt.draw_icon(self, &"vip", Vector2(plate.position.x + 18.0, plate.position.y + 19.0), 24.0, _t, false)
	U.text(self, "REVIEW", Vector2(plate.position.x + 36.0, plate.position.y + 24.0), 15, Palette.VIP_GOLD_DARK.darkened(0.3), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fb)
	var cap: String = String(rv.get("caption", ""))
	var cw: float = fr.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	U.text(self, cap, Vector2(plate.end.x - 10.0 - cw, plate.position.y + 24.0), 16, UITheme.TEXT_INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fr)
	var track := Rect2(plate.position.x + 10.0, plate.position.y + 33.0, plate.size.x - 20.0, 10.0)
	U.rr(self, track, 4.5, Color(0.17, 0.23, 0.36, 0.16))
	var v: float = clampf(float(rv.get("value", 0.0)), 0.0, 1.0)
	var col: Color = Palette.MINT if v >= 0.7 else (Palette.SUN if v >= 0.4 else Palette.CORAL)
	if v > 0.01:
		U.rr(self, Rect2(track.position, Vector2(maxf(track.size.y, track.size.x * v), track.size.y)), 4.5, col)
		U.rr(self, Rect2(track.position + Vector2(3, 1.2), Vector2(maxf(track.size.x * v - 6.0, 2.0), 2.2)), 1.1, Color(1, 1, 1, 0.4))
	var detail: String = String(rv.get("detail", ""))
	if detail != "":
		U.text(self, detail, Vector2(plate.position.x + 10.0, plate.position.y + 59.0), 14, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fr)


func _right_text(s: String, p: Vector2, f: Font) -> void:
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	U.text(self, s, Vector2(p.x - w, p.y), 16, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f)
