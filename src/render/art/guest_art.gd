class_name GuestArt
extends RefCounted
## Bean guests and crew, drawn in pixel space (guest ~14x22 px at zoom 1, feet at `feet`).
##
## API
##   GuestArt.draw_guest(ci, feet: Vector2, o: Dictionary)
##     o keys (all optional): prop (sun_hat|headband|glasses_3d|headphones|""), body_color: Color,
##       facing (-1|1), walk_phase (radians, one stride = TAU), pose (stand|walk|queue|sit|swim|lie|sleep|run|
##       slip|storm), sick: bool, seasick: bool (storm: pale seafoam bean, spiral eyes, puffed cheeks, slow sway; not the green food-sick look),
##       t: float (seconds, animation clock), highlight (0|1 hover|2 selected),
##       scale: float, slip_t: float (seconds since slip began; if absent the slip loops from `t`),
##       alpha: float (0..1 fade), body_scale: float (kids 0.75, multiplies `scale`),
##       vip: critic|celebrity|inspector (gold outline + floating star + the kind's accessory: beret + notepad,
##       sunglasses + sparkles, peaked cap + clipboard; pass the matching `prop` beret|sunglasses|inspector_cap),
##       group_color: Color (a matching little heart pin for couples / families)
##     prop ids also include propeller (the kids' beanie, its blades spin) and the three VIP accessories above.
##   GuestArt.draw_staff(ci, feet: Vector2, o: Dictionary)
##     o keys: role (janitor|mechanic|medic|entertainer|chef|warden), facing, walk_phase,
##       pose (stand|walk|work|run|perform|cook|sleep), tired: bool (droopy eyes + sweat drop), t, highlight, scale, alpha
##   GuestArt.staff_top(role) -> float   (px above the feet: where a bubble for that role should sit)
##   GuestArt.HEIGHT: float = 22.0  (px, for placing bubbles: anchor = feet + Vector2(0, -HEIGHT - 4))
## Perf note: the bean body (capsule, arms, face, prop) is baked once per look into a mipmapped sprite (ArtBake)
## and drawn as ONE textured quad (~5 draw commands per guest incl. shadow + feet). Until a sprite is baked
## (first frames) the vector parts are drawn instead. draw_guest sets ci.texture_filter to LINEAR_WITH_MIPMAPS.

const U := preload("res://src/render/art/art_util.gd")
const HEIGHT: float = 22.0

static var _sprites: Dictionary = {}
static var _requested: Dictionary = {}
static var _baker: ArtBake = null

const _STRAW := Color("F2C46D")
const _STRAW_DARK := Color("D9A24A")
const _SKIN := Color("FFD7B5")


static func _ph(feet: Vector2) -> float:
	return feet.x * 0.173 + feet.y * 0.291


