class_name Palette
extends RefCounted
## Colour palette for the whole game (SPEC §6). Flat, sunny, toy-like.
##
## API
##   Palette.NAVY / HULL_WHITE / CORAL / SUN / TEAL / SEA_DEEP / MINT / LILAC / INK / CREAM ... (constants)
##   Palette.dest(id: StringName) -> Dictionary   # per-destination sky/sea/scenery colours (cached)
##   Palette.shade(c: Color, amount: float) -> Color   # cool darker version (amount 0..1)
##   Palette.tint(c: Color, amount: float) -> Color    # warm lighter version (amount 0..1)
##   Palette.alpha(c: Color, a: float) -> Color
##   Palette.problem_color(kind: StringName, colorblind: bool) -> Color
##   Palette.alert_color(colorblind: bool) -> Color    # the shared "needs you" ring colour
##   Palette.archetype_color(id: StringName) -> Color  # default bean body colours

# ---- core brand colours -------------------------------------------------------------------------
const NAVY := Color("2B3A55")
const NAVY_LIGHT := Color("3D5073")
const NAVY_DARK := Color("1F2A40")
const HULL_WHITE := Color("F7F4EC")
const CORAL := Color("E8505B")
const CORAL_DARK := Color("C23B49")
const CORAL_LIGHT := Color("FF8B8F")
const SUN := Color("FFC857")
const SUN_DEEP := Color("F2A93B")
const TEAL := Color("3AA0C8")
const TEAL_DARK := Color("2A7FA6")
const TEAL_LIGHT := Color("8FD3EC")
const SEA_DEEP := Color("1F6F99")
const MINT := Color("7ED6A5")
const MINT_DARK := Color("4DB583")
const LILAC := Color("B39DDB")
const LILAC_DARK := Color("8A72BD")
const INK := Color("1E2433")
const CREAM := Color("FFF8EC")
const CREAM_DARK := Color("F2E6D0")
const PEACH := Color("FFB88C")
const PINK := Color("FF9EB5")
const ORANGE := Color("F58A3C")
const WOOD := Color("C98B54")
const WOOD_DARK := Color("A56A3A")
const WOOD_LIGHT := Color("E3AE7A")
const SKY_BLUE := Color("8EDBFF")
const STEEL := Color("9AA8BD")
const STEEL_DARK := Color("6F7E96")
const GOLD := Color("FFD36E")
const WHITE := Color("FFFFFF")
const GLASS := Color("BFEAFB")

# Wall colour per room id: {wall, accent} used by RoomArt (SPEC RoomDef.colors are only hints).
const ROOM_COLORS: Dictionary = {
	&"cabin": {"wall": Color("F6D9C8"), "accent": Color("E8505B")},
	&"buffet": {"wall": Color("FFE8B8"), "accent": Color("F58A3C")},
	&"toilets": {"wall": Color("CFEFF2"), "accent": Color("3AA0C8")},
	&"bar": {"wall": Color("7A4F6D"), "accent": Color("FFC857")},
	&"pool": {"wall": Color("BFEAFB"), "accent": Color("3AA0C8")},
	&"deck_chairs": {"wall": Color("FFF1CC"), "accent": Color("E8505B")},
	&"cinema": {"wall": Color("4A4570"), "accent": Color("B39DDB")},
	&"gym": {"wall": Color("D9EBFF"), "accent": Color("3AA0C8")},
	&"arcade": {"wall": Color("3B3566"), "accent": Color("FF6FA8")},
	&"restaurant": {"wall": Color("F7E0D2"), "accent": Color("C23B49")},
	&"medbay": {"wall": Color("E6F6F2"), "accent": Color("E8505B")},
	&"sauna": {"wall": Color("D9A066"), "accent": Color("FFC857")},
	&"ice_rink": {"wall": Color("DDF3FF"), "accent": Color("3AA0C8")},
	&"casino": {"wall": Color("45306B"), "accent": Color("7ED6A5")},
	&"stairs": {"wall": Color("EDE3D2"), "accent": Color("3AA0C8")},
	&"elevator": {"wall": Color("DCE4EE"), "accent": Color("3AA0C8")},
	&"generator": {"wall": Color("FFE3A6"), "accent": Color("F58A3C")},
	&"water_tank": {"wall": Color("CDEBF7"), "accent": Color("3AA0C8")},
}

# Interior structure colours (ShipArt)
const WALL_MAIN := Color("FBF3E4")
const WALL_ALT := Color("F4E9D6")
const WALL_SEAM := Color("E6D8BF")
const CEILING_TRIM := Color("3D5073")
const FLOOR_TOP := Color("D9B58B")
const FLOOR_FRONT := Color("B98F63")
const CARPET := Color("E8505B")
const CARPET_ALT := Color("FFC857")
# Empty (unbuilt) deck cells: deliberately calm / low-saturation so built rooms pop.
const EMPTY_WALL_TOP := Color("EFEADF")
const EMPTY_WALL_BOT := Color("E2DBCD")
const EMPTY_SEAM := Color("D3CBBB")
const EMPTY_FLOOR_TOP := Color("D3BFA3")
const EMPTY_FLOOR_FRONT := Color("B8A183")
const EMPTY_RUNNER := Color("A9B8C6")
const EMPTY_RUNNER_ALT := Color("C3CEDA")

