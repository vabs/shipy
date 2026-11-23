class_name Ghost
extends RefCounted
## Underworld ghost drifting along a deck through walls.

var id: int = 0
var deck: int = 0
var deck_f: float = 0.0
var prev_deck_f: float = 0.0
var x: float = 0.0
var prev_x: float = 0.0
## -1 drifts left, +1 drifts right.
var dir: int = 1
var speed: float = SimConst.GHOST_SPEED
var bob_phase: float = 0.0
var banished: bool = false
var hit: Dictionary = {}
var age: float = 0.0
## Always &"drift" (uniform with other entities).
var state: StringName = &"drift"

## Same as `dir` (uniform with other entities).
var facing: int:
	get:
		return dir
