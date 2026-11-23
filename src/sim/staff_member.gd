class_name StaffMember
extends Walker
## A crew member (janitor or mechanic). state: idle | walk | work (climbs/rides report as `walk`).

var id: int = 0
var def: StaffDef
var role: StringName = &"janitor"
var job: Job = null
## What is being worked on while state == work: kind (&"mess"/&"repair") and target id.
var work_kind: StringName = &""
var work_target_id: int = -1
var claim_timer: float = 0.0
var patrol_wait: float = 1.0
var last_job_deck: int = 0
var last_job_x: float = 1.5
var need_replan: bool = false
var jobs_done: int = 0


func _init() -> void:
	report_travel = false


func job_kind() -> StringName:
	return &"mess" if def.handles == &"mess" else &"repair"
