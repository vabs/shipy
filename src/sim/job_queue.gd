class_name JobQueue
extends RefCounted
## Open jobs for the crew. Staff claim nearest-first (see StaffSim).

var jobs: Array[Job] = []
var _next_id: int = 1


func post(kind: StringName, deck: int, x: float, target_id: int) -> Job:
	var existing: Job = find(kind, target_id)
	if existing != null:
		return existing
	var j := Job.new()
	j.id = _next_id
	_next_id += 1
	j.kind = kind
	j.deck = deck
	j.x = x
	j.target_id = target_id
	jobs.append(j)
	return j


func find(kind: StringName, target_id: int) -> Job:
	for j in jobs:
		if j.kind == kind and j.target_id == target_id:
			return j
	return null


func remove(job: Job) -> void:
	jobs.erase(job)


func unclaimed(kind: StringName) -> Array[Job]:
	var out: Array[Job] = []
	for j in jobs:
		if j.kind == kind and j.claimed_by == -1:
			out.append(j)
	return out


func count_of(kind: StringName) -> int:
	var n: int = 0
	for j in jobs:
		if j.kind == kind:
			n += 1
	return n
