class_name OvUtil
extends RefCounted
## Small shared helpers for menus / overlays (focus rings, number formatting, backdrops).
##
##   OvUtil.focusable(control, ring := SUN, radius := 14) -> Control   # keyboard/controller focus + visible ring
##   OvUtil.focus_box(ring, radius) -> StyleBoxFlat
##   OvUtil.money(n) "$1,240"   money_signed(n) "+$1,240" / "-$320"   time_text(sec) "3:20"
##   OvUtil.make_backdrop(alpha) -> ColorRect   (mouse-blocking dim layer)
##   OvUtil.pop_in(node, delay, dur)  /  OvUtil.fade_in(node, delay, dur)

const BACKDROP: Color = Color(0.08, 0.11, 0.2, 1.0)


static func focus_box(ring: Color = Palette.SUN, radius: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.draw_center = false
	sb.set_border_width_all(4)
	sb.border_color = ring
	sb.set_corner_radius_all(radius + 4)
	sb.corner_detail = 10
	sb.anti_aliasing = true
	sb.set_expand_margin_all(3.0)
	return sb


## Makes a control reachable by keyboard / controller and gives it a clear focus ring. Buttons also get the
## hover lift on focus.
static func focusable(c: Control, ring: Color = Palette.SUN, radius: int = 14) -> Control:
	c.focus_mode = Control.FOCUS_ALL
	c.add_theme_stylebox_override("focus", focus_box(ring, radius))
	if c is Button:
		var b: Button = c as Button
		b.focus_entered.connect(func() -> void: UIKit._scale_to(b, 1.05, 0.12))
		b.focus_exited.connect(func() -> void: UIKit._scale_to(b, 1.0, 0.14))
	return c


## Dev aid: `--save=/abs/file.json` points SaveManager at a scratch save so screenshots are deterministic
## (the player's real save is never touched). Called from the menu / map / settings screens' setup().
static func dev_save(params: Dictionary) -> void:
	if params.has("save"):
		SaveManager.save_path = String(params["save"])
		SaveManager.load_save()


static func money(n: int) -> String:
	var s: String = _grouped(absi(n))
	return ("-$" if n < 0 else "$") + s


static func money_signed(n: int) -> String:
	if n == 0:
		return "$0"
	return ("+$" if n > 0 else "-$") + _grouped(absi(n))


static func _grouped(n: int) -> String:
	var raw: String = str(n)
	var out: String = ""
	var cnt: int = 0
	for i in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return out


static func time_text(seconds: float) -> String:
	var s: int = int(round(seconds))
	return "%d:%02d" % [s / 60, s % 60]


static func make_backdrop(alpha: float = 0.6) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(BACKDROP.r, BACKDROP.g, BACKDROP.b, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## Scale-pop + fade-in (needs the node inside the tree).
static func pop_in(node: Control, delay: float = 0.0, dur: float = 0.34) -> void:
	if not node.is_inside_tree():
		node.ready.connect(func() -> void: pop_in(node, delay, dur), CONNECT_ONE_SHOT)
		return
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(0.7, 0.7)
	node.modulate.a = 0.0
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "scale", Vector2.ONE, dur).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, dur * 0.6).set_delay(delay)


static func fade_in(node: CanvasItem, delay: float = 0.0, dur: float = 0.3) -> void:
	if not node.is_inside_tree():
		node.ready.connect(func() -> void: fade_in(node, delay, dur), CONNECT_ONE_SHOT)
		return
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", 1.0, dur).set_delay(delay)


static func set_font_px(c: Control, px: int) -> void:
	c.add_theme_font_size_override("font_size", px)
