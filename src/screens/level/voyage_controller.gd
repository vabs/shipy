class_name VoyageController
extends Node
## Voyage driver: fixed-step accumulator (SimConst.TICK) x game speed (0/1/2/3) with render interpolation.
##
##   world: SimWorld            speed: int (0 = paused, 1..3)
##   alpha: float               interpolation factor between the previous and the current tick (0..1)
##   hold_room_uid: int         while >= 0 the player holds the repair button on that room
##   signal speed_changed(speed)   signal ticked()   signal finished(result)
##   set_speed(s) / toggle_pause() / fast_forward(seconds) / start_delay (seconds before the clock starts)

signal speed_changed(speed: int)
signal ticked
signal finished(result: Dictionary)

const MAX_STEPS_PER_FRAME: int = 8
const MAX_FRAME: float = 0.25

var world: SimWorld = null
var speed: int = 1
var last_speed: int = 1
var alpha: float = 1.0
var hold_room_uid: int = -1
## True only while the voyage is paused AND the hold is allowed (the tutorial pauses on purpose and asks for a
## hold-to-repair). Normal paused play never repairs: VoyageInput keeps this false.
var paused_hold_ok: bool = false
var start_delay: float = 0.0
var autoplayer: AutoPlayer = null
## Real seconds of animation clock that advance (frozen while paused).
var anim_clock: float = 0.0

var _acc: float = 0.0
var _ended_emitted: bool = false


func setup(w: SimWorld) -> void:
	world = w
	alpha = 1.0
	_acc = 0.0
	_ended_emitted = false
	w.voyage_ended.connect(_on_ended)


func _on_ended(result: Dictionary) -> void:
	if _ended_emitted:
		return
	_ended_emitted = true
	finished.emit(result)


func is_paused() -> bool:
	return speed == 0


func set_speed(s: int) -> void:
	s = clampi(s, 0, 3)
	if s == speed:
		return
	if speed > 0:
		last_speed = speed
	speed = s
	speed_changed.emit(speed)


func toggle_pause() -> void:
	if speed == 0:
		set_speed(maxi(last_speed, 1))
	else:
		set_speed(0)


## Runs the sim synchronously for `seconds` of voyage time (used for --sim-seconds and tests).
func fast_forward(seconds: float) -> void:
	var n: int = int(round(seconds / SimConst.TICK))
	for i in n:
		if world.finished:
			break
		_step()
	alpha = 1.0


func _step() -> void:
	if autoplayer != null:
		autoplayer.tick(SimConst.TICK)
	if hold_room_uid >= 0:
		world.player_hold_repair(hold_room_uid, SimConst.TICK)
	world.tick(SimConst.TICK)
	ticked.emit()


func _process(delta: float) -> void:
	if world == null or world.finished:
		return
	delta = minf(delta, MAX_FRAME)
	if speed > 0:
		anim_clock += delta * float(speed)
	if start_delay > 0.0:
		start_delay -= delta
		return
	if speed == 0:
		# Paused: everything is frozen, except a hold the tutorial explicitly allows (real time).
		if hold_room_uid >= 0 and paused_hold_ok:
			world.player_hold_repair(hold_room_uid, delta)
		return
	_acc += delta * float(speed)
	var steps: int = 0
	while _acc >= SimConst.TICK and steps < MAX_STEPS_PER_FRAME:
		_acc -= SimConst.TICK
		steps += 1
		_step()
		if world.finished:
			break
	if steps >= MAX_STEPS_PER_FRAME:
		_acc = 0.0
	alpha = clampf(_acc / SimConst.TICK, 0.0, 1.0)
