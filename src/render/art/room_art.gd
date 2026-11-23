class_name RoomArt
extends RefCounted
## Room interiors (SPEC §6). A room rect is one deck tall (76 px) and width*CELL_W wide, in ship-local px.
## Vertical structure of every room: ceiling beam 5 px, wall, floor band 11 px (guests' feet sit at rect.end.y).
##
## API
##   RoomArt.draw_room(ci, room_id: StringName, rect: Rect2, tier: int, state: Dictionary)
##       (state["pass"] 0|1|2 = all | static-only | dynamic-only is used by ShipView's texture baking; leave it unset)
##   RoomArt.draw_room_front(ci, room_id, rect, tier, state)     # layer drawn ON TOP of guests (water, counters, doors...)
##       state keys (all optional): broken: bool, busy_ratio: float 0..1 (users/capacity; slots 0..n-1 are the
##       occupied ones), repair_progress: float 0..1, t: float seconds, highlight: int (0 none/1 hover/2 selected),
##       invalid: bool (red preview tint), ghost_preview: bool (translucent preview; add invalid for red)
##   RoomArt.slot_position(room_id, rect, slot: int, capacity: int) -> Vector2   # FEET position for a guest in slot n
##   RoomArt.slot_pose(room_id) -> StringName        # stand|sit|swim|lie|run|sleep
##   RoomArt.slot_facing(room_id, rect, slot, capacity) -> int   # -1|1 suggested facing for that slot
##   RoomArt.capacity_for(room_id, tier) -> int      # SPEC capacity table incl. tier bonus (for art-side occupancy)
##   RoomArt.draw_stairs(ci, rect_two_decks: Rect2, t := 0.0)
##   RoomArt.draw_elevator(ci, column_rect: Rect2, car_deck_f: float, decks: int, t := 0.0)
##   RoomArt.default_width(room_id) -> int           # cells (for UI cards)
##   RoomArt.is_open_air(room_id) -> bool            # pool / deck_chairs (no wall, sky behind)
##   RoomArt.FLOOR_H = 11.0, RoomArt.CEIL_H = 5.0

const U := preload("res://src/render/art/art_util.gd")
const I := preload("res://src/render/art/room_interiors.gd")

const FLOOR_H: float = 11.0
const CEIL_H: float = 5.0

const _WIDTHS: Dictionary = {
	&"cabin": 2, &"buffet": 4, &"toilets": 2, &"bar": 3, &"pool": 6, &"deck_chairs": 3, &"cinema": 4,
	&"gym": 3, &"arcade": 3, &"restaurant": 4, &"medbay": 2, &"sauna": 2, &"ice_rink": 5, &"casino": 4,
	&"stairs": 1, &"elevator": 1, &"generator": 1, &"water_tank": 1,
}
const _CAPS: Dictionary = {
	&"cabin": 4, &"buffet": 6, &"toilets": 3, &"bar": 5, &"pool": 8, &"deck_chairs": 4, &"cinema": 8,
	&"gym": 4, &"arcade": 4, &"restaurant": 4, &"medbay": 2, &"sauna": 3, &"ice_rink": 6, &"casino": 6,
}


static func default_width(room_id: StringName) -> int:
	return _WIDTHS.get(room_id, 2)


static func is_open_air(room_id: StringName) -> bool:
	return room_id == &"pool" or room_id == &"deck_chairs"


static func capacity_for(room_id: StringName, tier: int) -> int:
	var base: int = _CAPS.get(room_id, 0)
	if base == 0:
		return 0
	if room_id == &"cabin":
		return base + 2 * (tier - 1)
	if room_id == &"medbay":
		return base
	return base + (tier - 1) * int(ceil(float(base) * 0.5))


# =================================================================================================
# main entry points
# =================================================================================================
static func draw_room(ci: CanvasItem, room_id: StringName, rect: Rect2, tier: int, state: Dictionary) -> void:
	U.set_pass(int(state.get("pass", 0)))
	_draw_room_inner(ci, room_id, rect, tier, state)
	U.set_pass(0)


