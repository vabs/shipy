class_name MutinyArt
extends Control
## Funny "the guests took over the ship" illustration: a gang of furious beans on the deck, the leader
## wearing the captain's hat, picket signs, steam puffs. Animated. Default size 560x250.

const U := preload("res://src/render/art/art_util.gd")
const PROPS: Array[StringName] = [&"sun_hat", &"headband", &"glasses_3d", &"headphones"]
const ARCH: Array[StringName] = [&"holidaymaker", &"fitness_fan", &"film_buff", &"gamer"]
const SIGNS: Array[String] = ["BOO!", "HUNGRY!", "LOO?!", "NAP!"]

var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(560, 250)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var r := Rect2(0, 0, w, h)
	# stormy sunset sky inside a rounded plate (clip by drawing the sky in rounded slices)
	U.rr(self, r, 22.0, Color("5A4A8C"))
	U.rr(self, Rect2(0, h * 0.28, w, h * 0.72), 22.0, Color("C0587F"))
	U.rr(self, Rect2(0, h * 0.5, w, h * 0.5), 22.0, Color("F08A6C"))
	U.rect(self, Rect2(0, h * 0.5, w, 30.0), Color("F08A6C"))
	# sun peeking, angry-red
	U.circ(self, Vector2(w * 0.78, h * 0.5), 62.0, Color(1.0, 0.82, 0.55, 0.25))
	U.circ(self, Vector2(w * 0.78, h * 0.5), 38.0, Color("FFD18A"))
	# dark clouds
	for i in range(4):
		var cx: float = lerpf(80.0, w - 80.0, 0.5 + 0.5 * sin(_t * 0.12 + float(i) * 1.9))
		var cy: float = 34.0 + float((i * 37) % 40)
		_cloud(Vector2(cx, cy), 0.9 + 0.2 * float(i % 2))
	# far sea
	U.rect(self, Rect2(0, h * 0.62, w, h * 0.38), Color("2B3A6B"))
	for i in range(14):
		var wx: float = float(i) * 46.0 + sin(_t * 0.9 + float(i)) * 6.0
		U.rr(self, Rect2(wx, h * 0.66 + float(i % 3) * 10.0, 30.0, 4.0), 2.0, Color(1, 1, 1, 0.14))
	# deck
	var deck_y: float = h - 54.0
	U.rr(self, Rect2(0, deck_y, w, 54.0), 14.0, Palette.WOOD)
	U.rect(self, Rect2(0, deck_y, w, 14.0), Palette.WOOD)
	U.rect(self, Rect2(0, deck_y, w, 6.0), Palette.WOOD_LIGHT)
	for i in range(1, 9):
		U.rect(self, Rect2(float(i) * w / 9.0, deck_y + 6.0, 3.0, 48.0), Palette.WOOD_DARK)
	# railing posts
	for i in range(9):
		var px: float = 20.0 + float(i) * (w - 40.0) / 8.0
		U.rr(self, Rect2(px - 4.0, deck_y - 38.0, 8.0, 40.0), 3.0, Palette.HULL_WHITE)
	U.rr(self, Rect2(8.0, deck_y - 44.0, w - 16.0, 8.0), 4.0, Palette.HULL_WHITE)
	# flag pole with a coral "mutiny" flag
	var fx: float = w * 0.5
	U.rr(self, Rect2(fx - 3.0, 18.0, 6.0, deck_y - 18.0), 3.0, Palette.WOOD_DARK)
	_flag(Vector2(fx + 3.0, 22.0))
	# the rebels
	var xs: Array[float] = [0.12, 0.27, 0.40, 0.58, 0.73, 0.86]
	var sign_of: Dictionary = {0: "BOO!", 3: "HUNGRY!", 5: "LOO?!"}
	for i in range(xs.size()):
		var leader: bool = i == 2
		var ph: float = float(i) * 1.3
		var hop: float = absf(sin(_t * 5.0 + ph)) * (8.0 if leader else 11.0)
		var feet := Vector2(w * xs[i], deck_y + 36.0 - hop)
		var k: int = i % 4
		var sc: float = 2.9 if leader else 2.3
		var head_y: float = feet.y - GuestArt.HEIGHT * sc
		if sign_of.has(i):
			_sign(Vector2(feet.x, head_y + 12.0), String(sign_of[i]), sin(_t * 4.0 + ph) * 0.12 + (0.1 if i % 2 == 0 else -0.1))
		GuestArt.draw_guest(self, feet, {
			"prop": &"" if leader else PROPS[k], "body_color": Palette.archetype_color(ARCH[k]), "facing": 1 if feet.x < fx else -1,
			"pose": &"storm", "walk_phase": _t * 9.0 + ph, "t": _t, "scale": sc,
		})
		if leader:
			_captain_hat(feet + Vector2(0, -GuestArt.HEIGHT * sc + 4.0), sc)
		if i == 1 or i == 4 or leader:
			IconArt.draw_bubble(self, Vector2(feet.x, head_y - (26.0 if leader else 8.0)), &"angry", fmod(_t * 1.2 + ph, 5.0), 1.0)


