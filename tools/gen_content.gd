extends SceneTree
## One-off content bootstrap. Writes every .tres under res://data from the tables below.
## Run: godot --headless --path . --script res://tools/gen_content.gd
## After running, the .tres files are the source of truth for designers; re-running overwrites them,
## so the balance pass edits THESE TABLES and regenerates.

const OUT: String = "res://data"

var _count: int = 0

# Star goals per level (index = campaign level - 1): [[type, value] x 3], produced by
# tests/balance.gd + tests/goals.py from the passive / human / active AutoPlayer runs:
#   goal 1 is a rating goal just under the passive mean (passive earns ~1 star),
#   goal 2 sits around human play, goal 3 needs active-level play (rating, profit, served or no-lost).
const GOALS: Array = [
	[["rating", 45], ["served", 45], ["no_lost_guests", 0]],
	[["rating", 56], ["rating", 78], ["served", 70]],
	[["rating", 42], ["rating", 73], ["no_lost_guests", 0]],
	[["rating", 41], ["rating", 62], ["no_lost_guests", 0]],
	[["rating", 40], ["served", 130], ["rating", 77]],
	[["rating", 29], ["rating", 62], ["served", 160]],
	[["rating", 38], ["rating", 59], ["no_lost_guests", 0]],
	[["rating", 40], ["served", 170], ["rating", 82]],
	[["rating", 31], ["rating", 47], ["served", 210]],
	[["rating", 29], ["profit", 1650], ["rating", 65]],
	[["rating", 46], ["served", 240], ["rating", 74]],
	[["rating", 30], ["rating", 53], ["served", 240]],
	[["rating", 21], ["profit", 1800], ["rating", 52]],
	[["rating", 32], ["served", 220], ["rating", 74]],
	[["rating", 27], ["rating", 52], ["served", 260]],
	[["rating", 33], ["profit", 3250], ["rating", 66]],
	[["rating", 39], ["served", 300], ["rating", 62]],
	[["rating", 33], ["rating", 45], ["served", 360]],
]