static func _draw_room_inner(ci: CanvasItem, room_id: StringName, rect: Rect2, tier: int, state: Dictionary) -> void:
	if room_id == &"stairs":
		_wrap_begin(state)
		draw_stairs(ci, rect, state.get("t", 0.0))
		_wrap_end(ci, rect, state, 6.0)
		return
	if room_id == &"elevator":
		_wrap_begin(state)
		draw_elevator(ci, rect, state.get("car_deck_f", 0.0), maxi(1, int(round(rect.size.y / 76.0))), state.get("t", 0.0))
		_wrap_end(ci, rect, state, 6.0)
		return
	var old_alpha := U.alpha
	_wrap_begin(state)
	var pal: Dictionary = Palette.ROOM_COLORS.get(room_id, {"wall": Palette.CREAM, "accent": Palette.TEAL})
	var wall: Color = pal["wall"]
	var open := is_open_air(room_id)
	if open:
		_open_floor(ci, room_id, rect)
	else:
		_shell(ci, room_id, rect, wall)
		if room_id != &"generator" and room_id != &"water_tank":
			_door(ci, room_id, rect, wall, tier, state)
	I.back(ci, room_id, rect, tier, state)
	_sign(ci, room_id, rect, tier, state)
	if state.get("broken", false):
		_broken_overlay(ci, rect, state, open)
	_wrap_end(ci, rect, state, 8.0)
	U.alpha = old_alpha


static func draw_room_front(ci: CanvasItem, room_id: StringName, rect: Rect2, tier: int, state: Dictionary) -> void:
	U.set_pass(int(state.get("pass", 0)))
	_draw_front_inner(ci, room_id, rect, tier, state)
	U.set_pass(0)


static func _draw_front_inner(ci: CanvasItem, room_id: StringName, rect: Rect2, tier: int, state: Dictionary) -> void:
	if room_id == &"stairs" or room_id == &"elevator" or room_id == &"generator" or room_id == &"water_tank":
		return
	var old_alpha := U.alpha
	_wrap_begin(state)
	I.front(ci, room_id, rect, tier, state)
	if state.get("broken", false):
		I.broken_front_dim(ci, room_id, rect)
	U.alpha = old_alpha


# =================================================================================================
# slots
# =================================================================================================
static func slot_pose(room_id: StringName) -> StringName:
	match room_id:
		&"cabin": return &"sleep"
		&"bar", &"cinema", &"restaurant", &"sauna": return &"sit"
		&"pool": return &"swim"
		&"deck_chairs", &"medbay": return &"lie"
		&"gym": return &"run"
	return &"stand"


static func slot_position(room_id: StringName, rect: Rect2, slot: int, capacity: int) -> Vector2:
	return I.slot_pos(room_id, rect, slot, maxi(capacity, 1))


static func slot_facing(room_id: StringName, rect: Rect2, slot: int, capacity: int) -> int:
	match room_id:
		&"cinema": return -1
		&"gym", &"cabin", &"medbay", &"deck_chairs": return 1
		&"restaurant":
			var k := slot % 4
			return 1 if k % 2 == 0 else -1
	return 1 if slot % 2 == 0 else -1


# =================================================================================================
# shared shell
# =================================================================================================
static func _wrap_begin(state: Dictionary) -> void:
	if state.get("ghost_preview", false):
		U.alpha *= 0.62


static func _wrap_end(ci: CanvasItem, rect: Rect2, state: Dictionary, rad: float) -> void:
	U.dyn_begin()
	_wrap_end_dyn(ci, rect, state, rad)
	U.dyn_end()


