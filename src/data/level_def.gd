class_name LevelDef
extends Resource
## One campaign level (see docs/SPEC.md §4).

@export var id: StringName = &""
## 1..6 within the destination
@export var index: int = 1
## 1..18 over the whole campaign
@export var campaign_index: int = 1
@export var display_name: String = ""
@export var blurb: String = ""
@export var destination: StringName = &"med"
@export var hull: StringName = &"small"
@export var budget: int = 1000
@export var ticket_price: int = 20
@export var duration: float = 180.0
## [{"t": float, "count": int}]
@export var waves: Array[Dictionary] = []
@export var archetype_weights: Dictionary = {}
## [{"t": float, "event": StringName}]
@export var scheduled_events: Array[Dictionary] = []
@export var random_event_interval: float = 0.0
## 3 goals: {"type":"rating","value":55} | {"type":"profit","value":800} |
## {"type":"no_lost_guests"} | {"type":"served","value":120}
@export var star_goals: Array[Dictionary] = []
## [{"room": id, "deck": int, "x": int, "locked": bool}]
@export var preset_rooms: Array[Dictionary] = []
## role id -> count of crew pre-hired (free)
@export var preset_staff: Dictionary = {}
@export var tutorial: bool = false
@export var mutiny_enabled: bool = true
## Difficulty knobs shaping the campaign curve (1.0 = the base numbers in the room/guest tables).
## Multiplies every room's mess chance.
@export var mess_mult: float = 1.0
## Multiplies room health (higher = breaks less often).
@export var health_mult: float = 1.0
## Multiplies all need decay rates.
@export var decay_mult: float = 1.0
## Multiplies queue patience.
@export var patience_mult: float = 1.0
## Multiplies the destination's ghost interval (higher = fewer ghosts).
@export var ghost_interval_mult: float = 1.0
## Staff get tired (docs/SPEC.md §13.4). Off by default; the campaign turns it on from campaign index 7.
@export var staff_fatigue: bool = false
## VIP guests (docs/SPEC.md §13.5): [{"t": float, "kind": &"critic" | &"celebrity" | &"inspector"}], each boards at time t.
@export var vips: Array[Dictionary] = []
## Share of every wave that boards as couples / families (docs/SPEC.md §13.6). 0 = everybody travels alone.
@export var group_ratio: float = 0.0
## Mid-voyage port stop (docs/SPEC.md §13.8): {} = none, else {"t": float, "name": String, "disembark": float (share of the guests
## aboard who go on excursion), "board": int (new guests boarding after the refit)}.
@export var port_stop: Dictionary = {}


## Everybody who boards: the waves plus the scheduled VIPs plus the guests joining at the port stop.
func total_guests() -> int:
	var n: int = vips.size() + port_board()
	for w in waves:
		n += int(w.get("count", 0))
	return n


## The most people aboard at the same time (cabin sizing): the same as `total_guests()` unless a port stop sends part of the crowd
## ashore, because excursion guests free their beds before the boarding wave arrives.
func peak_guests() -> int:
	if port_stop.is_empty():
		return total_guests()
	var stop_t: float = float(port_stop.get("t", 0.0))
	var before: int = 0
	var after: int = 0
	for w in waves:
		if float(w.get("t", 0.0)) <= stop_t:
			before += int(w.get("count", 0))
		else:
			after += int(w.get("count", 0))
	for v in vips:
		if float(v.get("t", 0.0)) <= stop_t:
			before += 1
		else:
			after += 1
	var gone: int = int(round(clampf(float(port_stop.get("disembark", 0.0)), 0.0, 1.0) * float(before)))
	return maxi(before, before - gone + port_board() + after)


## Guests who board at the mid-voyage port stop (0 without one).
func port_board() -> int:
	return maxi(int(port_stop.get("board", 0)), 0) if not port_stop.is_empty() else 0


## What a level brings besides the basics, for the map cards: [{icon, text, tint}] (VIPs, couples and families, storms, a port stop,
## tired crew). Pure data, so the tests can read it headless.
func features() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not vips.is_empty():
		var kinds: Array[String] = []
		for v in vips:
			var k: String = String(v.get("kind", "")).capitalize()
			if not kinds.has(k):
				kinds.append(k)
		out.append({"icon": &"vip", "tint": Color("FFE3A0"), "text": "%d VIP%s aboard: %s" % [vips.size(), "" if vips.size() == 1 else "s", ", ".join(kinds)]})
	if group_ratio > 0.0:
		out.append({"icon": &"family", "tint": Color("FFD0DC"), "text": "Couples and families with kids"})
	var storms: int = 0
	for e in scheduled_events:
		if StringName(e.get("event", &"")) == &"storm":
			storms += 1
	if storms > 0:
		out.append({"icon": &"storm", "tint": Color("C9DDF2"), "text": "A storm is forecast"})
	elif random_event_interval > 0.0 and campaign_index >= 8:
		out.append({"icon": &"storm", "tint": Color("C9DDF2"), "text": "Storms may roll in"})
	if not port_stop.is_empty():
		out.append({"icon": &"event", "tint": Color("CFEFD9"), "text": "Port stop: %s (quick refit)" % String(port_stop.get("name", "port"))})
	if staff_fatigue:
		out.append({"icon": &"zzz", "tint": Color("DCD3F2"), "text": "Crew get tired"})
	return out
