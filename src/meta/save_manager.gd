extends Node
## SaveManager autoload ("SaveManager") — campaign progress. See docs/SPEC.md §3 and §9.
##
## File: `user://save.json`
##   { "version": 1,
##     "levels": { "<level_id>": {"stars": int, "best_rating": float, "best_profit": int,
##                                "best_payout": int, "plays": int} },
##     "company": {"spent": int, "perks": {"<perk_id>": level}} }
## Company funds (docs/SPEC.md §13.1) = sum of every level's best_payout minus `company.spent`; they can never be farmed
## because only an improvement on a level's best payout is credited. Old saves without these keys load with defaults.
## Unknown top-level keys are preserved on write. Player *preferences* live in Settings
## (`user://settings.cfg`), not here, so resetting progress never touches them.
##
## Writes are atomic (`save.json.tmp` then rename). An unreadable / corrupt file is moved to
## `save.json.corrupt` and the game starts with a fresh save (`last_load_status == &"corrupt"`).
##
## Unlock rules (all data-driven; ContentDB is consulted at runtime when present):
##   * levels unlock sequentially inside a destination (previous level >= 1 star);
##   * destinations unlock by TOTAL stars (DestinationDef.stars_required, else 0 / 10 / 24);
##   * rooms unlock by campaign index (RoomDef.unlock_level) — a room is "reachable" once the
##     highest *playable* level index is >= unlock_level;
##   * tier II upgrades after clearing campaign level 3, tier III after level 9.
## "Cleared" = best result >= 1 star. Debug: launching with `--unlock-all` (user args) makes every
## query report unlocked.

signal progress_changed

const SAVE_VERSION: int = 1
const DEST_ORDER: Array[StringName] = [&"med", &"arctic", &"underworld"]
const DEFAULT_STARS_REQUIRED: Dictionary = {&"med": 0, &"arctic": 10, &"underworld": 24}
const DEST_NAMES: Dictionary = {&"med": "Mediterranean", &"arctic": "Arctic", &"underworld": "Underworld"}
const LEVELS_PER_DEST: int = 6
const TIER_2_AFTER_LEVEL: int = 3
const TIER_3_AFTER_LEVEL: int = 9
const MAX_STARS_PER_LEVEL: int = 3

## Used only when ContentDB cannot provide RoomDefs. Mirrors docs/SPEC.md §4.
const FALLBACK_ROOMS: Array[Array] = [
	[&"cabin", 1, &""], [&"buffet", 1, &""], [&"toilets", 1, &""], [&"bar", 1, &""],
	[&"pool", 1, &""], [&"deck_chairs", 1, &""], [&"stairs", 1, &""],
	[&"cinema", 2, &""], [&"gym", 3, &""], [&"medbay", 3, &""],
	[&"generator", 3, &""], [&"water_tank", 3, &""],
	[&"arcade", 4, &""], [&"sauna", 4, &"med"], [&"restaurant", 5, &""],
	[&"kids_club", 6, &""],
	[&"ice_rink", 7, &"arctic"], [&"elevator", 7, &""], [&"crew_quarters", 7, &""], [&"casino", 13, &"underworld"],
]

## Feature ids announced on the results screen. Crew roles are features named `staff_<role id>` (docs/SPEC.md §13.9).
const FEATURE_NAMES: Dictionary = {
	&"tier_2": "Tier II upgrades",
	&"tier_3": "Tier III upgrades",
	&"staff_medic": "Medic",
	&"staff_entertainer": "Entertainer",
	&"staff_chef": "Chef",
	&"staff_warden": "Ghost Warden",
	&"guests_vips": "VIP guests",
	&"guests_kids": "Kids & families",
}
## `guests_vips` / `guests_kids` are announced when the first level that schedules VIPs / boards couples and families (with
## kids) becomes playable (LevelDef.vips / group_ratio decide, see guest_features_at). The kids' club room is announced as a
## room by its own unlock level.
const STAFF_FEATURE_PREFIX: String = "staff_"

## Where the save lives. Tests override this before calling load_save().
var save_path: String = "user://save.json"
## Optional content provider override (an object with ContentDB's API). null = look up the
## /root/ContentDB autoload at call time.
var content: Object = null
## Debug override: everything counts as unlocked.
var unlock_all: bool = false
## &"ok", &"missing" or &"corrupt" — result of the last load_save().
var last_load_status: StringName = &"missing"

