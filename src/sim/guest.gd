class_name Guest
extends Walker
## One passenger. Renderers read: id, archetype, deck, x, prev_x, deck_f, prev_deck_f, facing, state,
## needs, satisfaction, sick, cabin_uid, target_uid, queue_index, slip_timer, mood, bubble_timer,
## walk_phase, slot (slot index inside the room while state == use), is_favorite_use.
##
## `state` is what to draw: boarding, wander, walk, queue, use, climb, elevator_wait, elevator_ride,
## storm_off, gone. (`mode` is the logical activity underneath a climb/elevator state.)

const BOARDING: StringName = &"boarding"
const WANDER: StringName = &"wander"
const WALK: StringName = &"walk"
const QUEUE: StringName = &"queue"
const USE: StringName = &"use"
const STORM_OFF: StringName = &"storm_off"
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
	return mode != GONE and mode != STORM_OFF