static func _wrap_end_dyn(ci: CanvasItem, rect: Rect2, state: Dictionary, rad: float) -> void:
	var t: float = state.get("t", 0.0)
	var hl: int = state.get("highlight", 0)
	if state.get("invalid", false):
		U.rr(ci, rect, rad, Color(0.95, 0.2, 0.25, 0.38))
		U.rr_outline(ci, rect.grow(-1.0), rad, Color(1.0, 0.3, 0.3, 0.95), 3.0)
	elif state.get("ghost_preview", false):
		var p := 0.55 + 0.35 * sin(t * 5.0)
		U.alpha = 1.0
		U.rr_outline(ci, rect.grow(-1.0), rad, Color(0.45, 0.95, 0.6, p), 3.0)
	if hl == 1:
		U.rr(ci, rect, rad, Color(1, 1, 1, 0.12))
		U.rr_outline(ci, rect.grow(-1.0), rad, Color(1, 1, 1, 0.9), 2.0)
	elif hl >= 2:
		var gp := 0.6 + 0.4 * sin(t * 4.0)
		U.rr(ci, rect, rad, Color(1.0, 0.85, 0.3, 0.1 + 0.06 * gp))
		U.rr_outline(ci, rect.grow(-1.5), rad, Color(Palette.SUN.r, Palette.SUN.g, Palette.SUN.b, 0.7 + 0.3 * gp), 3.0)
		# corner ticks
		var c := Palette.SUN
		var l := 9.0
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			var sx := 1.0 if corner.x <= rect.position.x + 1.0 else -1.0
			var sy := 1.0 if corner.y <= rect.position.y + 1.0 else -1.0
			U.pline(ci, PackedVector2Array([corner + Vector2(sx * l, sy * 1.0), corner + Vector2(sx * 1.0, sy * 1.0), corner + Vector2(sx * 1.0, sy * l)]), c, 3.0)


static func _open_floor(ci: CanvasItem, room_id: StringName, R: Rect2) -> void:
	var fy := R.end.y - FLOOR_H
	var w := R.size.x
	var x0 := R.position.x
	U.rect(ci, Rect2(x0, fy, w, 7.0), Color("E3B987"))
	U.rect(ci, Rect2(x0, fy + 7.0, w, 4.0), Color("B98F63"))
	var seam := Color(0.55, 0.38, 0.2, 0.25)
	var n := int(w / 20.0)
	for i in range(1, n + 1):
		U.rect(ci, Rect2(x0 + i * 20.0 - 0.5, fy, 1.0, 7.0), seam)
	U.rect(ci, Rect2(x0, fy, w, 1.2), Color(1, 1, 1, 0.3))


static func _shell(ci: CanvasItem, room_id: StringName, R: Rect2, wall: Color) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var w := R.size.x
	var fy := R.end.y - FLOOR_H
	var dark := room_id == &"bar" or room_id == &"cinema" or room_id == &"arcade" or room_id == &"casino"
	# wall
	U.vgrad(ci, Rect2(x0, y0 + CEIL_H, w, fy - y0 - CEIL_H), Palette.tint(wall, 0.1) if not dark else Palette.tint(wall, 0.05), Palette.shade(wall, 0.06))
	# wainscot
	U.rect(ci, Rect2(x0, fy - 12.0, w, 12.0), Palette.shade(wall, 0.12))
	U.rect(ci, Rect2(x0, fy - 13.0, w, 1.5), Palette.tint(wall, 0.4))
	# ceiling beam + soft shadow under it
	U.rect(ci, Rect2(x0, y0, w, CEIL_H), Palette.CEILING_TRIM)
	U.rect(ci, Rect2(x0, y0 + CEIL_H - 1.0, w, 1.0), Color(1, 1, 1, 0.12))
	U.vgrad(ci, Rect2(x0, y0 + CEIL_H, w, 7.0), Color(0.1, 0.15, 0.3, 0.2), Color(0.1, 0.15, 0.3, 0.0))
	# floor
	var fl: Color = Palette.FLOOR_TOP
	var ff: Color = Palette.FLOOR_FRONT
	if room_id == &"ice_rink":
		fl = Color("CFEFFF")
		ff = Color("8EC9E8")
	elif room_id == &"toilets" or room_id == &"medbay":
		fl = Color("CBE6E8")
		ff = Color("9CC7CC")
	elif room_id == &"cinema" or room_id == &"casino" or room_id == &"arcade":
		fl = Color("5B3F86") if room_id != &"arcade" else Color("463B8A")
		ff = Color("3F2B66") if room_id != &"arcade" else Color("322A66")
	elif room_id == &"sauna":
		fl = Color("C98B54")
		ff = Color("9C6A3C")
	elif room_id == &"bar":
		fl = Color("8A5A3C")
		ff = Color("66402A")
	U.rect(ci, Rect2(x0, fy, w, 7.0), fl)
	U.rect(ci, Rect2(x0, fy + 7.0, w, FLOOR_H - 7.0), ff)
	U.rect(ci, Rect2(x0, fy, w, 1.2), Color(1, 1, 1, 0.28))
	var seam := Color(0.2, 0.15, 0.3, 0.16)
	var n := int(w / 20.0)
	for i in range(1, n + 1):
		U.rect(ci, Rect2(x0 + i * 20.0 - 0.5, fy, 1.0, 7.0), seam)
	# side shading + separators
	U.hgrad(ci, Rect2(x0, y0 + CEIL_H, 6.0, fy - y0 - CEIL_H), Color(0.1, 0.15, 0.3, 0.16), Color(0.1, 0.15, 0.3, 0.0))
	U.hgrad(ci, Rect2(x0 + w - 6.0, y0 + CEIL_H, 6.0, fy - y0 - CEIL_H), Color(0.1, 0.15, 0.3, 0.0), Color(0.1, 0.15, 0.3, 0.16))
	U.rect(ci, Rect2(x0, y0 + CEIL_H, 1.0, R.size.y - CEIL_H), Color(0.1, 0.15, 0.3, 0.22))
	U.rect(ci, Rect2(x0 + w - 1.0, y0 + CEIL_H, 1.0, R.size.y - CEIL_H), Color(0.1, 0.15, 0.3, 0.22))