var _levels: Dictionary = {}  # String level_id -> Dictionary
var _extra: Dictionary = {}   # unknown top-level keys, written back untouched
var _spent: int = 0           # funds spent on perks
var _perks: Dictionary = {}   # StringName perk_id -> int level (1..Perks.MAX_LEVEL)


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	unlock_all = "--unlock-all" in args
	load_save()


# ---------------------------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------------------------

func stars_for(level_id: StringName) -> int:
	var e: Dictionary = _levels.get(String(level_id), {})
	return int(e.get("stars", 0))


## {stars, best_rating, best_profit, best_payout, plays, played}. Zeros when never played.
func best_for(level_id: StringName) -> Dictionary:
	var e: Dictionary = _levels.get(String(level_id), {})
	return {
		"stars": int(e.get("stars", 0)),
		"best_rating": float(e.get("best_rating", 0.0)),
		"best_profit": int(e.get("best_profit", 0)),
		"best_payout": int(e.get("best_payout", 0)),
		"plays": int(e.get("plays", 0)),
		"played": _levels.has(String(level_id)),
	}


func total_stars() -> int:
	var t: int = 0
	for e: Dictionary in _levels.values():
		t += int(e.get("stars", 0))
	return t


## Stars earned in one destination's levels.
func stars_in_destination(dest_id: StringName) -> int:
	var t: int = 0
	for row: Dictionary in _level_table():
		if row["dest"] == dest_id:
			t += stars_for(row["id"])
	return t


## Total stars needed to open a destination.
func stars_required(dest_id: StringName) -> int:
	var db := _db()
	if db != null and db.has_method("destination"):
		var d: Variant = db.call("destination", dest_id)
		if d != null:
			var v: Variant = _prop(d, "stars_required", null)
			if v != null:
				return int(v)
	return int(DEFAULT_STARS_REQUIRED.get(dest_id, 0))


func is_destination_unlocked(dest_id: StringName) -> bool:
	return unlock_all or _real_dest_unlocked(dest_id)


func is_level_unlocked(level_id: StringName) -> bool:
	return unlock_all or _real_level_unlocked(level_id)


## Highest campaign index (1-based) with >= 1 star; 0 when nothing is cleared.
func highest_cleared_index() -> int:
	if unlock_all:
		return _max_campaign_index()
	return _real_highest_cleared()


## tier 1 = base room (always); 2 / 3 = upgrade tiers.
func tier_unlocked(tier: int) -> bool:
	if tier <= 1 or unlock_all:
		return true
	var cleared: int = _real_highest_cleared()
	if tier == 2:
		return cleared >= TIER_2_AFTER_LEVEL
	return cleared >= TIER_3_AFTER_LEVEL


