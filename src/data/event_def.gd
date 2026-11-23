class_name EventDef
extends Resource
## Voyage event (see docs/SPEC.md §4 / §5). Effects are interpreted by EventDirector.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## Seconds the event lasts; 0 = instant.
@export var duration: float = 0.0
@export var destination_lock: StringName = &""
@export var icon: StringName = &""
## room id / fun tag / &"top_deck" -> appeal multiplier while active
@export var room_appeal_mult: Dictionary = {}
## need -> value; at event start every guest's need is capped at this value
@export var need_set: Dictionary = {}
@export var sick_count: int = 0
@export var break_count: int = 0
@export var mess_mult_top_deck: float = 1.0
## room id -> satisfaction bonus when a use finishes while that room is full
@export var full_room_bonus: Dictionary = {}
@export var ghost_count: int = 0
@export var top_deck_rush: bool = false
## Extra effect fields (not in the SPEC table)
@export var hygiene_decay_mult: float = 1.0
@export var top_deck_fun_rate: float = 0.0
@export var suspend_cold: bool = false
