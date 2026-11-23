class_name Job
extends RefCounted
## A task for crew. kind: &"mess" | &"repair".

var id: int = 0
var kind: StringName = &"mess"
var deck: int = 0
var x: float = 0.0
var target_id: int = 0
## StaffMember.id or -1
var claimed_by: int = -1
