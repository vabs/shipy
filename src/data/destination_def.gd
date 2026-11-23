class_name DestinationDef
extends Resource
## Cruise destination (see docs/SPEC.md §4).

@export var id: StringName = &""
@export var display_name: String = ""
@export var stars_required: int = 0
@export var sky_top: Color = Color.WHITE
@export var sky_bottom: Color = Color.WHITE
@export var sea: Color = Color.WHITE
@export var twist_text: String = ""
@export var hygiene_decay_mult: float = 1.0
@export var top_deck_appeal_mult: float = 1.0
## Satisfaction drained per second while a guest stands on the top deck (Arctic).
@export var top_deck_satisfaction_drain: float = 0.0
## Seconds between ghost spawns (min, max); (0,0) = no ghosts.
@export var ghost_interval: Vector2 = Vector2.ZERO
@export var pool_appeal_mult: float = 1.0
@export var random_events: Array[StringName] = []
@export var new_room: StringName = &""
