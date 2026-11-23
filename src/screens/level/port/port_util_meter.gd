class_name PortUtilMeter
extends Control
## Pill with an icon, a bar and "used / capacity" for power or water. Red when full. A pending
## placement can be previewed: `set_preview(extra_used, extra_capacity)` draws a pulsing segment.

const U := preload("res://src/render/art/art_util.gd")

var icon: StringName = &"power"
var bar_color: Color = Palette.MINT
var used: int = 0
var cap: int = 0
var preview_used: int = 0
var preview_cap: int = 0
var _t: float = 0.0
var _shown_used: float = 0.0
var _flash: float = 0.0


func _init(p_icon: StringName = &"power", p_color: Color = Palette.MINT) -> void:
	icon = p_icon
	bar_color = p_color
	custom_minimum_size = Vector2(214, 46)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_values(p_used: int, p_cap: int) -> void:
	if p_used > used and p_used >= p_cap and p_cap > 0:
		_flash = 1.0
	used = p_used
	cap = p_cap
	queue_redraw()


func set_preview(extra_used: int, extra_cap: int) -> void:
	if extra_used == preview_used and extra_cap == preview_cap:
		return
	preview_used = extra_used
	preview_cap = extra_cap
	queue_redraw()


func is_full() -> bool:
	return cap > 0 and used >= cap


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.0)
	var need_redraw: bool = preview_used != 0 or preview_cap != 0 or _flash > 0.0 or absf(_shown_used - float(used)) > 0.01
	_shown_used = lerpf(_shown_used, float(used), 1.0 - exp(-delta * 12.0))
	if absf(_shown_used - float(used)) < 0.02:
		_shown_used = float(used)
	if need_redraw:
		queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	U.rr_border(self, Rect2(0, 0, w, h), h * 0.5, Color(0.12, 0.17, 0.27, 0.78), Color(1, 1, 1, 0.10), 2.0)
	IconArt.draw_icon(self, icon, Vector2(26, h * 0.5), 28.0)
	var total_cap: int = cap + preview_cap
	var total_used: float = _shown_used + float(preview_used)
	var over: bool = total_used > float(total_cap) + 0.01
	var scale_to: float = maxf(maxf(float(total_cap), total_used), 1.0)
	var bx: float = 48.0
	var bw: float = w - bx - 74.0
	var by: float = h * 0.5 - 8.0
	var track := Rect2(bx, by, bw, 16.0)
	U.rr(self, track, 8.0, Color(1, 1, 1, 0.14))
	# capacity tick when the preview adds supply
	var frac: float = clampf(_shown_used / scale_to, 0.0, 1.0)
	var full: bool = cap > 0 and used >= cap
	var col: Color = bar_color
	if full or over:
		col = Palette.CORAL
	elif cap > 0 and float(used) / float(cap) >= 0.85:
		col = Palette.SUN
	if frac > 0.0:
		var fr := Rect2(bx, by, maxf(bw * frac, 14.0), 16.0)
		U.rr(self, fr, 8.0, Palette.shade(col, 0.18))
		U.rr(self, Rect2(fr.position.x, fr.position.y, fr.size.x, 12.0), 7.0, col)
		U.rr(self, Rect2(fr.position.x + 4.0, fr.position.y + 2.0, maxf(fr.size.x - 8.0, 2.0), 3.0), 1.5, Color(1, 1, 1, 0.35))
	if preview_used != 0:
		var f0: float = frac
		var f1: float = clampf(total_used / scale_to, 0.0, 1.0)
		var pa: float = 0.55 + 0.35 * sin(_t * 7.0)
		var pc: Color = Palette.CORAL_LIGHT if over else Color.WHITE
		U.rr(self, Rect2(bx + bw * f0, by, maxf(bw * (f1 - f0), 4.0), 16.0), 7.0, Color(pc.r, pc.g, pc.b, pa))
	if preview_cap != 0:
		var cf: float = clampf(float(cap) / scale_to, 0.0, 1.0)
		U.rr(self, Rect2(bx + bw * cf, by, maxf(bw * (1.0 - cf), 2.0), 16.0), 7.0, Color(Palette.MINT.r, Palette.MINT.g, Palette.MINT.b, 0.35 + 0.25 * sin(_t * 7.0)))
	# label
	var txt: String = "%d/%d" % [int(round(total_used)) if preview_used != 0 else used, total_cap]
	var tcol: Color = Palette.CORAL_LIGHT if (full or over) else Palette.CREAM
	if _flash > 0.0:
		tcol = tcol.lerp(Color.WHITE, _flash)
	U.text(self, txt, Vector2(bx + bw + 8.0, h * 0.5 + 7.0), 20, tcol, HORIZONTAL_ALIGNMENT_LEFT, 66.0, UITheme.font_bold())
