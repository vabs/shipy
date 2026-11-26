class_name Walker
extends RefCounted
## Base class for anything that walks the ship (Guest, StaffMember): position, interpolation
## snapshots and route following across stairs and elevators.
##
## `deck` is the last deck the walker stood on; `deck_f` is continuous (changes while climbing or
## riding). Renderers should interpolate prev_x/x and prev_deck_f/deck_f.

const T_NONE: int = 0
const T_CLIMB: int = 1
const T_WAIT: int = 2
const T_RIDE: int = 3

var x: float = 0.0
var prev_x: float = 0.0
var deck: int = 0
var deck_f: float = 0.0
var prev_deck_f: float = 0.0
## -1 faces left (towards the stern), +1 faces right (towards the bow).
var facing: int = 1
var state: StringName = &"idle"
var walk_phase: float = 0.0
## When false (crew) `state` is never replaced by climb / elevator_wait / elevator_ride.
var report_travel: bool = true
## Route as parallel arrays (mode, deck, x per waypoint) and the index of the one being followed.
## Modes: 0 = walk, 1 = stairs, 2 = elevator. Plan routes with plan_route(); read-only for renderers.
var wp_mode: PackedInt32Array = PackedInt32Array()
var wp_deck: PackedInt32Array = PackedInt32Array()
var wp_x: PackedFloat64Array = PackedFloat64Array()
var wp_i: int = 0
## Vertical travel bookkeeping.
var travel_mode: int = T_NONE
var travel_t: float = 0.0
var _travel_dur: float = 0.0
var _from_deck: int = 0
var _to_deck: int = 0
var _col: int = 0
var _resume_state: StringName = &"walk"


func snapshot() -> void:
	prev_x = x
	prev_deck_f = deck_f


func set_position(new_deck: int, new_x: float) -> void:
	deck = new_deck
	deck_f = float(new_deck)
	x = new_x
	prev_x = new_x
	prev_deck_f = deck_f


func has_route() -> bool:
	return wp_i < wp_mode.size()


func clear_route() -> void:
	wp_mode.resize(0)
	wp_deck.resize(0)
	wp_x.resize(0)
	wp_i = 0


## Number of waypoints left on the route.
func route_left() -> int:
	return maxi(wp_mode.size() - wp_i, 0)


## True while climbing stairs or using an elevator (route can't be changed safely).
func vertical_busy() -> bool:
	return travel_mode != T_NONE


## Plans a route to (t_deck, t_x). Returns false if unreachable. Does not touch `state`.
func plan_route(grid: ShipGrid, t_deck: int, t_x: float) -> bool:
	var g: WalkGraph = grid.graph
	var a: int = g.node(deck, int(x))
	var b: int = g.node(t_deck, int(t_x))
	if a != b and not g.reachable(a, b):
		return false
	var base: Array = g.route(a, b)
	clear_route()
	for wp in base:
		var m: StringName = wp["mode"]
		wp_mode.append(0 if m == &"walk" else (1 if m == &"stairs" else 2))
		wp_deck.append(int(wp["deck"]))
		wp_x.append(float(wp["x"]))
	var last_i: int = wp_mode.size() - 1
	if last_i >= 0 and wp_mode[last_i] == 0 and wp_deck[last_i] == t_deck:
		wp_x[last_i] = t_x
	else:
		wp_mode.append(0)
		wp_deck.append(t_deck)
		wp_x.append(t_x)
	return true


func begin_ride() -> void:
	travel_mode = T_RIDE
	travel_t = 0.0
	if report_travel:
		state = &"elevator_ride"


## Cancels a climb, an elevator wait or an elevator ride on the spot (the walker leaves the ship mid-hop): gives its place in the
## waiting line / the car back to `transit` and stands on the nearest deck. The route is left alone (the caller clears or re-plans it).
func abort_travel(transit: Transit) -> void:
	if travel_mode == T_NONE:
		return
	if transit != null:
		if travel_mode == T_WAIT:
			transit.dequeue(self, _col)
		elif travel_mode == T_RIDE:
			transit.release(_col)
	travel_mode = T_NONE
	travel_t = 0.0
	deck = clampi(int(round(deck_f)), mini(_from_deck, _to_deck), maxi(_from_deck, _to_deck))
	deck_f = float(deck)
	if report_travel:
		state = _resume_state


## Advances along the route by `dt` seconds. Returns true once the route is finished.
## `base_state` is restored after a vertical hop.
func step_route(dt: float, speed: float, transit: Transit, base_state: StringName) -> bool:
	var rem: float = dt
	var guard: int = 0
	while rem > 0.00001 and guard < 8:
		guard += 1
		if travel_mode == T_CLIMB:
			travel_t += rem
			if travel_t >= _travel_dur:
				rem = travel_t - _travel_dur
				deck = _to_deck
				deck_f = float(_to_deck)
				travel_mode = T_NONE
				if report_travel:
					state = _resume_state
				wp_i += 1
				continue
			deck_f = lerpf(float(_from_deck), float(_to_deck), travel_t / _travel_dur)
			return false
		elif travel_mode == T_WAIT:
			travel_t += rem
			return false
		elif travel_mode == T_RIDE:
			travel_t += rem
			if travel_t >= _travel_dur:
				rem = travel_t - _travel_dur
				deck = _to_deck
				deck_f = float(_to_deck)
				travel_mode = T_NONE
				if report_travel:
					state = _resume_state
				if transit != null:
					transit.release(_col)
				wp_i += 1
				continue
			deck_f = lerpf(float(_from_deck), float(_to_deck), travel_t / _travel_dur)
			return false
		if wp_i >= wp_mode.size():
			return true
		var mode: int = wp_mode[wp_i]
		var wx: float = wp_x[wp_i]
		if mode == 0:
			var dx: float = wx - x
			var step: float = speed * rem
			if absf(dx) <= step:
				if speed > 0.0:
					rem -= absf(dx) / speed
				x = wx
				wp_i += 1
				walk_phase += absf(dx) * 1.7
			else:
				var dirn: float = signf(dx)
				x += dirn * step
				facing = 1 if dirn > 0.0 else -1
				walk_phase += step * 1.7
				return false
		elif mode == 1:
			_resume_state = base_state
			_from_deck = deck
			_to_deck = wp_deck[wp_i]
			_travel_dur = SimConst.STAIRS_TIME_PER_DECK * float(absi(_to_deck - _from_deck))
			travel_mode = T_CLIMB
			travel_t = 0.0
			x = wx
			if report_travel:
				state = &"climb"
		elif mode == 2:
			_resume_state = base_state
			_from_deck = deck
			_to_deck = wp_deck[wp_i]
			_col = int(wx)
			_travel_dur = SimConst.ELEVATOR_TIME_PER_DECK * float(absi(_to_deck - _from_deck))
			travel_mode = T_WAIT
			travel_t = 0.0
			x = wx
			if report_travel:
				state = &"elevator_wait"
			if transit != null:
				transit.enqueue(self, _col)
			else:
				begin_ride()
		else:
			wp_i += 1
	return wp_i >= wp_mode.size() and travel_mode == T_NONE