static func _door(ci: CanvasItem, room_id: StringName, R: Rect2, wall: Color, tier: int, state: Dictionary) -> void:
	var cx := R.position.x + R.size.x * 0.5
	var fy := R.end.y - FLOOR_H
	var dark := room_id == &"bar" or room_id == &"cinema" or room_id == &"arcade" or room_id == &"casino" or room_id == &"sauna"
	var frame: Color = Palette.WOOD_DARK if not dark else Color("2B2347")
	var dc: Color = Palette.WOOD if not dark else Color("4A3D75")
	if tier >= 3:
		frame = Palette.SUN_DEEP
	var dr := Rect2(cx - 8.5, fy - 31.0, 17.0, 31.0)
	U.rr_ex(ci, dr, 8.0, 8.0, 0.0, 0.0, frame)
	var inner := Rect2(cx - 6.5, fy - 29.0, 13.0, 29.0)
	U.rr_ex(ci, inner, 6.0, 6.0, 0.0, 0.0, dc)
	U.rr_ex(ci, Rect2(inner.position.x, inner.position.y, 5.0, inner.size.y), 5.0, 0.0, 0.0, 0.0, Color(1, 1, 1, 0.1))
	U.circ(ci, Vector2(cx + 3.2, fy - 13.0), 1.2, Palette.GOLD)
	U.rr(ci, Rect2(cx - 3.0, fy - 24.0, 6.0, 7.0), 2.5, Color(0.6, 0.85, 1.0, 0.55) if not dark else Color(0.7, 0.6, 1.0, 0.35))


