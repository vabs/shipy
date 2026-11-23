# Cruise Ship Manager — Build Spec (v1)

This is the binding contract for everyone writing code in this repo. Source design doc:
"Cruise Ship Manager (2D) — Feature Plan". Scope = every feature marked **MVP** and **v1** in that
doc. "Later" items are out of scope (decor, groups, staff fatigue, medics/entertainers/chefs, weather,
leaderboards).

Working title: **Cruise Ship Manager**. Original game: own name, art, characters, levels. Never
reference or imitate any existing game's name, characters or art.

---------------------------------------------------------------------------------------------------

## 0. Ground rules for all contributors

- **Engine:** Godot **4.7.2** (`godot` is on PATH). GDScript only. Renderer: Forward+ with 2D MSAA.
- **Static typing everywhere** (`var x: int`, typed arrays, `-> void`). No warnings-as-errors games;
  but code must load with **zero script errors**.
- **No hand-authored .tscn beyond `scenes/main.tscn`.** Build node trees and UI in code. (Data lives
  in `.tres` resources, see §4.)
- **Simulation never touches Nodes, rendering, input or audio.** `src/sim/**` is pure `RefCounted`
  logic that can run headless at any speed. Rendering reads sim state; UI calls sim methods.
- **Determinism:** the sim owns a `RandomNumberGenerator` seeded from the level/seed. Never call global
  `randf()`/`randi()` inside sim code.
- **Ownership:** only edit files in directories you own (task brief lists them). If you need a change
  elsewhere, write it in your final report instead of editing.
- After adding/renaming any `class_name` script run `godot --headless --path . --import` once so
  the global class cache updates (otherwise other scripts fail to resolve the class).
- Before finishing, run the project's checks (see §12) and make sure nothing you own prints
  `SCRIPT ERROR`, `Parse Error` or `ERROR:` lines.

### Running things
```bash
# headless tests (sim/unit)
godot --headless --path . --script res://tests/run_tests.gd
# a screen with screenshot (opens a window for ~5 s, then quits). Use your own png path.
godot --path . -- --scene=level --level=med_3 --phase=voyage --autobuild --sim-seconds=60 \
      --shot=/abs/path/out.png --frames=60
```
`src/game/main.gd` parses those flags and passes them to `Router.goto(scene, params)`.

---------------------------------------------------------------------------------------------------

## 1. Directory layout

```
project.godot            scenes/main.tscn        icon.svg
docs/SPEC.md             this file
src/core/                ContentDB autoload, shared constants (SimConst, Palette)
src/data/                Resource class scripts (RoomDef, LevelDef, ...)
src/sim/                 pure simulation (ShipGrid, SimWorld, GuestSim, ...)
src/render/art/          stateless drawing library (RoomArt, GuestArt, IconArt, SeaArt, ...)
src/render/              ShipView, EntityLayer, FX — nodes that draw sim state
src/ui/theme/            UITheme (Theme built in code), fonts helpers, reusable widgets
src/audio/               AudioManager autoload, procedural SFX + music
src/meta/                Settings + SaveManager autoloads
src/game/                main.gd, router.gd, dev harness bits
src/screens/<name>/      one folder per screen: menu, map, level, settings, gallery
data/                    .tres content: rooms/, archetypes/, staff/, events/, destinations/, hulls/, levels/
assets/fonts/            OFL fonts
tests/                   run_tests.gd (headless unit), balance.gd (headless balance sweeps)
tools/                   gen_content.gd (one-off .tres bootstrap)
```

---------------------------------------------------------------------------------------------------

## 2. Coordinates & time

- **Logical space:** `deck` (int, 0 = lowest interior deck, `hull.decks - 1` = open-air **top deck**)
  and `x` (float, in cells, 0 at the stern/left; the bow points right). A room occupies integer cells
  `[x, x + width)` on one deck. Entities have float `x`; the centre of cell `c` is `c + 0.5`.
- **Corridor model:** every cell on every deck is walkable. Guests walk along the deck floor *in front
  of* rooms (side-view convention). Rooms only reserve space; they never block walking.
- Each room has a **door** at its centre cell (`door_x = x + width / 2.0`); guests queue in the
  corridor to the **left** of the door, spaced 0.45 cells, wrapping right if they hit x=0.
- **Vertical travel:** `stairs` (1 cell wide, 2 decks tall: placed at `(d, x)` it occupies `(d, x)`
  and `(d+1, x)`, connects d<->d+1). `elevator` (1 cell wide, occupies column x on **every** deck,
  connects all decks). Rooms other than stairs/elevator are exactly one deck tall.
- **Gangway:** guests board and storm off at the hull's `gangway_deck` (usually 1, or 0 on the small
  hull) at x = 0.5. Crew start at `x = 1.5` on deck 0.
- **Sim tick:** fixed `SimConst.TICK = 0.1` s. Game speed changes how many ticks run per real second
  (0, 1x, 2x, 3x); never the code path. Headless tests just call `tick()` in a loop.
