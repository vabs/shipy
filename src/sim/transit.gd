class_name Transit
extends RefCounted
## Elevator shared state: riders per shaft (capacity 4) and FIFO waiting lines.

## column -> Array[Walker]
var waiting: Dictionary = {}
## column -> int
var riders: Dictionary = {}


func riders_in(col: int) -> int:
	return int(riders.get(col, 0))


func waiting_in(col: int) -> int:
	var w: Array = waiting.get(col, [])
	return w.size()


func enqueue(w: Walker, col: int) -> void:
	if not waiting.has(col):
		waiting[col] = []
	waiting[col].append(w)


func release(col: int) -> void:
	riders[col] = maxi(int(riders.get(col, 0)) - 1, 0)


## Boards waiting walkers (front of line first) while the car has room.
func tick() -> void:
	for col in waiting:
		var line: Array = waiting[col]
		while line.size() > 0 and int(riders.get(col, 0)) < SimConst.ELEVATOR_CAPACITY:
			var w: Walker = line[0]
			if w.travel_t < SimConst.ELEVATOR_WAIT:
				break
			line.remove_at(0)
			riders[col] = int(riders.get(col, 0)) + 1
			w.begin_ride()