static func _sign(ci: CanvasItem, room_id: StringName, R: Rect2, tier: int, state: Dictionary) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var cx := x0 + R.size.x * 0.5
	var open := is_open_air(room_id)
	var no_door := room_id == &"generator" or room_id == &"water_tank"
	var sy := y0 + 9.0
	if open:
		# little pole + hanging banner
		U.rr(ci, Rect2(cx - 1.2, y0 + 4.0, 2.4, 26.0), 1.0, Palette.STEEL)
		sy = y0 + 6.0
		U.line(ci, Vector2(cx - 12, y0 + 5.0), Vector2(cx + 12, y0 + 5.0), Palette.STEEL, 2.0)
	var narrow := R.size.x < 100.0
	var sw := 29.0 if narrow else 34.0
	var sh := 19.0 if narrow else 22.0
	var rc := Rect2(cx - sw * 0.5, sy, sw, sh)
	# chains
	U.line(ci, Vector2(cx - 10, y0 + (3.0 if open else CEIL_H)), Vector2(cx - 10, sy + 1), Color(0.75, 0.78, 0.85, 0.9), 1.0)
	U.line(ci, Vector2(cx + 10, y0 + (3.0 if open else CEIL_H)), Vector2(cx + 10, sy + 1), Color(0.75, 0.78, 0.85, 0.9), 1.0)
	U.rr(ci, Rect2(rc.position.x, rc.position.y + 2.0, sw, sh), 7.0, Color(0.1, 0.15, 0.3, 0.2))
	var frame_c: Color = Palette.NAVY if tier <= 1 else (Color("8FA3C0") if tier == 2 else Color("E9B53F"))
	U.rr(ci, rc, 7.0, frame_c)
	U.rr(ci, rc.grow(-1.8), 5.5, Palette.CREAM)
	IconArt.draw_room_icon(ci, room_id, Vector2(rc.position.x + (9.5 if narrow else 11.0), rc.position.y + sh * 0.5), 12.5 if narrow else 14.5)
	# tier stars stacked on the right
	var sp := 4.6 if narrow else 5.4
	for i in range(3):
		var on := i < tier
		var c := Palette.SUN if on else Color(0.8, 0.74, 0.62, 0.6)
		U.star(ci, Vector2(rc.end.x - (6.8 if narrow else 8.0), rc.position.y + sh * 0.5 + (float(i) - 1.0) * sp), 2.4 if narrow else 2.6, c)
	# status lamp + repair bar are dynamic
	U.dyn_begin()
	var lamp_c := Palette.MINT
	if state.get("broken", false):
		var t: float = state.get("t", 0.0)
		lamp_c = Palette.CORAL if sin(t * 8.0) > 0.0 else Palette.CORAL_DARK
	elif float(state.get("busy_ratio", 0.0)) > 0.01 and not no_door:
		lamp_c = Palette.SUN
	U.circ(ci, Vector2(rc.end.x - 1.0, rc.position.y + 1.0), 3.0, Palette.NAVY)
	U.circ(ci, Vector2(rc.end.x - 1.0, rc.position.y + 1.0), 2.1, lamp_c)
	# repair progress under the sign
	var rp: float = state.get("repair_progress", 0.0)
	if rp > 0.001 and state.get("broken", false):
		var bar := Rect2(cx - 15.0, rc.end.y + 4.0, 30.0, 6.0)
		U.rr(ci, bar.grow(1.5), 4.0, Palette.NAVY)
		U.rr(ci, bar, 3.0, Color(0.2, 0.25, 0.4))
		U.rr(ci, Rect2(bar.position, Vector2(maxf(5.0, bar.size.x * rp), bar.size.y)), 3.0, Palette.MINT)
		IconArt.draw_icon(ci, &"wrench", Vector2(cx, rc.end.y + 18.0), 13.0, 0.0)
	U.dyn_end()


