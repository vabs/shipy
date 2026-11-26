class_name StaffDef
extends Resource
## Crew role (janitor / mechanic / medic / entertainer / chef / warden). See docs/SPEC.md §13.3.

@export var id: StringName = &""
@export var display_name: String = ""
## What the role does: &"mess" (janitor), &"breakdown" (mechanic), &"sick" (medic), &"ghost" (warden) or
## &"aura" (entertainer, chef: no jobs, they work a room instead).
@export var handles: StringName = &"mess"
@export var wage: int = 40
## Seconds of work to finish one job (medic: treating a guest, warden: channelling a banishing).
@export var work_time: float = 2.5
## Walking speed, cells per second.
@export var speed: float = 3.0
## Campaign index that unlocks the role (1 = from the start).
@export var unlock_level: int = 1
## "" or a destination id; the role is only offered in that destination (warden: underworld).
@export var destination_lock: StringName = &""
@export var description: String = ""


## True when the role can be hired while playing campaign level `campaign_index` in `destination_id`.
func is_available(campaign_index: int, destination_id: StringName) -> bool:
	if unlock_level > campaign_index:
		return false
	return destination_lock == &"" or destination_lock == destination_id


## Aura roles (entertainer, chef) have no jobs: they perform for a queue / station at a food room.
func is_aura() -> bool:
	return handles == &"aura"
