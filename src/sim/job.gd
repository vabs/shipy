class_name Job
extends RefCounted
## A task for crew. kind: &"mess" | &"repair" | &"sick" (target = guest id) | &"ghost" (target = ghost id).
## For sick / ghost jobs deck and x follow the target every tick (StaffSim).

var id: int = 0
var kind: StringName = &"mess"
var deck: int = 0
var x: float = 0.0
var target_id: int = 0
## StaffMember.id or -1
var claimed_by: int = -1
## 0..1 progress of a medic treatment / warden channel (mess and repair progress live on the Mess / room).
var progress: float = 0.0