# ---- destination palettes -----------------------------------------------------------------------
const _DEST: Dictionary = {
	&"med": {
		"sky_top": Color("7FD0F5"), "sky_mid": Color("C6E9F8"), "sky_bottom": Color("FFD9B0"),
		"sun": Color("FFE08A"), "sun_glow": Color("FFF0BF"),
		"cloud": Color("FFFFFF"), "cloud_shade": Color("FFE9D6"),
		"sea_top": Color("39B0D6"), "sea_bottom": Color("1B6E9C"),
		"wave_far": Color("5CC3E0"), "wave_mid": Color("2FA3CC"), "wave_near": Color("1F86B3"),
		"wave_front": Color("1A78A6"), "foam": Color("EAF9FF"), "sparkle": Color("FFFFFF"),
		"far_land": Color("A9D9C6"), "land": Color("8CCB8E"), "land_dark": Color("63AE78"),
		"rock": Color("E3C9A4"), "village_wall": Color("FFFDF6"), "village_roof": Color("E8505B"),
		"village_roof2": Color("3AA0C8"), "accent": Color("FFC857"),
	},
	&"arctic": {
		"sky_top": Color("BFAEE8"), "sky_mid": Color("D8D8F6"), "sky_bottom": Color("EAF6FF"),
		"sun": Color("FFF6E0"), "sun_glow": Color("F5F0FF"),
		"cloud": Color("F6F2FF"), "cloud_shade": Color("D6D0F0"),
		"sea_top": Color("7EC3E6"), "sea_bottom": Color("2D6F9E"),
		"wave_far": Color("9FD6F0"), "wave_mid": Color("6DB8E0"), "wave_near": Color("4A9BCB"),
		"wave_front": Color("3A8CBF"), "foam": Color("F4FBFF"), "sparkle": Color("FFFFFF"),
		"far_land": Color("C7D5F0"), "land": Color("EAF3FF"), "land_dark": Color("B9D2F0"),
		"rock": Color("93A9CC"), "village_wall": Color("FFFFFF"), "village_roof": Color("E8505B"),
		"village_roof2": Color("3AA0C8"), "accent": Color("7ED6A5"),
		"aurora1": Color("7ED6A5"), "aurora2": Color("66D9E8"), "aurora3": Color("B39DDB"),
	},
	&"underworld": {
		"sky_top": Color("2B1650"), "sky_mid": Color("6B2B7F"), "sky_bottom": Color("D9548F"),
		"sun": Color("F7D6F0"), "sun_glow": Color("FF9CCB"),
		"cloud": Color("8E4B9E"), "cloud_shade": Color("5C2D78"),
		"sea_top": Color("3C2A7A"), "sea_bottom": Color("160F3A"),
		"wave_far": Color("5B3E9E"), "wave_mid": Color("472F8A"), "wave_near": Color("33236F"),
		"wave_front": Color("2A1D5E"), "foam": Color("D9C2FF"), "sparkle": Color("C8FFE0"),
		"far_land": Color("5A2E78"), "land": Color("3E2055"), "land_dark": Color("2A1440"),
		"rock": Color("4B2A66"), "village_wall": Color("FFE9A8"), "village_roof": Color("E8505B"),
		"village_roof2": Color("3AA0C8"), "accent": Color("7DFFB0"),
		"lantern": Color("FFB347"), "wisp": Color("8BFFC2"),
	},
}


## Per-destination palette dictionary (keys: sky_top, sky_mid, sky_bottom, sun, sea_top, sea_bottom,
## wave_far/mid/near/front, foam, far_land, land, rock, accent, ... see _DEST). Unknown id -> med.
static func dest(id: StringName) -> Dictionary:
	return _DEST.get(id, _DEST[&"med"])


## Cool darker version of c (shadow). amount 0..1.
static func shade(c: Color, amount: float) -> Color:
	var d := c.lerp(Color(0.16, 0.2, 0.38, c.a), amount * 0.9)
	d.a = c.a
	return d


## Warm lighter version of c (highlight). amount 0..1.
static func tint(c: Color, amount: float) -> Color:
	var l := c.lerp(Color(1.0, 0.97, 0.88, c.a), amount)
	l.a = c.a
	return l


static func alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


# Problem / status icon colours: normal vs colourblind-safe (blue / orange / white / black).
const _PROBLEM: Dictionary = {
	&"mess": [Color("8B5E3C"), Color("0072B2")],
	&"breakdown": [Color("F58A3C"), Color("E69F00")],
	&"sick": [Color("5DC57A"), Color("FFFFFF")],
	&"angry": [Color("E8505B"), Color("000000")],
	&"ghost": [Color("F4F1FF"), Color("56B4E9")],
}


static func problem_color(kind: StringName, colorblind: bool = false) -> Color:
	var pair: Array = _PROBLEM.get(kind, [Color.WHITE, Color.WHITE])
	return pair[1 if colorblind else 0]


## Colour of the soft pulsing "needs you" ring / outline shared by every problem marker (mess, broken room,
## sick, angry, ghost, long queue): coral normally, vermillion in colourblind mode.
static func alert_color(colorblind: bool = false) -> Color:
	return Color("D55E00") if colorblind else CORAL


## Default body colours for guest archetypes.
static func archetype_color(id: StringName) -> Color:
	match id:
		&"holidaymaker": return Color("FFB347")
		&"fitness_fan": return Color("6EC6A5")
		&"film_buff": return Color("A58BE0")
		&"gamer": return Color("FF7FA8")
	return Color("F2B880")
