class_name GuestGroup
extends RefCounted
## A couple or family that boards together (docs/SPEC.md §13.6). `members` are guest ids, leader first (the first adult,
## who chooses normally; everyone else follows). `cabin_uid` is the shared cabin booked for all of them, or -1 when no
## cabin had enough free beds and the group `split` up (each member then loses SimConst.GROUP_SPLIT_SAT).

const COUPLE: StringName = &"couple"
const FAMILY: StringName = &"family"

## 1-based index in SimWorld.groups (== Guest.group_id).
var id: int = 0
var kind: StringName = COUPLE
## How many people board (2 for a couple, 3-4 for a family) and how many of them are kids.
var size: int = 2
var kids: int = 0
var members: Array[int] = []
var cabin_uid: int = -1
var split: bool = false


## Kinds of group a wave of `count` guests produces at group ratio `ratio`, as a list of kid counts (one entry per group).
## Deterministic (no rng) so the port manifest can show exactly who is coming: SimConst.GROUP_KIDS_PATTERN cycles
## family (1 kid) -> couple -> family (2 kids) -> couple; the last group shrinks to fit and a leftover single stays solo.
static func plan(count: int, ratio: float) -> Array[int]:
	var out: Array[int] = []
	var left: int = clampi(int(round(float(count) * clampf(ratio, 0.0, 1.0))), 0, count)
	var i: int = 0
	var pattern: Array[int] = SimConst.GROUP_KIDS_PATTERN
	while left >= 2:
		var kids_n: int = pattern[i % pattern.size()]
		i += 1
		if 2 + kids_n > left:
			kids_n = left - 2
		out.append(kids_n)
		left -= 2 + kids_n
	return out


static func kind_of(kids_n: int) -> StringName:
	return FAMILY if kids_n > 0 else COUPLE


## What a level's waves bring: {groups, couples, families, kids, grouped (people travelling in groups)}. Exact: it follows
## `plan` wave by wave, exactly as LevelDirector schedules the boarding.
static func summary(level: LevelDef) -> Dictionary:
	var couples: int = 0
	var families: int = 0
	var kids: int = 0
	var grouped: int = 0
	if level.group_ratio > 0.0:
		for wv in level.waves:
			var count: int = int(wv.get("count", 0))
			if count < 2:
				continue
			for kids_n in plan(count, level.group_ratio):
				if kids_n > 0:
					families += 1
				else:
					couples += 1
				kids += kids_n
				grouped += 2 + kids_n
	return {"groups": couples + families, "couples": couples, "families": families, "kids": kids, "grouped": grouped}
