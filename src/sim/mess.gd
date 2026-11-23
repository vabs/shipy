class_name Mess
extends RefCounted
## A spill in a corridor. `x` is a cell centre.

var id: int = 0
var deck: int = 0
var x: float = 0.0
var clean_progress: float = 0.0
var room_uid: int = -1
var age: float = 0.0
## Seconds until this (neglected) mess may spread again.
var spread_t: float = SimConst.MESS_SPREAD_INTERVAL
