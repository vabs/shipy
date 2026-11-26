class_name StaffMember
extends Walker
## A crew member (janitor, mechanic, medic, entertainer, chef or warden; docs/SPEC.md §13.3).
##
## `state` is what to draw: idle | walk | work | perform (entertainer juggling at a queue) | station (chef at a
## food room) | rest (asleep in a crew quarters bunk) | nap (asleep on the spot). Climbs and elevator rides report
## as `walk`. `goal` says what a walking member is heading for (see StaffSim).

var id: int = 0
var def: StaffDef
var role: StringName = &"janitor"
var job: Job = null
## What is being worked on while state == work: kind (&"mess"/&"repair"/&"sick"/&"ghost") and target id.
var work_kind: StringName = &""
var work_target_id: int = -1
var claim_timer: float = 0.0
var patrol_wait: float = 1.0
var last_job_deck: int = 0
var last_job_x: float = 1.5
var need_replan: bool = false
var jobs_done: int = 0
## Company perk multipliers (Crew Training): set by StaffSim.set_crew_perk, never touch the shared StaffDef.
var speed_mult: float = 1.0
var work_mult: float = 1.0

## Fatigue (docs/SPEC.md §13.4). Only meaningful when `fatigue_on` (LevelDef.staff_fatigue); energy stays 100 otherwise.
var energy: float = 100.0
var fatigue_on: bool = false
## What a walking member is heading for: &"" (a queue job), &"rest" (a crew quarters bunk), &"perform" or &"station".
var goal: StringName = &""
## Crew quarters uid whose bunk this member holds (reserved while walking there, asleep once there), or -1.
var rest_uid: int = -1
## Room the entertainer performs at / the chef is stationed at (-1 = none).
var aura_uid: int = -1
## Entertainer: sim time until which a player-ordered show must be kept up (0 = automatic, re-evaluated).
var aura_until: float = 0.0
## Seconds until the next automatic target re-evaluation (entertainer 3 s, chef 10 s).
var aura_eval: float = 0.0
## Medic / warden chase bookkeeping: time until the next re-plan and the spot the current route leads to.
var follow_timer: float = 0.0
var plan_deck: int = -1
var plan_x: float = 0.0
## Set once when energy first drops below the tired threshold (so the alert fires once per tired spell).
var tired_notified: bool = false


func _init() -> void:
	report_travel = false


## Tired = fatigue is on and energy is below the threshold. Slower walking and work, "zzz" bubble.
func is_tired() -> bool:
	return fatigue_on and energy < SimConst.STAFF_TIRED_ENERGY


func is_resting() -> bool:
	return state == &"rest" or state == &"nap"


## Walking speed in cells per second: def speed x Crew Training perk x tiredness (StaffSim reads this, never `def.speed`).
func eff_speed() -> float:
	var m: float = SimConst.STAFF_TIRED_SPEED if is_tired() else 1.0
	return def.speed * speed_mult * m


## Seconds of work per job: def work time x Crew Training perk x tiredness (StaffSim reads this, never `def.work_time`).
func eff_work_time() -> float:
	var m: float = SimConst.STAFF_TIRED_WORK if is_tired() else 1.0
	return def.work_time * work_mult * m


## Queue job kind this role claims: &"mess" | &"repair" | &"sick" | &"ghost", or &"" for aura roles.
func job_kind() -> StringName:
	match def.handles:
		&"mess": return &"mess"
		&"breakdown": return &"repair"
		&"sick": return &"sick"
		&"ghost": return &"ghost"
	return &""


## Aura roles work a room instead of a queue job: &"perform" (entertainer), &"station" (chef) or &"".
func aura_kind() -> StringName:
	if not def.is_aura():
		return &""
	return &"perform" if role == &"entertainer" else &"station"


## Energy 0..1 (for bars).
func energy_frac() -> float:
	return clampf(energy / 100.0, 0.0, 1.0)