# =================================================================================================
# GUESTS
# =================================================================================================
static func draw_guest(ci: CanvasItem, feet: Vector2, o: Dictionary) -> void:
	var pose: StringName = o.get("pose", &"stand")
	var sc: float = o.get("scale", 1.0) * float(o.get("body_scale", 1.0))
	var facing: float = float(o.get("facing", 1))
	if facing == 0.0:
		facing = 1.0
	var t: float = o.get("t", 0.0)
	var wp: float = o.get("walk_phase", 0.0)
	var vip: StringName = o.get("vip", &"")
	var group_col: Color = o.get("group_color", Color(0, 0, 0, 0))
	var body_c: Color = o.get("body_color", Palette.SUN)
	var sick: bool = o.get("sick", false)
	var seasick: bool = o.get("seasick", false) and not sick
	var cb: bool = o.get("colorblind", false)
	var hl: int = o.get("highlight", 0)
	var prop: StringName = o.get("prop", &"")
	var fade: float = o.get("alpha", 1.0)
	var old_alpha := U.alpha
	if fade < 1.0:
		U.alpha = old_alpha * fade
	var ph := _ph(feet)

	# ---- pose parameters -----------------------------------------------------------------------
	var hop := 0.0
	var rot := 0.0
	var sx := 1.0
	var sy := 1.0
	var top := -21.5      # top of body capsule
	var bot := -3.0       # bottom of body capsule
	var foot_l := Vector2(-3.4, -1.5)
	var foot_r := Vector2(3.4, -1.5)
	var arm_swing := 0.0
	var eyes_closed := false
	var mouth := 0        # 0 smile, 1 flat, 2 frown, 3 open (surprised), 4 wavy (sick), 5 gritted (angry)
	var lying := false
	var angry := false
	var pivot_y := -11.0
	var pos0 := feet
	var slip_state := -1.0
	var show_arms := true
	var swim := false
	var sit := false

	match pose:
		&"walk", &"run":
			var run := pose == &"run"
			var sp := wp
			hop = absf(sin(sp)) * (4.2 if run else 2.6)
			var sw := sin(sp)
			foot_l = Vector2(-3.4 + sw * (5.0 if run else 3.4), -1.5 - maxf(0.0, -cos(sp)) * (3.0 if run else 2.0))
			foot_r = Vector2(3.4 - sw * (5.0 if run else 3.4), -1.5 - maxf(0.0, cos(sp)) * (3.0 if run else 2.0))
			rot = sin(sp) * 0.05 + (0.16 if run else 0.0)
			sy = 1.0 + 0.05 * sin(sp * 2.0 + 1.6)
			sx = 1.0 - 0.04 * sin(sp * 2.0 + 1.6)
			arm_swing = sw * (1.2 if run else 0.8)
			mouth = 3 if run else 0
		&"storm":
			var sp := wp * 1.4 + t * 8.0
			hop = absf(sin(sp)) * 2.0
			foot_l = Vector2(-3.4 + sin(sp) * 3.2, -1.5)
			foot_r = Vector2(3.4 - sin(sp) * 3.2, -1.5)
			rot = sin(sp) * 0.07
			angry = true
			mouth = 5
			arm_swing = sin(sp) * 1.0
		&"queue":
			var tap := maxf(0.0, sin(t * 5.0 + ph))
			foot_r = Vector2(3.4, -1.5 - tap * 2.0)
			sy = 1.0 + 0.015 * sin(t * 2.0 + ph)
			rot = sin(t * 1.3 + ph) * 0.025
			mouth = 1
		&"sit":
			top = -15.5
			bot = -2.5
			foot_l = Vector2(5.0, -1.5)
			foot_r = Vector2(9.0, -1.5)
			sy = 1.0 + 0.012 * sin(t * 1.8 + ph)
			show_arms = true
			sit = true
		&"swim":
			swim = true
			var bobv := sin(t * 2.2 + ph) * 1.6
			hop = -4.0 + bobv
			rot = sin(t * 1.7 + ph) * 0.06
			top = -19.0
			bot = 1.0
			show_arms = false
			mouth = 0
		&"lie", &"sleep":
			lying = true
			eyes_closed = pose == &"sleep"
			sy = 1.0 + 0.02 * sin(t * 1.5 + ph)
			mouth = 3 if pose == &"sleep" else 0
			if pose == &"sleep":
				mouth = 1
		&"slip":
			var st: float = o.get("slip_t", fmod(t, 1.8))
			slip_state = st
			mouth = 3
		_:
			sy = 1.0 + 0.022 * sin(t * 2.0 + ph)
			sx = 1.0 - 0.012 * sin(t * 2.0 + ph)
			rot = sin(t * 0.8 + ph) * 0.012

	if sick:
		rot += sin(t * 7.0 + ph) * 0.1
		mouth = 4
	elif seasick:
		# a slow, green-around-the-gills sway (food sickness is a fast shiver)
		rot += sin(t * 2.3 + ph) * 0.17
		hop += maxf(0.0, sin(t * 2.3 + ph + 1.2)) * 0.8
		mouth = 6
	var bc := body_c
	if sick:
		# colourblind mode: pale / white instead of green (matches the white "sick" droplet icon)
		bc = bc.lerp(Color(0.55, 0.86, 0.45) if not cb else Color(0.97, 0.97, 1.0), 0.6 if not cb else 0.55)
	if seasick:
		# pale seafoam; colourblind mode: icy white-blue
		bc = bc.lerp(Color(0.36, 0.86, 0.86) if not cb else Color(0.86, 0.93, 1.0), 0.66)
	if angry:
		# colourblind mode: dark instead of red (matches the black "angry" burst icon)
		bc = bc.lerp(Color(0.95, 0.3, 0.3) if not cb else Color(0.14, 0.15, 0.22), 0.55 if not cb else 0.5)
	var shade := Palette.shade(bc, 0.32)

	# ---- slip animation: backflip and land flat ---------------------------------------------------
	var jump := 0.0
	var stars := false
	if slip_state >= 0.0:
		var st := slip_state
		if st < 0.32:
			var k := st / 0.32
			jump = sin(k * PI * 0.5) * 15.0
			rot = -facing * k * k * TAU * 1.0
		elif st < 0.52:
			var k2 := (st - 0.32) / 0.2
			jump = (1.0 - k2 * k2) * 15.0
			rot = -facing * (TAU + k2 * PI * 0.5)
		else:
			rot = -facing * (TAU + PI * 0.5)
			stars = true
		if st >= 0.32:
			lying = false
		eyes_closed = st >= 0.52
		hop = 0.0
		pos0 = feet + Vector2(0, 4.0 * sc * clampf((st - 0.3) / 0.2, 0.0, 1.0)) - Vector2(0, jump * sc)
	if lying:
		rot = -PI * 0.5 * facing
		pos0 = feet + Vector2(0, 4.0 * sc)
	elif slip_state < 0.0:
		pos0 = feet - Vector2(0, hop * sc)

	# ---- shadow + highlight ring (ground level, untransformed) -------------------------------------
	U.xf_end(ci)
	var grounded := hop <= 0.01 and slip_state < 0.0
	var sh_scale := 1.0 - clampf(hop / 14.0 + jump / 30.0, 0.0, 0.5)
	if not swim:
		if lying or slip_state >= 0.5:
			U.shadow(ci, feet + Vector2(0, 0.5) * sc, 13.0 * sc, 2.8 * sc, 0.2)
		else:
			U.shadow(ci, feet + Vector2(0, 0.5) * sc, 8.5 * sc * sh_scale, 2.5 * sc * sh_scale, 0.2)
	if vip != &"":
		var pulse := 0.5 + 0.5 * sin(t * 3.0 + ph)
		U.ellipse(ci, feet + Vector2(0, 0.5) * sc, (14.5 + pulse * 1.5) * sc, (5.0 + pulse * 0.6) * sc, Color(1.0, 0.82, 0.3, 0.16 + 0.1 * pulse))
		U.ellipse(ci, feet + Vector2(0, 0.5) * sc, 10.5 * sc, 3.4 * sc, Color(1.0, 0.82, 0.3, 0.34))
	if hl > 0:
		_highlight_ring(ci, feet, sc, hl, t)

	# ---- body ------------------------------------------------------------------------------------
	var s2 := Vector2(facing * sc * sx, sc * sy)
	var piv := Vector2(0, pivot_y) * sc
	var tr := Transform2D(0.0, Vector2.ONE, 0.0, pos0 + piv) * Transform2D(rot, Vector2.ONE, 0.0, Vector2.ZERO) * Transform2D(0.0, Vector2.ONE, 0.0, -piv) * Transform2D(0.0, s2, 0.0, Vector2.ZERO)
	U.xf_raw(ci, tr)

	if vip != &"":
		# a VIP wears a gold outline: a slightly larger capsule peeking out from behind the bean
		U.rr(ci, Rect2(-8.6, top - 1.7, 17.2, (bot - top) + 3.4), 8.6, Color("FFD36E"))
		U.rr(ci, Rect2(-8.6, top - 1.7, 17.2, (bot - top) + 3.4), 8.6, Color(1.0, 0.72, 0.2, 0.35))
	# feet
	if not lying and not swim:
		U.ellipse(ci, foot_l, 3.1, 2.1, Palette.shade(bc, 0.5))
		U.ellipse(ci, foot_r, 3.1, 2.1, Palette.shade(bc, 0.5))
	elif lying:
		U.ellipse(ci, Vector2(-3.4, -1.0), 3.1, 2.1, Palette.shade(bc, 0.5))
		U.ellipse(ci, Vector2(3.4, -1.0), 3.1, 2.1, Palette.shade(bc, 0.5))
	var hide_hat := prop == &"sun_hat" and (lying or slip_state >= 0.3)
	var sprite := _sprite(ci, bc, shade, top, bot, show_arms, eyes_closed, mouth, angry, sick, prop, hide_hat)
	if sprite != null:
		if ci.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
			ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		ci.draw_texture_rect(sprite, Rect2(-14.0, -31.0, 28.0, 36.0), false, U.col(Color.WHITE))
	else:
		_bean_parts(ci, bc, shade, top, bot, show_arms, arm_swing, eyes_closed, mouth, angry, sick, prop, hide_hat, t, ph)
	U.xf_end(ci)

	# ---- decorations in un-rotated space ---------------------------------------------------------
	var head := pos0 + Vector2(0, (top - 1.0) * sc)
	if lying:
		head = feet + Vector2(-9.0 * sc * facing, -8.0 * sc)
	if pose == &"sleep":
		_zzz(ci, feet + Vector2(-4.0 * facing * sc, -14.0 * sc), t, ph)
	if prop == &"propeller" and not lying and slip_state < 0.3:
		_propeller_blades(ci, pos0 + Vector2(0.4 * facing, top - 5.4) * sc, sc, t, ph)
	if group_col.a > 0.0 and not lying and not swim:
		_heart_pin(ci, pos0 + Vector2(-1.0 * facing, top + 14.2) * sc, sc, group_col)
	if vip != &"":
		_vip_decor(ci, vip, feet, pos0, head, sc, facing, t, ph, lying or swim)
	if angry:
		_steam(ci, feet + Vector2(0, (top - 2.0) * sc), t)
	if sick:
		var dr := fmod(t * 1.2 + ph, 1.0)
		U.circ(ci, head + Vector2(8.0 * sc, -2.0 * sc + dr * 8.0 * sc), 1.5 * sc, Color(0.55, 0.85, 1.0, 1.0 - dr))
		for i in range(3):
			var a := t * 2.6 + float(i) * TAU / 3.0
			U.circ(ci, head + Vector2(cos(a) * 8.0, -4.0 + sin(a) * 2.5) * sc, 1.1 * sc, Color(0.7, 0.95, 0.5, 0.9))
	if seasick and not lying:
		# queasy bubbles drifting up from the mouth and a cold sweat drop: reads as "ugh, the waves", not "ate something bad"
		for i in range(3):
			var f := fposmod(t * 0.7 + float(i) * 0.33 + ph * 0.1, 1.0)
			U.circ(ci, head + Vector2((3.0 + float(i) * 3.0 + sin(f * 6.0) * 2.0) * facing, 5.0 + 3.0 - f * 20.0) * sc, (1.2 + 1.6 * f) * sc, Color(0.78, 1.0, 0.92, 0.85 * (1.0 - f)))
		var dd := fposmod(t * 1.1 + ph, 1.0)
		U.circ(ci, head + Vector2(-8.0 * facing * sc, (-1.0 + dd * 9.0) * sc), 1.6 * sc, Color(0.55, 0.85, 1.0, 1.0 - dd))
	if stars:
		for i in range(3):
			var a := t * 4.0 + float(i) * TAU / 3.0
			U.star(ci, feet + Vector2(cos(a) * 9.0, -17.0 + sin(a) * 2.5) * sc, 2.6 * sc, Palette.SUN, a)
	if swim:
		_ripples(ci, feet, sc, t, ph)
	if pose == &"run":
		var d := fmod(wp / TAU, 1.0)
		U.circ(ci, feet + Vector2(-facing * (8.0 + d * 8.0) * sc, -2.0 * sc), (2.0 - d) * sc, Color(1, 1, 1, 0.5 * (1.0 - d)))
	if hl == 2:
		var bb := sin(t * 5.0) * 1.5
		var tp := feet + Vector2(0, (top - 9.0 + bb) * sc)
		U.poly(ci, PackedVector2Array([tp + Vector2(-4, -4) * sc, tp + Vector2(4, -4) * sc, tp]), Palette.SUN)
	U.alpha = old_alpha


