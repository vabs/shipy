class_name SimConst
extends RefCounted
## Shared constants used by sim, render and UI. See docs/SPEC.md §2.

## Fixed simulation step in seconds.
const TICK: float = 0.1
## Pixels per logical cell (x axis) at zoom 1.
const CELL_W: float = 40.0
## Pixels per deck (y axis) at zoom 1.
const DECK_H: float = 76.0

const NEEDS: Array[StringName] = [&"rest", &"hunger", &"fun", &"hygiene"]

# --- Simulation tuning (docs/SPEC.md §5). Added by the SIM agent; the balance pass tunes these. ---
## Need order used by Guest.nv (matches NEEDS).
const N_REST: int = 0
const N_HUNGER: int = 1
const N_FUN: int = 2
const N_HYGIENE: int = 3
## Base decay per second, same order as NEEDS.
const BASE_DECAY: Array[float] = [0.45, 0.80, 1.00, 0.60]

## Satisfaction per second: all needs >= 50, each need < 30, and the extra for each need < 15.
static var SAT_GOOD_RATE: float = 0.3
## Mild recovery while no need is below 30 (but some are below 50).
static var SAT_OK_RATE: float = 0.06
static var SAT_LOW_RATE: float = 0.45
static var SAT_CRIT_RATE: float = 0.3
## Satisfaction gained when a use finishes (normal / favourite room).
static var SAT_USE_GAIN: float = 5.0
static var SAT_USE_GAIN_FAV: float = 10.0

## Guests board with needs in this range (a narrower range than 55..90 makes meals and queues cluster).
static var INITIAL_NEED_MIN: float = 58.0
static var INITIAL_NEED_MAX: float = 80.0

const GUEST_SPEED: float = 2.2
## Wander strolls move at this fraction of GUEST_SPEED.
const STROLL_SPEED_MULT: float = 0.55
const STAIRS_TIME_PER_DECK: float = 1.6
const ELEVATOR_TIME_PER_DECK: float = 0.5
const ELEVATOR_WAIT: float = 1.0
const ELEVATOR_CAPACITY: int = 4
const CREW_SPAWN_X: float = 1.5
const GANGWAY_X: float = 0.5

const TIER2_UNLOCK_LEVEL: int = 4
const TIER3_UNLOCK_LEVEL: int = 10
const SELL_REFUND: float = 0.75
const MID_VOYAGE_HIRE_MULT: float = 1.5

const MUTINY_RATING: float = 20.0
const MUTINY_TIME: float = 30.0
const WAVE_SPREAD: float = 4.0

const QUEUE_SPACING: float = 0.45
const QUEUE_PATIENCE: float = 28.0
const AVOID_ROOM_TIME: float = 20.0
const MESS_SLIP_CHANCE: float = 0.25
const SLIP_TIME: float = 1.2
const PLAYER_MESS_CLICK: float = 0.34
const PLAYER_REPAIR_RATE: float = 0.4
## A mess left alone longer than MESS_SPREAD_AGE seconds may spread to a neighbouring cell every
## MESS_SPREAD_INTERVAL seconds (stains compound on busy corridors; per-deck cap still applies).
const MESS_SPREAD_AGE: float = 12.0
const MESS_SPREAD_INTERVAL: float = 7.0
const MESS_SPREAD_CHANCE: float = 0.6
## Guests queueing at a broken room lose patience this much faster and this much extra satisfaction/s.
const BROKEN_QUEUE_PATIENCE_MULT: float = 1.7
const BROKEN_QUEUE_SAT_DRAIN: float = 0.35
const MAX_MESSES_PER_DECK: int = 4
const MAX_BROKEN_PER_DECK: int = 2
const SICK_RECOVER_TIME: float = 75.0
const SICK_INFECT_RADIUS: float = 1.2
const SICK_INFECT_CHANCE: float = 0.04
const GHOST_SPEED: float = 1.2
const GHOST_RADIUS: float = 1.5


## Ship-local pixel position of a logical point. y is the FLOOR of the (possibly fractional) deck.
static func to_px(x: float, deck_f: float) -> Vector2:
	return Vector2(x * CELL_W, -deck_f * DECK_H)


## Inverse of to_px: returns Vector2(x_cells, deck_f) where deck_f is the floor-relative deck.
static func from_px(p: Vector2) -> Vector2:
	return Vector2(p.x / CELL_W, -p.y / DECK_H)


## Pixel rect of a room occupying [x, x+width) on deck (top-left origin, positive size).
static func room_rect(deck: int, x: int, width: int, decks_tall: int = 1) -> Rect2:
	var top_left := Vector2(x * CELL_W, -(deck + decks_tall) * DECK_H)
	return Rect2(top_left, Vector2(width * CELL_W, decks_tall * DECK_H))
