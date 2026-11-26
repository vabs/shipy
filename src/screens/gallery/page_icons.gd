extends Node2D
## Gallery page: all icons at several sizes, colourblind variants, room badges, bubbles.

const U := preload("res://src/render/art/art_util.gd")
var _t: float = 0.0
var _dest: StringName = &"med"


func setup(dest: StringName) -> void:
	_dest = dest


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var d := Palette.dest(_dest)
	U.vgrad(self, Rect2(0, 0, 1920, 1080), d["sky_top"], d["sky_bottom"])
	# left cream card (light bg), right navy card (dark bg)
	U.rr(self, Rect2(30, 30, 1000, 1020), 24, Palette.CREAM)
	U.rr(self, Rect2(1050, 30, 840, 1020), 24, Palette.NAVY)
	var f := U.font_bold()
	var icons := IconArt.ICONS
	for i in range(icons.size()):
		var col := i % 6
		var row := i / 6
		var c := Vector2(100 + col * 160, 110 + row * 130)
		IconArt.draw_icon(self, icons[i], c, 72.0, _t)
		IconArt.draw_icon(self, icons[i], c + Vector2(60, 24), 24.0, _t)
		IconArt.draw_icon(self, icons[i], c + Vector2(60, -16), 16.0, _t)
		U.text(self, String(icons[i]), c + Vector2(-48, 62), 16, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	# colorblind row
	U.text(self, "colourblind", Vector2(60, 700), 20, Palette.INK)
	var probs: Array[StringName] = [&"mess", &"breakdown", &"sick", &"angry", &"ghost"]
	for i in range(probs.size()):
		IconArt.draw_icon(self, probs[i], Vector2(110 + i * 150, 760), 72.0, _t, true)
		IconArt.draw_icon(self, probs[i], Vector2(110 + i * 150, 860), 32.0, _t, true)
	# room icons
	var rooms := IconArt.ROOM_ICONS
	for i in range(rooms.size()):
		var col := i % 9
		var row := i / 9
		var c := Vector2(1100 + col * 90, 100 + row * 110)
		IconArt.draw_room_icon(self, rooms[i], c, 64.0)
		IconArt.draw_room_icon(self, rooms[i], c + Vector2(0, 46), 20.0)
	# icons on dark
	for i in range(icons.size()):
		var col := i % 10
		var row := i / 10
		IconArt.draw_icon(self, icons[i], Vector2(1100 + col * 80, 420 + row * 80), 48.0, _t)
	# bubbles
	var bubbles: Array[StringName] = [&"heart", &"smile", &"meh", &"frown", &"angry", &"need_hunger", &"need_rest", &"sick", &"need_fun", &"need_hygiene"]
	for i in range(bubbles.size()):
		var tt := fmod(_t + i * 0.3, 3.0)
		IconArt.draw_bubble(self, Vector2(1100 + i * 75, 760), bubbles[i], tt, 1.0)
		GuestArt.draw_guest(self, Vector2(1100 + i * 75, 800), {"body_color": Palette.SUN, "pose": &"stand", "t": _t})
	# Shipyard perk badges + v2 UI glyphs (PerkArt)
	var perk_ids := PerkArt.IDS
	for i in range(perk_ids.size()):
		PerkArt.draw_badge(self, perk_ids[i], Vector2(1110 + i * 100, 930), 76.0, _t)
		U.text(self, String(perk_ids[i]), Vector2(1060 + i * 100, 995), 14, Palette.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 100.0, f)