func _init() -> void:
	for sub in ["rooms", "archetypes", "staff", "events", "destinations", "hulls", "levels"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/%s" % [OUT, sub]))
	_gen_rooms()
	_gen_archetypes()
	_gen_staff()
	_gen_events()
	_gen_destinations()
	_gen_hulls()
	_gen_levels()
	print("gen_content: wrote %d resources" % _count)
	quit()


func _save(res: Resource, sub: String, id: String) -> void:
	var path := "%s/%s/%s.tres" % [OUT, sub, id]
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("gen_content: failed to save %s (%d)" % [path, err])
	else:
		_count += 1


# ---------------------------------------------------------------------------------------------
# Rooms
# ---------------------------------------------------------------------------------------------
## Balance pass 2: rooms are tighter than the SPEC table (capacity / service time) so queues actually
## form and upgrades matter. id -> [capacity, service_time]. Everything else follows the SPEC table.
const TIGHTER: Dictionary = {
	"buffet": [4, 8.0], "toilets": [2, 6.0], "bar": [4, 9.0], "pool": [6, 11.0], "deck_chairs": [3, 9.0],
	"cinema": [6, 13.0], "gym": [3, 9.0], "arcade": [3, 8.0], "restaurant": [3, 10.0], "sauna": [2, 8.0],
	"ice_rink": [5, 10.0], "casino": [4, 10.0],
}


func _room(id: String, name: String, cat: String, w: int, cap: int, svc: float, sat: Dictionary,
		tag: String, spend: int, cost: int, upkeep: float, pwr: int, wtr: int, place: String,
		mess: float, brk: float, wear: float, unlock: int, dlock: String, appeal: float,
		desc: String, wall: Color, accent: Color, tiers: bool = true, sick: float = 0.0) -> void:
	if TIGHTER.has(id):
		cap = int(TIGHTER[id][0])
		svc = float(TIGHTER[id][1])
	var r := RoomDef.new()
	r.id = StringName(id)
	r.display_name = name
	r.category = StringName(cat)
	r.width = w
	r.capacity = cap
	r.service_time = svc
	r.satisfies = sat
	r.fun_tag = StringName(tag)
	r.appeal = appeal
	r.spend = spend
	r.cost = cost
	r.upkeep = upkeep
	r.power = pwr
	r.water = wtr
	r.placement = StringName(place)
	r.mess_chance = mess
	r.breakdown_time = brk
	r.wear_per_use = wear
	r.unlock_level = unlock
	r.destination_lock = StringName(dlock)
	r.description = desc
	r.sick_chance = sick
	r.colors = {"wall": wall, "accent": accent}
	var bonus: Array[Dictionary] = []
	if tiers and cap > 0:
		var add: int = ceili(cap * 0.5)
		bonus.append({"cost": int(round(cost * 0.6)), "capacity_add": add, "speed_mult": 1.0})
		bonus.append({"cost": int(round(cost * 0.9)), "capacity_add": add, "speed_mult": 1.25})
	r.tier_bonus = bonus
	_save(r, "rooms", id)


func _gen_rooms() -> void:
	_room("cabin", "Cabin", "rest", 2, 4, 9.0, {&"rest": 90.0, &"hygiene": 15.0}, "relax", 0, 120, 2.0, 0, 1,
		"interior", 0.0, 0.0, 0.0, 1, "", 1.0, "Bunks for four sleepy guests.",
		Color("#E9DCC8"), Color("#B39DDB"))
	_room("buffet", "Buffet", "food", 4, 6, 7.0, {&"hunger": 85.0}, "", 4, 300, 6.0, 3, 2,
		"interior", 0.22, 110.0, 5.0, 1, "", 1.0, "All-you-can-eat. Messy.",
		Color("#FBE3B8"), Color("#E8505B"), true, 0.015)
	_room("toilets", "Toilets", "hygiene", 2, 3, 5.0, {&"hygiene": 90.0}, "", 0, 120, 3.0, 0, 3,
		"interior", 0.25, 90.0, 6.0, 1, "", 1.0, "Three stalls. Never enough.",
		Color("#CFE8F0"), Color("#3AA0C8"))
	_room("bar", "Bar", "fun", 3, 5, 8.0, {&"fun": 70.0}, "relax", 9, 250, 5.0, 2, 1,
		"interior", 0.18, 100.0, 5.0, 1, "", 1.0, "Cocktails and chatter.",
		Color("#F1D2B6"), Color("#FFC857"))
	_room("pool", "Pool", "fun", 6, 8, 10.0, {&"fun": 60.0, &"hygiene": 35.0}, "water", 3, 500, 8.0, 2, 5,
		"top_deck", 0.12, 130.0, 4.0, 1, "", 1.1, "Splash! Top deck only.",
		Color("#BFE6F5"), Color("#3AA0C8"))
	_room("deck_chairs", "Deck Chairs", "rest", 3, 4, 9.0, {&"rest": 55.0, &"fun": 30.0}, "relax", 0, 150, 1.0, 0, 0,
		"top_deck", 0.06, 0.0, 0.0, 1, "", 0.8, "Sun loungers under umbrellas.",
		Color("#FFE9B0"), Color("#E8505B"))
	_room("cinema", "Cinema", "fun", 4, 8, 12.0, {&"fun": 90.0}, "movies", 6, 400, 7.0, 4, 0,
		"interior", 0.10, 120.0, 4.0, 2, "", 1.0, "Popcorn and plot twists.",
		Color("#3B3358"), Color("#B39DDB"))
	_room("gym", "Gym", "fun", 3, 4, 9.0, {&"fun": 75.0}, "fitness", 3, 300, 5.0, 2, 1,
		"interior", 0.15, 95.0, 6.0, 3, "", 0.9, "Treadmills with a sea view.",
		Color("#D6EDDD"), Color("#7ED6A5"))
	_room("medbay", "Medbay", "service", 2, 2, 6.0, {}, "", 5, 300, 6.0, 2, 1,
		"interior", 0.0, 0.0, 0.0, 3, "", 1.0, "Cures seasickness and dodgy shrimp.",
		Color("#F7F4EC"), Color("#E8505B"), false)
	_room("arcade", "Arcade", "fun", 3, 4, 8.0, {&"fun": 85.0}, "gaming", 8, 350, 6.0, 4, 0,
		"interior", 0.08, 85.0, 6.0, 4, "", 1.0, "Beeps, boops and high scores.",
		Color("#2B3A55"), Color("#7ED6A5"))
	_room("restaurant", "Restaurant", "food", 4, 4, 10.0, {&"hunger": 100.0, &"fun": 20.0}, "", 16, 450, 8.0, 3, 2,
		"interior", 0.12, 120.0, 5.0, 5, "", 1.1, "Candlelit tables, white tablecloths.",
		Color("#F6DCCB"), Color("#E8505B"), true, 0.006)
	_room("sauna", "Sauna", "rest", 2, 3, 8.0, {&"rest": 50.0, &"hygiene": 60.0}, "relax", 5, 280, 5.0, 3, 2,
		"interior", 0.10, 100.0, 5.0, 4, "med", 0.9, "Steamy relaxation.",
		Color("#D9A877"), Color("#FFC857"))
	_room("ice_rink", "Ice Rink", "fun", 5, 6, 10.0, {&"fun": 90.0}, "", 7, 600, 9.0, 5, 2,
		"interior", 0.10, 110.0, 5.0, 7, "arctic", 1.0, "Skate in circles. Happily.",
		Color("#DDF2FA"), Color("#3AA0C8"))
	_room("casino", "Casino", "fun", 4, 6, 10.0, {&"fun": 95.0}, "gaming", 14, 650, 9.0, 4, 1,
		"interior", 0.12, 100.0, 5.0, 13, "underworld", 1.1, "Fortunes won, souls wagered.",
		Color("#2D6A4F"), Color("#B39DDB"))
	_room("stairs", "Stairs", "transport", 1, 0, 0.0, {}, "", 0, 60, 0.0, 0, 0,
		"any", 0.0, 0.0, 0.0, 1, "", 1.0, "Connects two decks.",
		Color("#C9B8A0"), Color("#2B3A55"), false)
	_room("elevator", "Elevator", "transport", 1, 4, 0.0, {}, "", 0, 400, 4.0, 2, 0,
		"any", 0.0, 0.0, 0.0, 7, "", 1.0, "Connects every deck. Carries four.",
		Color("#B8C4D0"), Color("#FFC857"), false)
	_room("generator", "Generator", "utility", 1, 0, 0.0, {}, "", 0, 200, 3.0, -8, 0,
		"interior", 0.0, 0.0, 0.0, 3, "", 1.0, "Supplies 8 power.",
		Color("#9AA5B1"), Color("#FFC857"), false)
	_room("water_tank", "Water Tank", "utility", 1, 0, 0.0, {}, "", 0, 180, 2.0, 0, -8,
		"interior", 0.0, 0.0, 0.0, 3, "", 1.0, "Supplies 8 water.",
		Color("#8FC7E3"), Color("#1F6F99"), false)


# ---------------------------------------------------------------------------------------------
# Archetypes / staff / hulls
# ---------------------------------------------------------------------------------------------
func _gen_archetypes() -> void:
	var a := ArchetypeDef.new()
	a.id = &"holidaymaker"
	a.display_name = "Holidaymaker"
	a.prop = &"sun_hat"
	a.body_color = Color("#FFC857")
	a.favorite_tags = [&"relax", &"water"]
	a.favorite_rooms = [&"pool", &"deck_chairs", &"bar"]
	a.quirk_text = "Balanced: loves the pool, the bar and a good sunbed."
	_save(a, "archetypes", "holidaymaker")

	a = ArchetypeDef.new()
	a.id = &"fitness_fan"
	a.display_name = "Fitness Fan"
	a.prop = &"headband"
	a.body_color = Color("#7ED6A5")
	a.favorite_tags = [&"fitness"]
	a.favorite_rooms = [&"gym", &"pool"]
	a.decay_mult = {&"hunger": 1.5}
	a.quirk_text = "Gets hungry 50% faster."
	_save(a, "archetypes", "fitness_fan")

	a = ArchetypeDef.new()
	a.id = &"film_buff"
	a.display_name = "Film Buff"
	a.prop = &"glasses_3d"
	a.body_color = Color("#B39DDB")
	a.favorite_tags = [&"movies"]
	a.favorite_rooms = [&"cinema"]
	a.patience_mult_non_favorite = 0.6
	a.quirk_text = "Loses patience 40% faster in any queue but the cinema's."
	_save(a, "archetypes", "film_buff")

	a = ArchetypeDef.new()
	a.id = &"gamer"
	a.display_name = "Gamer"
	a.prop = &"headphones"
	a.body_color = Color("#3AA0C8")
	a.favorite_tags = [&"gaming"]
	a.favorite_rooms = [&"arcade", &"casino"]
	a.off_tag_fun_decay_mult = 2.0
	a.quirk_text = "Gets bored twice as fast unless playing games."
	_save(a, "archetypes", "gamer")


func _gen_staff() -> void:
	var s := StaffDef.new()
	s.id = &"janitor"
	s.display_name = "Janitor"
	s.handles = &"mess"
	s.wage = 40
	s.work_time = 3.5
	s.speed = 2.6
	_save(s, "staff", "janitor")
	s = StaffDef.new()
	s.id = &"mechanic"
	s.display_name = "Mechanic"
	s.handles = &"breakdown"
	s.wage = 60
	s.work_time = 7.0
	s.speed = 2.6
	_save(s, "staff", "mechanic")


func _gen_hulls() -> void:
	_hull("small", "Pocket Cruiser", 24, 4, 1, 16, 16, 4)
	_hull("medium", "Coastal Liner", 32, 5, 1, 26, 24, 6)
	_hull("large", "Grand Liner", 40, 6, 1, 38, 34, 8)


func _hull(id: String, name: String, w: int, decks: int, gw: int, pwr: int, wtr: int, staff: int) -> void:
	var h := HullDef.new()
	h.id = StringName(id)
	h.display_name = name
	h.width = w
	h.decks = decks
	h.gangway_deck = gw
	h.power = pwr
	h.water = wtr
	h.max_staff = staff
	_save(h, "hulls", id)


# ---------------------------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------------------------
func _event(id: String, name: String, desc: String, dur: float, icon: String, dlock: String = "") -> EventDef:
	var e := EventDef.new()
	e.id = StringName(id)
	e.display_name = name
	e.description = desc
	e.duration = dur
	e.icon = StringName(icon)
	e.destination_lock = StringName(dlock)
	return e


func _gen_events() -> void:
	var e := _event("film_night", "Film Night", "The cinema is the place to be. Everyone fancies a movie.", 60.0, "film")
	e.room_appeal_mult = {&"cinema": 2.5}
	e.need_set = {&"fun": 45.0}
	_save(e, "events", "film_night")

	e = _event("lunch_rush", "Lunch Rush", "Everyone is suddenly starving!", 0.0, "fork")
	e.need_set = {&"hunger": 20.0}
	_save(e, "events", "lunch_rush")

	e = _event("pool_party", "Pool Party", "The top deck is the place to be. Expect a mess.", 45.0, "sun")
	e.room_appeal_mult = {&"top_deck": 1.5}
	e.mess_mult_top_deck = 2.0
	_save(e, "events", "pool_party")

	e = _event("food_poisoning", "Food Poisoning", "Something was off in the shrimp.", 0.0, "skull_drop")
	e.sick_count = 3
	_save(e, "events", "food_poisoning")

	e = _event("power_surge", "Power Surge", "Lights flicker. Two machines give up.", 0.0, "bolt")
	e.break_count = 2
	_save(e, "events", "power_surge")

	e = _event("captains_dinner", "Captain's Dinner", "The restaurant is the place to be. Full tables delight guests.", 60.0, "star")
	e.room_appeal_mult = {&"restaurant": 3.0}
	e.full_room_bonus = {&"restaurant": 10.0}
	_save(e, "events", "captains_dinner")

	e = _event("northern_lights", "Northern Lights", "Everyone rushes to the top deck to watch the sky dance.", 40.0, "aurora", "arctic")
	e.room_appeal_mult = {&"top_deck": 2.5}
	e.top_deck_rush = true
	e.top_deck_fun_rate = 1.5
	e.suspend_cold = true
	_save(e, "events", "northern_lights")

	e = _event("haunting", "Haunting", "Four ghosts materialise at once. Click them away!", 0.0, "ghost", "underworld")
	e.ghost_count = 4
	_save(e, "events", "haunting")

	e = _event("heat_wave", "Heat Wave", "Sticky guests crowd the pool.", 50.0, "thermo", "med")
	e.hygiene_decay_mult = 1.8
	e.room_appeal_mult = {&"pool": 2.0}
	_save(e, "events", "heat_wave")


# ---------------------------------------------------------------------------------------------
# Destinations
# ---------------------------------------------------------------------------------------------
func _gen_destinations() -> void:
	var d := DestinationDef.new()
	d.id = &"med"
	d.display_name = "Mediterranean"
	d.stars_required = 0
	d.sky_top = Color("#7CC7F0")
	d.sky_bottom = Color("#FFD9B8")
	d.sea = Color("#3AA0C8")
	d.twist_text = "Sun-baked decks: guests get grubby 25% faster and everyone loves the pool."
	d.hygiene_decay_mult = 1.25
	d.pool_appeal_mult = 1.4
	d.random_events = [&"heat_wave"]
	d.new_room = &"sauna"
	_save(d, "destinations", "med")

	d = DestinationDef.new()
	d.id = &"arctic"
	d.display_name = "Arctic"
	d.stars_required = 10
	d.sky_top = Color("#CDBFEF")
	d.sky_bottom = Color("#CFEBFA")
	d.sea = Color("#6AA6D6")
	d.twist_text = "Freezing top deck: outdoor rooms lose appeal and chill guests. Until the aurora shows up."
	d.top_deck_appeal_mult = 0.7
	d.top_deck_satisfaction_drain = 0.25
	d.random_events = [&"northern_lights"]
	d.new_room = &"ice_rink"
	_save(d, "destinations", "arctic")

	d = DestinationDef.new()
	d.id = &"underworld"
	d.display_name = "Underworld"
	d.stars_required = 24
	d.sky_top = Color("#2A1450")
	d.sky_bottom = Color("#B33A8F")
	d.sea = Color("#3A1F5E")
	d.twist_text = "Ghosts drift through the decks, spooking guests and hurrying queues. Banish them!"
	d.ghost_interval = Vector2(25.0, 40.0)
	d.random_events = [&"haunting"]
	d.new_room = &"casino"
	_save(d, "destinations", "underworld")


# ---------------------------------------------------------------------------------------------
# Levels
# ---------------------------------------------------------------------------------------------
## Builds wave dicts: `count` guests split over fractions of the duration.
func _waves(count: int, dur: float, times: Array, fracs: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var left: int = count
	for i in times.size():
		var c: int = int(round(count * float(fracs[i])))
		if i == times.size() - 1:
			c = left
		c = clampi(c, 0, left)
		left -= c
		if c > 0:
			out.append({"t": snappedf(float(times[i]) * dur, 0.5), "count": c})
	return out


func _evs(pairs: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in pairs:
		out.append({"t": float(p[0]), "event": StringName(p[1])})
	return out


func _goal_list(i: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in GOALS[i]:
		var d: Dictionary = {"type": g[0]}
		if String(g[0]) != "no_lost_guests":
			d["value"] = int(g[1])
		out.append(d)
	return out


func _level(id: String, idx: int, cidx: int, name: String, blurb: String, dest: String, hull: String,
		budget: int, ticket: int, dur: float, waves: Array[Dictionary], weights: Dictionary,
		events: Array[Dictionary], rand_interval: float, goals: Array[Dictionary],
		presets: Array[Dictionary] = [], preset_staff: Dictionary = {}, tutorial: bool = false,
		knobs: Dictionary = {}) -> void:
	var l := LevelDef.new()
	l.id = StringName(id)
	l.index = idx
	l.campaign_index = cidx
	l.display_name = name
	l.blurb = blurb
	l.destination = StringName(dest)
	l.hull = StringName(hull)
	l.budget = budget
	l.ticket_price = ticket
	l.duration = dur
	l.waves = waves
	l.archetype_weights = weights
	l.scheduled_events = events
	l.random_event_interval = rand_interval
	l.star_goals = goals
	l.preset_rooms = presets
	l.preset_staff = preset_staff
	l.tutorial = tutorial
	l.mutiny_enabled = not tutorial
	var k: Dictionary = knobs if not knobs.is_empty() else _knobs(cidx)
	l.mess_mult = float(k.get("mess", 1.0))
	l.health_mult = float(k.get("health", 1.0))
	l.decay_mult = float(k.get("decay", 1.0))
	l.patience_mult = float(k.get("patience", 1.0))
	l.ghost_interval_mult = float(k.get("ghost", 1.0))
	_save(l, "levels", id)


## Per-level difficulty knobs [mess, health, decay] produced by tests/tune.gd so that the active
## AutoPlayer lands on the campaign curve (94 -> 78 rating) with a passive gap growing from ~9 to ~22.
## Every level gets its own personality (messy, hungry, fragile...).
const KNOBS: Array = [
	[1.0, 2.2, 1.0], [1.00, 1.00, 1.00], [1.05, 0.96, 1.18], [1.15, 0.87, 1.08], [1.19, 0.84, 1.12], [1.24, 0.81, 0.96],
	[1.27, 0.79, 1.20], [1.19, 0.84, 1.20], [1.18, 0.85, 1.20], [1.21, 0.83, 1.12], [1.25, 0.80, 1.10], [1.41, 0.71, 0.80],
	[1.14, 0.88, 1.14], [1.25, 0.80, 1.20], [1.30, 0.77, 1.20], [1.35, 0.74, 1.05], [1.40, 0.71, 1.05], [1.50, 0.66, 1.08],
]


func _knobs(cidx: int) -> Dictionary:
	var k: Array = KNOBS[cidx - 1]
	return {"mess": k[0], "health": k[1], "decay": k[2], "patience": 1.2 if cidx == 1 else 1.0}


func _gen_levels() -> void:
	var W_MED: Dictionary = {&"holidaymaker": 0.45, &"fitness_fan": 0.2, &"film_buff": 0.2, &"gamer": 0.15}
	var W_ARC: Dictionary = {&"holidaymaker": 0.25, &"fitness_fan": 0.2, &"film_buff": 0.3, &"gamer": 0.25}
	var W_UND: Dictionary = {&"holidaymaker": 0.2, &"fitness_fan": 0.15, &"film_buff": 0.25, &"gamer": 0.4}
	var TUT_W: Dictionary = {&"holidaymaker": 0.7, &"fitness_fan": 0.1, &"film_buff": 0.1, &"gamer": 0.1}
	var T5: Array = [0.0, 0.14, 0.30, 0.46, 0.62]
	var F5: Array = [0.28, 0.22, 0.20, 0.18, 0.12]
	var T4: Array = [0.0, 0.18, 0.38, 0.58]
	var F4: Array = [0.35, 0.25, 0.22, 0.18]

	# ---- Mediterranean -------------------------------------------------------------------
	var tut_presets: Array[Dictionary] = [
		{"room": &"cabin", "deck": 1, "x": 0, "locked": true},
		{"room": &"toilets", "deck": 1, "x": 2, "locked": true},
		{"room": &"stairs", "deck": 1, "x": 11, "locked": true},
	]
	_level("med_1", 1, 1, "Maiden Voyage", "Learn the ropes with a handful of cheerful passengers.",
		"med", "small", 1700, 20, 180.0, _waves(8, 180.0, [0.0, 0.14], [0.5, 0.5]), TUT_W,
		_evs([[80, "power_surge"], [120, "lunch_rush"]]), 0.0,
		_goal_list(0), tut_presets, {}, true)
	_level("med_2", 2, 2, "Sunny Side Up", "Movie fans come aboard. Give them something to watch.",
		"med", "small", 2500, 20, 180.0, _waves(14, 180.0, T4, F4), W_MED,
		_evs([[70, "film_night"], [115, "lunch_rush"]]), 0.0,
		_goal_list(1))
	_level("med_3", 3, 3, "Lido Rush Hour", "Power and water get tight. Build a generator and a tank.",
		"med", "small", 3200, 22, 200.0, _waves(18, 200.0, T5, F5), W_MED,
		_evs([[70, "lunch_rush"], [110, "pool_party"], [150, "power_surge"]]), 0.0,
		_goal_list(2))
	_level("med_4", 4, 4, "Spa Day at Sea", "Sticky guests, steamy saunas and a little too much shrimp.",
		"med", "medium", 3600, 24, 210.0, _waves(22, 210.0, T5, F5), W_MED,
		_evs([[60, "heat_wave"], [120, "food_poisoning"], [160, "lunch_rush"]]), 0.0,
		_goal_list(3))
	_level("med_5", 5, 5, "Captain's Table", "Fine dining for fussy folk. The captain wants a full house.",
		"med", "medium", 4400, 26, 220.0, _waves(25, 220.0, T5, F5), W_MED,
		_evs([[55, "lunch_rush"], [95, "captains_dinner"], [150, "power_surge"]]), 0.0,
		_goal_list(4))
	_level("med_6", 6, 6, "Mediterranean Meltdown", "Everything happens at once. Hold on to your hat.",
		"med", "medium", 4700, 28, 240.0, _waves(28, 240.0, T5, F5), W_MED,
		_evs([[55, "heat_wave"], [100, "lunch_rush"], [140, "power_surge"], [175, "food_poisoning"]]), 75.0,
		_goal_list(5))

	# ---- Arctic ---------------------------------------------------------------------------
	_level("arctic_1", 1, 7, "Cold Open", "Brr! The top deck is freezing. Keep guests inside, then watch the sky.",
		"arctic", "medium", 3700, 26, 220.0, _waves(24, 220.0, T5, F5), W_ARC,
		_evs([[85, "northern_lights"], [135, "lunch_rush"], [175, "power_surge"]]), 0.0,
		_goal_list(6))
	_level("arctic_2", 2, 8, "Frostbitten Fun", "Skating, popcorn and a surprising number of broken machines.",
		"arctic", "medium", 4300, 27, 230.0, _waves(27, 230.0, T5, F5), W_ARC,
		_evs([[60, "film_night"], [120, "northern_lights"], [170, "power_surge"]]), 0.0,
		_goal_list(7))
	_level("arctic_3", 3, 9, "Whiteout Buffet", "Snowed in with hungry guests. The buffet is in demand.",
		"arctic", "medium", 4600, 28, 240.0, _waves(31, 240.0, T5, F5), W_ARC,
		_evs([[55, "lunch_rush"], [110, "food_poisoning"], [150, "northern_lights"], [195, "power_surge"]]), 0.0,
		_goal_list(8))
	_level("arctic_4", 4, 10, "Penguin Parade", "A bigger crowd and fussier tastes. Keep the rinks spinning.",
		"arctic", "medium", 4800, 29, 250.0, _waves(34, 250.0, T5, F5), W_ARC,
		_evs([[50, "film_night"], [105, "lunch_rush"], [150, "northern_lights"], [195, "power_surge"]]), 90.0,
		_goal_list(9))
	_level("arctic_5", 5, 11, "Polar Express", "Full ship, tight budget, and the temperature keeps dropping.",
		"arctic", "medium", 5000, 30, 260.0, _waves(37, 260.0, T5, F5), W_ARC,
		_evs([[50, "lunch_rush"], [95, "captains_dinner"], [150, "northern_lights"], [195, "food_poisoning"]]), 80.0,
		_goal_list(10))
	_level("arctic_6", 6, 12, "Aurora Gala", "The grand finale of the north. Everyone wants everything.",
		"arctic", "medium", 5200, 32, 270.0, _waves(40, 270.0, T5, F5), W_ARC,
		_evs([[45, "film_night"], [90, "captains_dinner"], [145, "northern_lights"], [190, "power_surge"], [215, "lunch_rush"]]), 75.0,
		_goal_list(11))

	# ---- Underworld -----------------------------------------------------------------------
	_level("underworld_1", 1, 13, "Gloom Cruise", "Spooky! Ghosts drift through the decks. Click them away.",
		"underworld", "medium", 5200, 30, 240.0, _waves(32, 240.0, T5, F5), W_UND,
		_evs([[90, "haunting"], [150, "lunch_rush"], [190, "power_surge"]]), 0.0,
		_goal_list(12))
	_level("underworld_2", 2, 14, "Ferryman's Special", "The guests are dead hungry. The ghosts are dead keen.",
		"underworld", "medium", 5400, 31, 250.0, _waves(36, 250.0, T5, F5), W_UND,
		_evs([[55, "lunch_rush"], [115, "haunting"], [175, "power_surge"]]), 0.0,
		_goal_list(13))
	_level("underworld_3", 3, 15, "Spectral Spa", "A bigger ship at last. Plenty of room for plenty of trouble.",
		"underworld", "large", 6000, 32, 260.0, _waves(40, 260.0, T5, F5), W_UND,
		_evs([[55, "film_night"], [110, "haunting"], [160, "food_poisoning"], [205, "power_surge"]]), 0.0,
		_goal_list(14))
	_level("underworld_4", 4, 16, "Casino of Souls", "High rollers and higher stakes. Watch the slot machines.",
		"underworld", "large", 6600, 34, 270.0, _waves(46, 270.0, T5, F5), W_UND,
		_evs([[50, "lunch_rush"], [100, "haunting"], [150, "captains_dinner"], [205, "power_surge"]]), 90.0,
		_goal_list(15))
	_level("underworld_5", 5, 17, "Haunted Holiday", "Fully booked, fully haunted. Do not panic.",
		"underworld", "large", 7000, 35, 285.0, _waves(51, 285.0, T5, F5), W_UND,
		_evs([[45, "film_night"], [90, "haunting"], [140, "lunch_rush"], [190, "food_poisoning"], [235, "haunting"]]), 85.0,
		_goal_list(16))
	_level("underworld_6", 6, 18, "Crown of Shadows", "The final voyage. Every problem at once, all the way down.",
		"underworld", "large", 7400, 36, 300.0, _waves(56, 300.0, T5, F5), W_UND,
		_evs([[45, "lunch_rush"], [85, "haunting"], [135, "captains_dinner"], [185, "power_surge"], [225, "haunting"], [250, "food_poisoning"]]), 70.0,
		_goal_list(17))
