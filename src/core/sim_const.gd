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

# --- Crew roles & fatigue (docs/SPEC.md §13.3 / §13.4) ---
## Energy drained per second while working, walking and while an aura role (entertainer / chef) is performing.
static var STAFF_DRAIN_WORK: float = 1.0
static var STAFF_DRAIN_WALK: float = 0.2
static var STAFF_DRAIN_AURA: float = 0.6
## Below this energy a crew member is tired: slower walking, slower work.
static var STAFF_TIRED_ENERGY: float = 30.0
static var STAFF_TIRED_SPEED: float = 0.85
static var STAFF_TIRED_WORK: float = 1.2
## Energy regained per second in a crew quarters bunk (x the quarters' tier speed) and napping on the spot.
static var STAFF_REST_RATE: float = 12.0
static var STAFF_NAP_RATE: float = 5.0
## Medic / warden: how close (cells) the target must be to start working, and how often the chase is re-planned.
const MEDIC_REACH: float = 1.0
const WARDEN_REACH: float = 1.0
const FOLLOW_REPLAN: float = 0.5
## Entertainer: re-evaluates every ENTERTAINER_INTERVAL s, needs a queue of ENTERTAINER_MIN_QUEUE, affects guests
## within ENTERTAINER_RADIUS cells; a player-ordered show lasts ENTERTAINER_STAY s.
const ENTERTAINER_INTERVAL: float = 3.0
const ENTERTAINER_MIN_QUEUE: int = 3
const ENTERTAINER_RADIUS: float = 2.0
const ENTERTAINER_STAY: float = 20.0
## Cheered queue guests: patience drain x AURA_PATIENCE_MULT, queue sat drain replaced by +AURA_SAT_RATE, fun +AURA_FUN_RATE per s.
const AURA_PATIENCE_MULT: float = 0.5
const AURA_SAT_RATE: float = 0.1
const AURA_FUN_RATE: float = 0.4
## Chef: re-evaluates the food room every CHEF_INTERVAL s; a stationed chef speeds service and cuts mess chance.
const CHEF_INTERVAL: float = 10.0
const CHEF_SERVICE_MULT: float = 0.7
const CHEF_MESS_MULT: float = 0.6

# --- VIP guests (docs/SPEC.md §13.5) ---
## A VIP counts this many times in the ship rating mean.
static var VIP_RATING_WEIGHT: float = 3.0
## Verdict money: a great review pays, a bad one costs and sours the guests standing nearby.
const VIP_GREAT_PAY: int = 250
const VIP_BAD_COST: int = 150
const VIP_BAD_RADIUS: float = 4.0
const VIP_BAD_SAT: float = 10.0
## Critic: boards hungry; each food use is worth points by how long the wait was and whether the door was clean.
const CRITIC_HUNGER: float = 25.0
const CRITIC_MEALS: int = 2
const CRITIC_FAST_WAIT: float = 8.0
const CRITIC_OK_WAIT: float = 20.0
const CRITIC_MESS_RADIUS: float = 2.0
const CRITIC_POINTS_FAST: float = 40.0
const CRITIC_POINTS_OK: float = 20.0
const CRITIC_RESTAURANT_MULT: float = 1.5
static var CRITIC_GREAT: float = 70.0
static var CRITIC_OK: float = 35.0
## Celebrity: impatient, fun-seeking, pulls a crowd to whatever they use; judged on mean mood over the review window.
static var CELEB_PATIENCE_MULT: float = 0.4
const CELEB_APPEAL_MULT: float = 1.5
const CELEB_FUN_DECAY_MULT: float = 1.4
const CELEB_START_FUN: float = 40.0
const CELEB_REVIEW_WINDOW: float = 90.0
static var CELEB_GREAT: float = 70.0
static var CELEB_OK: float = 45.0
## Inspector: strolls every deck end to end counting spills and broken rooms (within INSPECT_RADIUS cells).
static var INSPECTOR_GREAT: int = 4
static var INSPECTOR_OK: int = 9
const INSPECT_SPEED_MULT: float = 0.85
const INSPECT_RADIUS: float = 2.0
const INSPECT_SCAN: float = 0.2

# --- Guest groups & kids (docs/SPEC.md §13.6) ---
## A group that cannot share a cabin splits up: every member loses this much satisfaction when boarding.
static var GROUP_SPLIT_SAT: float = 5.0
## Members within GROUP_TOGETHER_RADIUS cells on the same deck gain GROUP_TOGETHER_RATE satisfaction per second.
const GROUP_TOGETHER_RADIUS: float = 3.0
static var GROUP_TOGETHER_RATE: float = 0.1
## When a member storms off, every other member loses this much.
const GROUP_STORM_SAT: float = 15.0
## An idle follower adopts the leader's target when it satisfies a need below this.
const GROUP_ADOPT_NEED: float = 75.0
## Followers trot (stroll speed x this) to keep up with their leader.
const GROUP_CATCHUP_MULT: float = 1.7
## Kids per group, cycled: family (1 kid), couple, family (2 kids), couple. Deterministic so the port manifest is exact.
const GROUP_KIDS_PATTERN: Array[int] = [1, 0, 2, 0]

# --- Storms (docs/SPEC.md §13.7) ---
## Seasickness: every SEASICK_INTERVAL s each guest rolls SEASICK_CHANCE (x SEASICK_CABIN_MULT inside a cabin); a seasick guest
## loses hygiene and satisfaction for SEASICK_DURATION s (not contagious; the medbay or a medic cures at once).
const SEASICK_INTERVAL: float = 5.0
const SEASICK_CHANCE: float = 0.06
const SEASICK_CABIN_MULT: float = 0.3
const SEASICK_DURATION: float = 25.0
const SEASICK_HYGIENE_RATE: float = 1.0
const SEASICK_SAT_RATE: float = 0.3
## Weather intensity eases 0 -> 1 over this many seconds at both ends of a storm.
const STORM_EASE: float = 4.0

# --- Mid-voyage port stop (docs/SPEC.md §13.8) ---
## Seconds the ship takes to glide up to the quay (sea scroll easing to a stop) before the excursion guests walk off.
const DOCK_TIME: float = 7.0
## Excursion guests walk to the gangway at this multiple of the usual speed; the walk-off is cut short after EXCURSION_MAX s.
const EXCURSION_SPEED_MULT: float = 1.15
const EXCURSION_MAX: float = 14.0
## Seconds after "Cast off" before the dock has slid away and the ship is at full speed again.
const DEPART_TIME: float = 4.0
## Quick refit prices are 1.0x (rooms and upgrades) and the crew come at their normal wage (SimWorld.mid_voyage_hire_cost).
const REFIT_HIRE_MULT: float = 1.0


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
