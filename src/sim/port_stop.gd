class_name PortStop
extends RefCounted
## Mid-voyage port stop (docs/SPEC.md §13.8). Owned by SimWorld as `port_stop`; a level opts in with `LevelDef.port_stop`
## `{t, name, disembark, board}`.
##
## Timeline (all in sim seconds, driven by SimWorld.tick):
##   t                       the ship starts to dock: `port_stop_started(name)`, a running storm ends, `dock_progress` eases 0 -> 1 over
##                           SimConst.DOCK_TIME while the sea scroll eases to a stop and the dock slides in      (phase `docking`)
##   + DOCK_TIME             the excursion: `disembark` x the guests aboard (random, never a VIP whose review is still open) walk off
##                           to the gangway for good. They keep their satisfaction in the rating and are not lost  (phase `excursion`)
##   all ashore              `port_stop_ready()`; the sim holds still (SimWorld.tick does nothing) until the player casts off.
##                           The Quick refit (SimWorld.add_room / upgrade_room / hire_staff_mid_voyage) is open     (phase `ready`)
##   SimWorld.cast_off()     `board` new guests board as a wave, `port_stop_ended()`, the dock slides away over DEPART_TIME
##                           and the voyage goes on                                                                 (phase `departing`)
## `SimWorld.refit_manual` decides who casts off: the level screen sets it (the player presses "Cast off"); with the default
## (false) the sim casts off by itself the moment it is ready, so headless runs and tests never stall.

const NONE: StringName = &""
const DOCKING: StringName = &"docking"
const EXCURSION: StringName = &"excursion"
const READY: StringName = &"ready"
const DEPARTING: StringName = &"departing"
const DONE: StringName = &"done"

## The level has a port stop at all.
var configured: bool = false
var t: float = 0.0
var stop_name: String = ""
var disembark: float = 0.0
var board: int = 0

var phase: StringName = NONE
var phase_t: float = 0.0
## 0 = at sea, 1 = alongside the quay (eases in while docking, out while departing); the renderers slide the dock in with it and
## slow the sea scroll down to a stop.
var dock_progress: float = 0.0
## Guests sent ashore / boarded at this stop, and money spent in the quick refit.
var excursion_count: int = 0
var boarded: int = 0
var refit_spent: int = 0
var refit_rooms: int = 0
var refit_upgrades: int = 0


func setup(w: SimWorld) -> void:
	var d: Dictionary = w.level.port_stop
	configured = not d.is_empty()
	phase = NONE
	phase_t = 0.0
	dock_progress = 0.0
	excursion_count = 0
	boarded = 0
	refit_spent = 0
	refit_rooms = 0
	refit_upgrades = 0
	if configured:
		t = float(d.get("t", 0.0))
		stop_name = String(d.get("name", "the harbour"))
		disembark = clampf(float(d.get("disembark", 0.0)), 0.0, 1.0)
		board = maxi(int(d.get("board", 0)), 0)


## The ship is somewhere between "docking at" and "dock gone" (the sea is not at full speed, no new storm may start).
func is_active() -> bool:
	return phase == DOCKING or phase == EXCURSION or phase == READY or phase == DEPARTING


## The sim holds still: the Quick refit is open and the player has not cast off yet.
func is_ready() -> bool:
	return phase == READY


## Rooms may be added / upgraded and crew hired at the normal wage.
func can_refit() -> bool:
	return phase == READY


## Storms must not start from shortly before the stop until it is over.
func blocks_storm(time: float) -> bool:
	return configured and phase != DONE and time >= t - 40.0


## Seconds until the stop starts (negative once it has begun), for HUD hints. 0 without a stop.
func seconds_to_go(time: float) -> float:
	return t - time if configured and phase == NONE else 0.0


func tick(w: SimWorld, dt: float) -> void:
	match phase:
		NONE:
			if configured and w.time >= t:
				_begin(w)
		DOCKING:
			phase_t += dt
			dock_progress = smoothstep(0.0, 1.0, clampf(phase_t / SimConst.DOCK_TIME, 0.0, 1.0))
			if phase_t >= SimConst.DOCK_TIME:
				_begin_excursion(w)
		EXCURSION:
			phase_t += dt
			if _ashore(w) or phase_t >= SimConst.EXCURSION_MAX:
				_finish_excursion(w)
		DEPARTING:
			phase_t += dt
			dock_progress = 1.0 - smoothstep(0.0, 1.0, clampf(phase_t / SimConst.DEPART_TIME, 0.0, 1.0))
			if phase_t >= SimConst.DEPART_TIME:
				phase = DONE
				dock_progress = 0.0


func _begin(w: SimWorld) -> void:
	phase = DOCKING
	phase_t = 0.0
	dock_progress = 0.0
	w.events.end_storms(w)
	w.port_stop_started.emit(stop_name)


## Guests who may go ashore: aboard (not just stepping on at the gangway), and no VIP whose review is still open.
func candidates(w: SimWorld) -> Array[Guest]:
	var out: Array[Guest] = []
	for g in w.guests:
		if not g.is_aboard() or g.mode == Guest.BOARDING:
			continue
		if g.vip_kind != &"" and g.vip_grade == &"":
			continue   # never a VIP mid-review
		out.append(g)
	return out


## How many guests go on excursion: `disembark` x the guests aboard (VIPs mid-review count as aboard but never go).
func excursion_quota(w: SimWorld) -> int:
	var aboard: int = 0
	for g in w.guests:
		if g.is_aboard() and g.mode != Guest.BOARDING:
			aboard += 1
	return int(round(disembark * float(aboard)))


func _begin_excursion(w: SimWorld) -> void:
	phase = EXCURSION
	phase_t = 0.0
	dock_progress = 1.0
	var pool: Array[Guest] = candidates(w)
	var n: int = mini(excursion_quota(w), pool.size())
	# partial Fisher-Yates with the sim rng: the first n entries are the random pick
	for i in n:
		var j: int = i + w.rng.randi() % (pool.size() - i)
		var tmp: Guest = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for i in n:
		w.guest_sim.begin_excursion(w, pool[i])
	excursion_count = n


func _ashore(w: SimWorld) -> bool:
	for g in w.guests:
		if g.mode == Guest.EXCURSION or g.excursion_pending:
			return false
	return true


## Time is up (or everybody is ashore): whoever is still on the way steps off. A guest caught on the stairs or in the lift gives
## their place in the elevator back first, and one who had not even begun the walk (`excursion_pending`) goes through the normal
## excursion bookkeeping (bed freed, counted as an excursion, never lost). Freed beds then go to guests who had none.
func _finish_excursion(w: SimWorld) -> void:
	for g in w.guests:
		if g.mode == Guest.EXCURSION or g.excursion_pending:
			g.abort_travel(w.transit)
			if g.excursion_pending:
				g.excursion_pending = false
				w.guest_sim.begin_excursion(w, g)
			g.clear_route()
			g.mode = Guest.GONE
			g.state = Guest.GONE
	w.room_sim.fill_homeless(w)
	phase = READY
	phase_t = 0.0
	w.port_stop_ready.emit()


## "Cast off": the boarding wave comes aboard and the ship sails on. False unless the stop is ready (nothing else to do).
func cast_off(w: SimWorld) -> bool:
	if phase != READY:
		return false
	boarded = board
	w.director.add_wave(w, board)
	phase = DEPARTING
	phase_t = 0.0
	w.port_stop_ended.emit()
	return true