- **Render mapping** (`SimConst`): `CELL_W = 40.0` px, `DECK_H = 76.0` px. Ship-local pixel of a
  logical point: `Vector2(x * CELL_W, -(deck_f) * DECK_H)` where y is the **floor** of that deck,
  deck 0 floor at y = 0, decks stack upward (negative y). Renderers interpolate between the previous
  and current tick using `prev_x`/`prev_deck_f`.

---------------------------------------------------------------------------------------------------

## 3. Game structure

Campaign: 3 destinations × 6 levels = 18 levels. Each level = **port → voyage → results**.

- **Port (build):** start from the level's hull (+ optional preset rooms). Budget-limited. Place /
  move (free) / sell (75% refund of cost + upgrades; `locked` preset rooms can't be sold or moved) /
  upgrade rooms; hire staff; read the guest manifest; "Set sail" (validation must
  pass: every deck that has rooms is connected to the gangway deck; enough cabins is a *warning* not
  an error).
- **Voyage (react):** real-time, 180–300 s. Guests board in waves, pick rooms, queue, make messes,
  wear rooms out, get sick, react to events. Player dispatches staff, clicks messes, holds on broken
  rooms, banishes ghosts, pauses, changes speed, may hire staff mid-voyage (1.5x wage). **No building
  during the voyage.**
- **Results:** stars (0–3), rating, profit breakdown, guests served/lost, new unlocks; Retry / Next /
  Map.
- **Fail state (mutiny):** ship rating < 20% continuously for 30 s → voyage ends, 0 stars. A visible
  warning with countdown shows while below 20%. Disabled on the tutorial level.

### Unlocks / progression
- Levels unlock sequentially inside a destination (previous level ≥ 1 star).
- Destinations unlock by total stars: Mediterranean 0, Arctic 10, Underworld 24 (max 54).
- Rooms unlock by campaign level index (1-based, Med 1–6 = 1–6, Arctic = 7–12, Underworld = 13–18),
  see the room table. Tier II upgrades unlock after clearing level 3; tier III after level 9.
  Generator & water tank unlock at level 3. Elevator unlocks at level 7.
- Results screen lists anything newly unlocked by that clear.

---------------------------------------------------------------------------------------------------

## 4. Data model (`src/data/*.gd`, content in `data/**.tres`)

All defs extend `Resource`, use `@export` fields, and have `class_name`. `ContentDB` (autoload) loads
every `.tres` under `res://data/` (handle `.remap` suffix in exports) and indexes by `id`:
`ContentDB.room(id) -> RoomDef`, `.archetype(id)`, `.staff_role(id)`, `.event(id)`,
`.destination(id)`, `.hull(id)`, `.level(id)`, `.levels_for(destination_id) -> Array[LevelDef]`
(sorted by `index`), `.all_rooms() -> Array[RoomDef]`, `.campaign() -> Array[LevelDef]` (by
`campaign_index`). Sim code takes defs as arguments; it may also use ContentDB when running inside
the game, but tests construct `SimWorld` via ContentDB too, so ContentDB must work headless (autoloads
DO run under `--script` only if the test script instantiates it; tests should `load()` ContentDB's
script and call its loader directly if the autoload is absent).

`tools/gen_content.gd` (run with `godot --headless --path . --script res://tools/gen_content.gd`)
bootstraps all `.tres` from tables. After that, the `.tres` files are the source of truth for
balancing (designers edit them in the inspector); re-running the generator overwrites them, so the
balance pass updates both the generator tables and the `.tres`.

### RoomDef
| field | type | notes |
|---|---|---|
| id | StringName | `cabin`, `buffet`, `toilets`, `bar`, `pool`, `deck_chairs`, `cinema`, `gym`, `arcade`, `restaurant`, `medbay`, `sauna`, `ice_rink`, `casino`, `stairs`, `elevator`, `generator`, `water_tank` |
| display_name | String | |
| category | StringName | `rest`, `food`, `hygiene`, `fun`, `service`, `transport`, `utility` |
| width | int | cells |
| capacity | int | simultaneous users (cabin = sleepers assigned) |
| service_time | float | seconds a use takes |
| satisfies | Dictionary | need -> amount restored over one full use, e.g. `{&"hunger": 85.0}` |
| fun_tag | StringName | `""`, `movies`, `fitness`, `gaming`, `relax`, `water` (archetype matching) |
| appeal | float | base attractiveness multiplier (1.0 typical) |
| spend | int | money earned per use |
| cost | int | build cost |
| upkeep | float | money per minute of voyage |
| power / water | int | utility draw (generator/water_tank have negative = supply) |
| placement | StringName | `interior`, `top_deck`, `any` |
| mess_chance | float | chance a finished use spawns a mess |
| breakdown_time | float | seconds of health; 0 = never breaks |
| wear_per_use | float | seconds of health removed per use |
| unlock_level | int | campaign index that unlocks it (1 = start) |
| destination_lock | StringName | `""` or a destination id; room only offered in that destination |
| tier_bonus | Array[Dictionary] | index 0 = tier II, 1 = tier III: `{"cost": int, "capacity_add": int, "speed_mult": float}` |
| colors | Dictionary | `{"wall": Color, "accent": Color}` hints for art |
| description | String | one line for the catalog |

### Rooms — starting numbers (balance pass may tune)
Cabin capacity is **4** (deviation from the design doc's 2, to keep cabin counts sane).

| id | cat | w | cap | svc s | satisfies | tag | spend | cost | upkeep/min | pwr | wtr | place | mess | brk s | wear | unlock |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| cabin | rest | 2 | 4 | 9 | rest 90 | relax | 0 | 120 | 2 | 0 | 1 | interior | 0.00 | 0 | 0 | 1 |
| buffet | food | 4 | 6 | 7 | hunger 85 | | 4 | 300 | 6 | 3 | 2 | interior | 0.22 | 110 | 5 | 1 |
| toilets | hygiene | 2 | 3 | 5 | hygiene 90 | | 0 | 120 | 3 | 0 | 3 | interior | 0.25 | 90 | 6 | 1 |
| bar | fun | 3 | 5 | 8 | fun 70 | relax | 9 | 250 | 5 | 2 | 1 | interior | 0.18 | 100 | 5 | 1 |
| pool | fun | 6 | 8 | 10 | fun 60, hygiene 35 | water | 3 | 500 | 8 | 2 | 5 | top_deck | 0.12 | 130 | 4 | 1 |
| deck_chairs | rest | 3 | 4 | 9 | rest 55, fun 30 | relax | 0 | 150 | 1 | 0 | 0 | top_deck | 0.06 | 0 | 0 | 1 |
| cinema | fun | 4 | 8 | 12 | fun 90 | movies | 6 | 400 | 7 | 4 | 0 | interior | 0.10 | 120 | 4 | 2 |
| gym | fun | 3 | 4 | 9 | fun 75 | fitness | 3 | 300 | 5 | 2 | 1 | interior | 0.15 | 95 | 6 | 3 |
| medbay | service | 2 | 2 | 6 | (cures sickness) | | 5 | 300 | 6 | 2 | 1 | interior | 0.00 | 0 | 0 | 3 |
| arcade | fun | 3 | 4 | 8 | fun 85 | gaming | 8 | 350 | 6 | 4 | 0 | interior | 0.08 | 85 | 6 | 4 |
| restaurant | food | 4 | 4 | 10 | hunger 100, fun 20 | | 16 | 450 | 8 | 3 | 2 | interior | 0.12 | 120 | 5 | 5 |
| sauna | rest | 2 | 3 | 8 | rest 50, hygiene 60 | relax | 5 | 280 | 5 | 3 | 2 | interior | 0.10 | 100 | 5 | 4 (Med only) |
| ice_rink | fun | 5 | 6 | 10 | fun 90 | | 7 | 600 | 9 | 5 | 2 | interior | 0.10 | 110 | 5 | 7 (Arctic only) |
| casino | fun | 4 | 6 | 10 | fun 95 | gaming | 14 | 650 | 9 | 4 | 1 | interior | 0.12 | 100 | 5 | 13 (Underworld only) |
| stairs | transport | 1 | – | – | – | | 0 | 60 | 0 | 0 | 0 | any (2 decks) | – | 0 | 0 | 1 |
| elevator | transport | 1 | 4 | – | – | | 0 | 400 | 4 | 2 | 0 | all decks | – | 0 | 0 | 7 |
| generator | utility | 1 | – | – | supplies power 8 | | 0 | 200 | 3 | -8 | 0 | interior | – | 0 | 0 | 3 |
| water_tank | utility | 1 | – | – | supplies water 8 | | 0 | 180 | 2 | 0 | -8 | interior | – | 0 | 0 | 3 |

Tier bonuses (rooms with capacity > 0 except cabin/medbay/transport): tier II
`{cost: 60% of base, capacity_add: ceil(cap*0.5), speed_mult: 1.0}`; tier III `{cost: 90% of base,
capacity_add: ceil(cap*0.5), speed_mult: 1.25}` (speed_mult divides service_time). Cabin tiers add
+2 sleepers each. Breakdown health ×1.2 per tier.

### ArchetypeDef
`id, display_name, prop (StringName: sun_hat|headband|glasses_3d|headphones), body_color: Color,
favorite_tags: Array[StringName], favorite_rooms: Array[StringName], decay_mult: Dictionary (need ->
mult), patience_mult_non_favorite: float, quirk_text: String`.

| id | prop | favorites | quirk |
|---|---|---|---|
| holidaymaker | sun_hat | pool, deck_chairs, bar | balanced |
| fitness_fan | headband | gym, pool | hunger decay ×1.5 |
| film_buff | glasses_3d | cinema | patience ×0.6 in non-cinema queues |
| gamer | headphones | arcade, casino | fun decay ×2 when last fun room used was not gaming |

Favorite rooms: utility ×1.6 and +8 satisfaction on finishing (instead of +4).

### StaffDef
`id (janitor|mechanic), display_name, handles (mess|breakdown), wage: int (40 / 60),
work_time: float (janitor 2.5 s per mess, mechanic 5 s per repair), speed: float (cells/s, 3.0)`.
Max staff by hull: small 4, medium 6, large 8.

### EventDef
`id, display_name, description, duration: float (0 = instant), destination_lock, icon: StringName`
plus effect fields interpreted by `EventDirector` (`room_appeal_mult: Dictionary room_id/tag ->
mult`, `need_set: Dictionary need -> value` (caps the need at value), `sick_count: int`,
`break_count: int`, `mess_mult_top_deck: float`, `full_room_bonus: Dictionary`, `ghost_count: int`,
`top_deck_rush: bool`).

| id | effect | lasts |
|---|---|---|
| film_night | cinema appeal ×2.5; every guest's fun capped at 45 | 60 s |
| lunch_rush | every guest's hunger capped at 20 | instant |
| pool_party | top-deck rooms appeal ×1.5, mess chance ×2 on the top deck | 45 s |
| food_poisoning | 3 guests nearest a buffet/restaurant get sick | instant |
| power_surge | 2 random breakable rooms break now | instant |
| captains_dinner | restaurant appeal ×3; finishing a use while the restaurant is full gives +10 satisfaction | 60 s |
| northern_lights (Arctic) | guests rush the top deck: wandering on the top deck restores fun 1.5/s; top-deck appeal ×2.5; cold penalty suspended | 40 s |
| haunting (Underworld) | spawns 4 ghosts at once | instant |
| heat_wave (Med) | hygiene decay ×1.8, pool appeal ×2 | 50 s |

### DestinationDef
`id (med|arctic|underworld), display_name, stars_required, sky_top/sky_bottom/sea colors, twist_text,
hygiene_decay_mult (Med 1.25), top_deck_appeal_mult (Arctic 0.7), top_deck_satisfaction_drain
(Arctic 0.25/s while on top deck), ghost_interval: Vector2 (Underworld: (25, 40) s; else 0),
pool_appeal_mult (Med 1.4), random_events: Array[StringName], new_room: StringName`.

### HullDef
| id | width | decks (incl. top) | gangway_deck | power | water | max_staff |
|---|---|---|---|---|---|---|
| small | 24 | 4 | 1 | 16 | 16 | 4 |
| medium | 32 | 5 | 1 | 26 | 24 | 6 |
| large | 40 | 6 | 1 | 38 | 34 | 8 |

### LevelDef
`id (med_1..med_6, arctic_1.., underworld_1..), index (1..6), campaign_index (1..18), display_name,
blurb, destination, hull, budget, ticket_price, duration (s), waves: Array[Dictionary]
({"t": float, "count": int}), archetype_weights: Dictionary, scheduled_events: Array[Dictionary]
({"t": float, "event": StringName}), random_event_interval: float (0 = none), star_goals:
Array[Dictionary] (3 goals; types: {"type":"rating","value":55} | {"type":"profit","value":800} |
{"type":"no_lost_guests"} | {"type":"served","value":120}), preset_rooms: Array[Dictionary]
({"room": id, "deck": int, "x": int, "locked": bool}), preset_staff: Dictionary, tutorial: bool,
mutiny_enabled: bool`.

Stars = number of goals met (goal 1 is always a rating goal); mutiny = 0 stars.

Level curve (balance pass finalises): Med 1 tutorial (8 guests, small hull, presets, no mutiny) →
Med 6 ~28 guests; Arctic 24–40 guests (medium hull); Underworld 32–56 (medium → large hull).
Durations 180 s (early) to 300 s (late).

---------------------------------------------------------------------------------------------------

## 5. Simulation rules (`src/sim/`)

### Modules (all `RefCounted`, `class_name` as named)
| class | responsibility |
|---|---|
| `ShipLayout` | hull + list of `PlacedRoom` (uid, def, deck, x, tier, locked). Pure data, duplicable. |
| `ShipGrid` | placement checks, place/move/sell/upgrade, utilities, connectivity validation, walk graph (AStar2D) + route cache |
| `PortState` | budget, layout, hired staff counts, manifest summary; all port-phase mutations go through it |
| `SimWorld` | owns everything during a voyage; `tick(dt)`; signals; player-action methods; queries |
| `GuestSim` / `Guest` | need decay, utility scoring, state machine, satisfaction |
| `RoomSim` / `RoomRuntime` | queues, users, service timers, health/breakdown, repair progress |
| `ProblemSim` / `Mess` | mess spawn/slip/cleanup, sickness spread, ghosts |
| `JobQueue` / `StaffMember` | jobs; staff claim nearest; player override |
| `EventDirector` | scheduled + random events, modifiers, destination twists |
| `Economy` | money, income/expense ledger by category |
| `LevelDirector` | waves, voyage clock, rating, mutiny, star scoring, result dict |
| `AutoBuilder` | builds a sensible layout for a level within budget (tests, `--autobuild`, balance) |
| `AutoPlayer` | optional scripted "player" for balance runs (clicks messes, holds repairs, banishes ghosts with a reaction delay) |

Modules talk through signals declared on `SimWorld` (UI/audio subscribe to the same ones).

### ShipGrid rules
- In bounds; no overlap; `top_deck` rooms only on the top deck; `interior` rooms not on the top deck;
  stairs need `(d, x)` and `(d+1, x)` free (`d+1` may be the top deck); elevator needs column x free
  on all decks. Budget and utilities (power/water used ≤ capacity incl. generator/tank supply).
  Room must be unlocked for this level/destination.
- `can_place(def_id, deck, x, ignore_uid := -1) -> Dictionary {ok: bool, reason: String}` with
  short human reasons ("Not enough money", "Top deck only", "Needs 2 free decks", "Overlaps
  Buffet", "Not enough power").
- `validate_for_voyage() -> Dictionary {errors: Array[String], warnings: Array[String]}`. Error: a
  deck with rooms not reachable from the gangway deck. Warnings: cabins < guests, no food, no
  toilets, no fun, no staff.
- Walk graph: one AStar2D point per (deck, cell). Horizontal edges cost 1/guest_speed; stairs edges
  cost 1.6 s per deck; elevator edges cost 0.5 s per deck + 1.0 s. Rebuild only when layout changes.
  Route cache keyed by (from point, to point). Paths are converted to waypoint lists of
  `{deck, x, mode: walk|stairs|elevator}`.

### Guests
- Fields (read by renderers): `id, archetype (ArchetypeDef), deck, x, prev_x, deck_f, prev_deck_f,
  facing (-1|1), state, needs {rest,hunger,fun,hygiene} 0..100 (100 = fully satisfied),
  satisfaction 0..100, sick: bool, cabin_uid, target_uid, queue_index, slip_timer, mood
  (StringName: happy|ok|unhappy|angry|sick|need_<name>), bubble_timer, walk_phase (for bobbing)`.
- States: `boarding, wander, walk, queue, use, climb, elevator_wait, elevator_ride, storm_off, gone`.
- Board at gangway; assigned a cabin with free beds (fill cabins in order of distance to the
  gangway); no cabin → `cabin_uid = -1`, −0.15 sat/s ("homeless").
- Initial needs random 55–90; satisfaction 72.
- Base decay per second: hunger 0.80, fun 1.00, hygiene 0.60, rest 0.45 (× archetype ×
  destination × event multipliers).
- **Choosing**: when idle (wander) re-evaluate every 1.5 s, or immediately when any need < 45.
  Candidates = unbroken rooms that satisfy some need with value < 75 (own cabin only for cabins;
  medbay only when sick and then with ×10 priority).
  `score = Σ_needs urgency(n) × amount(n)/100 × appeal × favourite(1.6) × event/destination mults
  ÷ (walk_time + expected_wait + 4)`, `urgency = clamp((90 − n)/90, 0, 1)^1.5`,
  `expected_wait = queue_len × service_time / capacity`; if `queue_len ≥ capacity` multiply by 0.6
  (crowding). Ties broken by rng. Score below 0.02 → wander (stroll 2–6 cells, sometimes to another
  deck's rail).
- **Queue**: patience 28 s (× archetype quirks; ghosts −8 s on pass). Satisfaction −0.15/s while
  queueing. Patience out → leave queue, −10 satisfaction, mood `angry`, avoid that room 20 s.
- **Use**: occupies a slot; needs restored linearly over `service_time / tier speed_mult`; then +4
  satisfaction (+8 favourite), pay `spend`, maybe spawn mess, add wear; leave → wander.
- **Satisfaction per second**: each need < 30: −0.6; each need < 15: an extra −0.6; all needs ≥ 50:
  +0.25; within 1.5 cells of a mess on the same deck: −0.5; sick: −0.6; Arctic top-deck cold drain.
  Clamp 0..100.
- **Storm off**: satisfaction ≤ 5 for 8 s → walk to gangway (state `storm_off`), then `gone`; counts
  as a lost guest with satisfaction 0 in the rating.
- **Ship rating** = mean satisfaction over all guests boarded so far (gone = 0). 0..100.
- Walk speed 2.2 cells/s; ×0.5 on a mess cell; sick ×0.8. Stepping onto a mess: 25% slip →
  `slip_timer = 1.2` (stand still, comedic animation), −4 satisfaction, `guest_slipped` signal.

### Rooms at runtime (`RoomRuntime`)
`uid, def, deck, x, width, tier, users: Array[int], queue: Array[int], broken: bool, health: float,
repair_progress 0..1, busy_ratio (for art), uses: int, door_x`. Health starts at
`breakdown_time × (1.2^tier_index) × rng(0.8..1.2)`, drops 1/s during voyage and `wear_per_use` per
use. At 0 → broken (unless 2 rooms on that deck are already broken → retry in 10 s): users are
ejected (−3 sat), queue keeps waiting with patience ticking, `room_broken` signal, a repair job is
posted. Repaired → health reset, `room_repaired`.

### Problems
- **Mess**: on a use finishing, `mess_chance` (× event mults) → mess at a corridor cell next to the
  door (door ±1, nearest free). Cap 4 messes per deck. `{id, deck, x(cell centre), clean_progress}`.
  Posts a janitor job. Player click: +0.34 progress per click (3 clicks). Cleaned → `mess_cleaned`.
- **Sickness**: after a buffet use 1.5% chance; `food_poisoning` event. Each sick guest, each second,
  infects one random non-sick guest within 1.2 cells on its deck with p = 0.04. Sick guests go to the
  medbay with top priority; cured there (+3 sat). No medbay → recover after 75 s.
- **Ghosts** (Underworld): spawn at a random deck edge every `ghost_interval` s, drift across the
  deck through walls at 1.2 cells/s with a sine bob; each guest they pass within 1.5 cells: −4
  satisfaction once and queue patience −8 s. Player click banishes (+`ghost_banished`). Ghosts
  leave the far edge if not banished.
- **Fairness caps**: ≤ 4 messes and ≤ 2 broken rooms per deck at once.

### Staff & jobs
- Staff spawn at the crew door (deck 0, x 1.5); speed 3.0 cells/s; use stairs/elevators.
- `JobQueue`: jobs `{id, kind: mess|repair, deck, x, target_id, claimed_by}`. Idle staff of the
  matching role claim the unclaimed job with the lowest path cost (nearest first), re-checked every
  0.5 s. States `idle (patrol slowly near last job), walk, work`. Work progress adds to the same
  progress the player's clicks add to.
- **Player override**: `assign_staff(staff_id, kind, target_id) -> bool` — staff drops its current
  job (which returns to the queue) and takes this one (stealing it from whoever had it).
- Mid-voyage hire: `hire_staff_mid_voyage(role_id) -> bool` costs 1.5× wage from voyage money,
  respects hull max_staff.

### Economy
- Voyage money starts at the budget left over from port. Tickets: `ticket_price` per guest on
  boarding. Spend per use. Upkeep: per room per minute, charged continuously. Wages: paid at hire
  (port). Ledger categories: `tickets, spending, upkeep, wages, hires`. `profit = money_end −
  money_start_of_voyage`.
- Money can go negative during the voyage (no hard stop); profit goals simply fail.

### Events
`EventDirector` fires `scheduled_events` at their times plus, if `random_event_interval > 0`, a
random pick from destination + generic pool every interval × rng(0.8..1.2) (never two at once).
Active modifiers are queryable for UI (`active_events: Array[Dictionary] {id, def, time_left}`).

### LevelDirector
Voyage clock `time`, `duration`; waves spawn guests (spread over 4 s per wave, archetypes by
weights); `rating()`; mutiny timer (`mutiny_time_left`); at `time >= duration` (or mutiny) →
`voyage_ended(result)` once, where `result = {stars, goals: [{text, met}], rating, profit, ledger,
guests_total, guests_lost, served, mutiny: bool, level_id}`.

### SimWorld public API (UI codes against this)
```gdscript
class_name SimWorld extends RefCounted
signal guest_boarded(guest_id: int)
signal guest_stormed_off(guest_id: int)
signal guest_patience_out(guest_id: int, room_uid: int)
signal guest_slipped(guest_id: int)
signal guest_got_sick(guest_id: int)
signal guest_cured(guest_id: int)
signal room_used(room_uid: int, guest_id: int, spend: int)
signal room_broken(room_uid: int)
signal room_repaired(room_uid: int)
signal mess_spawned(mess_id: int)
signal mess_cleaned(mess_id: int)
signal ghost_spawned(ghost_id: int)
signal ghost_banished(ghost_id: int)
signal event_started(event_id: StringName)
signal event_ended(event_id: StringName)
signal wave_started(wave_index: int, count: int)
signal money_changed(money: int, delta: int, reason: StringName)
signal mutiny_warning(seconds_left: float)
signal mutiny_cleared()
signal voyage_ended(result: Dictionary)

func _init(level: LevelDef, layout: ShipLayout, staff_counts: Dictionary, seed: int, money_start: int)
func tick(dt: float) -> void            # dt is always SimConst.TICK in practice
var time: float; var duration: float; var money: int; var finished: bool
var guests: Array[Guest]; var rooms: Array[RoomRuntime]; var staff: Array[StaffMember]
var messes: Array[Mess]; var ghosts: Array[Ghost]; var grid: ShipGrid
func rating() -> float
func guest_by_id(id: int) -> Guest      # also room_by_uid, staff_by_id, mess_by_id, ghost_by_id
func pick_at(deck: int, x: float) -> Dictionary  # {kind: "mess"|"room"|"staff"|"guest"|"ghost"|"", id}
func player_click_mess(mess_id: int) -> void
func player_hold_repair(room_uid: int, dt: float) -> void   # 0.4 progress per second held
func player_banish_ghost(ghost_id: int) -> void
func assign_staff(staff_id: int, kind: StringName, target_id: int) -> bool
func hire_staff_mid_voyage(role: StringName) -> bool
func active_events() -> Array[Dictionary]
func stats() -> Dictionary  # {rating, money, guests_on_board, guests_total, lost, served, problems}
func ledger() -> Dictionary
```
Every entity keeps `prev_x`/`prev_deck_f` (set at the start of each tick) for interpolation.

---------------------------------------------------------------------------------------------------

## 6. Art direction (flat vector, drawn in code)

Mood: sunny, cute, toy-like. Soft gradients, rounded shapes, gentle motion, no outlines heavier than
2 px, warm highlights, cool shadows. Everything drawn with `CanvasItem` draw calls
(`draw_polygon`, `draw_colored_polygon`, `draw_rect`, `draw_circle`, `draw_arc`,
`draw_polyline` with antialiasing, `draw_string` with the UI font). MSAA 2D is on.

- **Palette** (`src/render/art/palette.gd`, `class_name Palette`, constants): navy `#2B3A55`, hull white
  `#F7F4EC`, coral red `#E8505B`, sun yellow `#FFC857`, teal `#3AA0C8`, sea deep `#1F6F99`, mint
  `#7ED6A5`, lilac `#B39DDB`, ink `#1E2433`, plus per-destination skies (Med: peach→sky blue; Arctic:
  pale lavender→ice blue with aurora ribbons; Underworld: deep violet→magenta dusk with green
  will-o'-wisps).
- **Background**: sky gradient, sun/moon, layered clouds, distant scenery per destination (Med
  islands with white villages; Arctic icebergs; Underworld jagged rocks + lanterns), 3 parallax wave
  layers scrolling left (ship moves right), sparkles on water, gulls (Med), snow (Arctic), drifting
  embers/fireflies (Underworld).
- **Ship**: side cutaway. Navy hull below deck 0 with coral stripe at the waterline, portholes, bow
  curve on the right and stern on the left, white superstructure walls with deck separators, a
  funnel and bridge drawn *behind* the top deck (not blocking cells). Water overlaps the hull bottom.
  Whole ship bobs ±3 px and tilts ±0.5° (sine ~0.22 Hz).
- **Rooms**: each type has a recognisable interior (cabin bunks + porthole, buffet counter with
  food trays, toilets stalls with tiles, bar counter + bottles + stools, pool water with shimmer and
  ladder, deck chairs + umbrellas, cinema screen glow + seat rows, gym treadmills/weights, medbay
  red cross + bed, arcade cabinets with glowing screens, restaurant tables + candles, sauna wood +
  steam, ice rink white ice with sparkles, casino roulette + green felt with ghostly purple light,
  stairs zig-zag, elevator shaft + car, generator with spinning fan, water tank). A small sign with
  an icon above the door. Tier stars on the sign. Broken = darkened, sparks + smoke puffs, hazard
  stripes. Empty slots vs used slots visible (guests drawn inside at slot positions).
- **Guests**: bean bodies (rounded capsule ~14×22 px at zoom 1) with archetype body colour, two dot
  eyes, tiny feet that alternate while walking, hop/bob while walking, prop on head (sun hat,
  headband, 3D glasses, headphones). Sick = green tint + wobble. Slipping = spin & fall flat.
  Storming off = red face + steam puffs. Mood bubble above (heart/smile/meh/frown/angry
  scribble/need icon/sick swirl).
- **Staff**: same bean style but navy uniform, janitor with mop + bucket, mechanic with wrench and
  yellow hard hat; working = animated tool.
- **Icons** (`IconArt`): every problem has a unique silhouette *and* colour so it reads in
  grayscale: mess = brown/teal splat puddle, breakdown = orange gear with zig-zag bolt, sick = green
  droplet with swirl, angry = red jagged burst, ghost = white sheet, money = gold coin, star = star.
  Colourblind mode switches to a high-contrast palette (blue/orange/white/black) with the same
  shapes.
- **Feedback**: floating "+$9" texts, star/heart particles on happy use, puffs on clean, sparkles
  on repair, wobble on new problem, camera shake (tiny) on breakdown.

## 7. UI (code-built Controls themed by `UITheme.build() -> Theme`)

- Font: **Fredoka** (OFL, `assets/fonts/`), fallback Godot default. Rounded panels (StyleBoxFlat
  corner radius 14–18, soft drop shadow), cream panels `#FFF8EC` on navy translucent bars, coral
  primary buttons, teal secondary, hover lift, pressed squash. Sizes for a 1920×1080 base viewport.
- **Top bar** (both phases): money (coin), voyage progress bar (little ship sailing towards a flag;
  in port shows level name + budget), satisfaction meter (gradient red→yellow→green with the three
  star thresholds marked), star counter, speed controls (pause, 1×, 2×, 3×) in voyage.
- **Bottom bar — port:** category tabs (Cabins & Rest, Food, Fun, Hygiene & Health, Transport,
  Utility) with room cards (mini art, name, cost, width, power/water, locked state with "Unlocks at
  level N"); Staff panel (hire/fire janitor & mechanic, wage); Manifest panel (guest count by
  archetype, cabins needed vs built, waves); utilities bars (power, water); "Set sail" button
  (big, coral) showing validation errors/warnings.
- **Bottom bar — voyage:** staff roster cards (bean portrait, role, idle/busy/working, click to
  select), mid-voyage hire button, alert feed (newest first, icon + text + time, click to pan to
  it), active event banners with timers.
- **On ship:** mood bubbles, queue counters over doors once queue > 3, problem icons with a
  wobble, selected staff ring + dashed path preview, hover highlight & tooltip (room: users/queue/
  health; guest: needs bars, archetype, satisfaction).
- Interactions: left-click mess = clean click; press-and-hold on broken room = repair; click staff
  then click problem = assign; click ghost = banish; right-click / Esc = cancel selection; mouse
  wheel / +/- = zoom (2 levels + fit); WASD/arrows/middle-drag = pan; Space = pause; 1/2/3 = speed.
- **Port interactions:** drag a card onto the ship → ghost preview snapped to cells, green/red with
  reason text; click placed room → small popover (Move, Upgrade (cost), Sell (+refund)); drag to
  move; Esc cancels.

## 8. Audio
Procedural (no external files): SFX generated into `AudioStreamWAV` at startup — ui_click, ui_hover,
place, sell, upgrade, coin, mess_splat, clean, breakdown, repair_done, slip, sick, cure, ghost,
banish, alert, event_horn, star_1/2/3, mutiny_warn, set_sail_horn, wave_board. Two music loops
(calm "port", bouncy "voyage") synthesised from simple chords + bass + soft percussion, plus a
short "results" sting. Buses: Master, Music, SFX (created in code). `AudioManager.play_sfx(name)`,
`play_music(name)`, `stop_music()`, plus it listens to `SimWorld` signals when told
`AudioManager.bind_sim(sim)`.

## 9. Meta: Settings & Save
- `Settings` autoload: registers input actions in code with defaults (pause, speed_1/2/3,
  zoom_in/out, pan_left/right/up/down, cancel, toggle_alerts?) and applies saved remaps; volume
  (master/music/sfx 0..1), colorblind mode, fullscreen, screen shake on/off. `signal changed`.
- `SaveManager` autoload: JSON at `user://save.json`
  `{version, levels: {id: {stars, best_rating, best_profit}}, settings: {...}}`, helpers
  `stars_for(level_id)`, `total_stars()`, `record_result(result) -> Dictionary (newly unlocked
  info)`, `is_level_unlocked(level)`, `is_destination_unlocked(dest)`, `unlocked_rooms_at(index)`,
  `reset_progress()`. Writes atomically (tmp + rename).

## 10. Screens (`src/screens/`)
- `menu`: animated title scene (ship sailing on the sea), Play, Settings, Quit.
- `map`: three destination cards/islands on a stylised sea map, stars required + lock, level list
  with stars/best rating, Play.
- `level`: owns the level flow: port → voyage → results (results as an overlay). Hosts `ShipView`.
- `settings`: volumes, colorblind, fullscreen, screen shake, key remapping list.
- `gallery` (dev): renders every room/guest/icon/background for visual QA.

## 11. Tutorial (level `med_1`)
`TutorialDirector` drives a hint panel with an arrow/highlight: 1) welcome; 2) place a cabin; 3)
place a buffet; 4) place toilets; 5) stairs connect decks; 6) hire a janitor; 7) set sail; 8) click a
mess to clean it (game pauses until done); 9) hold on a broken room to repair (event forced); 10)
pause & speed controls; 11) finish. Steps advance on conditions, never block forever (Skip button).

## 12. Quality bar & checks
- `tests/run_tests.gd`: unit tests for grid placement/validation, pathfinding across stairs and
  elevators, queue patience, staff job claiming and override, mess/repair/click progress, economy
  ledger, events, star scoring, mutiny, determinism (same seed → same result). Prints `ALL TESTS
  PASSED` or failures and exits non-zero on failure.
- `tests/balance.gd`: for each level, AutoBuilder layout + {passive, active} AutoPlayer × 5 seeds at
  max speed; prints a table and writes `tests/out/balance.csv` (rating, profit, stars, lost,
  problems spawned/handled, avg queue). Targets: active player on a sensible build reaches 2–3 stars
  on every level; passive play scores ~15–25 rating points lower than active (the game must not
  play itself); no level is unwinnable at 1 star; problem rate ramps across a voyage.
- Visual checks via `--shot` screenshots; every screen must look finished at 1920×1080 and
  1280×720.
