class_name Perks
extends RefCounted
## Company perks bought in the Shipyard (docs/SPEC.md §13.1). Pure data + helpers shared by SaveManager (what is
## owned), PortState (budget bonus), SimWorld.apply_perks (everything else) and the Shipyard UI.
##
## A "perks" dictionary is plain data: `{perk_id: level}` with level 0..MAX_LEVEL. Keys may be StringName or String
## (JSON round-trips make them Strings); every helper here accepts both.

const MAX_LEVEL: int = 3
const IDS: Array[StringName] = [&"budget", &"crew", &"tickets", &"service", &"maintenance"]
## Price of buying level 1 / 2 / 3 of any perk. Calibrated with tests/payout.gd: payout = cash on hand at the end of a
## voyage (leftover budget + profit), which averages about $340 / 1,000 / 1,270 / 1,480 / 2,400 / 2,840 on med_1..6
## (Mediterranean total ~9,300; whole campaign ~50,000). So clearing Med buys two level-1 perks with a third in sight,
## and the campaign buys every level 1 plus a few level 2s but not everything. (SPEC's 600 / 1500 / 3000 assumed
## profit-sized payouts.)
const PRICES: Array[int] = [3000, 7500, 15000]

## Per-level numbers (fractions).
const BUDGET_PER_LEVEL: float = 0.06
const CREW_SPEED_PER_LEVEL: float = 0.10
const CREW_WORK_PER_LEVEL: float = 0.10
const TICKETS_PER_LEVEL: float = 0.08
const SERVICE_PER_LEVEL: float = 0.10
const MAINTENANCE_PER_LEVEL: float = 0.12

const DEFS: Dictionary = {
	&"budget": {"name": "Investors", "blurb": "Backers top up every port budget."},
	&"crew": {"name": "Crew Training", "blurb": "Staff walk faster and finish jobs sooner."},
	&"tickets": {"name": "Marketing", "blurb": "Every guest pays a little more at the gangway."},
	&"service": {"name": "Hospitality School", "blurb": "Guests wait longer before giving up on a queue."},
	&"maintenance": {"name": "Maintenance Contract", "blurb": "Rooms last longer before they break down."},
}


# ---- reading a perks dictionary ------------------------------------------------------------------
## Level of `id` in `perks`, clamped to 0..MAX_LEVEL (accepts StringName or String keys).
static func level_of(perks: Dictionary, id: StringName) -> int:
	var v: Variant = perks.get(id, perks.get(String(id), 0))
	return clampi(int(v), 0, MAX_LEVEL)


## A clean copy: StringName keys, known perks only, levels clamped, zero levels dropped.
static func normalized(perks: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in IDS:
		var lv: int = level_of(perks, id)
		if lv > 0:
			out[id] = lv
	return out


static func is_perk(id: StringName) -> bool:
	return id in IDS


# ---- prices ----------------------------------------------------------------------------------------
## Price of buying `level` (1..MAX_LEVEL) of a perk; 0 for anything else.
static func price(level: int) -> int:
	if level < 1 or level > MAX_LEVEL:
		return 0
	return PRICES[level - 1]


## Everything paid to own `level` levels of one perk.
static func total_cost(level: int) -> int:
	var t: int = 0
	for l in range(1, clampi(level, 0, MAX_LEVEL) + 1):
		t += price(l)
	return t


## Everything paid for a whole perks dictionary (what a full refund returns).
static func total_value(perks: Dictionary) -> int:
	var t: int = 0
	for id in IDS:
		t += total_cost(level_of(perks, id))
	return t


# ---- effects (sim side) ----------------------------------------------------------------------------
## Extra port budget for a level whose base budget is `base_budget`.
static func budget_bonus(perks: Dictionary, base_budget: int) -> int:
	return int(round(float(base_budget) * BUDGET_PER_LEVEL * float(level_of(perks, &"budget"))))


static func crew_speed_mult(perks: Dictionary) -> float:
	return 1.0 + CREW_SPEED_PER_LEVEL * float(level_of(perks, &"crew"))


## Multiplier on a job's work time (lower = faster).
static func crew_work_mult(perks: Dictionary) -> float:
	return 1.0 - CREW_WORK_PER_LEVEL * float(level_of(perks, &"crew"))


static func ticket_mult(perks: Dictionary) -> float:
	return 1.0 + TICKETS_PER_LEVEL * float(level_of(perks, &"tickets"))


static func patience_mult(perks: Dictionary) -> float:
	return 1.0 + SERVICE_PER_LEVEL * float(level_of(perks, &"service"))


static func health_mult(perks: Dictionary) -> float:
	return 1.0 + MAINTENANCE_PER_LEVEL * float(level_of(perks, &"maintenance"))


# ---- text (UI side) --------------------------------------------------------------------------------
static func display_name(id: StringName) -> String:
	return String((DEFS.get(id, {}) as Dictionary).get("name", String(id).capitalize()))


static func blurb(id: StringName) -> String:
	return String((DEFS.get(id, {}) as Dictionary).get("blurb", ""))


static func _pct(per_level: float, level: int) -> String:
	return "%d%%" % int(round(per_level * 100.0 * float(level)))


## One-line effect at `level` (0 = "No bonus yet").
static func effect_text(id: StringName, level: int) -> String:
	if level <= 0:
		return "No bonus yet"
	match id:
		&"budget": return "+%s port budget" % _pct(BUDGET_PER_LEVEL, level)
		&"crew": return "+%s speed, -%s job time" % [_pct(CREW_SPEED_PER_LEVEL, level), _pct(CREW_WORK_PER_LEVEL, level)]
		&"tickets": return "+%s ticket price" % _pct(TICKETS_PER_LEVEL, level)
		&"service": return "+%s queue patience" % _pct(SERVICE_PER_LEVEL, level)
		&"maintenance": return "+%s room durability" % _pct(MAINTENANCE_PER_LEVEL, level)
	return ""


## Short effect per level, for the card's "each level" line.
static func per_level_text(id: StringName) -> String:
	match id:
		&"budget": return "+%s port budget" % _pct(BUDGET_PER_LEVEL, 1)
		&"crew": return "+%s speed, -%s job time" % [_pct(CREW_SPEED_PER_LEVEL, 1), _pct(CREW_WORK_PER_LEVEL, 1)]
		&"tickets": return "+%s ticket price" % _pct(TICKETS_PER_LEVEL, 1)
		&"service": return "+%s queue patience" % _pct(SERVICE_PER_LEVEL, 1)
		&"maintenance": return "+%s room durability" % _pct(MAINTENANCE_PER_LEVEL, 1)
	return ""