static func _broken_overlay(ci: CanvasItem, R: Rect2, state: Dictionary, open: bool) -> void:
	var t: float = state.get("t", 0.0)
	# darken
	U.rr(ci, R, 3.0, Color(0.1, 0.12, 0.25, 0.46))
	# hazard stripes along the floor
	var y := R.end.y - 9.0
	var stripe_w := 8.0
	var n := int(R.size.x / stripe_w) + 1
	for i in range(n):
		var x := R.position.x + float(i) * stripe_w
		var wdt := minf(stripe_w, R.end.x - x)
		if wdt <= 0.0:
			break
		if i % 2 == 0:
			U.poly(ci, PackedVector2Array([Vector2(x, y + 7.0), Vector2(x + wdt * 0.5, y), Vector2(x + wdt, y), Vector2(x + wdt * 0.5, y + 7.0)]), Palette.SUN)
		else:
			pass
	U.rect(ci, Rect2(R.position.x, y - 1.0, R.size.x, 1.0), Color(0, 0, 0, 0.25))
	# sparks + smoke + warning pulse are dynamic
	U.dyn_begin()
	var cx := R.position.x + R.size.x * 0.5
	var base := Vector2(R.position.x + R.size.x * 0.28, R.position.y + 36.0)
	var base2 := Vector2(R.position.x + R.size.x * 0.74, R.position.y + 44.0)
	for pass_i in range(2):
		var b := base if pass_i == 0 else base2
		for i in range(3):
			var k := fmod(t * 0.8 + float(i) / 3.0 + float(pass_i) * 0.37, 1.0)
			var p := b + Vector2(sin(k * 7.0 + float(i) * 2.0) * 4.0, -k * 26.0)
			var r := 3.0 + k * 6.0
			U.circ(ci, p, r, Color(0.2, 0.22, 0.3, 0.55 * (1.0 - k)))
			U.circ(ci, p + Vector2(-1.0, -1.0), r * 0.6, Color(0.35, 0.37, 0.47, 0.4 * (1.0 - k)))
	# sparks: flickering zig-zags
	var spark_t := fmod(t * 6.0, 3.0)
	for i in range(3):
		var on := fmod(t * 5.0 + float(i) * 0.7, 1.0) < 0.35
		if not on:
			continue
		var sp := Vector2(R.position.x + R.size.x * (0.2 + 0.3 * float(i)) + sin(t * 3.0 + float(i)) * 6.0, R.position.y + 30.0 + 10.0 * float(i % 2))
		var d := Vector2(cos(float(i) * 2.1 + t), sin(float(i) * 2.1 + t)) * 4.0
		U.pline(ci, PackedVector2Array([sp, sp + Vector2(d.x, -4.0), sp + Vector2(-d.y, -1.0), sp + Vector2(d.x * 1.5, -8.0)]), Palette.SUN, 1.6)
		U.circ(ci, sp, 1.6, Color(1, 1, 0.8))
	# little warning triangle
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	IconArt.draw_icon(ci, &"warning", Vector2(R.position.x + 12.0, R.position.y + 20.0), 12.0 + pulse * 1.5)
	U.dyn_end()


