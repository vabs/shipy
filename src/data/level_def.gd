class_name LevelDef
extends Resource
## One campaign level (see docs/SPEC.md §4).

@export var id: StringName = &""
## 1..6 within the destination
@export var index: int = 1
## 1..18 over the whole campaign
@export var campaign_index: int = 1
@export var display_name: String = ""
@export var blurb: String = ""
@export var destination: StringName = &"med"
@export var hull: StringName = &"small"
@export var budget: int = 1000
@export var ticket_price: int = 20
@export var duration: float = 180.0
## [{"t": float, "count": int}]
@export var waves: Array[Dictionary] = []
@export var archetype_weights: Dictionary = {}
## [{"t": float, "event": StringName}]
@export var scheduled_events: Array[Dictionary] = []
@export var random_event_interval: float = 0.0
## 3 goals: {"type":"rating","value":55} | {"type":"profit","value":800} |
## {"type":"no_lost_guests"} | {"type":"served","value":120}
@export var star_goals: Array[Dictionary] = []
## [{"room": id, "deck": int, "x": int, "locked": bool}]
@export var preset_rooms: Array[Dictionary] = []
## role id -> count of crew pre-hired (free)
@export var preset_staff: Dictionary = {}
@export var tutorial: bool = false
@export var mutiny_enabled: bool = true
## Difficulty knobs shaping the campaign curve (1.0 = the base numbers in the room/guest tables).
## Multiplies every room's mess chance.
@export var mess_mult: float = 1.0
## Multiplies room health (higher = breaks less often).
@export var health_mult: float = 1.0
## Multiplies all need decay rates.
@export var decay_mult: float = 1.0
## Multiplies queue patience.
@export var patience_mult: float = 1.0
## Multiplies the destination's ghost interval (higher = fewer ghosts).
@export var ghost_interval_mult: float = 1.0


func total_guests() -> int:
	var n: int = 0
	for w in waves:
		n += int(w.get("count", 0))
	return n
