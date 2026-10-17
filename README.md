# Hexard

A hexagonal rotation match-3 puzzle game — a faithful-in-spirit rebuild of *Hexic HD* (Carbonated Games / Microsoft Game Studios, 2005), built in **Godot 4**.

Rotate trios of gems around the points where three hexes meet. Match three or more to clear them, then use gravity cascades, bonus stars, starflowers and black pearls to bend the board toward the perfect finish: a ring of six black pearls.

## Status

**M3 complete** — all three modes are playable end to end: a mode/difficulty menu, the Timed clock, Survival's
rounds and frozen pieces, and a result screen that says how (and whether) you won.

| Milestone | State |
|---|---|
| M0 · repo, design doc, pinned engine, geometry core | ✅ 85 cells, 135 vertices, 17×5 half-rows verified |
| M1 · playable core (rotate → match → gravity → cascade → score) + dev-art scene | ✅ 75 tests, smoke test, 10,000-move soak |
| M2 · specials (bonus stars, starflowers, black pearls, bombs) | ✅ 101 tests, soak plays specials |
| M3 · modes (Marathon / Timed / Survival), difficulty, menu, result screen | ✅ 124 tests, soak plays all three modes |
| M4 · art, audio, tutorial, saves, stats, achievements | next |
| M5 · balance, accessibility, exports | planned |

## Documentation

- 📄 **[Game design document](docs/design.md)** — vision, rules spec, board geometry, pieces, modes, scoring, UX, architecture, milestones, deviations from the original.
- 🔍 **[Research evidence ledger](docs/research/sources.md)** — every claim with a source URL and confidence rating, including what the original game *doesn't* do (no Hypercube, gravity is real, no combo timer).

## Getting started

```bat
install-godot.cmd       :: downloads the pinned engine (Godot 4.7.2) into tools/, git-ignored
run_tests.cmd           :: unit suite + view smoke test; exits non-zero on failure
run_tests.cmd -Soak     :: ... plus a 10,000-move randomised soak
```

Then play it: `tools\godot\Godot_v4.7.2-stable_win64.exe --path .` (or open `project.godot` in the editor).

| Action | Keys |
|---|---|
| Menu: pick mode / difficulty | ←/→ mode, ↑/↓ difficulty, `Enter` start (or click) |
| Move cursor | Arrows / WASD, or hover with the mouse |
| Rotate trio | `Z` CCW / `X` CW, or right/left click |
| Turn a starflower or pearl under the cursor | `F` (or click the piece) |
| Hint | `H` |
| New board | `R` |
| Toggle STRICT / FREE rotation | `T` |
| Result screen: play again / menu | `R` / `M` |
| Quit | `Esc` |

The cursor dot is **green** when a spin there will clear and **grey** when it would just revert —
which in STRICT mode is most vertices. `H` jumps to a spin that clears.

The `.cmd` wrappers invoke the PowerShell scripts with a per-process `-ExecutionPolicy Bypass`, because some
machines block unsigned `.ps1` files; the scripts are Windows PowerShell 5.1 compatible (no `pwsh` needed).
`run_tests.ps1` resolves the engine from `$env:HEXARD_GODOT`, then `tools/godot/`, then `PATH`.

## Layout

```
src/core/     pure GDScript rules + geometry — no Node dependencies, fully unit-testable
src/view/     Godot rendering, HUD (dev art; the art pass is M4)
src/app/      scene + controller that wires core to view
tests/        headless suites: unit (run_tests.gd), view smoke (smoke_scene.gd), soak (soak.gd)
docs/         design document and research notes
```

## Verified behaviour

Rules and geometry are validated by the test suite, not by assumption:

- **85 cells** in 10 columns of alternating height 9/8, **17 staggered half-rows of 5**, **135 rotation
  vertices** — matching an independent fan reverse-engineering of the original.
- Matches are **vertex triangles**: three mutually adjacent same-coloured gems. A straight line of three
  never clears, which is the rule that makes flower-building the real game.
- Gravity is per column, never sideways, and runs **before matches are judged** on every committed move.
- Scoring is `base × level × difficulty × cascade`, driven by `data/scoring.json`.
- **Specials** (M2): bonus stars multiply a clear ×2 each and three of them clear everything they touch;
  6 same-coloured gems ringing a centre bloom into a starflower; a starflower then turns its whole ring;
  6 starflowers ring into a black pearl; **3 pearls, or 6 in a ring, end the run**; bombs tick once per move,
  are defused by a colour cluster, and a same-coloured bonus star wipes that colour off the board.
- **Modes** (M3): Marathon (endless), Timed (clock that only clears refill, starflowers buy 10s and raise the
  cap to 120s) and Survival (no refills; leftover pieces freeze and pile up, thawed only by flowers and star
  blasts; win by clearing the board or surviving 50 rounds). Difficulty moves score, bomb pressure and the
  starting clock.
- A dead board is detected and shuffled back to life (Survival ends the round instead).
- Seed + command log reproduces a run exactly (the base for replays and regression tests).

Four real bugs were found by this suite during bring-up, including an empty cell decoding as a matchable
colour and a rotation that could leave a piece floating on a gappy board.

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