## Room ids a player can build once campaign level `index` is reachable (unlock_level <= index).
func unlocked_rooms_at(index: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for row: Dictionary in _room_table():
		if int(row["unlock_level"]) <= index:
			out.append(row["id"])
	return out


## Rooms available given current progress (ignores per-level destination locks).
func unlocked_rooms() -> Array[StringName]:
	return unlocked_rooms_at(_max_campaign_index() if unlock_all else _real_max_playable())


func next_level_id(level_id: StringName) -> StringName:
	var table := _level_table()
	for i in table.size():
		if table[i]["id"] == level_id and i + 1 < table.size():
			return table[i + 1]["id"]
	return &""


## Short reason a level is locked ("" when it is playable).
func level_lock_reason(level_id: StringName) -> String:
	if is_level_unlocked(level_id):
		return ""
	var info: Dictionary = _level_info(level_id)
	var dest: StringName = info["dest"]
	if not _real_dest_unlocked(dest):
		return "%s needs %d stars (you have %d)" % [_dest_name(dest), stars_required(dest), total_stars()]
	return "Earn a star in level %d first" % (int(info["index"]) - 1)


func feature_display_name(feature_id: StringName) -> String:
	var role: StringName = staff_role_of_feature(feature_id)
	if role != &"":
		var db := _db()
		if db != null and db.has_method("staff_role"):
			var d: Variant = db.call("staff_role", role)
			if d != null and String(_prop(d, "display_name", "")) != "":
				return String(_prop(d, "display_name", ""))
	return String(FEATURE_NAMES.get(feature_id, String(feature_id).capitalize()))


## Role id of a `staff_<role>` feature ("" for every other feature).
static func staff_role_of_feature(feature_id: StringName) -> StringName:
	var s: String = String(feature_id)
	if s.begins_with(STAFF_FEATURE_PREFIX):
		return StringName(s.trim_prefix(STAFF_FEATURE_PREFIX))
	return &""


## Guest features (`guests_vips`, `guests_kids`) available once campaign level `index` is reachable: the first campaign level
## with LevelDef.vips / LevelDef.group_ratio set introduces them. Empty when no content provider lists the campaign.
func guest_features_at(index: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var db := _db()
	if db == null or not db.has_method("campaign"):
		return out
	var first_vips: int = 0
	var first_groups: int = 0
	var levels: Variant = db.call("campaign")
	if levels is Array:
		for lv: Variant in levels:
			var ci: int = int(_prop(lv, "campaign_index", 0))
			var vips: Variant = _prop(lv, "vips", [])
			if vips is Array and not (vips as Array).is_empty() and (first_vips == 0 or ci < first_vips):
				first_vips = ci
			if float(_prop(lv, "group_ratio", 0.0)) > 0.0 and (first_groups == 0 or ci < first_groups):
				first_groups = ci
	if first_vips > 0 and index >= first_vips:
		out.append(&"guests_vips")
	if first_groups > 0 and index >= first_groups:
		out.append(&"guests_kids")
	return out


## Crew roles a player can hire once campaign level `index` is reachable (`unlock_level <= index`; ids).
## Empty when no content provider lists roles (the headless meta tests).
func unlocked_staff_at(index: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var db := _db()
	if db != null and db.has_method("all_staff_roles"):
		var roles: Variant = db.call("all_staff_roles")
		if roles is Array:
			for r: Variant in roles:
				var id: String = String(_prop(r, "id", ""))
				if id != "" and int(_prop(r, "unlock_level", 1)) <= index:
					out.append(StringName(id))
	return out


# ---------------------------------------------------------------------------------------------
# Company funds & perks (docs/SPEC.md §13.1)
# ---------------------------------------------------------------------------------------------

## Funds earned so far: the best payout of every level, summed.
func funds_earned() -> int:
	var t: int = 0
	for e: Dictionary in _levels.values():
		t += int(e.get("best_payout", 0))
	return t


## Funds spent on perks so far.
func funds_spent() -> int:
	return _spent


## Spendable company funds = earned - spent (never negative).
func funds() -> int:
	return maxi(funds_earned() - _spent, 0)


## Level (0..Perks.MAX_LEVEL) of one perk.
func perk_level(perk_id: StringName) -> int:
	return int(_perks.get(perk_id, 0))


## Copy of everything owned, `{perk_id: level}` with StringName keys. Hand it to PortState.perks.
func perks() -> Dictionary:
	return _perks.duplicate()


## `{ok, reason, price}` for buying the next level of a perk.
func can_buy_perk(perk_id: StringName) -> Dictionary:
	if not Perks.is_perk(perk_id):
		return {"ok": false, "reason": "Unknown perk", "price": 0}
	var next: int = perk_level(perk_id) + 1
	if next > Perks.MAX_LEVEL:
		return {"ok": false, "reason": "Already maxed", "price": 0}
	var price: int = Perks.price(next)
	if funds() < price:
		return {"ok": false, "reason": "Need $%d more" % (price - funds()), "price": price}
	return {"ok": true, "reason": "", "price": price}


## Buys the next level of a perk for company funds. False when unknown, maxed or too expensive.
func buy_perk(perk_id: StringName) -> bool:
	var chk: Dictionary = can_buy_perk(perk_id)
	if not bool(chk["ok"]):
		return false
	_spent += int(chk["price"])
	_perks[perk_id] = perk_level(perk_id) + 1
	save()
	progress_changed.emit()
	return true


## Gives back every perk for its full price. Returns the amount refunded (0 when nothing was owned).
func refund_perks() -> int:
	var value: int = _spent
	if _perks.is_empty() and _spent == 0:
		return 0
	_perks.clear()
	_spent = 0
	save()
	progress_changed.emit()
	return value


# ---------------------------------------------------------------------------------------------
# Mutations
# ---------------------------------------------------------------------------------------------

## Records a finished voyage: `{level_id, stars, rating, profit, payout}`. Keeps per-field bests and
## returns what the result unlocked and earned:
## `{new_stars, total_stars, best_stars, newly_unlocked_levels, newly_unlocked_destinations,
##   newly_unlocked_rooms, newly_unlocked_features, funds_earned, funds_total, best_payout}`
## (`new_stars` = improvement on the old best; `funds_earned` = `max(0, payout - old best payout)`, the only thing
## credited to company funds; `funds_total` = spendable funds afterwards; `best_payout` = the level's best so far).
func record_result(result: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"new_stars": 0,
		"total_stars": total_stars(),
		"best_stars": 0,
		"newly_unlocked_levels": [] as Array[StringName],
		"newly_unlocked_destinations": [] as Array[StringName],
		"newly_unlocked_rooms": [] as Array[StringName],
		"newly_unlocked_features": [] as Array[StringName],
		"funds_earned": 0,
		"funds_total": funds(),
		"best_payout": 0,
	}
	var id := StringName(String(result.get("level_id", "")))
	if id == &"":
		return out

	var before: Dictionary = _snapshot()
	var key := String(id)
	var stars: int = clampi(int(result.get("stars", 0)), 0, MAX_STARS_PER_LEVEL)
	var rating: float = float(result.get("rating", 0.0))
	var profit: int = int(result.get("profit", 0))
	var payout: int = maxi(0, int(result.get("payout", 0)))

	var old_stars: int = stars_for(id)
	var old_payout: int = int(best_for(id)["best_payout"])
	var entry: Dictionary
	if _levels.has(key):
		entry = _levels[key]
		entry["stars"] = maxi(int(entry.get("stars", 0)), stars)
		entry["best_rating"] = maxf(float(entry.get("best_rating", 0.0)), rating)
		entry["best_profit"] = maxi(int(entry.get("best_profit", profit)), profit)
		entry["best_payout"] = maxi(old_payout, payout)
		entry["plays"] = int(entry.get("plays", 0)) + 1
	else:
		entry = {"stars": stars, "best_rating": rating, "best_profit": profit, "best_payout": payout, "plays": 1}
	_levels[key] = entry

	var after: Dictionary = _snapshot()
	out["new_stars"] = maxi(0, int(entry["stars"]) - old_stars)
	out["best_stars"] = int(entry["stars"])
	out["total_stars"] = total_stars()
	out["newly_unlocked_levels"] = _diff(before["levels"], after["levels"])
	out["newly_unlocked_destinations"] = _diff(before["destinations"], after["destinations"])
	out["newly_unlocked_rooms"] = _diff(before["rooms"], after["rooms"])
	out["newly_unlocked_features"] = _diff(before["features"], after["features"])
	out["funds_earned"] = maxi(0, payout - old_payout)
	out["funds_total"] = funds()
	out["best_payout"] = int(entry["best_payout"])

	save()
	progress_changed.emit()
	return out


## Wipes all level progress, company funds and perks (not the settings) and saves.
func reset_progress() -> void:
	_levels.clear()
	_perks.clear()   # funds come from the levels, so the company starts over with them
	_spent = 0
	save()
	# Seen tutorial / first-time hints live in their own file; a progress reset shows them again.
	const HINT_STORE_PATH := "res://src/screens/level/tutorial/hint_store.gd"
	if ResourceLoader.exists(HINT_STORE_PATH):
		var hint_store: Script = load(HINT_STORE_PATH)
		hint_store.call(&"wipe_file")
	progress_changed.emit()


# ---------------------------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------------------------

## Atomic write: `<save_path>.tmp` then rename over the real file. Returns true on success.
func save() -> bool:
	var data: Dictionary = _extra.duplicate(true)
	data["version"] = SAVE_VERSION
	data["levels"] = _levels
	var perks_out: Dictionary = {}
	for k: StringName in _perks:
		perks_out[String(k)] = int(_perks[k])
	data["company"] = {"spent": _spent, "perks": perks_out}
	var tmp: String = save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: cannot write %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	var write_err: Error = f.get_error()
	f.close()
	if write_err != OK:
		push_warning("SaveManager: write failed for %s (error %d)" % [tmp, write_err])
		DirAccess.remove_absolute(tmp)
		return false
	var err: Error = DirAccess.rename_absolute(tmp, save_path)
	if err != OK:
		# Platforms that refuse to rename over an existing file.
		DirAccess.remove_absolute(save_path)
		err = DirAccess.rename_absolute(tmp, save_path)
		if err != OK:
			push_warning("SaveManager: cannot move %s into place (error %d)" % [tmp, err])
			return false
	return true


## (Re)loads `save_path`. Returns true when a valid save (or no save) was found; false when the
## file was corrupt and has been set aside.
func load_save() -> bool:
	_levels.clear()
	_extra.clear()
	_perks.clear()
	_spent = 0
	if not FileAccess.file_exists(save_path):
		last_load_status = &"missing"
		return true
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		last_load_status = &"corrupt"
		_set_aside_corrupt()
		return false
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		last_load_status = &"corrupt"
		_set_aside_corrupt()
		return false
	var data: Dictionary = json.data
	var raw_levels: Variant = data.get("levels", {})
	if raw_levels is Dictionary:
		for k: Variant in raw_levels.keys():
			var v: Variant = raw_levels[k]
			if v is Dictionary:
				_levels[String(k)] = {
					"stars": clampi(int(v.get("stars", 0)), 0, MAX_STARS_PER_LEVEL),
					"best_rating": float(v.get("best_rating", 0.0)),
					"best_profit": int(v.get("best_profit", 0)),
					"best_payout": maxi(0, int(v.get("best_payout", 0))),
					"plays": maxi(0, int(v.get("plays", 1))),
				}
	var raw_company: Variant = data.get("company", {})
	if raw_company is Dictionary:
		var co: Dictionary = raw_company
		_spent = maxi(0, int(co.get("spent", 0)))
		var raw_perks: Variant = co.get("perks", {})
		if raw_perks is Dictionary:
			for k: Variant in (raw_perks as Dictionary).keys():
				var pid := StringName(String(k))
				var lv: int = clampi(int((raw_perks as Dictionary)[k]), 0, Perks.MAX_LEVEL)
				if lv > 0 and Perks.is_perk(pid):
					_perks[pid] = lv
	for k: Variant in data.keys():
		var ks: String = String(k)
		if ks != "version" and ks != "levels" and ks != "company":
			_extra[ks] = data[k]
	last_load_status = &"ok"
	return true


func _set_aside_corrupt() -> void:
	var backup: String = save_path + ".corrupt"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	var err: Error = DirAccess.rename_absolute(save_path, backup)
	push_warning("SaveManager: corrupt save moved to %s (rename error %d); starting fresh" % [backup, err])


# ---------------------------------------------------------------------------------------------
# Unlock rules (real = ignoring the --unlock-all override)
# ---------------------------------------------------------------------------------------------

func _real_dest_unlocked(dest_id: StringName) -> bool:
	return total_stars() >= stars_required(dest_id)


func _real_level_unlocked(level_id: StringName) -> bool:
	var info: Dictionary = _level_info(level_id)
	if info.is_empty():
		return true  # unknown (dev / test) levels are never gated
	if not _real_dest_unlocked(info["dest"]):
		return false
	var idx: int = int(info["index"])
	if idx <= 1:
		return true
	for row: Dictionary in _level_table():
		if row["dest"] == info["dest"] and int(row["index"]) == idx - 1:
			return stars_for(row["id"]) >= 1
	return true


func _real_highest_cleared() -> int:
	var best: int = 0
	for row: Dictionary in _level_table():
		if stars_for(row["id"]) >= 1:
			best = maxi(best, int(row["campaign"]))
	return best


func _real_max_playable() -> int:
	var best: int = 0
	for row: Dictionary in _level_table():
		if _real_level_unlocked(row["id"]):
			best = maxi(best, int(row["campaign"]))
	return best


func _max_campaign_index() -> int:
	var best: int = 0
	for row: Dictionary in _level_table():
		best = maxi(best, int(row["campaign"]))
	return best


## Everything unlock-related as arrays of ids, using the real rules.
func _snapshot() -> Dictionary:
	var levels: Array[StringName] = []
	var max_playable: int = 0
	for row: Dictionary in _level_table():
		if _real_level_unlocked(row["id"]):
			levels.append(row["id"])
			max_playable = maxi(max_playable, int(row["campaign"]))
	var dests: Array[StringName] = []
	for d in DEST_ORDER:
		if _real_dest_unlocked(d):
			dests.append(d)
	var features: Array[StringName] = []
	var cleared: int = _real_highest_cleared()
	if cleared >= TIER_2_AFTER_LEVEL:
		features.append(&"tier_2")
	if cleared >= TIER_3_AFTER_LEVEL:
		features.append(&"tier_3")
	for role: StringName in unlocked_staff_at(max_playable):
		features.append(StringName(STAFF_FEATURE_PREFIX + String(role)))
	for gf in guest_features_at(max_playable):
		features.append(gf)
	return {
		"levels": levels,
		"destinations": dests,
		"rooms": unlocked_rooms_at(max_playable),
		"features": features,
	}


static func _diff(before: Array, after: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in after:
		if id not in before:
			out.append(id)
	return out


# ---------------------------------------------------------------------------------------------
# Content lookups (ContentDB when available, SPEC defaults otherwise)
# ---------------------------------------------------------------------------------------------

func _db() -> Object:
	if content != null:
		return content
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("ContentDB")


## Reads a field off a Resource / Object / Dictionary.
static func _prop(obj: Variant, field: String, default: Variant) -> Variant:
	if obj is Dictionary:
		return (obj as Dictionary).get(field, default)
	if obj is Object:
		var v: Variant = (obj as Object).get(field)
		return default if v == null else v
	return default


## [{id, dest, index, campaign}] sorted by campaign index.
func _level_table() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var db := _db()
	if db != null and db.has_method("campaign"):
		var camp: Variant = db.call("campaign")
		if camp is Array:
			for lv: Variant in camp:
				var row := _row_from_level(lv)
				if not row.is_empty():
					rows.append(row)
	if rows.is_empty():
		for di in DEST_ORDER.size():
			for i in range(1, LEVELS_PER_DEST + 1):
				rows.append({
					"id": StringName("%s_%d" % [DEST_ORDER[di], i]),
					"dest": DEST_ORDER[di],
					"index": i,
					"campaign": di * LEVELS_PER_DEST + i,
				})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["campaign"]) < int(b["campaign"]))
	return rows


static func _row_from_level(lv: Variant) -> Dictionary:
	var id: String = String(_prop(lv, "id", ""))
	if id == "":
		return {}
	var dest: String = String(_prop(lv, "destination", ""))
	var index: int = int(_prop(lv, "index", 0))
	var campaign: int = int(_prop(lv, "campaign_index", 0))
	if dest == "" or index <= 0:
		var parsed := _parse_level_id(StringName(id))
		if parsed.is_empty():
			return {}
		if dest == "":
			dest = String(parsed["dest"])
		if index <= 0:
			index = int(parsed["index"])
		if campaign <= 0:
			campaign = int(parsed["campaign"])
	if campaign <= 0:
		campaign = maxi(0, DEST_ORDER.find(StringName(dest))) * LEVELS_PER_DEST + index
	return {"id": StringName(id), "dest": StringName(dest), "index": index, "campaign": campaign}


## "arctic_3" -> {dest: arctic, index: 3, campaign: 9}; {} when it does not look like a level id.
static func _parse_level_id(level_id: StringName) -> Dictionary:
	var s := String(level_id)
	var cut: int = s.rfind("_")
	if cut <= 0:
		return {}
	var dest := StringName(s.substr(0, cut))
	var tail: String = s.substr(cut + 1)
	if not tail.is_valid_int() or dest not in DEST_ORDER:
		return {}
	var index: int = int(tail)
	return {"dest": dest, "index": index, "campaign": DEST_ORDER.find(dest) * LEVELS_PER_DEST + index}


func _level_info(level_id: StringName) -> Dictionary:
	for row: Dictionary in _level_table():
		if row["id"] == level_id:
			return row
	var parsed := _parse_level_id(level_id)
	if parsed.is_empty():
		return {}
	parsed["id"] = level_id
	return parsed


## [{id, unlock_level, dest_lock}] from ContentDB or the SPEC fallback.
func _room_table() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var db := _db()
	if db != null and db.has_method("all_rooms"):
		var rooms: Variant = db.call("all_rooms")
		if rooms is Array:
			for r: Variant in rooms:
				var id: String = String(_prop(r, "id", ""))
				if id != "":
					rows.append({
						"id": StringName(id),
						"unlock_level": int(_prop(r, "unlock_level", 1)),
						"dest_lock": StringName(String(_prop(r, "destination_lock", ""))),
					})
	if rows.is_empty():
		for r: Array in FALLBACK_ROOMS:
			rows.append({"id": r[0], "unlock_level": r[1], "dest_lock": r[2]})
	return rows


func _dest_name(dest_id: StringName) -> String:
	var db := _db()
	if db != null and db.has_method("destination"):
		var d: Variant = db.call("destination", dest_id)
		if d != null:
			var n: String = String(_prop(d, "display_name", ""))
			if n != "":
				return n
	return String(DEST_NAMES.get(dest_id, String(dest_id).capitalize()))
