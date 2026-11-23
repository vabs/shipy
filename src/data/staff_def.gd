class_name StaffDef
extends Resource
## Crew role (janitor / mechanic).

@export var id: StringName = &""
@export var display_name: String = ""
## &"mess" or &"breakdown"
@export var handles: StringName = &"mess"
@export var wage: int = 40
## Seconds of work to finish one job.
@export var work_time: float = 2.5
## Walking speed, cells per second.
@export var speed: float = 3.0
