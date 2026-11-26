class_name Guest
extends Walker
## One passenger. Renderers read: id, archetype, deck, x, prev_x, deck_f, prev_deck_f, facing, state,
## needs, satisfaction, sick, cabin_uid, target_uid, queue_index, slip_timer, mood, bubble_timer,
## walk_phase, slot (slot index inside the room while state == use), is_favorite_use.
##
## `state` is what to draw: boarding, wander, walk, queue, use, climb, elevator_wait, elevator_ride,
## storm_off, gone, plus `inspect` (a VIP inspector strolling the decks) and `excursion` (walking off the ship at a port stop,
## docs/SPEC.md §13.8). (`mode` is the logical activity underneath a climb/elevator state.)

const BOARDING: StringName = &"boarding"
const WANDER: StringName = &"wander"
const WALK: StringName = &"walk"
const QUEUE: StringName = &"queue"
const USE: StringName = &"use"
const STORM_OFF: StringName = &"storm_off"
const INSPECT: StringName = &"inspect"
const EXCURSION: StringName = &"excursion"
const GONE: StringName = &"gone"

const NEED_MOODS: Array[StringName] = [&"need_rest", &"need_hunger", &"need_fun", &"need_hygiene"]

var id: int = 0
var archetype: ArchetypeDef
var satisfaction: float = 72.0
var sick: bool = false
var cabin_uid: int = -1
var target_uid: int = -1
var queue_index: int = -1
var slip_timer: float = 0.0
var mood: StringName = &"ok"
var bubble_timer: float = 0.0

## Need values in SimConst order (rest, hunger, fun, hygiene); 100 = fully satisfied.
var nv: PackedFloat32Array = PackedFloat32Array([75.0, 75.0, 75.0, 75.0])
## Per-need base decay per second including archetype multipliers.
var decay: PackedFloat32Array = PackedFloat32Array([0.45, 0.8, 1.0, 0.6])

## Logical activity (see class doc). `state` mirrors it except during vertical travel.
var mode: StringName = BOARDING
var boarded_at: float = 0.0
var mode_t: float = 0.0
var eval_timer: float = 0.5
var wander_pause: float = 1.0
var patience: float = 0.0
var queue_x: float = 0.0
var slot: int = -1
var bed_slot: int = -1
var use_dur: float = 1.0
var use_timer: float = 0.0
var use_applied: float = 0.0
var use_rates: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var use_favorite: bool = false
var last_fun_tag: StringName = &""
var storm_timer: float = 0.0
var sick_timer: float = 0.0
## Seasick (storm, docs/SPEC.md §13.7): separate from `sick` (food poisoning); not contagious, wears off after `seasick_timer`
## seconds, cured at once by the medbay or a medic.
var seasick: bool = false
var seasick_timer: float = 0.0
## Port stop (docs/SPEC.md §13.8): set once the guest has gone ashore on the excursion (they keep their satisfaction in the
## rating and are not "lost"); `excursion_pending` waits for a climb / ride to finish before the walk-off begins.
var excursion: bool = false
var excursion_pending: bool = false
var angry_timer: float = 0.0
var last_cell: int = -1
## room uid -> time until which the guest avoids that room.
var avoid: Dictionary = {}
var lost: bool = false
var uses: int = 0
var slow_t: float = 0.0
var storm_pending: bool = false
## room uid -> true for rooms this guest's archetype loves (shared per archetype).
var fav: Dictionary = {}
## Sim time until which a medic is treating this guest (the guest stands still) / an entertainer is cheering them up.
var hold_until: float = 0.0
var cheer_until: float = 0.0

# --- Groups (docs/SPEC.md §13.6) ---
## Index of the guest's GuestGroup in SimWorld.groups + 1 (-1 = travelling alone); `group_slot` 0 = the leader.
var group_id: int = -1
var group_slot: int = 0

# --- VIPs (docs/SPEC.md §13.5): `vip_kind` is &"" for everybody else ---
var vip_kind: StringName = &""
## Set once the verdict is in: &"great" | &"ok" | &"bad".
var vip_grade: StringName = &""
## Critic: points scored so far. Celebrity: sum of the satisfaction samples. Inspector: spills + broken rooms seen.
var vip_score: float = 0.0
## Critic: meals reviewed. Celebrity: samples taken.
var vip_n: int = 0
## Money the verdict paid (negative = a fine).
var vip_pay: int = 0
## Inspector: deck index -> true once he has walked that deck end to end; the legs still to walk (deck, x) and the one
## being walked; ids of the spills / breakdowns already counted.
var inspected_decks: Dictionary = {}
var inspect_legs: Array[Vector2] = []
var inspect_i: int = 0
var vip_seen: Dictionary = {}
var vip_scan_t: float = 0.0
## Sim time this guest joined its current queue (NOT_QUEUED = not queueing) and how long the last wait lasted.
const NOT_QUEUED: float = -1.0e9
var queue_since: float = NOT_QUEUED
var use_wait: float = 0.0
## The critic noted a mess near the door of the food room he is about to eat at.
var saw_mess: bool = false
## Celebrity: uid of the room whose appeal they are currently boosting (-1 = none).
var celeb_room: int = -1

## Dictionary view of the needs (read-only snapshot): {rest, hunger, fun, hygiene}.
var needs: Dictionary:
	get:
		return {
			&"rest": nv[0], &"hunger": nv[1], &"fun": nv[2], &"hygiene": nv[3],
		}


func get_need(need: StringName) -> float:
	return nv[SimConst.NEEDS.find(need)]


func set_need(need: StringName, value: float) -> void:
	nv[SimConst.NEEDS.find(need)] = clampf(value, 0.0, 100.0)


## 0..1 progress through the current use (0 when not using).
func use_fraction() -> float:
	if mode != USE or use_dur <= 0.0:
		return 0.0
	return clampf(1.0 - use_timer / use_dur, 0.0, 1.0)


func min_need() -> float:
	return minf(minf(nv[0], nv[1]), minf(nv[2], nv[3]))


func lowest_need_index() -> int:
	var best: int = 0
	for i in range(1, 4):
		if nv[i] < nv[best]:
			best = i
	return best


func is_aboard() -> bool:
	return mode != GONE and mode != STORM_OFF and mode != EXCURSION


## Ill in either way: food poisoning (`sick`) or seasickness. The medbay and the medic treat both.
func is_ailing() -> bool:
	return sick or seasick


func is_vip() -> bool:
	return vip_kind != &""


func is_kid() -> bool:
	return archetype != null and archetype.kid