## Body capsule + arms + face + prop in the bean's local frame (feet at the origin, facing +x).
static func _bean_parts(ci: CanvasItem, bc: Color, shade: Color, top: float, bot: float, show_arms: bool, arm_swing: float, eyes_closed: bool, mouth: int, angry: bool, sick: bool, prop: StringName, hide_hat: bool, t: float, ph: float) -> void:
	# arms behind body (back arm)
	if show_arms:
		U.ellipse(ci, Vector2(-7.6, (top + bot) * 0.5 + 2.0 - arm_swing), 2.3, 3.6, shade)
	# capsule body: darker base, lighter top
	var h := bot - top
	U.rr(ci, Rect2(-7.0, top, 14.0, h), 7.0, shade)
	U.rr(ci, Rect2(-7.0, top, 14.0, h - 2.6), 7.0, bc)
	U.ellipse(ci, Vector2(-3.6, top + 6.5), 1.5, 3.4, Color(1, 1, 1, 0.33))
	# front arm
	if show_arms:
		U.ellipse(ci, Vector2(7.6, (top + bot) * 0.5 + 2.0 + arm_swing), 2.3, 3.6, bc)
	# face
	var look := 1.3
	var ey := top + 7.2
	if mouth == 6:
		# seasick: spiral eyes
		for sx in [-2.9, 2.9]:
			var c0 := Vector2(sx + look, ey)
			var sp := PackedVector2Array()
			for k in range(13):
				var f := float(k) / 12.0
				var ang := f * TAU * 1.6
				sp.append(c0 + Vector2(cos(ang), sin(ang)) * (0.35 + 1.7 * f))
			U.pline(ci, sp, Palette.INK, 0.9)
	elif not eyes_closed:
		U.circ(ci, Vector2(-2.9 + look, ey), 1.55, Palette.INK)
		U.circ(ci, Vector2(2.9 + look, ey), 1.55, Palette.INK)
		U.circ(ci, Vector2(-2.5 + look, ey - 0.5), 0.5, Color(1, 1, 1, 0.9))
		U.circ(ci, Vector2(3.3 + look, ey - 0.5), 0.5, Color(1, 1, 1, 0.9))
	else:
		U.arc(ci, Vector2(-2.9 + look, ey - 0.4), 1.5, 0.15, PI - 0.15, Palette.INK, 1.1, 6)
		U.arc(ci, Vector2(2.9 + look, ey - 0.4), 1.5, 0.15, PI - 0.15, Palette.INK, 1.1, 6)
	if not angry:
		U.circ(ci, Vector2(-5.1 + look * 0.6, ey + 2.5), 1.5, Color(1.0, 0.5, 0.55, 0.38))
		U.circ(ci, Vector2(5.1 + look * 0.6, ey + 2.5), 1.5, Color(1.0, 0.5, 0.55, 0.38))
	var mp := Vector2(look, ey + 3.6)
	match mouth:
		0: U.arc(ci, mp + Vector2(0, -1.2), 2.0, 0.4, PI - 0.4, Palette.INK, 1.1, 6)
		1: U.line(ci, mp + Vector2(-1.4, 0.2), mp + Vector2(1.4, 0.2), Palette.INK, 1.1)
		2: U.arc(ci, mp + Vector2(0, 2.2), 2.0, PI + 0.4, TAU - 0.4, Palette.INK, 1.1, 6)
		3: U.ellipse(ci, mp + Vector2(0, 0.4), 1.2, 1.5, Palette.INK)
		4:
			U.pline(ci, PackedVector2Array([mp + Vector2(-2, 0.5), mp + Vector2(-1, -0.5), mp + Vector2(0, 0.5), mp + Vector2(1, -0.5), mp + Vector2(2, 0.5)]), Color(0.2, 0.4, 0.2), 1.0)
		6:
			U.pline(ci, PackedVector2Array([mp + Vector2(-2.2, 0.8), mp + Vector2(-1.1, -0.4), mp + Vector2(0, 0.8), mp + Vector2(1.1, -0.4), mp + Vector2(2.2, 0.8)]), Color(0.16, 0.38, 0.34), 1.0)
			U.circ(ci, mp + Vector2(-3.7, -0.6), 1.9, Color(0.78, 1.0, 0.92, 0.7))
			U.circ(ci, mp + Vector2(3.7, -0.6), 1.9, Color(0.78, 1.0, 0.92, 0.7))
		5:
			U.line(ci, mp + Vector2(-2.0, 0.6), mp + Vector2(2.0, 0.6), Palette.INK, 1.2)
			U.line(ci, mp + Vector2(-0.7, 0.0), mp + Vector2(-0.7, 1.2), Palette.INK, 0.8)
			U.line(ci, mp + Vector2(0.7, 0.0), mp + Vector2(0.7, 1.2), Palette.INK, 0.8)
	if angry:
		U.line(ci, Vector2(-5.4 + look, ey - 3.6), Vector2(-1.2 + look, ey - 1.8), Palette.INK, 1.5)
		U.line(ci, Vector2(5.4 + look, ey - 3.6), Vector2(1.2 + look, ey - 1.8), Palette.INK, 1.5)
	if sick:
		U.ellipse(ci, Vector2(0, ey + 1.0), 6.0, 3.5, Color(0.5, 0.85, 0.4, 0.28))

	if not hide_hat:
		_prop(ci, prop, top, look, ey, t, ph)


static func _prop_id(prop: StringName) -> int:
	match prop:
		&"sun_hat": return 1
		&"headband": return 2
		&"glasses_3d": return 3
		&"headphones": return 4
		&"propeller": return 5
		&"beret": return 6
		&"sunglasses": return 7
		&"inspector_cap": return 8
	return 0


## Baked body sprite (see ArtBake). Returns null until baked (the caller then draws the vector parts).
static func _sprite(ci: CanvasItem, bc: Color, shade: Color, top: float, bot: float, show_arms: bool, eyes_closed: bool, mouth: int, angry: bool, sick: bool, prop: StringName, hide_hat: bool) -> Texture2D:
	var key: int = (bc.to_rgba32() << 24) | (_prop_id(prop) << 20) | (mouth << 16) | ((1 if eyes_closed else 0) << 15) | ((1 if show_arms else 0) << 14) | ((1 if angry else 0) << 13) | ((1 if sick else 0) << 12) | ((1 if hide_hat else 0) << 11) | (int(round((top + 40.0) * 2.0)) << 4) | int(round((bot + 10.0) * 0.5))
	var tex: Texture2D = _sprites.get(key)
	if tex != null:
		return tex
	if _requested.has(key):
		var k2 := "gs%d" % key
		var t2 := ArtBake.get_tex(k2)
		if t2 != null:
			_sprites[key] = t2
		elif not ArtBake.is_pending(k2):
			_requested.erase(key)   # the baker went away: request again next frame
		return t2
	_requested[key] = true
	if _baker == null or not is_instance_valid(_baker):
		_baker = ArtBake.new()
		_baker.name = "GuestBaker"
		ci.get_tree().root.add_child.call_deferred(_baker)
	var skey := "gs%d" % key
	_baker.request(skey, Vector2(28.0, 36.0), 5.0, func(c: CanvasItem) -> void:
		U.begin_scaled(c, Vector2(14.0, 31.0), 1.0)
		_bean_parts(c, bc, shade, top, bot, show_arms, 0.0, eyes_closed, mouth, angry, sick, prop, hide_hat, 0.0, 0.0)
		U.end_scaled(c))
	return null


static func _highlight_ring(ci: CanvasItem, feet: Vector2, sc: float, hl: int, t: float) -> void:
	if hl == 1:
		U.ellipse(ci, feet, 12.0 * sc, 4.0 * sc, Color(1, 1, 1, 0.35))
		U.ring(ci, feet, 1.0, Color(0, 0, 0, 0), 1.0)
		U.dashed_ring(ci, feet, 12.0 * sc, 4.0 * sc, Color(1, 1, 1, 0.95), 1.6, t, 12)
	else:
		U.ellipse(ci, feet, 13.0 * sc, 4.5 * sc, Color(Palette.SUN.r, Palette.SUN.g, Palette.SUN.b, 0.35))
		U.dashed_ring(ci, feet, 13.0 * sc, 4.5 * sc, Palette.SUN, 2.0, t, 14)