# =================================================================================================
# stairs & elevator
# =================================================================================================
static func draw_stairs(ci: CanvasItem, R: Rect2, t: float = 0.0) -> void:
	var x0 := R.position.x
	var w := R.size.x
	var dh := 76.0
	var top_deck := Rect2(x0, R.position.y, w, dh)
	var bot_deck := Rect2(x0, R.position.y + dh, w, dh)
	var wall := Color("E9DFCB")
	_shell(ci, &"stairs", top_deck, wall)
	_shell(ci, &"stairs", bot_deck, wall)
	var sl := R.end.y - 6.0          # lower walking surface
	var su := sl - dh                # upper walking surface
	var mid := (sl + su) * 0.5
	var xl := x0 + 2.0
	var xr := x0 + w - 2.0
	var n := 6
	# stairwell opening in the upper floor: shadowed well + railing
	U.rect(ci, Rect2(x0 + 11.0, su - 4.0, w - 11.0, 11.0), Color(0.15, 0.12, 0.3, 0.55))
	# flight B (back, open steps): from the right landing (xr, mid) up to the left (xl + 9, su)
	var bx0 := xr - 5.0
	var bx1 := xl + 9.0
	var brun := (bx0 - bx1) / float(n)
	var brise := (mid - su) / float(n)
	for i in range(n):
		var sx := bx0 - float(i + 1) * brun
		var sy := mid - float(i + 1) * brise
		U.rect(ci, Rect2(sx, sy, brun + 0.6, 2.2), Color("D9B684"))
		U.rect(ci, Rect2(sx, sy + 2.2, brun + 0.6, brise - 2.2), Color("A9825A"))
	U.line(ci, Vector2(bx0 + 1.0, mid - 1.0), Vector2(bx1 - 1.0, su - 1.0), Color(0.45, 0.3, 0.2, 0.6), 1.4)
	# flight A (front, solid wedge): from (xl, sl) up to the right landing (xr - 6, mid)
	var ax1 := xr - 7.0
	var arun := (ax1 - xl) / float(n)
	var arise := (sl - mid) / float(n)
	for i in range(n):
		var sx := xl + float(i) * arun
		var sy := sl - float(i + 1) * arise
		U.rect(ci, Rect2(sx, sy, arun + 0.6, sl - sy + 2.0), Color("C99A63"))
		U.rect(ci, Rect2(sx, sy, arun + 0.6, 2.4), Color("F3D9AE"))
		U.rect(ci, Rect2(sx, sy + 2.4, arun + 0.6, 1.0), Color(0, 0, 0, 0.1))
	U.poly(ci, PackedVector2Array([Vector2(xl, sl + 1.0), Vector2(ax1, mid + 1.0), Vector2(ax1, sl + 1.0)]), Color(0.2, 0.15, 0.3, 0.14))
	# landing at the right
	U.rr(ci, Rect2(ax1 - 1.0, mid - 1.0, xr - ax1 + 1.0, 4.0), 1.5, Palette.WOOD_DARK)
	U.rect(ci, Rect2(xr - 2.0, mid + 3.0, 2.0, sl - mid - 3.0), Color(0.55, 0.4, 0.25, 0.55))
	# handrails (chrome)
	var rc := Palette.STEEL
	var rd := Palette.STEEL_DARK
	U.line(ci, Vector2(xl + 2.0, sl - 19.0), Vector2(ax1, mid - 19.0), rd, 2.4)
	U.line(ci, Vector2(xl + 2.0, sl - 19.6), Vector2(ax1, mid - 19.6), rc, 1.3)
	for i in range(3):
		var f := float(i) / 2.0
		var px := lerpf(xl + 2.0, ax1, f)
		var py := lerpf(sl - 19.0, mid - 19.0, f)
		U.rect(ci, Rect2(px - 0.6, py, 1.4, 19.0 - float(i) * 0.0 - (sl - mid) * f), Color(0.62, 0.68, 0.78, 0.9))
	# upper opening railing
	U.line(ci, Vector2(x0 + 11.0, su - 20.0), Vector2(x0 + w - 1.0, su - 20.0), rd, 2.4)
	U.line(ci, Vector2(x0 + 11.0, su - 20.6), Vector2(x0 + w - 1.0, su - 20.6), rc, 1.3)
	for i in range(4):
		U.rect(ci, Rect2(x0 + 12.0 + float(i) * (w - 14.0) / 3.0, su - 20.0, 1.5, 20.0), Color(0.62, 0.68, 0.78, 0.9))
	# sign (stairs icon on a hanging plate)
	var cx := x0 + w * 0.5
	U.line(ci, Vector2(cx - 6.0, R.position.y + CEIL_H), Vector2(cx - 6.0, R.position.y + 10.0), Color(0.75, 0.78, 0.85, 0.9), 1.0)
	U.line(ci, Vector2(cx + 6.0, R.position.y + CEIL_H), Vector2(cx + 6.0, R.position.y + 10.0), Color(0.75, 0.78, 0.85, 0.9), 1.0)
	U.rr(ci, Rect2(cx - 11.0, R.position.y + 9.0, 22.0, 16.0), 6.0, Palette.NAVY)
	U.rr(ci, Rect2(cx - 9.6, R.position.y + 10.4, 19.2, 13.2), 5.0, Palette.CREAM)
	IconArt.draw_room_icon(ci, &"stairs", Vector2(cx, R.position.y + 17.0), 12.0)


