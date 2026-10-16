# Hexard

A hexagonal rotation match-3 puzzle game — a faithful-in-spirit rebuild of *Hexic HD* (Carbonated Games / Microsoft Game Studios, 2005), built in **Godot 4**.

Rotate trios of gems around the points where three hexes meet. Match three or more to clear them, then use gravity cascades, bonus stars, starflowers and black pearls to bend the board toward the perfect finish: a ring of six black pearls.

## Status

**M0 complete** — rules designed, geometry core built, test suite green. Next up is M1: the playable rotation/match/gravity loop.

| Milestone | State |
|---|---|
| M0 · repo, design doc, pinned engine, geometry core | ✅ 37 tests / 0 failed |
| M1 · playable core loop (rotate → match → gravity → cascade → score) | next |
| M2 · specials (bonus stars, starflowers, black pearls, bombs) | planned |
| M3 · levels, modes (Marathon / Timed / Survival), difficulty | planned |
| M4 · art, audio, HUD, tutorial, saves, meta | planned |
| M5 · balance, accessibility, exports | planned |

## Documentation

- 📄 **[Game design document](docs/design.md)** — vision, rules spec, board geometry, pieces, modes, scoring, UX, architecture, milestones, deviations from the original.
- 🔍 **[Research evidence ledger](docs/research/sources.md)** — every claim with a source URL and confidence rating, including what the original game *doesn't* do (no Hypercube, gravity is real, no combo timer).

## Getting started

```bat
install-godot.cmd   :: downloads the pinned engine (Godot 4.7.2) into tools/, git-ignored
run_tests.cmd       :: runs the headless core suite; exits non-zero on failure
```

The `.cmd` wrappers invoke the PowerShell scripts with a per-process `-ExecutionPolicy Bypass`, because some
machines block unsigned `.ps1` files; the scripts are Windows PowerShell 5.1 compatible (no `pwsh` needed).
`run_tests.ps1` resolves the engine from `$env:HEXARD_GODOT`, then `tools/godot/`, then `PATH`.

Open `project.godot` in Godot to work in the editor (`tools\godot\Godot_v4.7.2-stable_win64.exe --path .`).

## Layout

```
src/core/     pure GDScript rules + geometry — no Node dependencies, fully unit-testable
src/view/     Godot rendering, input, audio (M1+)
tests/        headless test suite: run_tests.gd + test_*.gd (no plugin dependency)
docs/         design document and research notes
```

## Verified geometry (M0)

The board model is validated by the test suite, not by assumption:

- **85 cells** in 10 vertical columns, heights alternating **9 / 8** (the short, odd columns are the shifted ones).
- **17 staggered half-rows of exactly 5 cells** — matching an independent fan reverse-engineering of the original.
- **135 rotation vertices**, each a mutually adjacent triple of cells.
- Flat-top hexes, 6 edge-neighbours, neighbour centres exactly one hex edge apart.
- Gravity compacts per column only, preserving order, and never slides gems sideways.

## Key decisions so far

| Decision | Choice |
|---|---|
| Reference | Hexic HD core: Marathon / Timed / Survival, stars, starflowers, pearls, bombs, 7 levels |
| Engine | Godot **4.7.2** (pinned, GDScript), 2D, fixed single-screen board |
| Rotation | Discrete 60° presses; a non-matching position persists (deliberate deviation, behind a `FREE`/`STRICT` ruleset flag) |
| Architecture | Pure deterministic rules core (seeded RNG, replays, unit-testable) + a thin Godot view layer |
| Out of scope | Hexic 2 Battle mode, Emerald/Ruby tiers, online multiplayer, free-to-play meta |

## Legal

Game mechanics are not protected, but *Hexic* and its artwork, music and trade dress are Microsoft IP. Hexard uses its own name, art and audio. Reference screenshots in `docs/research/` are research-only and git-ignored.
