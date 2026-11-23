# Cruise Ship Manager (working title)

A cute 2D side-view cruise ship management game made in **Godot 4.7**. Build your ship in port, then
survive a hectic 3–5 minute voyage: keep guests fed, entertained, clean and healthy, and out of queues.

- 3 destinations (Mediterranean, Arctic, Underworld) × 6 levels, three stars each
- 14 guest rooms + stairs, elevators, generators and water tanks, with tier II/III upgrades
- 4 guest archetypes, janitors and mechanics, 9 events, sickness, ghosts, mutiny
- Flat-vector art, procedural sound and music, all generated in code (no asset files besides the font)

## Run it

```bash
brew install --cask godot          # Godot 4.7.x
godot --path .                     # play
godot -e --path .                  # open in the editor
```

## Controls

| Action | Input |
|---|---|
| Clean a spill | Click it (3 clicks) |
| Repair a broken room | Press and hold on it |
| Send crew | Click a crew member (on the ship or roster), then click a problem |
| Banish a ghost | Click it |
| Pause / speed | Space, 1 / 2 / 3 |
| Zoom / pan | Mouse wheel or + / -, WASD / arrows / middle-drag |
| Cancel / pause menu | Right-click, Esc |
| Build (port) | Drag a card onto the ship; Shift keeps placing; click a room to move, upgrade or sell; Ctrl/Cmd+Z undoes |

All keys can be remapped in Settings.

## Project layout

| Path | What |
|---|---|
| `docs/SPEC.md` | Build spec: rules, numbers, APIs, art direction |
| `src/sim/` | Pure simulation (no nodes): ShipGrid, SimWorld, guests, rooms, problems, staff, events, economy, AutoBuilder, AutoPlayer |
| `src/data/`, `data/` | Resource classes and the `.tres` content (rooms, archetypes, staff, events, destinations, hulls, levels) |
| `src/render/` | ShipView, sea background, camera, voyage renderer, FX, and the stateless vector art kit in `art/` |
| `src/ui/` | Theme, widgets, overlays (results, pause, settings, dialogs, banners) |
| `src/screens/` | Screens: `menu`, `map`, `level` (port + voyage + results + tutorial), `settings`, `gallery` (dev), `portdev` (dev) |
| `src/audio/`, `src/meta/` | Procedural audio, settings, save/unlocks |
| `tests/`, `tools/` | Headless tests, balance sweeps, content generator |

## Balancing

Content lives in `data/**/*.tres` and can be edited in the Godot inspector.
`tools/gen_content.gd` bootstraps those files from tables (re-running it overwrites them):

```bash
godot --headless --path . --script res://tools/gen_content.gd
```

Balance sweep (AutoBuilder layouts played by passive / human-like / active bots, many seeds):

```bash
godot --headless --path . --script res://tests/balance.gd -- --seeds=5 [--levels=med_3,arctic_2]
# writes tests/out/balance.csv
```

## Tests

```bash
godot --headless --path . --script res://tests/run_tests.gd        # simulation (≈2.5k checks)
godot --headless --path . --script res://tests/meta/test_meta.gd   # save / settings / audio
```

Interaction self-tests drive real input events through the camera:

```bash
godot --path . -- --scene=level --level=med_4 --phase=voyage --sim-seconds=30 --seed=5 --selftest=clean   # also: repair, assign, ghost, flow, keys
godot --path . -- --scene=portdev --level=med_3 --selftest=build
godot --path . -- --scene=level --level=med_1 --selftest=tutorial
```

## Dev flags

Pass after `--`: `--scene=<menu|map|level|settings|gallery|portdev>`, `--level=<id>`,
`--phase=<port|voyage>`, `--autobuild`, `--sim-seconds=<n>`, `--seed=<n>`, `--unlock-all`,
`--shot=<abs.png> --frames=<n>` (screenshot then quit). Dev runs of the level screen save to
`user://dev_save.json` so they don't touch real progress.
