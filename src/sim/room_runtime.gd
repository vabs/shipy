class_name RoomRuntime
extends RefCounted
## Runtime state of one placed room during a voyage. Renderers read: uid, def, deck, x, width, tier,
## users, queue, broken, health, max_health, repair_progress, busy_ratio, uses, door_x.
## Every placed room (including stairs, elevators and utilities) has a RoomRuntime.

var uid: int = 0
var def: RoomDef
var deck: int = 0
var x: int = 0
var width: int = 1
var tier: int = 0
var locked: bool = false
var door_x: float = 0.0
var top_deck: bool = false

## Guest ids currently using the room / waiting in line (front first).
var users: Array[int] = []
var queue: Array[int] = []
## slot index -> guest id (-1 free). Size = capacity.
var slots: Array[int] = []
## Cabin: guest ids assigned a bed.
var sleepers: Array[int] = []
## Guests walking here (not yet in line); used by the guests' wait estimate.
var incoming: int = 0

var broken: bool = false
var health: float = 0.0
var max_health: float = 0.0
var repair_progress: float = 0.0
var busy_ratio: float = 0.0
var uses: int = 0
var appeal_now: float = 1.0
var broken_count: int = 0
## Cached for the guests' decision loop (tier is fixed during a voyage).
var cap: int = 0
var breakable: bool = false
var svc: float = 1.0
var door_node: int = 0
var need_idx: PackedInt32Array = PackedInt32Array()
var need_amt: PackedFloat32Array = PackedFloat32Array()


func capacity() -> int:
	return def.capacity_at(tier)


func service_time() -> float:
	return def.service_time_at(tier)


func is_full() -> bool:
	return users.size() >= capacity()


func is_breakable() -> bool:
	return def.breakdown_time > 0.0


func resize_slots() -> void:
	var n: int = capacity()
	while slots.size() < n:
		slots.append(-1)


## Takes the lowest free slot for guest `gid`; returns the slot index (or -1 if none).
func take_slot(gid: int) -> int:
	resize_slots()
	for i in slots.size():
		if slots[i] == -1:
			slots[i] = gid
			return i
	slots.append(gid)
	return slots.size() - 1


func free_slot(gid: int) -> void:
	for i in slots.size():
		if slots[i] == gid:
			slots[i] = -1
			return


func slot_of(gid: int) -> int:
	for i in slots.size():
		if slots[i] == gid:
			return i
	return -1


## Free beds in a cabin.
func free_beds() -> int:
	return capacity() - sleepers.size()