static func _prop(ci: CanvasItem, prop: StringName, top: float, look: float, ey: float, t: float, ph: float) -> void:
	match prop:
		&"sun_hat":
			U.ellipse(ci, Vector2(0.5, top + 1.2), 11.5, 2.9, _STRAW_DARK)
			U.ellipse(ci, Vector2(0.5, top + 0.7), 11.5, 2.6, _STRAW)
			U.ellipse(ci, Vector2(0.5, top - 1.5), 6.6, 5.0, _STRAW)
			U.rect(ci, Rect2(-6.0, top - 0.4, 13.0, 2.2), Palette.CORAL)
			U.ellipse(ci, Vector2(-1.5, top - 3.4), 2.6, 1.4, Color(1, 1, 1, 0.3))
		&"headband":
			U.rr(ci, Rect2(-7.2, top + 3.0, 14.4, 3.2), 1.6, Palette.CORAL)
			U.rr(ci, Rect2(-7.2, top + 3.0, 14.4, 1.4), 0.7, Color(1, 1, 1, 0.3))
			# knot with tails at the back
			U.circ(ci, Vector2(-7.4, top + 4.6), 2.0, Palette.CORAL_DARK)
			U.poly(ci, PackedVector2Array([Vector2(-8.5, top + 4.6), Vector2(-12.5, top + 2.0 + sin(t * 6.0 + ph) * 0.8), Vector2(-12.0, top + 6.0)]), Palette.CORAL)
		&"glasses_3d":
			var gy := ey - 0.3
			U.rr(ci, Rect2(-6.2 + look, gy - 2.6, 5.6, 5.2), 1.6, Color(Palette.CORAL.r, Palette.CORAL.g, Palette.CORAL.b, 0.82))
			U.rr(ci, Rect2(0.6 + look, gy - 2.6, 5.6, 5.2), 1.6, Color(0.25, 0.8, 0.95, 0.82))
			U.rr_outline(ci, Rect2(-6.2 + look, gy - 2.6, 5.6, 5.2), 1.6, Palette.HULL_WHITE, 1.2)
			U.rr_outline(ci, Rect2(0.6 + look, gy - 2.6, 5.6, 5.2), 1.6, Palette.HULL_WHITE, 1.2)
			U.line(ci, Vector2(-0.6 + look, gy), Vector2(0.6 + look, gy), Palette.HULL_WHITE, 1.2)
			U.line(ci, Vector2(-6.2 + look, gy), Vector2(-8.0, gy - 0.5), Palette.HULL_WHITE, 1.0)
		&"headphones":
			U.arc(ci, Vector2(0, top + 6.5), 8.2, PI + 0.15, TAU - 0.15, Palette.NAVY, 1.9, 12)
			U.rr(ci, Rect2(-10.0, top + 4.0, 4.0, 7.0), 2.0, Palette.TEAL)
			U.rr(ci, Rect2(6.0, top + 4.0, 4.0, 7.0), 2.0, Palette.TEAL)
			U.rr(ci, Rect2(-10.0, top + 4.0, 1.6, 7.0), 1.0, Color(1, 1, 1, 0.3))
		&"propeller":
			# kids' beanie: striped dome, teal band, little stem + button (the blades spin on top, see _propeller_blades)
			U.ellipse(ci, Vector2(0.4, top + 2.4), 8.0, 4.8, Palette.shade(Palette.CORAL, 0.3))
			U.ellipse(ci, Vector2(0.4, top + 1.8), 7.8, 4.6, Palette.CORAL)
			U.arc(ci, Vector2(0.4, top + 2.6), 5.6, PI + 0.55, TAU - 0.55, Palette.SUN, 1.5, 10)
			U.arc(ci, Vector2(0.4, top + 2.6), 3.0, PI + 0.9, TAU - 0.9, Color.WHITE, 1.2, 8)
			U.rr(ci, Rect2(-7.4, top + 2.2, 15.6, 2.4), 1.2, Palette.TEAL)
			U.rr(ci, Rect2(-7.4, top + 2.2, 15.6, 0.9), 0.5, Color(1, 1, 1, 0.3))
			U.ellipse(ci, Vector2(-2.2, top - 0.4), 2.4, 1.2, Color(1, 1, 1, 0.34))
			U.rect(ci, Rect2(0.0, top - 4.6, 0.9, 2.2), Palette.STEEL_DARK)
			U.circ(ci, Vector2(0.45, top - 2.2), 1.2, Palette.SUN_DEEP)
		&"beret":
			# critic: floppy raspberry beret tipped to one side with a little stalk
			U.ellipse(ci, Vector2(1.8, top + 1.0), 9.4, 4.6, Color("7C2442"))
			U.ellipse(ci, Vector2(1.8, top + 0.4), 9.2, 4.4, Color("B83A63"))
			U.ellipse(ci, Vector2(-1.2, top - 1.2), 3.8, 1.5, Color(1, 1, 1, 0.26))
			U.circ(ci, Vector2(2.0, top - 3.9), 1.1, Color("7C2442"))
			U.rr(ci, Rect2(-6.4, top + 1.8, 13.6, 1.5), 0.7, Color("7C2442"))
		&"sunglasses":
			# celebrity: big dark shades with a glint
			var sy := ey - 0.2
			U.rr(ci, Rect2(-6.6 + look, sy - 2.3, 6.2, 4.8), 2.0, Color("1B2236"))
			U.rr(ci, Rect2(0.4 + look, sy - 2.3, 6.2, 4.8), 2.0, Color("1B2236"))
			U.line(ci, Vector2(-0.4 + look, sy - 0.6), Vector2(0.4 + look, sy - 0.6), Color("1B2236"), 1.3)
			U.line(ci, Vector2(-6.6 + look, sy - 0.8), Vector2(-8.3, sy - 1.2), Color("1B2236"), 1.1)
			U.poly(ci, PackedVector2Array([Vector2(-5.2 + look, sy - 1.6), Vector2(-3.6 + look, sy - 1.6), Vector2(-4.8 + look, sy + 0.9), Vector2(-6.2 + look, sy + 0.9)]), Color(1, 1, 1, 0.5))
			U.poly(ci, PackedVector2Array([Vector2(1.8 + look, sy - 1.6), Vector2(3.4 + look, sy - 1.6), Vector2(2.2 + look, sy + 0.9), Vector2(0.8 + look, sy + 0.9)]), Color(1, 1, 1, 0.5))
		&"inspector_cap":
			# inspector: navy peaked cap with a gold badge
			U.ellipse(ci, Vector2(0.4, top + 2.0), 7.8, 4.8, Palette.NAVY_DARK)
			U.ellipse(ci, Vector2(0.4, top + 1.4), 7.6, 4.6, Palette.NAVY_LIGHT)
			U.rr(ci, Rect2(-7.2, top + 2.0, 15.2, 2.2), 1.0, Palette.NAVY_DARK)
			U.rr(ci, Rect2(-7.2, top + 2.0, 15.2, 0.8), 0.4, Palette.SUN)
			U.poly(ci, PackedVector2Array([Vector2(1.0, top + 3.4), Vector2(11.0, top + 4.0), Vector2(11.4, top + 5.4), Vector2(1.0, top + 4.8)]), Color("141C2E"))
			U.circ(ci, Vector2(0.6 + look * 0.4, top + 1.6), 1.7, Palette.SUN)
			U.circ(ci, Vector2(0.6 + look * 0.4, top + 1.6), 0.8, Palette.SUN_DEEP)


## Spinning blades of the kids' propeller beanie (`hub` = top of the stem, in un-rotated pixel space).
static func _propeller_blades(ci: CanvasItem, hub: Vector2, sc: float, t: float, ph: float) -> void:
	var a := t * 16.0 + ph * 2.0
	var v := Vector2(cos(a) * 5.4, sin(a) * 1.0) * sc
	var cols: Array[Color] = [Palette.TEAL, Palette.SUN]
	U.line(ci, hub - v, hub + v, Color(Palette.NAVY.r, Palette.NAVY.g, Palette.NAVY.b, 0.35), 2.4 * sc)
	U.line(ci, hub - v, hub, cols[0], 1.9 * sc)
	U.line(ci, hub, hub + v, cols[1], 1.9 * sc)
	U.circ(ci, hub, 1.15 * sc, Palette.NAVY_LIGHT)


## Public heart glyph (centre `p`, half width `r`) in `col` with a white rim: group links and pins.
static func draw_heart(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	_heart_pin(ci, p + Vector2(0, -r * 0.55), r / 1.55, col)


## A tiny heart pin in the group's colour (couples and families wear matching ones).
static func _heart_pin(ci: CanvasItem, p: Vector2, sc: float, col: Color) -> void:
	var r := 1.55 * sc
	U.circ(ci, p + Vector2(-r * 0.78, -r * 0.3), r, Color(1, 1, 1, 0.9))
	U.circ(ci, p + Vector2(r * 0.78, -r * 0.3), r, Color(1, 1, 1, 0.9))
	U.poly(ci, PackedVector2Array([p + Vector2(-r * 1.9, 0.0), p + Vector2(r * 1.9, 0.0), p + Vector2(0, r * 2.4)]), Color(1, 1, 1, 0.9))
	var q := r * 0.8
	U.circ(ci, p + Vector2(-q * 0.78, -q * 0.3), q, col)
	U.circ(ci, p + Vector2(q * 0.78, -q * 0.3), q, col)
	U.poly(ci, PackedVector2Array([p + Vector2(-q * 1.88, 0.0), p + Vector2(q * 1.88, 0.0), p + Vector2(0, q * 2.35)]), col)


## Everything a VIP adds in un-rotated space: the floating gold star and the kind's prop in hand / sparkles round the head.
static func _vip_decor(ci: CanvasItem, kind: StringName, feet: Vector2, pos0: Vector2, head: Vector2, sc: float, facing: float, t: float, ph: float, flat: bool) -> void:
	if not flat:
		var bob := sin(t * 3.2 + ph) * 1.4
		var sp := head + Vector2(0, -9.5 * sc + bob)
		var gold := Color("FFD36E")
		U.circ(ci, sp + Vector2(0, 0.6), 7.4 * sc, Color(1.0, 0.85, 0.35, 0.22))
		U.star(ci, sp + Vector2(0, 0.5), 6.6 * sc, Color(0.45, 0.25, 0.05, 0.55), t * 0.5)
		U.star(ci, sp, 5.6 * sc, gold, t * 0.5)
		U.star(ci, sp, 3.2 * sc, Color("FFF1B8"), t * 0.5)
	match kind:
		&"critic":
			# notepad + pencil in the front hand
			var np := pos0 + Vector2(8.6 * facing, -8.6) * sc
			U.xf(ci, np, 0.12 * facing, Vector2(sc, sc))
			U.rr(ci, Rect2(-3.3, -4.6, 6.6, 9.2), 1.0, Color("DCC9A6"))
			U.rr(ci, Rect2(-3.3, -4.9, 6.4, 8.9), 1.0, Color("FFF8E6"))
			for k in range(3):
				U.line(ci, Vector2(-2.0, -2.6 + float(k) * 2.2), Vector2(2.2, -2.6 + float(k) * 2.2), Color("9CB4D8"), 0.7)
			for k in range(4):
				U.circ(ci, Vector2(-3.3, -3.6 + float(k) * 2.4), 0.6, Color("7C2442"))
			var wob := sin(t * 9.0 + ph) * 0.6
			U.line(ci, Vector2(1.8, 1.6 + wob), Vector2(4.6, -3.0), Color("F2A93B"), 1.1)
			U.xf_end(ci)
		&"inspector":
			# clipboard with ticks
			var cp := pos0 + Vector2(8.8 * facing, -9.0) * sc
			U.xf(ci, cp, -0.1 * facing, Vector2(sc, sc))
			U.rr(ci, Rect2(-3.6, -5.2, 7.2, 10.4), 1.0, Palette.WOOD_DARK)
			U.rr(ci, Rect2(-2.9, -4.2, 5.8, 8.6), 0.7, Color("FFFDF4"))
			U.rr(ci, Rect2(-1.6, -6.0, 3.2, 1.8), 0.6, Palette.STEEL)
			for k in range(3):
				var y := -2.6 + float(k) * 2.4
				U.pline(ci, PackedVector2Array([Vector2(-2.0, y), Vector2(-1.4, y + 0.7), Vector2(-0.4, y - 0.7)]), Palette.MINT_DARK, 0.7)
				U.line(ci, Vector2(0.3, y), Vector2(2.2, y), Color("9CB4D8"), 0.7)
			U.xf_end(ci)
		&"celebrity":
			if not flat:
				for k in range(3):
					var a := t * 1.7 + float(k) * TAU / 3.0 + ph
					var tw := 0.5 + 0.5 * sin(t * 6.0 + float(k) * 2.0 + ph)
					var sp2 := head + Vector2(cos(a) * 11.5, sin(a) * 4.0 - 2.0) * sc
					_sparkle4(ci, sp2, (1.6 + tw * 1.6) * sc, Color("FFF6C8"))


## Little four-point sparkle.
static func _sparkle4(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	U.poly(ci, PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.28, -r * 0.28), p + Vector2(r, 0), p + Vector2(r * 0.28, r * 0.28), p + Vector2(0, r), p + Vector2(-r * 0.28, r * 0.28), p + Vector2(-r, 0), p + Vector2(-r * 0.28, -r * 0.28)]), col)