func _cloud(c: Vector2, s: float) -> void:
	var col := Color(0.25, 0.2, 0.42, 0.7)
	U.ellipse(self, c, 52.0 * s, 16.0 * s, col)
	U.circ(self, c + Vector2(-20.0, -10.0) * s, 20.0 * s, col)
	U.circ(self, c + Vector2(12.0, -16.0) * s, 24.0 * s, col)


func _flag(p: Vector2) -> void:
	var pts := PackedVector2Array()
	var steps: int = 8
	var fw: float = 96.0
	var fh: float = 56.0
	for i in range(steps + 1):
		var x: float = fw * float(i) / float(steps)
		pts.append(p + Vector2(x, sin(_t * 5.0 - float(i) * 0.7) * 4.0 * (float(i) / float(steps))))
	for i in range(steps, -1, -1):
		var x2: float = fw * float(i) / float(steps)
		pts.append(p + Vector2(x2, fh + sin(_t * 5.0 - float(i) * 0.7) * 4.0 * (float(i) / float(steps))))
	U.poly(self, pts, Palette.CORAL_DARK)
	# bean-skull emblem
	var e := p + Vector2(fw * 0.5, fh * 0.5 + 2.0 + sin(_t * 5.0 - 3.0) * 2.0)
	U.circ(self, e, 15.0, Palette.CREAM)
	U.circ(self, e + Vector2(-5.5, -2.0), 3.2, Palette.INK)
	U.circ(self, e + Vector2(5.5, -2.0), 3.2, Palette.INK)
	U.rr(self, Rect2(e.x - 5.0, e.y + 5.0, 10.0, 3.0), 1.5, Palette.INK)
	U.line(self, e + Vector2(-9.0, -7.0), e + Vector2(-2.0, -4.0), Palette.INK, 2.0)
	U.line(self, e + Vector2(9.0, -7.0), e + Vector2(2.0, -4.0), Palette.INK, 2.0)


func _sign(head: Vector2, text: String, rot: float) -> void:
	var tw: float = U.font_bold().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 24.0
	draw_set_transform(head, rot, Vector2.ONE)
	U.rr(self, Rect2(-3.0, -62.0, 6.0, 70.0), 2.0, Palette.WOOD_DARK)
	U.rr(self, Rect2(-tw * 0.5 + 2.0, -104.0, tw, 42.0), 9.0, Palette.WOOD_DARK)
	U.rr(self, Rect2(-tw * 0.5, -107.0, tw, 42.0), 9.0, Palette.CREAM)
	draw_string(U.font_bold(), Vector2(-tw * 0.5, -76.0), text, HORIZONTAL_ALIGNMENT_CENTER, tw, 24, Palette.CORAL_DARK)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _captain_hat(head: Vector2, sc: float) -> void:
	var hs: float = sc * 0.55
	draw_set_transform(head + Vector2(0, -2.0), sin(_t * 4.0) * 0.08, Vector2(hs, hs))
	# brim
	U.rr(self, Rect2(-16.0, -3.0, 32.0, 7.0), 3.0, Palette.NAVY)
	# crown
	U.rr(self, Rect2(-12.0, -16.0, 24.0, 15.0), 6.0, Palette.NAVY_LIGHT)
	U.rect(self, Rect2(-12.0, -6.0, 24.0, 4.0), Palette.CREAM)
	U.circ(self, Vector2(0, -10.0), 3.4, Palette.SUN)
	draw_set_transform_matrix(Transform2D.IDENTITY)
