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
## Random pick only from this campaign level index on (0 = always); scheduled use is not limited. The storm is 8.
@export var min_campaign_index: int = 0
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
## Storm (docs/SPEC.md §13.7): `storm` events drive SimWorld.weather_intensity (eased in and out over `weather_ease` seconds at
## each end of the event); `top_deck_closed` shuts every top-deck room while the event runs; guests may get seasick (each
## `seasick_interval` s each guest rolls `seasick_chance`, x `seasick_cabin_mult` while inside a cabin, for `seasick_duration` s);
## `mess_mult_all` multiplies every room's mess chance.
@export var storm: bool = false
@export var weather_ease: float = 4.0
@export var top_deck_closed: bool = false
@export var seasick_chance: float = 0.0
@export var seasick_cabin_mult: float = 0.3
@export var seasick_interval: float = 5.0
@export var seasick_duration: float = 25.0
@export var mess_mult_all: float = 1.0