static func draw_elevator(ci: CanvasItem, R: Rect2, car_deck_f: float, decks: int, t: float = 0.0) -> void:
	var x0 := R.position.x
	var w := R.size.x
	var dh := 76.0
	var steel := Color("DCE4EE")
	# shaft
	U.vgrad(ci, R, Color("C9D4E3"), Color("AEBBD0"))
	U.rect(ci, Rect2(x0, R.position.y, 1.0, R.size.y), Color(0.1, 0.15, 0.3, 0.25))
	U.rect(ci, Rect2(x0 + w - 1.0, R.position.y, 1.0, R.size.y), Color(0.1, 0.15, 0.3, 0.25))
	# guide rails
	U.rect(ci, Rect2(x0 + 3.0, R.position.y, 2.0, R.size.y), Color("8E9CB4"))
	U.rect(ci, Rect2(x0 + w - 5.0, R.position.y, 2.0, R.size.y), Color("8E9CB4"))
	# per-deck landing: ceiling beam, floor band, door frame + call lights
	for d in range(decks):
		var fy_bottom := R.end.y - float(d) * dh
		var top := fy_bottom - dh
		U.rect(ci, Rect2(x0, top, w, CEIL_H), Palette.CEILING_TRIM)
		U.rect(ci, Rect2(x0, fy_bottom - FLOOR_H, w, 7.0), Palette.FLOOR_TOP)
		U.rect(ci, Rect2(x0, fy_bottom - FLOOR_H + 7.0, w, FLOOR_H - 7.0), Palette.FLOOR_FRONT)
		# landing door frame (little dark door with arrow lamp)
		var door := Rect2(x0 + 8.0, fy_bottom - FLOOR_H - 30.0, w - 16.0, 30.0)
		U.rr_ex(ci, door, 4.0, 4.0, 0.0, 0.0, Color("6F7E96"))
		U.rr_ex(ci, door.grow(-1.8), 3.0, 3.0, 0.0, 0.0, Color("E7EEF7"))
		U.rect(ci, Rect2(door.position.x + door.size.x * 0.5 - 0.6, door.position.y + 2.0, 1.2, door.size.y - 2.0), Color("A7B5C9"))
		U.circ(ci, Vector2(x0 + w * 0.5, door.position.y - 4.5), 2.2, Color("6F7E96"))
		U.dyn_begin()
		if absf(car_deck_f - float(d)) < 0.08:
			U.circ(ci, Vector2(x0 + w * 0.5, door.position.y - 4.5), 2.2, Palette.MINT)
		U.dyn_end()
	# car (dynamic)
	U.dyn_begin()
	var car_floor := R.end.y - car_deck_f * dh - FLOOR_H + 2.0
	var car := Rect2(x0 + 6.0, car_floor - 40.0, w - 12.0, 40.0)
	U.rr(ci, car.grow(1.8), 6.0, Color(0.1, 0.15, 0.3, 0.3))
	U.rr(ci, car, 5.0, Palette.TEAL_DARK)
	U.rr(ci, car.grow(-2.2), 4.0, Color("FFF2CF"))
	U.rr(ci, Rect2(car.position.x + 3.0, car.position.y + 4.0, car.size.x - 6.0, 6.0), 3.0, Color(1, 1, 1, 0.55))
	U.rect(ci, Rect2(car.position.x + car.size.x * 0.5 - 0.5, car.position.y + 8.0, 1.0, car.size.y - 8.0), Color(0.7, 0.55, 0.3, 0.5))
	U.rr(ci, Rect2(car.position.x + 2.0, car.end.y - 7.0, car.size.x - 4.0, 2.5), 1.0, Palette.WOOD)
	# cable
	U.line(ci, Vector2(x0 + w * 0.5, R.position.y), Vector2(x0 + w * 0.5, car.position.y - 1.0), Palette.STEEL_DARK, 1.6)
	U.circ(ci, Vector2(x0 + w * 0.5, car.position.y - 1.0), 2.0, Palette.STEEL_DARK)
	U.dyn_end()
	# sign at the top
	var cx := x0 + w * 0.5
	U.rr(ci, Rect2(cx - 11.0, R.position.y + 9.0, 22.0, 16.0), 6.0, Palette.NAVY)
	U.rr(ci, Rect2(cx - 9.6, R.position.y + 10.4, 19.2, 13.2), 5.0, Palette.CREAM)
	IconArt.draw_room_icon(ci, &"elevator", Vector2(cx, R.position.y + 17.0), 12.0)
