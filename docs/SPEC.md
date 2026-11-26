# Ship Manager — Build Spec (v1)

This is the binding contract for everyone writing code in this repo. Source design doc:
"Cruise Ship Manager (2D) — Feature Plan". Scope = every feature marked **MVP** and **v1** in that
doc. "Later" items are out of scope except those pulled into v2 (§13): decor, weather beyond storms,
leaderboards stay out.

Title: **Ship Manager**. Original game: own name, art, characters, levels. Never
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

`LevelDef.total_guests()` = everybody who ever boards (waves + VIPs + the port-stop boarding wave, used for stats, goals and crew sizing);
`LevelDef.peak_guests()` = the most people aboard at the same time (excursion guests free their beds at a port stop), used for cabin sizing
(AutoBuilder, the port manifest's "cabins needed" / beds bar and the bed warning). Without a port stop both are equal.

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
- States: `boarding, wander, walk, queue, use, climb, elevator_wait, elevator_ride, storm_off, gone` (+ `inspect`, a VIP inspector on his
  walk-round, see §13.5).
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
banish, alert, event_horn, star_1/2/3, mutiny_warn, set_sail_horn, wave_board, vip_arrive, vip_great, vip_ok, vip_bad. Two music loops
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
  Phase 4b measured with every v2 system on: the passive gap is 24 (Med) / 32 (Arctic) / 37 (Underworld), human play gets >= 1 star in every
  run and ~2.3 on average, the active bot 2-3 stars; "<= ~40" is the working target, 15-25 stays aspirational.
  Extra flags: `--modes=`, `--base=<seed>`, relative knobs `--knobs=messx:0.9,healthx:1.1,decayx:1.05,patiencex:1.0`, diagnostics `--knobs=vips:0|groups:0|
  fatigue:0|port:0|storm:0`, and `--sim=drain:1.0,nap:5,rest:12,walk:0.2,aura:0.6,tired_speed:0.85,tired_work:1.2,celeb_pat:0.4,vip_w:3,insp_great:4,
  insp_ok:9,celeb_great:70,celeb_ok:45,critic_great:70` (those `SimConst` values are `static var`s for this). The CSV gains `vip_great/ok/bad`, `seasick`,
  `rests`, `naps`; the console prints VIP verdicts per kind. `tests/out/` is git-ignored (a local sample).
- Visual checks via `--shot` screenshots; every screen must look finished at 1920×1080 and
  1280×720.

---------------------------------------------------------------------------------------------------

## 13. v2 features (binding addendum)

v2 adds: company funds + Shipyard perks, voyage report + heatmap, four new staff roles, staff
fatigue + crew quarters, VIP guests, guest groups + kids, storms, and a mid-voyage port stop. Every
rule in §0 still applies (pure sim, static typing, code-built UI, deterministic rng, zero script
errors). Numbers below are starting values; the balance pass may tune them. Each phase adds unit
tests to `tests/run_tests.gd` and keeps `ALL TESTS PASSED`. Sim code never reads `SaveManager` or
`Settings`: the screen passes data in.

### 13.1 Company funds & Shipyard
- **Payout** of a voyage = `max(0, money_end) × star share` where `money_end` = final
  `economy.money` (leftover port budget + voyage profit) and star share = `[0.25, 0.6, 0.8, 1.0]`
  by stars (`LevelDirector.payout_for`). Mutiny → payout 0. Add `money_start`, `money_end` and `payout` to the
  result dict.
- **Funds never farm:** SaveManager stores per level `best_payout`. Credit on a result =
  `max(0, payout − old best_payout)`. `funds = Σ best_payout − spent`. Save gains
  `company: {spent: int, perks: {perk_id: level}}` (old saves load with defaults).
- `record_result()` output gains `funds_earned`, `funds_total`, `best_payout`.
- **Perks** (level 0..3, price per level `[3000, 7500, 15000]` (`Perks.PRICES`, confirmed by the phase 4b payout run: a human-level player earns
  ~$8.2k clearing Med = 2 level-1 perks and change, ~$34.5k over the campaign = all five level-1 perks plus ~3 level-2s):

| id | name | per level |
|---|---|---|
| `budget` | Investors | port budget +6% |
| `crew` | Crew Training | staff speed +10%, work time −10% |
| `tickets` | Marketing | ticket price +8% |
| `service` | Hospitality School | guest queue patience +10% |
| `maintenance` | Maintenance Contract | room breakdown health +12% |

- Perks reach the sim as a plain `perks: Dictionary` (perk_id → level): `PortState.perks` applies the
  budget bonus; `PortState.create_world()` calls `SimWorld.apply_perks(perks)` before the first tick.
  Tests and `tests/balance.gd` run with no perks.
- **Shipyard screen** `src/screens/shipyard/`: reached from the map ("Shipyard" button with funds
  badge). Funds header, 5 perk cards (icon, name, effect text, 3 level pips, Buy $price / Maxed),
  "Refund all" (full refund, confirm dialog). Same look as the rest of the UI.
- **Results panel**: a funds row: "+$X company funds (new best!)" or "Beat $best to earn funds".

### 13.2 Voyage report & heatmap
- `src/sim/voyage_telemetry.gd` (`class_name VoyageTelemetry`), owned by SimWorld as `telemetry`,
  sampled every 1.0 s of sim time. Per (deck, cell): `traffic` (guests standing there, not GONE/USE),
  `unhappy` (satisfaction < 40), `queue` (guests queueing). Per room uid: utilisation sum
  (users/capacity), queue sum, samples, broken seconds, patience-outs, uses. Rating every 5 s.
- `telemetry.report() -> Dictionary` `{rooms: [{uid, id, name, deck, x, util, avg_queue,
  broken_frac, patience_outs, uses, tag}], tips: Array[String] (max 3), rating_curve: Array[float],
  grids: {traffic, unhappy, queue}}`. Tags: `overloaded` (avg_queue ≥ 2 or patience_outs ≥ 3),
  `idle` (util < 0.15 and uses < 3; not cabins/transport/utility), `unreliable` (broken_frac ≥ 0.2),
  else `ok`. Tips are short and actionable, built from rules (overloaded category → "add/upgrade",
  idle → "swap for what your manifest likes", unhappiest deck, homeless guests, unhandled problems).
  `result["report"] = telemetry.report()`.
- **UI**: Results panel gets "Voyage report" → report view (room rows with coloured tag chips, tips,
  rating sparkline) and "Show heatmap" → results hide, `src/render/heatmap_overlay.gd` tints ship
  cells (transparent → sun yellow → coral; colourblind: blue → orange) with mode tabs Traffic /
  Unhappy / Queues, a legend and "Back to results".
- After **Retry**, the port phase keeps the last report and offers a "Last voyage" heatmap toggle.

### 13.3 New staff roles
`StaffDef` gains `unlock_level: int`, `destination_lock: StringName`, `description: String`.
`handles` values: `mess` (janitor), `breakdown` (mechanic), `sick`, `ghost`, `aura` (no jobs).

| id | handles | wage | unlock | behaviour |
|---|---|---|---|---|
| `medic` | sick | 70 | 3 | Guest gets sick → `sick` job (target = guest, position follows the guest). Medic walks to the guest (re-path ≥ every 1 s); the guest stands still once a medic claiming it is within 1 cell; treats 3 s → cured (+3 sat, `guest_cured`). Sick guests still head for the medbay if no medic arrives first. |
| `entertainer` | aura | 55 | 4 | Every 3 s walks to the door of the room with the longest queue (≥ 3). Within 2 cells of a queue: those guests' patience drain ×0.5, queue satisfaction drain replaced by +0.1/s, fun +0.4/s. Juggling animation. |
| `chef` | aura | 65 | 5 | Stations at the food room (buffet/restaurant) with the most users + queue, re-evaluated every 10 s. While stationed: that room's service time ×0.7, mess chance ×0.6. |
| `warden` | ghost | 60 | 13 (Underworld only) | Ghost spawns → `ghost` job. Chases the ghost's current x (speed 3.4), within 1 cell → channels 1.0 s → banish. |

- Player override extends `assign_staff()`: kinds `sick` (guest id), `ghost` (ghost id),
  `perform` (entertainer → room uid, stays 20 s), `station` (chef → food room uid), `rest` (any
  staff → crew quarters uid, see 13.4). Invalid combos return false.
- Art (original): medic white coat + cap with red cross; entertainer striped shirt + juggling balls;
  chef white toque + ladle; warden dark hooded cloak + glowing lantern. Port crew panel lists every
  unlocked role compactly; roster cards show a role icon.

### 13.4 Staff fatigue & crew quarters
- `LevelDef.staff_fatigue: bool` (true for campaign_index ≥ 7).
- `StaffMember.energy` 0..100 (start 100). Drain/s: working 1.0, walking 0.2, aura active 0.6 (phase 4b: halved from the 2.0 / 0.35 / 0.8 starting values).
  `energy < 30` → tired: speed ×0.85, work time ×1.2 (was ×0.75 / ×1.35), "zzz" bubble. `energy ≤ 0` → drops its job
  (back to queue), walks to the nearest crew quarters with a free bunk, rests +12/s to 100; no crew
  quarters → naps on the spot at +5/s.
- Room `crew_quarters`: category service, w 2, capacity 2 (staff bunks), cost 220, upkeep 2, power
  1, water 1, interior, unlock 7, tiers +1 bunk / rest speed ×1.25. Guests never use it. Art: bunks,
  lockers, coffee mug, "crew only" sign.
- Port validation warning when fatigue is on and there are no crew quarters. HUD shows each staff's
  energy on the roster card.

**Phase 2 as built (extends the rules above, nothing else changes):**
- `StaffDef.unlock_level / destination_lock / description` + `is_available(campaign_index, destination)`; `ContentStore.staff_available()`;
  `PortState.can_hire()` refuses locked roles ("Unlocks at level N" / "Underworld only"), `SimWorld.hire_staff_mid_voyage()` too.
  Crew passed to `SimWorld._init` is not checked (tests / dev flags may field any role).
- Job kinds are `mess | repair | sick | ghost`; `sick` / `ghost` jobs follow their target (`Job.deck/x` refreshed every tick) and the chase is
  re-planned every 0.5 s. `StaffMember.state`: `idle walk work perform station rest nap`; `goal` (`"" rest perform station`) says what a walker
  heads for. A ghost-channelling warden glides along with the ghost; a treated guest stands still (`Guest.hold_until`), cheered queue guests carry
  `Guest.cheer_until`; a stationed chef sets `RoomRuntime.svc_mult / mess_mult / chef_on`.
- `assign_staff(id, kind, target)`: `mess` janitor, `repair`/`breakdown` mechanic, `sick` medic -> sick guest, `ghost` warden -> ghost,
  `perform` entertainer -> service room (not a cabin; stays 20 s), `station` chef -> food room (also holds 20 s, so a player order is not
  immediately undone by the 10 s re-evaluation), `rest` any crew -> crew quarters with a free bunk. `rest` needs energy < 100.
- Fatigue: `StaffMember.energy / fatigue_on / is_tired() / eff_speed() / eff_work_time()` (tired x0.75 / x1.35 multiplies INTO the Crew Training
  perk values). Idle crew do not drain and do not recover on their own. Exhausted (energy <= 0) crew drop their job back to the queue, walk to the
  nearest crew quarters with a free bunk (`RoomRuntime.users` / `slots` hold the sleeping staff; the bunk is reserved while walking) and rest at
  12/s x the quarters' tier speed (x1.25 per tier, +1 bunk per tier), otherwise nap at 5/s (phase 4b values; `SimConst.STAFF_*`).
- New SimWorld signals: `staff_tired(staff_id)` (energy fell below 30; fires once per tired spell), `staff_rested(staff_id)`.
  New metrics: `medic_cures`, `warden_banishes`, `rests`, `naps`.
- Save / results: crew roles unlock as features named `staff_<role id>` (results chip "NEW CREW"), `crew_quarters` as a room.
- AutoBuilder (`new_roles` opt): warden when the destination has ghosts, chef / medic from 30 guests, entertainer from 36 (one each, crew room and
  money permitting); crew quarters on fatigue levels. AutoPlayer (active) sends tired crew (energy < 30, idle crew < 60) to a free bunk.
- Dev flags: `--crew=role:n,...`, `--tab=crew`, `--tired=<energy>`, `--sicken=<n>`, `--ghosts=<n>`, `--jam=<room>`, `--wait=<s>`,
  `--stage=crew` (frozen showcase, use with `--speed=0`); gallery `--page=crew`; interaction self-test `--selftest=crew`.

### 13.5 VIP guests
- `LevelDef.vips: Array[Dictionary]` `{t: float, kind: StringName}`. VIPs board at the gangway as
  normal guests with `vip_kind` set, count ×3 in the rating mean, and give a **verdict** when their
  review completes or they leave: `great` (+$250), `ok` (+$0), `bad` (−$150, extra −10 sat to guests
  within 4 cells).
  - `critic`: boards with hunger 25. Scores each food use: +40 if waited ≤ 8 s and no mess within 2
    cells of the door, +20 if waited ≤ 20 s, else 0 (restaurant ×1.5). Verdict after 2 meals:
    ≥ 70 great, ≥ 35 ok, else bad.
  - `celebrity`: patience ×0.4, fun-seeking; rooms they are using get appeal ×1.5 for other guests.
    Verdict on leaving the review window (90 s after boarding) from mean satisfaction: ≥ 70 great (phase 4b; was 75), ≥ 45 ok (was 50),
    ≥ 50 ok, else bad.
  - `inspector`: walks every deck end to end (new guest state `inspect`), counting messes and broken
    rooms seen. ≤ 4 great, ≤ 9 ok, else bad (phase 4b; was ≤ 2 / ≤ 5).
- Signals `vip_boarded(guest_id, kind)`, `vip_verdict(guest_id, kind, grade)` → banner, alert, SFX.
  Result dict gains `vips: [{kind, grade}]`; results panel lists them.
- Art: gold outline, floating gold star marker, kind accessory (critic beret + notepad, celebrity
  sunglasses + sparkles, inspector cap + clipboard). Guest tooltip shows the VIP's review meter.

### 13.6 Guest groups & kids
- `LevelDef.group_ratio: float` (default 0): that fraction of each wave boards as groups. Couples
  (2 adults) or families (2 adults + 1–2 kids). `Guest.group_id` (−1 = solo).
- A group shares one cabin when one has enough free beds; otherwise it splits (−5 sat each).
- Leader = first member, chooses normally. An idle follower adopts the leader's current target if
  it satisfies one of the follower's needs < 75, else chooses alone. Members within 3 cells on the
  same deck: +0.1 sat/s. A member storming off → other members −15 sat.
- Archetype `kid`: 0.75 scale bean, propeller beanie, favourites `kids_club`, `pool`, `arcade`, fun
  decay ×1.6, hunger ×1.2; boards only inside families.
- Room `kids_club`: fun, w 3, cap 6, svc 9, fun 90, tag `kids`, spend 4, cost 320, upkeep 5, power
  2, water 1, mess 0.20, breakdown 100, wear 5, unlock 6. Adults score it ×0.2. Art: ball pit,
  slide, crayon drawings.

**Phase 3 as built (VIPs, groups, kids; extends the rules above, nothing else changes):**
- Data: `LevelDef.vips: Array[Dictionary]` (default `[]`) and `LevelDef.group_ratio` (default 0.0), both empty for every campaign level until phase 4b filled them in (see 13.9)
  fills them in (`tools/gen_content.gd` has `VIPS` / `GROUP_RATIO` tables keyed by level id). `LevelDef.total_guests()` now counts the VIPs
  (cabins, budget hints, `guests_planned`). `ArchetypeDef.kid` + `body_scale` (kid.tres: sky-blue bean, propeller beanie, 0.75 scale) and
  `RoomDef.adult_mult` (kids_club 0.2; every other room 1.0). Kids are never in `archetype_weights`; they only exist inside families.
- `VipSim` (`src/sim/vip_sim.gd`, owned by `SimWorld.vip_sim`, no rng): `board(w, kind)`, `tick`, hooks called by GuestSim, `finish(w)`,
  `entries()`, `meter(w, guest)`, plus pure rule functions `critic_points(wait, clean, restaurant)`, `critic_grade`, `celebrity_grade`,
  `inspector_grade`, `pay_for(grade)`. Constants live in `SimConst` (VIP_*, CRITIC_*, CELEB_*, INSPECT*, GROUP_*). Guest fields: `vip_kind`,
  `vip_grade`, `vip_score`, `vip_n`, `vip_pay`, `inspected_decks`, `queue_since`, `use_wait`, `group_id`, `group_slot`.
- Signals on SimWorld: `vip_boarded(guest_id: int, kind: StringName)`, `vip_verdict(guest_id: int, kind: StringName, grade: StringName)`, each once
  per VIP. New metrics: `vips vip_great vip_ok vip_bad inspector_issues groups groups_split group_follows group_storm_hits kids`. The verdict pays
  through the ledger categories `vip_bonus` / `vip_fines` (created lazily, so levels without VIPs keep the five old categories); the guests within
  4 cells (same deck) of a bad VIP lose 10. The rating mean weighs a VIP x3 (`LevelDirector.compute_rating`, bit-identical to the old mean when
  there are none). Result dict gains `vips: [{id, kind, grade, pay, detail}]` and `groups: {count, split, kids, members}`; the report gains
  `groups` / `groups_split` and tips for a bad VIP (priority 120) and split groups.
- Critic: boards with hunger 25. A meal is a use of a `food` room; its wait is the time since the guest joined the queue (0 when seated at once);
  "clean" = no spill within 2 cells of the door when he arrived and when he sat down. 40 / 20 / 0 points as in §13.5 (x1.5 in the restaurant), verdict
  after the 2nd meal (70 great, 35 ok). Celebrity: start fun 40, fun decay x1.4, queue patience x0.4; while one uses a room it gets appeal x1.5
  (`RoomRuntime.celeb_users`, refreshed instantly); satisfaction is sampled every 0.5 s and the verdict falls 90 s after boarding. Inspector: needs
  and mood are frozen while he inspects, speed x0.85, he walks the gangway deck, up to the top deck, then down to deck 0, each deck as two legs
  (left end -> right end, alternating); every spill within 2 cells and every broken room he passes (within 1 cell of its footprint) counts once
  (`vip_score`); decks that cannot be reached are skipped; the verdict is given when the last leg is done, after which he is an ordinary guest.
  A VIP who storms off gives a `bad` verdict on the way out; at the end of the voyage every open review is judged on what was seen so far (a critic
  who never ate: bad). `critic_meal` etc. never score after the verdict.
- Groups: the wave composition is deterministic (no rng) so the manifest is exact: `GuestGroup.plan(count, ratio)` turns round(count x ratio) guests
  into groups by cycling family(1 kid), couple, family(2 kids), couple (`SimConst.GROUP_KIDS_PATTERN`), the last one shrinking to fit; groups board
  back to back (adults first, kids last) spread evenly between the solo guests (`LevelDirector.wave_members`). `SimWorld.groups` holds the
  `GuestGroup`s (`Guest.group_id` is the 1-based index). The first member booking a cabin picks the nearest cabin with enough free beds and holds them
  (`RoomRuntime.reserved`, `RoomSim.plan_group_cabin`), else `split` (-5 sat on boarding). Followers adopt the leader's WALK / QUEUE / USE target
  (cabins only if it is their own, medbay only when sick) when it satisfies a need < 75, otherwise choose alone; while strolling they trot to a
  spot just behind the leader; the leader's choice nudges followers' next evaluation. Togetherness (+0.1/s within 3 cells, same deck) and the
  storm-off penalty (-15 to the others) are as in §13.6. `PortState.manifest()` gains `groups`, `kids`, `vips`; `AutoBuilder` adds a spare cabin per
  three groups and one kids' club per ~8 kids; `AutoPlayer` (active) cleans spills near the inspector / the critic's food room first.
- Save: `guests_vips` / `guests_kids` are results-screen features announced with the first campaign level whose `vips` / `group_ratio` is set
  (`SaveManager.guest_features_at`), so phase 4 only has to fill in the level data. `kids_club` is announced as a room at level 6.
- UI/art: kid (0.75 bean, spinning propeller beanie), VIP (gold outline + aura, floating gold star, beret + notepad / sunglasses + sparkles / peaked cap
  + clipboard), matching heart pins on group members and, for a hovered / pinned member, a dashed heart link and rings in the group colour; kids'
  club interior (ball pit with a front rim, slide, crayon drawings, bunting; tier II/III rainbow); icons `vip critic celebrity inspector kid family` +
  `kids_club` badge. HUD: arrival / verdict pills (compact banners), VIP chips with live progress next to the event chips, alert rows, verdict plate
  floating over the VIP, "Noted!" when the inspector writes something down, tooltip with the review meter and the group line. Results: "VIP verdicts"
  plate, VIP lines in the accounts, "couples & families" pill. Port manifest: VIP stars on the wave chart, a families/kids line (coral "build a
  Kids' Club!" hint while there is none). New SFX `vip_arrive vip_great vip_ok vip_bad`.
- Fix found on the way: `GuestSim.setup` sorted the archetype ids as StringNames, which compares memory addresses, so the archetype roll order (and
  with it every voyage) differed between processes; now sorted as Strings (alphabetical). In-process determinism was never affected.
- Dev flags: `--vips=critic:20,celebrity:40,inspector:60` and `--groups=0.4` (level: play a private copy with the feature on), `--stage=vips`
  (+ `--speed=0 --pin=<guest id> --nopin --verdict=critic:great,inspector:bad`, frozen showcase in front of the kids' club), gallery `--page=vips`.
- Balance notes (AutoBuilder + active AutoPlayer, 8 seeds, 3 VIPs + groups at 0.45): VIPs cost ~4-8 rating points (their mean mood is 58-76 vs
  78-89 for the others and they weigh x3); critic and inspector end great about two thirds of the time for an active player, the impatient celebrity
  is the hard one (0-3 great of 8); passive play mostly gets bad / ok. Great verdicts add up to +$750 of profit. Groups alone are rating-neutral
  (-3 .. +3), splits are rare with the AutoBuilder's spare cabins. Kids visit the club ~1x per voyage because they also follow their parents.

### 13.7 Storms
- Event `storm` (generic, 45 s; random pool from campaign index 8, scheduled in some levels).
  `SimWorld.weather_intensity` 0..1 eases in/out over 4 s.
  - Top deck closed: top-deck rooms unusable (users leave without penalty, queues clear); guests on
    the top deck head inside.
  - Seasickness: every 5 s each guest p = 0.06 (×0.3 inside a cabin) → `seasick` for 25 s: hygiene
    −1/s, sat −0.3/s, own mood icon. Not contagious; medbay or medic cures at once.
  - Mess chance ×1.5 everywhere.
- Render: dark clouds, rain, lightning flashes, taller waves, ship bob ×3 and tilt ×4, all scaled by
  `weather_intensity`.

### 13.8 Mid-voyage port stop
- `LevelDef.port_stop: Dictionary` (`{}` = none) `{t, name, disembark: float, board: int}`.
- At `t`: banner "Docking at <name>", sea scroll eases to a stop, a dock + island backdrop slides
  in. `disembark` × on-board guests (random, never VIPs mid-review) walk off on excursion: they leave
  for good and keep their current satisfaction in the rating (not lost). Then the sim pauses and a
  **Quick refit** panel opens: place new rooms and upgrade rooms with voyage money (1.0× cost; no
  sell, no move, can't overlap anything) and hire staff at normal wage. "Cast off" resumes: `board`
  new guests board as a wave, the ship sails on.
- Sim API: `SimWorld.add_room(def_id, deck, x) -> int uid` (−1 on fail), `upgrade_room(uid) -> bool`,
  `can_add_room(def_id, deck, x) -> {ok, reason}`; rebuild the walk graph, clear route caches, re-path
  walking guests/staff. Signals `port_stop_started(name)`, `port_stop_ready()`, `port_stop_ended()`.

**Phase 4a as built (storms + mid-voyage port stop; extends the rules above, nothing else changes; the campaign opts in with phase 4b, see 13.9):**
- Data: `EventDef` gains `storm`, `weather_ease` (4), `top_deck_closed`, `seasick_chance` (0.06), `seasick_cabin_mult` (0.3), `seasick_interval` (5), `seasick_duration` (25),
  `mess_mult_all` (1.5 for the storm). `data/events/storm.tres` (and `tools/gen_content.gd`, kept in sync) is the tenth event; phase 4b schedules it in a few levels and adds it to
  `GENERIC_POOL` from campaign level 8. `LevelDef.port_stop: Dictionary` (default `{}`: `{t, name, disembark, board}`) and `LevelDef.port_board()`; `total_guests()` now also
  counts the boarding wave, so `PortState.manifest()` / `AutoBuilder` size cabins for it and the manifest shows a "Port stop at ..." line.
- Storm: `SimWorld.weather_intensity` = `EventDirector.weather_curve(elapsed, time_left, ease)` (smoothstep, 0 -> 1 over the first 4 s, 1 -> 0 over the last 4 s).
  `EventDirector.top_closed` / `RoomRuntime.closed`: when a storm starts `RoomSim.set_top_closed` shuts every top-deck service room; `GuestSim.evacuate_room` sends users, queue
  and walkers-to-it away (`send_away`: back to wander, no penalty, no avoid mark; a guest still on the stairs turns round in `_arrive`). Guests on the top deck head for
  the deck below (`_shelter`, the wander picker never chooses the top deck, `top_deck_rush` is off while closed). Seasickness: `Guest.seasick / seasick_timer` (separate
  from `sick`), rolled by `EventDirector._roll_seasick` every 5 s of storm in ascending guest-id order (cabin = guest in USE of a cabin, x0.3), `GuestSim.make_seasick`,
  effects in `_slow` (hygiene -1/s, satisfaction -0.3/s, mood `seasick`), wears off after 25 s, never spreads. The medbay (`is_ailing()`) and the medic (the `sick` job
  also covers seasick guests; `Guest.is_ailing()`) cure it at once (`cure()` clears both flags). New signal `guest_got_seasick(guest_id)`, metric `seasick`,
  `ProblemSim.seasick_count`. Mess chance x1.5 via `EventDirector.mess_mult` (`mess_all_mult`, stacks with pool party). A running storm ends when docking starts and no storm starts
  within 40 s before a stop (`PortStop.blocks_storm`, also makes scheduled / random storms infeasible there).
- Port stop (`src/sim/port_stop.gd`, `SimWorld.port_stop`): phases `docking` (SimConst.DOCK_TIME 7 s, `dock_progress` 0 -> 1 smoothstep) -> `excursion` (`excursion_quota` =
  round(disembark x guests aboard, not counting boarders), picked with a partial Fisher-Yates on the sim rng from `candidates()` = aboard, not boarding, no VIP with an open
  review; they walk to the gangway in the new guest mode `Guest.EXCURSION`, free their bed, keep their satisfaction frozen, `Guest.excursion = true`, never `lost`; `is_aboard()` is
  false for them; cut short after EXCURSION_MAX 14 s) -> `ready` (`port_stop_ready`; `SimWorld.tick` is a no-op while `refit_manual` is true, otherwise the sim casts off by
  itself so headless runs never stall; the level screen sets `refit_manual = true`) -> `SimWorld.cast_off()` (`LevelDirector.add_wave` boards `board` guests, `port_stop_ended`)
  -> `departing` (DEPART_TIME 4 s, `dock_progress` -> 0) -> `done`. `SimWorld.refit_open()`.
- Refit API (only while `ready`): `can_add_room(def_id, deck, x) -> {ok, reason}` (`ShipGrid.can_refit_place`: voyage money, unlock level, power / water, no overlap, deck connected
  to the gangway deck, "Not connected"; reason "Not at a port" otherwise), `add_room(def_id, deck, x) -> uid` (-1 on failure; rebuilds the walk graph for stairs / elevators and
  re-plans every walking guest / crew route, assigns homeless guests to a new cabin, registers the room with GuestSim favourites + telemetry), `can_upgrade_room(uid)`,
  `upgrade_room(uid) -> bool`, `cast_off() -> bool`; signals `port_stop_started(name)`, `port_stop_ready()`, `port_stop_ended()`, `room_added(room_uid)`, `room_upgraded(room_uid)`.
  Spending goes to the ledger category `refit` (created lazily, shown as "Port refit" in the results accounts); `hire_staff_mid_voyage` / `mid_voyage_hire_cost` use the normal wage
  (`SimConst.REFIT_HIRE_MULT`) during the refit. Telemetry: rooms added mid-voyage are averaged over their own time aboard (`added_at`, `tier` in the report rows, never "idle" in
  their first 40 s); excursion guests are not counted in the heatmap or as homeless. `AutoPlayer.refit()` (active + human: beds for the boarders, then add / upgrade the most overloaded
  room kinds, keeping $250) and casts off; passive just casts off. `result["port_stop"]` (`name, excursion, boarded, refit_spent, rooms, upgrades`) exists only on levels with a stop.
- UI: `RefitState extends PortState` (src/screens/level/port/refit_state.gd) wraps the live sim (grid flags switched on while open) so `PortPhase` is reused as it is: `PortState.is_refit()`
  hides Back / Undo / Manifest / Move / Sell / Fire, "Quick refit - <port>" title pill, "Cast off!" button, voyage money chip, normal-wage hiring. `LevelScreen` pauses and locks
  the speed (`VoyageController.locked`) at `port_stop_ready`, hides the crew bar (`VoyageHud.set_refit_mode`), keeps 470 px free on the left for the pier, and on "Cast off!" restores everything.
  Banners: "Docking at <name>", "Shore leave!" pill, "Cast off!". Alerts: storm row, grouped "N guests are seasick" row, "Docked" row. HUD: storm event chip + icon, seasick tooltip lines,
  "CLOSED" room tooltip.
- Render: `SeaWeather` (gloom, dark cloud bank, two rain layers, splashes, jagged bolts + soft flash, signal `SeaBackground.lightning(strength)` -> thunder + camera shake), taller waves
  (x2.5 at full), whole-scene tint, `ShipView.weather` (bob x3, tilt x4, quicker, dimmer ship), closed top-deck rooms get a veil + hazard tape + "Closed" sign, seasick bean (aqua body, spiral
  eyes, puffed cheeks, slow sway, queasy bubbles, aqua face bubble `IconArt` `seasick`, event icon `storm`, FX `queasy`). `SeaDock`: harbour town per destination (whitewashed Med village +
  lighthouse + moored boats, snowy Arctic huts with chimney smoke, Underworld castle + torches + wisps) and a pier with posts, bollard + mooring rope to the gangway ramp, lamps, bunting, name sign,
  crates, a destination prop (kiosk + palm / sled / bubbling cauldron) and waiting beans; both slide in with `dock_progress` while the sea scroll eases to a stop.
  Audio: `dock_horn`, `thunder`, looping `rain` bed (`AudioManager.set_ambience`, `SfxBank.LOOPING`; the web audio cache is regenerated by `tools/bake_audio.gd`).
- Dev flags: `--storm=<t>`, `--portstop=<t>` (+ `--portname --disembark --board`), `--refitroom=<id>`, `--refitselect=<id>`, `--castoff=<s>`, `--boltshot`, `--stage=seasick`,
  `--selftest=portstop` (real input: drag a cabin card onto the ship, upgrade a room from its popover, hire a janitor, Cast off, boarding wave).
- Fix: the VIP verdict plate's money line no longer touches the plate's bottom edge (plate is 72 px tall with a sub line).

### 13.9 Content, unlocks & balance
- SaveManager `FEATURE_NAMES`/unlock lists include the new staff roles and rooms so the results
  screen announces them.
- Levels opt in to the new systems (VIPs from med_4, groups from med_6, fatigue in Arctic +
  Underworld, storms from arctic_2, port stops in a few late levels per destination).
- AutoBuilder/AutoPlayer learn the new systems (hire medic/chef/warden when sensible, crew quarters
  when fatigue is on, send exhausted staff to rest, refit at port stops by adding/upgrading the most
  overloaded room type). `tests/balance.gd` targets from §12 still hold.

**Phase 4b as built (the campaign opts in, balance pass, hints; extends the rules above):**

*What each level uses* (`tools/gen_content.gd`: `VIPS`, `GROUP_RATIO`, `PORT_STOPS`, storms inline in the event lists, `GOALS`, `KNOBS`; kept in sync with `data/levels/*.tres`).
Med 1-3 are untouched (only med_3's blurb changed), everything below is on top of the v1 content. VIP times are `t` seconds; every VIP boards at least 110 s
(critic / celebrity) or 130 s (inspector) before the end.

| level | VIPs | groups | fatigue | storm | port stop (t, ashore, board) |
|---|---|---|---|---|---|
| med_4 | critic 50 | - | - | - | - |
| med_5 | inspector 40 | - | - | - | Santorini (125, 30%, 6); waves 25 -> 22 |
| med_6 | critic 50 | 0.33 | - | - | - |
| arctic_1 | celebrity 40 | 0.33 | yes | - | - |
| arctic_2 | inspector 40, critic 105 | 0.33 | yes | scheduled 100 | - |
| arctic_3 | critic 45 | 0.33 | yes | scheduled 85 | - |
| arctic_4 | celebrity 40, critic 115 | 0.38 | yes | random pool | Penguin Point (130, 30%, 8); waves 34 -> 30 |
| arctic_5 | critic 40, inspector 95 | 0.33 | yes | random pool | - |
| arctic_6 | celebrity 40, critic 110 | 0.33 | yes | random pool | Aurora Bay (125, 25%, 10); waves 40 -> 35 |
| underworld_1 | inspector 40, critic 110 | 0.38 | yes | - | - |
| underworld_2 | celebrity 45, inspector 105 | 0.35 | yes | scheduled 130 | - |
| underworld_3 | critic 45, inspector 100 | 0.35 | yes | scheduled 135 | - |
| underworld_4 | celebrity 40, critic 105 | 0.35 | yes | random pool | Styx Landing (130, 30%, 10); waves 46 -> 41 |
| underworld_5 | inspector 45, celebrity 125 | 0.35 | yes | scheduled 145 + random | - |
| underworld_6 | critic 45, celebrity 115 | 0.35 | yes | random pool | Charon's Wharf (160, 25%, 12); waves 56 -> 49 |

- Group ratios are 0.33-0.38 (a wave needs >= 3 grouped guests to produce a family with a kid, so every level from med_6 on has at least one family; arctic_1 stays
  at 0.33 = couples only, a single family there cost the active bot ~12 rating points because of the extra kids' club). Families per level: 1 in med_6 / arctic_1-3,
  2 in arctic_4-6 / underworld_1-2, 3-4 in underworld_3-6.
- Port-stop levels have their wave counts cut by about the boarding wave so the crowd stays on the old curve. Scheduled events were shifted a little to keep
  clear of the stop and of the storms (the sim also refuses a storm within 40 s before a stop). Random storms: `EventDef.min_campaign_index` (storm = 8) and
  `&"storm"` joined `EventDirector.GENERIC_POOL`; the random pool of campaign levels < 8 is unchanged (med_6 never rolls one).
- `LevelDef.peak_guests()` (see §4) drives `AutoBuilder` cabin sizing, `PortState.manifest()["cabins_needed"]` / `["peak_guests"]`, the manifest's beds bar and the
  bed warning in `ShipGrid.validate_for_voyage`; crew, food and fun sizing still use `total_guests()`.
- `LevelDef.features()` lists what a level brings (VIP, families, storm, port stop, tired crew); the map's level cards show it as small icon plates with
  tooltips (new `LevelCard._set_features`), the manifest's event list has the storm icon and "maybe a storm" from level 8.
- Balance numbers (all `SimConst` unless noted): fatigue drain 2.0 / 0.35 / 0.8 -> 1.0 / 0.2 / 0.6, tired x0.75 / x1.35 -> x0.85 / x1.2, rest 10 -> 12/s, nap 4 -> 5/s;
  celebrity great 75 -> 70, ok 50 -> 45; inspector great <= 2 -> <= 4, ok <= 5 -> <= 9 (the active bot now ends great ~40% / ok ~40% / bad ~15%, the human
  mostly ok, passive mostly bad); celebrity patience x0.4 and VIP weight x3 stay (the weight only costs ~1 rating point once the verdict rules are fair).
  `KNOBS` of levels 4-18 x0.86 mess / x1.14 health / x0.94 decay, med_6, arctic_3 and underworld_1-3, 5 eased again (underworld_2-3 a lot), see the generator.
  `GOALS` of levels 4-18 re-derived with `tests/goals.py` from 16 seeds x 3 modes (goal 1 just under the passive mean again).
- Result (12 fresh seeds, base 5000, rating / stars per mode): Med (all six) passive 65.3 / 1.5, human 82.0 / 2.5, active 89.0 / 2.7 (gap 23.7); Arctic 51.8 / 0.8,
  74.6 / 2.2, 84.0 / 2.8 (gap 32.2); Underworld 46.7 / 0.9, 72.1 / 2.1, 83.9 / 2.9 (gap 37.2). Before the pass (phase 4a, nothing opted in): Arctic gap 49, Underworld 58;
  with everything on and the old numbers: Arctic 42, Underworld 49 and the human got ~1.8 stars in the Underworld. The active bot averaged 2.4-3.0 stars on every level (one arctic_4 seed
  dropped to 1), the human never below 1.
- Funds (`tests/payout.gd`, 6 seeds): human play earns ~$0.3k .. $2.4k per Med level (Med total ~$8.2k), ~$10.1k over Arctic, ~$16.1k over Underworld
  (campaign total ~$34.5k, the active bot ~$43k, passive ~$23k). `Perks.PRICES` stay `[3000, 7500, 15000]`.
- Hints (`HintTexts.HINTS` in `src/screens/level/tutorial/hint_texts.gd`, shown by `HintDirector`; every one once per save): port - `crew_medic / crew_entertainer /
  crew_chef / crew_warden` (first level with the role), `vip_plan`, `families`, `fatigue`, `portstop_plan`; voyage - `vip_critic / vip_celebrity / vip_inspector`
  (`vip_boarded`), `event_storm`, `tired` / `tired_none` (`staff_tired`, depending on crew quarters), `portstop` (`port_stop_started`), `refit` (`port_stop_ready`,
  card sits above the refit bar); results - `funds` (any payout) and `report` (Voyage report + heatmap buttons). Dev: `--hint=<id>`; `--selftest=tutorial_hints` checks
  the v2 signals too. `HintTexts` is a headless-safe copy of the strings (the director needs the autoloads).
- Results screen: a port-stop pill ("Penguin Point: 8 ashore, 8 boarded, refit +1"); the card now scales itself down (`ResultsPanel._fit_card`) when a busy voyage (VIPs,
  groups, port stop, funds, unlocks) is taller than the screen, and keeps 130 px free at the bottom while a hint card is up (`reserve_bottom`).
- Gallery `ui` page: the crew row shows all six roles.
- Tests: `_t_campaign_features` (opt-in rules per level, VIP timing, stops per destination, random storm gate, `peak_guests` maths, manifest / autobuilder) and `_t_hints_v2`;
  fatigue / VIP-grade tests read the `SimConst` values instead of hard-coded numbers; `_blank_level` strips VIPs / groups / port stop.
- To check by hand (needs a human): how the celebrity feels at patience x0.4, whether the passive-heavy early Underworld levels (underworld_1, arctic_1) are fun at 1 star for a
  real beginner, whether five port-stop levels in a row of the late game feel like a lot, hint pacing on a fresh save (arctic_1 queues the destination, elevator and fatigue tips).
