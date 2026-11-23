class_name PortUndo
extends RefCounted
## Snapshot-based undo for the port phase (place / move / sell / upgrade / hire / fire).
## Call push() BEFORE mutating the PortState; call drop_last() if the mutation turned out to fail.

class Snap:
	var label: String = ""
	var rooms: Array[PlacedRoom] = []
	var budget: int = 0
	var hired: Dictionary = {}

const MAX_STEPS: int = 80

var _stack: Array[Snap] = []


func push(port: PortState, label: String) -> void:
	var s := Snap.new()
	s.label = label
	for r in port.layout.rooms:
		s.rooms.append(r.copy())
	s.budget = port.budget
	s.hired = port.hired.duplicate()
	_stack.append(s)
	if _stack.size() > MAX_STEPS:
		_stack.pop_front()


func drop_last() -> void:
	if not _stack.is_empty():
		_stack.pop_back()


func can_undo() -> bool:
	return not _stack.is_empty()


func steps() -> int:
	return _stack.size()


func peek_label() -> String:
	return _stack.back().label if not _stack.is_empty() else ""


func clear() -> void:
	_stack.clear()


## Restores the previous snapshot. Returns its label ("" when there was nothing to undo).
func undo(port: PortState) -> String:
	if _stack.is_empty():
		return ""
	var s: Snap = _stack.pop_back()
	port.layout.rooms.clear()
	for r in s.rooms:
		port.layout.rooms.append(r.copy())
	port.budget = s.budget
	port.hired = s.hired.duplicate()
	port.grid.invalidate_graph()
	port.changed.emit()
	return s.label