static func _zzz(ci: CanvasItem, base: Vector2, t: float, ph: float) -> void:
	for i in range(3):
		var k := fmod(t * 0.55 + float(i) / 3.0 + ph * 0.05, 1.0)
		var p := base + Vector2(k * 10.0 + sin(k * 6.0) * 2.0, -k * 20.0)
		var s := 2.0 + k * 3.0
		var a := (1.0 - k) * minf(1.0, k * 6.0)
		var c := Color(0.9, 0.95, 1.0, a)
		var sh := Color(0.35, 0.4, 0.65, a * 0.9)
		var pts := PackedVector2Array([p + Vector2(-s, -s), p + Vector2(s, -s), p + Vector2(-s, s), p + Vector2(s, s)])
		U.pline(ci, pts, sh, 2.2)
		U.pline(ci, pts, c, 1.2)


static func _steam(ci: CanvasItem, base: Vector2, t: float) -> void:
	for i in range(4):
		var k := fmod(t * 1.1 + float(i) * 0.25, 1.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := base + Vector2(side * (4.0 + k * 4.0), -k * 14.0)
		U.circ(ci, p, 1.6 + k * 2.8, Color(1, 1, 1, 0.75 * (1.0 - k)))


static func _ripples(ci: CanvasItem, feet: Vector2, sc: float, t: float, ph: float) -> void:
	var k := fmod(t * 0.9 + ph, 1.0)
	U.arc(ci, feet + Vector2(0, -3.0 * sc), (9.0 + k * 5.0) * sc, 0.0, PI, Color(1, 1, 1, 0.5 * (1.0 - k)), 1.2, 10)


# =================================================================================================
# STAFF
# =================================================================================================
## Height (px above the feet, at scale 1) of a role's silhouette: where a mood / "zzz" bubble should sit.
static func staff_top(role: StringName) -> float:
	match role:
		&"chef": return 37.0
		&"entertainer": return 32.0
		&"warden": return 31.0
	return 27.0


## [coat, coat shade, trim] colours of a role's uniform.
static func _staff_colors(role: StringName) -> Array[Color]:
	match role:
		&"medic": return [Color("F6FAFD"), Color("BCCFE2"), Palette.CORAL]
		&"entertainer": return [Color("FFF1DA"), Color("E8C79B"), Palette.CORAL]
		&"chef": return [Color("FFFFFF"), Color("CFD6E2"), Palette.STEEL]
		&"warden": return [Color("57479A"), Color("352B66"), Palette.SUN]
	return [Palette.NAVY_LIGHT, Palette.NAVY_DARK, Palette.SUN]


## Half width of the body pill at height y (the visible torso below the face plate narrows like a circle).
static func _body_hw(y: float) -> float:
	if y >= -12.6:
		return sqrt(maxf(49.0 - (y + 12.6) * (y + 12.6) * 0.78, 0.0))
	return 7.0


## One horizontal stripe across the torso between y0 and y1.
static func _band(ci: CanvasItem, y0: float, y1: float, c: Color) -> void:
	var a := _body_hw(y0) - 0.2
	var b := _body_hw(y1) - 0.2
	U.poly(ci, PackedVector2Array([Vector2(-a, y0), Vector2(a, y0), Vector2(b, y1), Vector2(-b, y1)]), c)


## Floating "z z z" above a sleeper (public so the renderer can draw it over the room's front layer).
static func draw_zzz(ci: CanvasItem, base: Vector2, t: float, seed_phase: float = 0.0) -> void:
	_zzz(ci, base, t, seed_phase)


static func draw_staff(ci: CanvasItem, feet: Vector2, o: Dictionary) -> void:
	var role: StringName = o.get("role", &"janitor")
	var pose: StringName = o.get("pose", &"stand")
	var sc: float = o.get("scale", 1.0)
	var facing: float = float(o.get("facing", 1))
	if facing == 0.0:
		facing = 1.0
	var t: float = o.get("t", 0.0)
	var wp: float = o.get("walk_phase", 0.0)
	var hl: int = o.get("highlight", 0)
	var fade: float = o.get("alpha", 1.0)
	var tired: bool = o.get("tired", false)
	var old_alpha := U.alpha
	if fade < 1.0:
		U.alpha = old_alpha * fade
	var ph := _ph(feet)
	var lying := pose == &"sleep"
	var working := pose == &"work"
	var performing := pose == &"perform"
	var cooking := pose == &"cook"
	var moving := pose == &"walk" or pose == &"run"
	var cols := _staff_colors(role)
	var unif: Color = cols[0]
	var unif_dark: Color = cols[1]
	var trim: Color = cols[2]

	var hop := 0.0
	var rot := 0.0
	var foot_l := Vector2(-3.4, -1.5)
	var foot_r := Vector2(3.4, -1.5)
	var sy := 1.0
	var arm_sw := 0.0
	var arms_up := 0.0
	if moving:
		var sp := wp
		var run := pose == &"run"
		hop = absf(sin(sp)) * (3.8 if run else (1.5 if tired else 2.4))
		foot_l = Vector2(-3.4 + sin(sp) * 3.4, -1.5 - maxf(0.0, -cos(sp)) * 2.0)
		foot_r = Vector2(3.4 - sin(sp) * 3.4, -1.5 - maxf(0.0, cos(sp)) * 2.0)
		rot = sin(sp) * 0.05 + (0.12 if run else 0.0)
		arm_sw = sin(sp)
	elif working:
		var wv := sin(t * 7.0)
		hop = maxf(0.0, wv) * 0.8
		sy = 1.0 + 0.03 * sin(t * 14.0)
		rot = 0.06 * sin(t * 7.0)
	elif performing:
		hop = absf(sin(t * 5.0 + ph)) * 1.6
		rot = 0.05 * sin(t * 2.5 + ph)
		arms_up = 1.0
		sy = 1.0 + 0.02 * sin(t * 10.0)
	elif cooking:
		sy = 1.0 + 0.02 * sin(t * 3.0 + ph)
		rot = 0.03 * sin(t * 2.0 + ph)
	else:
		sy = 1.0 + 0.02 * sin(t * (1.2 if tired else 2.0) + ph)
	if tired and not lying:
		sy *= 0.97

	var pos0 := feet - Vector2(0, hop * sc)
	if lying:
		rot = -PI * 0.5 * facing
		pos0 = feet + Vector2(0, 4.0 * sc)
		sy = 1.0 + 0.02 * sin(t * 1.5 + ph)

	U.xf_end(ci)
	if lying:
		U.shadow(ci, feet + Vector2(0, 0.5) * sc, 13.0 * sc, 2.8 * sc, 0.2)
	else:
		U.shadow(ci, feet + Vector2(0, 0.5) * sc, 8.5 * sc, 2.5 * sc, 0.2)
	if hl > 0:
		_staff_ring(ci, feet, sc, hl, t)
	# the warden's lantern glow sits behind everyone else on the deck
	if role == &"warden" and not lying:
		_warden_glow(ci, feet, sc, facing, working, t, ph)

	var piv := Vector2(0, -11.0) * sc
	var s2 := Vector2(facing * sc, sc * sy)
	var tr := Transform2D(0.0, Vector2.ONE, 0.0, pos0 + piv) * Transform2D(rot, Vector2.ONE, 0.0, Vector2.ZERO) * Transform2D(0.0, Vector2.ONE, 0.0, -piv) * Transform2D(0.0, s2, 0.0, Vector2.ZERO)
	U.xf_raw(ci, tr)

	# ---- behind the body ------------------------------------------------------------------------
	if role == &"janitor" and not lying:
		_janitor_tools(ci, moving, working, t, wp)
	if role == &"warden" and not lying:
		_warden_staff(ci, moving, working, t)
	# warden hood and cloak hem are wider than the bean
	if role == &"warden":
		U.poly(ci, PackedVector2Array([Vector2(-6.5, -13.0), Vector2(-10.6, -2.6), Vector2(0.0, -1.2), Vector2(10.6, -2.6), Vector2(6.5, -13.0)]), unif_dark)
		U.poly(ci, PackedVector2Array([Vector2(-8.0, -14.5), Vector2(-7.4, -21.0), Vector2(-2.6, -27.6), Vector2(2.2, -29.8), Vector2(7.4, -21.0), Vector2(8.0, -14.5)]), unif_dark)
	if not lying:
		U.ellipse(ci, foot_l, 3.3, 2.2, Color("1A2236"))
		U.ellipse(ci, foot_r, 3.3, 2.2, Color("1A2236"))
	else:
		U.ellipse(ci, Vector2(-3.4, -1.0), 3.3, 2.2, Color("1A2236"))
		U.ellipse(ci, Vector2(3.4, -1.0), 3.3, 2.2, Color("1A2236"))
	var back_arm_y := -10.0 - arm_sw - arms_up * 4.0
	var front_arm_y := -10.0 + arm_sw - arms_up * 4.0
	U.ellipse(ci, Vector2(-7.6, back_arm_y), 2.3, 3.6, unif_dark)
	U.rr(ci, Rect2(-7.0, -21.5, 14.0, 18.5), 7.0, unif_dark)
	U.rr(ci, Rect2(-7.0, -21.5, 14.0, 15.9), 7.0, unif)
	# torso markings (visible below the face plate)
	match role:
		&"entertainer":
			_band(ci, -10.6, -8.9, trim)
			_band(ci, -7.7, -6.0, trim)
		&"warden":
			U.poly(ci, PackedVector2Array([Vector2(-6.6, -13.0), Vector2(-9.2, -4.0), Vector2(-3.0, -4.6), Vector2(-3.4, -13.0)]), Color(1, 1, 1, 0.07))
	# ---- head ----------------------------------------------------------------------------------
	if role == &"warden":
		U.rr(ci, Rect2(-6.2, -20.2, 12.4, 9.8), 4.8, Color("231B47"))
	U.rr(ci, Rect2(-5.3, -19.0, 10.6, 8.2), 4.0, _SKIN)
	U.rr(ci, Rect2(-5.3, -14.6, 10.6, 3.8), 2.0, Color(1.0, 0.82, 0.68, 1.0))
	U.rr(ci, Rect2(-5.3, -19.0, 10.6, 8.2), 4.0, _SKIN)
	var look := 1.0
	if lying or tired:
		U.line(ci, Vector2(-4.1 + look, -15.5), Vector2(-1.2 + look, -15.3), Palette.INK, 1.2)
		U.line(ci, Vector2(1.2 + look, -15.3), Vector2(4.1 + look, -15.5), Palette.INK, 1.2)
		if tired and not lying:
			U.ellipse(ci, Vector2(-2.6 + look, -14.3), 1.8, 0.8, Color(0.55, 0.45, 0.7, 0.35))
			U.ellipse(ci, Vector2(2.6 + look, -14.3), 1.8, 0.8, Color(0.55, 0.45, 0.7, 0.35))
	else:
		U.circ(ci, Vector2(-2.6 + look, -15.6), 1.35, Palette.INK)
		U.circ(ci, Vector2(2.6 + look, -15.6), 1.35, Palette.INK)
	if tired and not lying:
		U.arc(ci, Vector2(look, -12.6), 1.7, PI + 0.5, TAU - 0.5, Color("B5604A"), 1.0, 6)
	elif lying or performing:
		U.arc(ci, Vector2(look, -14.2 if performing else -13.2), 1.9, 0.3, PI - 0.3, Color("B5604A"), 1.1, 6)
	else:
		U.arc(ci, Vector2(look, -13.8), 1.7, 0.4, PI - 0.4, Color("B5604A"), 1.0, 6)
	U.circ(ci, Vector2(-4.2 + look * 0.5, -13.6), 1.2, Color(1.0, 0.5, 0.55, 0.4))
	U.circ(ci, Vector2(4.2 + look * 0.5, -13.6), 1.2, Color(1.0, 0.5, 0.55, 0.4))
	if tired and not lying:
		var dr := fmod(t * 0.9 + ph, 1.0)
		U.circ(ci, Vector2(6.4, -18.6 + dr * 4.0), 1.1 * (1.0 - dr * 0.5), Color(0.6, 0.85, 1.0, 1.0 - dr))
	# ---- collar / badge / belt ---------------------------------------------------------------
	match role:
		&"medic":
			U.poly(ci, PackedVector2Array([Vector2(-3.8, -10.8), Vector2(3.8, -10.8), Vector2(0, -6.4)]), Palette.TEAL_LIGHT)
			U.poly(ci, PackedVector2Array([Vector2(-2.6, -10.8), Vector2(2.6, -10.8), Vector2(0, -7.6)]), Color.WHITE)
			# red cross badge on the chest + a stethoscope loop
			U.rect(ci, Rect2(-5.2, -9.6, 3.6, 1.2), trim)
			U.rect(ci, Rect2(-4.0, -10.8, 1.2, 3.6), trim)
			U.arc(ci, Vector2(1.6, -10.6), 3.1, 0.15, PI - 0.15, Palette.STEEL_DARK, 0.9, 8)
			U.circ(ci, Vector2(1.6, -7.4), 1.0, Palette.STEEL)
		&"chef":
			U.poly(ci, PackedVector2Array([Vector2(-3.6, -10.8), Vector2(3.6, -10.8), Vector2(0, -7.0)]), Color("D7DDE8"))
			U.poly(ci, PackedVector2Array([Vector2(-2.2, -10.8), Vector2(2.2, -10.8), Vector2(0, -8.4)]), Palette.CORAL)
			for bx in [-2.6, 2.6]:
				for by in [-8.2, -6.4]:
					U.circ(ci, Vector2(bx, by), 0.75, Color("9AA8BD"))
		&"entertainer":
			# bow tie
			U.poly(ci, PackedVector2Array([Vector2(0, -10.6), Vector2(-3.8, -12.2), Vector2(-3.8, -9.0)]), Palette.TEAL)
			U.poly(ci, PackedVector2Array([Vector2(0, -10.6), Vector2(3.8, -12.2), Vector2(3.8, -9.0)]), Palette.TEAL)
			U.circ(ci, Vector2(0, -10.6), 1.0, Palette.TEAL_DARK)
		&"warden":
			U.circ(ci, Vector2(0, -10.2), 1.7, Palette.SUN_DEEP)
			U.circ(ci, Vector2(0, -10.2), 1.1, Palette.SUN)
		_:
			U.poly(ci, PackedVector2Array([Vector2(-3.5, -10.6), Vector2(3.5, -10.6), Vector2(0, -7.4)]), Palette.HULL_WHITE)
			U.rect(ci, Rect2(-7.0, -6.0, 14.0, 1.6), Palette.SUN)
			U.circ(ci, Vector2(3.8, -8.4), 1.2, Palette.CORAL)
	# front arm (raised while juggling / cooking)
	var arm_c := unif
	if role == &"entertainer":
		arm_c = Palette.CORAL.lerp(Color.WHITE, 0.25)
	if arms_up > 0.0:
		U.ellipse(ci, Vector2(7.6, front_arm_y), 2.3, 3.6, arm_c)
		U.ellipse(ci, Vector2(7.7, front_arm_y - 2.6), 2.0, 1.8, _SKIN)
		U.ellipse(ci, Vector2(-7.7, back_arm_y - 2.6), 2.0, 1.8, _SKIN)
	else:
		U.ellipse(ci, Vector2(7.6, front_arm_y), 2.3, 3.6, arm_c)
		U.ellipse(ci, Vector2(7.7, front_arm_y + 2.3), 2.0, 1.8, _SKIN)
	# ---- hats and handheld props ---------------------------------------------------------------
	match role:
		&"mechanic":
			U.ellipse(ci, Vector2(0, -21.0), 8.6, 2.2, Palette.SUN_DEEP)
			U.poly(ci, PackedVector2Array([Vector2(-7.6, -21.0), Vector2(-6.2, -25.2), Vector2(0, -27.2), Vector2(6.2, -25.2), Vector2(7.6, -21.0)]), Palette.SUN)
			U.rect(ci, Rect2(-1.2, -27.0, 2.4, 5.2), Palette.SUN_DEEP)
			U.circ(ci, Vector2(0.5, -23.6), 1.5, Palette.CREAM)
			U.ellipse(ci, Vector2(-3.4, -24.8), 1.6, 1.0, Color(1, 1, 1, 0.5))
			if not lying:
				_mechanic_tool(ci, moving, working, t)
		&"medic":
			U.rr(ci, Rect2(-6.8, -25.4, 13.6, 5.6), 2.8, Color("DCE7F2"))
			U.rr(ci, Rect2(-6.8, -26.0, 13.6, 5.0), 2.8, Color("FFFFFF"))
			U.rect(ci, Rect2(-6.8, -21.9, 13.6, 1.5), Palette.TEAL_LIGHT)
			U.rect(ci, Rect2(-1.0, -25.2, 4.8, 1.5), trim)
			U.rect(ci, Rect2(0.6, -26.9, 1.6, 4.8), trim)
			U.ellipse(ci, Vector2(-3.8, -24.6), 1.6, 0.9, Color(1, 1, 1, 0.7))
			if not lying:
				_medic_bag(ci, moving, working, t)
		&"entertainer":
			U.rr(ci, Rect2(-6.9, -23.4, 13.8, 2.8), 1.4, Palette.CREAM)
			if lying:
				# asleep: the floppy tips are tucked in so the hat stays inside the bunk
				U.poly(ci, PackedVector2Array([Vector2(-6.9, -22.6), Vector2(-7.6, -25.6), Vector2(-3.6, -25.0), Vector2(-0.4, -23.6)]), Palette.CORAL)
				U.poly(ci, PackedVector2Array([Vector2(6.9, -22.6), Vector2(7.6, -25.4), Vector2(3.6, -24.6), Vector2(0.4, -23.6)]), Palette.TEAL)
				U.poly(ci, PackedVector2Array([Vector2(-3.4, -23.0), Vector2(0, -27.0), Vector2(3.4, -23.0)]), Palette.SUN)
			else:
				U.poly(ci, PackedVector2Array([Vector2(-6.9, -22.6), Vector2(-9.0, -27.6), Vector2(-11.2, -30.2), Vector2(-3.6, -25.0), Vector2(-0.4, -23.6)]), Palette.CORAL)
				U.poly(ci, PackedVector2Array([Vector2(6.9, -22.6), Vector2(9.0, -27.0), Vector2(11.2, -29.4), Vector2(3.6, -24.6), Vector2(0.4, -23.6)]), Palette.TEAL)
				U.poly(ci, PackedVector2Array([Vector2(-3.4, -23.0), Vector2(0, -28.4), Vector2(3.4, -23.0)]), Palette.SUN)
				U.circ(ci, Vector2(-11.5, -30.6), 1.9, Palette.SUN_DEEP)
				U.circ(ci, Vector2(-11.5, -30.6), 1.2, Palette.SUN)
				U.circ(ci, Vector2(11.5, -29.8), 1.9, Palette.SUN_DEEP)
				U.circ(ci, Vector2(11.5, -29.8), 1.2, Palette.SUN)
				U.circ(ci, Vector2(0, -28.8), 1.6, Palette.CORAL)
			if not lying:
				_juggle(ci, performing, moving, t, ph)
		&"chef":
			if not lying:
				U.circ(ci, Vector2(-4.4, -28.6), 4.0, Color("E4E9F1"))
				U.circ(ci, Vector2(0.4, -32.0), 4.8, Color("E4E9F1"))
				U.circ(ci, Vector2(4.6, -28.4), 4.0, Color("E4E9F1"))
				U.circ(ci, Vector2(-4.4, -29.0), 3.8, Color.WHITE)
				U.circ(ci, Vector2(0.4, -32.5), 4.6, Color.WHITE)
				U.circ(ci, Vector2(4.6, -28.8), 3.8, Color.WHITE)
				U.rect(ci, Rect2(-5.8, -29.2, 11.6, 6.0), Color.WHITE)
				U.ellipse(ci, Vector2(-1.2, -33.4), 2.0, 1.1, Color(1, 1, 1, 0.9))
			U.rr(ci, Rect2(-6.4, -24.6, 12.8, 3.6), 1.6, Color("E4E9F1"))
			U.rect(ci, Rect2(-6.4, -24.6, 12.8, 1.2), Color(1, 1, 1, 0.8))
			if not lying:
				_chef_ladle(ci, moving, cooking, t)
		&"warden":
			# the hood's brim frames the face
			U.arc(ci, Vector2(0, -15.0), 7.4, PI + 0.15, TAU - 0.15, Color("6B5BB0"), 1.8, 14)
			U.circ(ci, Vector2(1.4, -29.0), 1.5, Color("6B5BB0"))
			U.ellipse(ci, Vector2(-3.4, -24.4), 1.8, 1.0, Color(1, 1, 1, 0.22))
		_:
			U.poly(ci, PackedVector2Array([Vector2(-7.0, -21.0), Vector2(-5.6, -24.8), Vector2(0, -26.0), Vector2(5.6, -24.8), Vector2(7.0, -21.0)]), Palette.TEAL)
			U.rr(ci, Rect2(-1.0, -22.2, 11.0, 2.2), 1.0, Palette.TEAL_DARK)
			U.rect(ci, Rect2(-7.0, -22.0, 14.0, 1.4), Palette.CREAM)
			U.ellipse(ci, Vector2(-2.8, -24.2), 1.6, 0.9, Color(1, 1, 1, 0.45))
			if not lying:
				_janitor_front(ci, moving, working, t)
	U.xf_end(ci)

	# ---- effects in un-rotated space -----------------------------------------------------------
	if lying and not o.get("skip_zzz", false):
		_zzz(ci, feet + Vector2(-4.0 * facing * sc, -14.0 * sc), t, ph)
	if working:
		match role:
			&"mechanic":
				for i in range(3):
					var k := fmod(t * 3.0 + float(i) * 0.33, 1.0)
					var a := -0.9 + float(i) * 0.9
					var p := feet + Vector2(facing * (13.0 + cos(a) * k * 8.0), -9.0 - sin(a) * k * 9.0 - 4.0) * sc
					U.circ(ci, p, 1.4 * (1.0 - k) * sc, Palette.SUN)
			&"medic":
				for i in range(3):
					var k := fmod(t * 1.1 + float(i) * 0.33, 1.0)
					var p := feet + Vector2(facing * (12.0 + sin(k * 7.0 + float(i)) * 2.5), -8.0 - k * 18.0) * sc
					var pa := (1.0 - k) * minf(1.0, k * 8.0)
					var pc := Color(Palette.CORAL.r, Palette.CORAL.g, Palette.CORAL.b, pa)
					U.rect(ci, Rect2(p - Vector2(0.9, 2.6) * sc, Vector2(1.8, 5.2) * sc), pc)
					U.rect(ci, Rect2(p - Vector2(2.6, 0.9) * sc, Vector2(5.2, 1.8) * sc), pc)
			&"warden":
				for i in range(4):
					var k := fmod(t * 1.6 + float(i) * 0.25, 1.0)
					var p := feet + Vector2(facing * (6.0 + k * 20.0), -26.0 + sin(k * 9.0 + float(i)) * 3.5 + k * 10.0) * sc
					var pa2 := (1.0 - k) * minf(1.0, k * 6.0)
					U.star(ci, p, (1.2 + 1.5 * (1.0 - k)) * sc, Color(0.85, 0.95, 1.0, pa2), t * 3.0 + float(i))
			_:
				for i in range(3):
					var k := fmod(t * 1.3 + float(i) * 0.33, 1.0)
					var p := feet + Vector2(facing * (11.5 + sin(k * 9.0 + float(i)) * 2.0), -6.0 - k * 14.0) * sc
					U.circ(ci, p, (1.0 + k * 1.5) * sc, Color(0.8, 0.95, 1.0, 0.8 * (1.0 - k)))
	if cooking:
		_steam_pot(ci, feet, sc, facing, t)
	if hl == 2:
		var tp := feet + Vector2(0, (-staff_top(role) - 4.0 + sin(t * 5.0) * 1.5) * sc)
		U.poly(ci, PackedVector2Array([tp + Vector2(-4, -4) * sc, tp + Vector2(4, -4) * sc, tp]), Palette.SUN)
	U.alpha = old_alpha


static func _staff_ring(ci: CanvasItem, feet: Vector2, sc: float, hl: int, t: float) -> void:
	if hl == 1:
		U.ellipse(ci, feet, 12.0 * sc, 4.0 * sc, Color(1, 1, 1, 0.35))
		U.dashed_ring(ci, feet, 12.0 * sc, 4.0 * sc, Color(1, 1, 1, 0.95), 1.6, t, 12)
	else:
		U.ellipse(ci, feet, 14.0 * sc, 5.0 * sc, Color(Palette.SUN.r, Palette.SUN.g, Palette.SUN.b, 0.4))
		U.dashed_ring(ci, feet, 14.0 * sc, 5.0 * sc, Palette.SUN, 2.2, t, 14)


static func _janitor_tools(ci: CanvasItem, moving: bool, working: bool, t: float, wp: float) -> void:
	# mop behind the body (back hand)
	var swing := 0.0
	var base := Vector2(-9.5, -9.0)
	if working:
		swing = sin(t * 7.0) * 0.5
	elif moving:
		swing = 0.25 + sin(wp) * 0.1
	var tip := base + Vector2(sin(swing), cos(swing)) * 10.0
	var top := base - Vector2(sin(swing), cos(swing)) * 15.0
	U.capsule(ci, top, tip, 0.9, Palette.WOOD)
	# mop head
	var prev := U.xf_push(ci, tip, -swing, Vector2.ONE)
	U.poly(ci, PackedVector2Array([Vector2(-1.8, -1.0), Vector2(1.8, -1.0), Vector2(4.0, 3.2), Vector2(-4.0, 3.2)]), Palette.TEAL_DARK)
	U.ellipse(ci, Vector2(0, 2.8), 4.4, 1.7, Color(0.92, 0.98, 1.0))
	U.ellipse(ci, Vector2(0, 2.8), 3.0, 1.1, Palette.TEAL_LIGHT)
	U.xf_load(ci, prev)


static func _janitor_front(ci: CanvasItem, moving: bool, working: bool, t: float) -> void:
	# bucket in front hand
	var bp := Vector2(10.5, -3.6)
	if moving:
		bp.y -= 1.2
	U.poly(ci, PackedVector2Array([bp + Vector2(-3.6, -3.6), bp + Vector2(3.6, -3.6), bp + Vector2(2.8, 3.0), bp + Vector2(-2.8, 3.0)]), Palette.TEAL)
	U.rect(ci, Rect2(bp.x - 3.6, bp.y - 3.6, 7.2, 1.4), Palette.TEAL_LIGHT)
	U.rect(ci, Rect2(bp.x - 3.0, bp.y + 0.2, 6.0, 1.0), Palette.TEAL_DARK)
	U.arc(ci, bp + Vector2(0, -3.6), 3.2, PI, TAU, Palette.STEEL, 0.9, 6)
	U.ellipse(ci, bp + Vector2(0, -3.4), 3.0, 0.8, Color(0.85, 0.97, 1.0))


static func _mechanic_tool(ci: CanvasItem, moving: bool, working: bool, t: float) -> void:
	var hand := Vector2(8.6, -8.0)
	var ang := -0.6
	if working:
		ang = -0.2 + sin(t * 9.0) * 0.6
	elif moving:
		ang = -0.9
	var prev := U.xf_push(ci, hand, ang, Vector2.ONE)
	U.capsule(ci, Vector2(0, 0), Vector2(0, -11), 1.3, Palette.STEEL_DARK)
	U.capsule(ci, Vector2(0, 0), Vector2(0, -10.5), 0.9, Palette.STEEL)
	U.arc(ci, Vector2(0, -12.5), 2.6, PI * 1.5 + 0.7, PI * 1.5 + TAU - 0.7, Palette.STEEL_DARK, 2.0, 8)
	U.arc(ci, Vector2(0, -12.5), 2.6, PI * 1.5 + 0.7, PI * 1.5 + TAU - 0.7, Palette.STEEL, 1.4, 8)
	U.xf_load(ci, prev)


## Medic: white first-aid case with a red cross in the front hand (lifted while treating).
static func _medic_bag(ci: CanvasItem, moving: bool, working: bool, t: float) -> void:
	var bp := Vector2(11.0, -3.4)
	if moving:
		bp.y -= 1.0
	if working:
		bp += Vector2(1.5, -3.5 + sin(t * 5.0) * 0.6)
	U.arc(ci, bp + Vector2(0, -3.4), 2.6, PI, TAU, Palette.STEEL_DARK, 1.0, 8)
	U.rr(ci, Rect2(bp.x - 4.4, bp.y - 3.4, 8.8, 7.0), 1.8, Color("B8C6D8"))
	U.rr(ci, Rect2(bp.x - 4.4, bp.y - 3.6, 8.8, 6.4), 1.8, Color.WHITE)
	U.rect(ci, Rect2(bp.x - 3.8, bp.y - 0.9, 7.6, 1.4), Palette.CORAL)
	U.rect(ci, Rect2(bp.x - 0.8, bp.y - 2.9, 1.6, 5.0), Palette.CORAL)
	U.rect(ci, Rect2(bp.x - 3.6, bp.y - 3.2, 7.2, 1.0), Color(1, 1, 1, 0.8))


## Entertainer: three balls. Juggled in an arc above the head while performing, one ball in hand otherwise.
static func _juggle(ci: CanvasItem, performing: bool, moving: bool, t: float, ph: float) -> void:
	var ball_cols: Array[Color] = [Palette.CORAL, Palette.SUN, Palette.TEAL]
	if not performing:
		var bp := Vector2(10.4, -4.8 - (1.0 if moving else 0.0))
		U.circ(ci, bp, 2.8, Palette.CORAL_DARK)
		U.circ(ci, bp + Vector2(-0.2, -0.2), 2.5, Palette.CORAL)
		U.circ(ci, bp + Vector2(-0.9, -1.1), 0.8, Color(1, 1, 1, 0.7))
		return
	for i in range(3):
		var p := fmod(t * 1.15 + float(i) / 3.0, 1.0)
		var dir := 1.0 if (int(floor(t * 1.15 + float(i) / 3.0)) % 2 == 0) else -1.0
		var x := dir * (-7.5 + 15.0 * p)
		var y := -22.0 - 14.0 * 4.0 * p * (1.0 - p)
		var c: Color = ball_cols[i]
		U.circ(ci, Vector2(x, y) + Vector2(0.3, 0.5), 3.0, Color(0.1, 0.1, 0.2, 0.18))
		U.circ(ci, Vector2(x, y), 3.0, Palette.shade(c, 0.28))
		U.circ(ci, Vector2(x - 0.2, y - 0.2), 2.7, c)
		U.circ(ci, Vector2(x - 1.0, y - 1.1), 0.9, Color(1, 1, 1, 0.75))


## Chef: a ladle in the front hand (stirring while cooking).
static func _chef_ladle(ci: CanvasItem, moving: bool, cooking: bool, t: float) -> void:
	var hand := Vector2(9.0, -7.0)
	var ang := 0.5
	if cooking:
		ang = 0.9 + sin(t * 4.5) * 0.35
	elif moving:
		ang = 0.2
	var prev := U.xf_push(ci, hand, ang, Vector2.ONE)
	U.capsule(ci, Vector2(0, 0), Vector2(0, -13.0), 0.9, Palette.WOOD_DARK)
	U.capsule(ci, Vector2(0, 0), Vector2(0, -12.6), 0.5, Palette.WOOD_LIGHT)
	U.ellipse(ci, Vector2(0, -14.4), 2.8, 2.4, Palette.STEEL_DARK)
	U.ellipse(ci, Vector2(0, -14.2), 2.2, 1.8, Palette.STEEL)
	U.ellipse(ci, Vector2(-0.6, -14.8), 0.9, 0.6, Color(1, 1, 1, 0.7))
	U.xf_load(ci, prev)


## Chef at the stove: a little pot with steam in front of the feet.
static func _steam_pot(ci: CanvasItem, feet: Vector2, sc: float, facing: float, t: float) -> void:
	var c := feet + Vector2(facing * 15.0, -1.0) * sc
	U.ellipse(ci, c + Vector2(0, 0.8 * sc), 6.5 * sc, 1.9 * sc, Color(0.1, 0.12, 0.25, 0.2))
	U.rr(ci, Rect2(c.x - 5.4 * sc, c.y - 8.0 * sc, 10.8 * sc, 8.6 * sc), 2.2 * sc, Palette.STEEL_DARK)
	U.rr(ci, Rect2(c.x - 5.0 * sc, c.y - 7.8 * sc, 10.0 * sc, 7.2 * sc), 2.0 * sc, Palette.STEEL)
	U.rect(ci, Rect2(c.x - 5.0 * sc, c.y - 7.8 * sc, 10.0 * sc, 1.4 * sc), Color(1, 1, 1, 0.45))
	U.ellipse(ci, c + Vector2(0, -8.0 * sc), 5.0 * sc, 1.5 * sc, Color("C95F3B"))
	U.rr(ci, Rect2(c.x - 7.4 * sc, c.y - 6.0 * sc, 2.2 * sc, 1.6 * sc), 0.8 * sc, Palette.STEEL_DARK)
	U.rr(ci, Rect2(c.x + 5.2 * sc, c.y - 6.0 * sc, 2.2 * sc, 1.6 * sc), 0.8 * sc, Palette.STEEL_DARK)
	_steam(ci, c + Vector2(0, -9.0 * sc), t)


## Warden: a staff in the front hand with a hanging lantern.
static func _warden_staff(ci: CanvasItem, moving: bool, working: bool, t: float) -> void:
	var hand := Vector2(10.2, -8.5)
	var ang := 0.05 + (sin(t * 6.0) * 0.04 if moving else 0.0)
	var h := 22.0
	if working:
		ang = 0.22
		h = 24.0
	var prev := U.xf_push(ci, hand, ang, Vector2.ONE)
	U.capsule(ci, Vector2(0, 5.0), Vector2(0, -h), 0.95, Palette.WOOD_DARK)
	U.capsule(ci, Vector2(0, 5.0), Vector2(0, -h), 0.5, Palette.WOOD)
	U.arc(ci, Vector2(1.6, -h), 1.8, PI, TAU + 0.6, Palette.WOOD_DARK, 1.0, 8)
	# lantern body
	var lc := Vector2(3.4, -h + 3.4)
	var flick := 0.88 + 0.12 * sin(t * 11.0 + 1.3)
	U.rr(ci, Rect2(lc.x - 3.0, lc.y - 3.4, 6.0, 1.4), 0.6, Palette.STEEL_DARK)
	U.rr(ci, Rect2(lc.x - 3.0, lc.y + 2.6, 6.0, 1.4), 0.6, Palette.STEEL_DARK)
	U.rr(ci, Rect2(lc.x - 2.6, lc.y - 2.2, 5.2, 5.0), 1.4, Color(1.0, 0.86, 0.45, 0.55 + 0.4 * flick))
	U.circ(ci, lc + Vector2(0, 0.2), 1.9 * flick, Color(1.0, 0.98, 0.8))
	U.line(ci, Vector2(lc.x, lc.y - 2.0), Vector2(lc.x, lc.y + 2.6), Palette.STEEL_DARK, 0.6)
	U.xf_load(ci, prev)


## Soft glow around the lantern (drawn in un-rotated space, behind the bean).
static func _warden_glow(ci: CanvasItem, feet: Vector2, sc: float, facing: float, working: bool, t: float, ph: float) -> void:
	var h := 24.0 if working else 22.0
	var lc := feet + Vector2(facing * (10.2 + (5.4 if working else 3.4)), -8.5 - h + 3.6) * sc
	var flick := 0.88 + 0.12 * sin(t * 11.0 + 1.3 + ph)
	var big := (17.0 if working else 12.0) * sc * flick
	U.circ(ci, lc, big, Color(1.0, 0.86, 0.45, 0.10))
	U.circ(ci, lc, big * 0.68, Color(1.0, 0.88, 0.5, 0.14))
	U.circ(ci, lc, big * 0.38, Color(1.0, 0.92, 0.6, 0.22))
