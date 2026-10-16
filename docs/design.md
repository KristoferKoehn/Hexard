# Hexard — Game Design Document

**Working title:** Hexard
**Genre:** Tile-matching puzzle (hexagonal rotation match-3)
**Reference:** *Hexic HD* (Carbonated Games / Microsoft Game Studios, Xbox 360, 2005), designed by Alexey Pajitnov
**Engine:** Godot 4 (GDScript), 2D
**Players:** 1 (local)
**Status:** Draft v0.1 — rules locked, numbers tunable

> **IP note.** Game mechanics are not protected, but *Hexic*, its artwork, its music and its trade dress are Microsoft IP. Hexard ships its own name, art, audio and UI. No Microsoft asset, soundtrack (*Hexophilia*) or store art is used or redistributed. Reference screenshots in `docs/research/` are research-only and git-ignored.

---

## 1. Vision

Rank up your flower of gems, one rotation at a time, until six black pearls close the board. Hexard is a faithful-in-spirit rebuild of *Hexic HD*: a slow, deliberate, deeply strategic match-3 where **clearing is easy and shaping is hard**.

The one-line pitch: **the goal is not to clear gems — it is to arrange them.** Random clearing is how you lose.

### Design pillars

1. **Rotation, not swapping.** The only verb is turning a trio of gems around a shared point. No swapping, no dragging, no gravity you control.
2. **Building beats clearing.** Stars, starflowers, pearls and the pearl finish are the real game. Points are a by-product.
3. **Readable cause and effect.** Every board change is explainable — rotation, clear, gravity, refill — so the player can plan 3+ moves ahead.
4. **Respect the clock, never rush the player.** Marathon has no timer. Time pressure and bombs are opt-in modes/difficulty.
5. **Accessible from the first minute.** The original's biggest documented weakness was onboarding; ours is a strength (interactive tutorial, hint glow, colour-blind patterns, full remapping).

### Non-goals (v1)

- Hexic 2's Battle mode, Emerald/Ruby tiers, chain detonation, per-colour attack tanks.
- Online multiplayer, accounts, cloud saves, monetisation, lives/boosts (that is the 2014 free-to-play remake, a different game).
- 3D gem rendering (Hexic 2's look). We ship clean 2D HD-style gems.

---

## 2. Board

### 2.1 Geometry (locked)

| Property | Value |
|---|---|
| Cell count | **85**, all playable, no holes, no blocked cells |
| Layout | **10 vertical columns** (`q = 0..9`), flat-top hexes |
| Column heights | `h(q) = 9` for even `q`, `h(q) = 8` for odd `q` (5×9 + 5×8 = 85) |
| Parity rule | The **short (odd) columns are the shifted ones.** If the unshifted columns were short, the protruding bottom cells would lose their lateral neighbours (guarded by a test) |
| Row index | `r = 0..h(q)-1`, `r = 0` is the top cell of that column |
| Outline | Zigzag ("brick") top and bottom edges — **not** a tapering hexagon |
| Adjacency | 6 edge-neighbours per cell |
| Rotation vertices | **135** points where exactly 3 cells meet — verified by the M0 suite |
| Half-row structure | **17 staggered half-rows of exactly 5 cells** — independently reverse-engineered, and asserted as a test |

Pixel placement (flat-top, `s` = hex size, odd columns shifted down half a cell):

```
x = q * 1.5 * s
y = r * sqrt(3) * s  +  (q is odd ? sqrt(3)/2 * s : 0)
```

Neighbour offsets, odd-`q` offset layout:

```
q odd :  (q,r-1) (q,r+1) (q-1,r) (q-1,r+1) (q+1,r) (q+1,r+1)
q even:  (q,r-1) (q,r+1) (q-1,r-1) (q-1,r) (q+1,r-1) (q+1,r)
```

Our screenshots confirm ~10 columns and a scalloped bottom edge; the 85-cell count comes from two independent fan re-implementations (`hexic-solver`, `hectic-hexagons`). Treat the exact parity (which columns are the short ones) as a **cosmetic** decision — it does not change rules — but it must stay consistent with the gravity chains below.

### 2.2 Gravity (locked)

Gravity is **per column, straight down**. There is no sideways sliding and no falling toward the centre.

1. A cleared cell becomes empty.
2. Every cell above it in the same column falls by one, repeatedly, until it rests on a cell or on the column floor (`r = h(q)-1`).
3. Vacated cells at the top of each column are filled with new gems that spawn **above the board** (visual start `r ≈ -4`) and fall in.
4. The board is re-evaluated for matches, repeating until stable → **cascade**.

**Survival mode is the exception:** no refill during a round (see §6.3).

### 2.3 Rotation vertices

A rotation vertex is the point shared by exactly **3 mutually edge-adjacent cells** (a triangle in the hex grid). The cursor snaps to these 135 points only. Enumerate them as: every sorted triple `{a,b,c}` of cells where each pair is adjacent.

---

## 3. Core loop (rules spec)

### 3.1 The move

A move = `rotate(vertex, direction)`, where `direction ∈ {CW, CCW}` and the rotation advances the 3 gems around `vertex` by one 60° step.

**Commit rule (v1, deliberate deviation — see §11):**

- Each press = **one 60° step** (120 ms tween). The trio may be left in **any** position; a step that does not create a match still persists.
- If a step **does** create a match, the rotation locks immediately and resolves — the player cannot spin through a match by accident.
- `Ruleset.rotation_mode = FREE` implements the above. `STRICT` (fidelity option) instead spins the trio through up to 3 steps, stopping at the first matching step, and **reverts with no move consumed** if no step matches.

**Special-piece rotation always persists** in both modes:

- Rotating via a **starflower** cycles its 6 neighbours one 60° step, no match required.
- Rotating via a **black pearl** cycles 3 of its 6 neighbours (Y or inverted-Y), no match required.

### 3.2 Match predicate (locked)

A match exists at a vertex `V` when **all 3 cells around `V` hold the same gem colour**. This is the only match trigger — a straight line of 3 same-coloured gems in a column or diagonal does **not** clear, because those cells share no vertex.

When any match triggers, the **clear set** is the maximal 6-connected group of same-coloured cells containing the matched cells (so 3, 4, 5, 6+ gem clears all work, with escalating score).

Flower formation (6 same-coloured gems ringing one centre) takes **precedence** over a plain colour cluster that would form in the same step.

### 3.3 Resolution pipeline

Deterministic, in this order, looping until stable:

```
on_rotate(vertex, dir):
  apply_step(vertex, dir)
  if not any_match_exists(): return          # FREE mode: position persists, no move consumed
  begin_move()

  loop:
    if flowers_exist():        resolve_flowers()        # 6-ring → starflower / pearl
    elif star_clusters_exist():resolve_star_clusters()  # 3 adjacent bonus stars
    elif bombs_in_cluster():    resolve_bomb_clusters()
    else:                       resolve_colour_clusters() # all connected groups ≥3, simultaneously
    award_score(cleared)
    increment_combo_counter()                          # one per clear event, cascades included
    apply_gravity()
    if mode != SURVIVAL: refill_from_top()
    if not any_match_exists(): break

  end_move(): tick_bombs(), check_level_up(), check_dead_board(), check_game_over()
```

`any_match_exists()` is also the dead-board test (see §5.3) and the hint source.

### 3.4 Gems and specials

| Piece | Look | Created by | Behaviour |
|---|---|---|---|
| **Gem** | Hexagonal crystal, one of N colours | Refill / start | Matches by colour |
| **Bonus star** | A *coloured* gem with a star embossed | Random spawn from level 2 (rate in config) | ×2 per star in a clear (stacking); 3 adjacent bonus stars of **any** colours form a cluster that clears the stars **plus every gem each star touches**; defends a bomb (§3.4 bombs) |
| **Starflower** | A *bare* silver 6-point star | 6 same-coloured gems ringing one centre gem → ring clears, centre blooms into a starflower | Selectable: rotate all 6 neighbours by 60°, always persists. Matching 3+ starflowers pays a large bonus. Only tool for building pearls |
| **Black pearl** | Dark iridescent sphere in a hex | 6 starflowers ringing one centre | Selectable: rotate 3 of its 6 neighbours in Y / inverted-Y (two orientations by column parity), always persists |
| **Bomb** | A *coloured* gem with a number | Random spawn from level 3 | Ticks down 1 per move; at 0 → game over. Defused by clearing it in a colour cluster. If that cluster also contains ≥1 bonus star of the bomb's colour → **every gem of that colour on the board clears** |

**The two stars are different objects.** The bonus star is a coloured multiplier that falls in as new gems; the starflower is the bare, uncoloured product of a flower. Both appeared in our reference screenshots. Do not merge them.

**Pearl finish (win condition).** Either a **cluster of 3 black pearls** or a **ring of 6 black pearls around a centre** ends the run immediately as a *perfect finish*, with a large bonus. In Marathon this is the goal; the HUD celebrates it with a dedicated sequence.

### 3.5 Colours

Seven hues in the full palette; **five in play at level 1**, the rest gated by level (matching the reference's documented ramp).

| Slot | Hue | In play |
|---|---|---|
| 1–5 | Red, Yellow, Green, Cyan, Violet | Level 1+ |
| 6 | Orange | Level 4+ |
| 7 | Blue | Level 5+ |

Every hue also has a **pattern overlay** (7 distinct shapes: ring, cross, chevron, dots, stripes, star, diamond) toggleable in options, applied to gems, bonus stars **and** bomb numbers. This is a day-one accessibility requirement, not a stretch goal.

> Deviation: the reference's exact palette is genuinely ambiguous (sources list "light green, dark green, pink" and elsewhere six colours). Our seven are chosen for maximal hue separation and colour-blind safety.

---

## 4. Scoring

All values live in `res://src/core/data/scoring.tres` (or JSON) — never hard-coded in logic. Every clear scores `base × level × difficulty_multiplier × star_multiplier`, plus cascade bonus.

| Event | Base value | Source of number |
|---|---|---|
| Cluster of 3 | 5 | Reference (community, converging) |
| Cluster of 4 | 10 | Reference (community) |
| Cluster of 5 | 25 | Ours (extrapolated) |
| Cluster of 6+ | 50 | Ours (extrapolated) |
| Starflower cleared | 1,000 | Reference (community) |
| Black pearl cleared | 10,000 | Reference (community) |
| Pearl cluster (3) | 100,000 | Ours |
| Pearl ring (6) — perfect finish | 250,000 | Reference (community) |
| Bonus star in a clear | ×2 each, stacking (×2, ×4, ×8…) | Reference |
| Cascade step after the first | ×1.5 per extra depth step | Ours |
| Difficulty | Easy ×0.5, Normal ×1, Hard ×2 | Reference (direction only) |

**Progression is driven by combos, not score** — this is a locked reference rule that keeps the two systems independent (§5.1).

---

## 5. Progression, levels and failure

### 5.1 Levels

Seven levels, advanced by **combos** (clears). Each clear event — including every cascade step and every flower formation — counts as one combo.

| Advance | Combos required |
|---|---|
| 1 → 2 | 50 |
| 2 → 3 | 60 |
| 3 → 4 | 70 |
| 4 → 5 | 80 |
| 5 → 6 | 90 |
| 6 → 7 | 100 |
| At 7 | Level stays; HUD shows "MAX" and score scales at ×7 |

HUD shows **Level** and **Combos remaining** (verified in the reference HUD: "LEVEL 5 / COMBOS REMAINING 7").

### 5.2 Per-level content ramp

| Level | Adds |
|---|---|
| 1 | 5 colours, no specials, no bombs |
| 2 | **Bonus stars** start spawning |
| 3 | **Bombs** start spawning |
| 4 | +1 colour (orange), shorter bomb timers |
| 5 | +1 colour (blue = full palette) |
| 6–7 | Shorter bomb timers, higher bomb spawn rate, slightly lower bonus-star rate |

### 5.3 Dead board (our rule — undocumented in the original)

A board is dead when **no rotation at any vertex produces a match**. In Marathon/Timed this can only happen in a pathological refill state, but it must be handled:

1. Detect (reuse `any_match_exists()`).
2. Play a short shuffle animation (gems jitter and re-settle), regenerate the board.
3. **No penalty**, no score change, keep level and combo progress.
4. Log the event to telemetry — if it happens often, the refill RNG needs work.

In Survival, a dead board is not an error: it ends the round (§6.3).

### 5.4 Game over / game win

| Trigger | Result |
|---|---|
| Bomb counter hits 0 | Immediate game over (explosion sequence, score summary) |
| Timed: clock hits 0 | Game over |
| Survival: every gem locked | Game over |
| Pearl cluster / pearl ring | **Perfect finish** — run ends as a win with bonus |
| Survival: board cleared or 50 rounds survived | Win |

---

## 6. Modes

### 6.1 Marathon (default)

Endless. Board always refills. Bombs and bonus stars spawn per level ramp. The only ways out are a bomb or the pearl finish. No timer, no move limit — the thinking mode. Difficulty setting (Easy/Normal/Hard) tunes score multiplier, bomb timers, bomb spawn rate and bonus-star rate.

### 6.2 Clocks (Timed)

Marathon plus a countdown. Reference behaviour, expressed as config:

- Start: 50 s at Normal (Easy 60 s / Hard 40 s).
- Every cleared gem: +0.25 s; each combo event: +1 s (cap: timer max).
- **Starflower formed: timer refills to maximum and the maximum rises by 10 s.**
- **Maximum timer cap: 120 s.**
- Level up: timer refills to maximum.
- Clock hits 0 → game over.

### 6.3 Survival

Clear the board with no refills.

- No new gems fall during a round. Cleared cells stay empty (cursor can still sit on empty vertices — the reference allows this).
- When no match remains, the **round ends**: leftover gems **lock** (cannot be rotated) and empty cells are refilled over/around them; pay a round-end bonus per gem cleared this round.
- Clearing a cluster containing a bonus star **unlocks** locked gems it touches.
- Forming a flower **unlocks the whole board and clears every gem matching the flower centre's colour** (no starflower is created in this mode).
- Bombs and black pearls do not appear in Survival.
- **Win:** clear the entire board, or survive 50 rounds. **Lose:** every gem on the board is locked.

---

## 7. Input, camera, HUD

### 7.1 Controls (all remappable)

| Action | Keyboard | Mouse | Gamepad | Touch |
|---|---|---|---|---|
| Move cursor | Arrows / WASD | Hover a vertex | Left stick / D-pad | Drag |
| Rotate CCW | `Z` / `Q` | Left-click (left side of cursor) | `X` / LT | Swipe counter-clockwise |
| Rotate CW | `X` / `E` | Left-click (right side of cursor) | `A` / RT | Swipe clockwise |
| Select special | `E` / Enter on a starflower or pearl | Click the piece | `Y` | Tap the piece |
| Hint | `H` | Hint button in HUD | `Back`/`Select` | Hint button |
| Pause | `Esc` / `Space` | HUD pause | `Start` | HUD pause |

Guard rails: input buffering (150 ms) so fast rotations never drop, and a "confirm rotation direction" visual on the cursor (a curved arrow that lights up before the tween starts).

### 7.2 Camera

Fixed single screen showing the whole 85-cell board, 16:9 safe. No zoom, no pan (matches the reference). Responsive scaling for windowed/desktop/web; portrait touch layout moves the HUD to the top.

### 7.3 HUD

- Top bar: **Score**, **Level**, **Combos remaining** (to next level).
- Mode-specific: countdown clock (Timed), round number + locked-gem count (Survival).
- Left/right: rotation direction indicators that light on press.
- Contextual: bomb counters float on the bombs themselves (a number badge on the gem), hint glow after idle delay, floating `+points` popups, cascade depth markers, "PERFECT FINISH" banner.
- Menus: Main (Marathon / Timed / Survival / Tutorial / Stats / Options / Quit), Pause (Resume / Restart / Options / Quit to menu), Options (difficulty, rotation mode FREE/STRICT, colour-blind patterns, volumes, hint delay, screen shake, reduced motion, HUD scale, remap), Stats, Achievements.

### 7.4 Tutorial

Six scripted steps on a fixed seed board, each teaching one verb: move cursor → rotate → make a 3-cluster → watch gravity and a cascade → make a flower → use a starflower to build toward a pearl. Skippable, replayable, and the board state is a literal fixture so it can be regression-tested.

---

## 8. Presentation and audio

- **Art:** flat-top hexagonal gems, 2D, high-contrast bevels and specular highlights; each hue has a distinct value/saturation so it reads at small sizes. Optional pattern overlays on top.
- **Motion:** 120 ms rotation tween per step; gravity with slight per-cell delay and squash on landing; clear = flash + shatter particles; starflower bloom = expanding ring; pearl finish = full-board sequence with board-wide pulse.
- **Juice toggles:** screen shake, flash reduction, reduced-motion mode (all motion ≤ 100 ms, no shake, no pulsing).
- **Audio:** a distinct SFX per event class (rotary tick, cluster clear by size, bonus-star chime, starflower bloom, pearl thud, bomb tick, bomb defuse, explosion); cascade chains raise pitch per depth step. Music: original ambient loop with 2–3 intensity layers that respond to combo streaks. Custom soundtrack support is out of scope for v1.

---

## 9. Meta systems

| System | v1 scope |
|---|---|
| Autosave | Per mode, after every move; resume prompt on launch |
| Stats | Games played, best score per mode/difficulty, total combos, total points, pearls made, bombs defused, highest level |
| Leaderboards | Local table per mode + difficulty. `LeaderboardService` interface with a local backend so an online backend can be added later without touching game code |
| Achievements | 12 in-game milestones mirroring the reference ladder: first cluster, 25 combos, 5,000 combos, first starflower, first bonus-star cluster, first pearl, pearl cluster, pearl ring, 150,000 in Marathon, 75,000 in Timed, beat Survival, 100 games |
| Replays | Seed + command log per run; save/replay the last game (also our regression-test format) |
| Daily seed | Optional: a fixed date-seeded Marathon board for comparable scores |

---

## 10. Technical design (Godot 4)

### 10.1 Architecture rule

**Rules live in a pure, engine-free core; Godot only draws and listens.** The core is deterministic, side-effect free and unit-testable without a scene tree. This is what makes a puzzle game balanceable and regression-safe.

```
res://
  project.godot
  src/
    core/                 # pure GDScript, extends RefCounted, no Node, no signals to the view
      hex_grid.gd         #   coords, neighbours, vertices, gravity chains, pixel conversion
      board.gd            #   cell array, mutators, invariants
      ruleset.gd          #   Resource: rotation_mode, colours, level table, scoring, bomb params
      match_finder.gd     #   vertex predicate, cluster extraction, flower detection
      resolver.gd         #   cascade state machine (§3.3)
      scoring.gd          #   pure score computation from events
      rng.gd              #   seeded, deterministic, per-stream (refill / specials / bombs)
      game_state.gd       #   mode, level, combos, bombs, clock, win/lose
      events.gd           #   GameEvent records emitted per step (for view + tests + replays)
      game.gd             #   facade: apply(command) -> Array[GameEvent]
    view/
      board_view.gd       #   renders board, diffs events, drives tweens
      cell_view.gd, cursor_view.gd, effects.gd, hud.gd, menu.gd, options.gd
      input_controller.gd #   keyboard/mouse/gamepad/touch -> core commands
      audio_director.gd
    app/
      main.gd, scene_router.gd, save_service.gd, stats_service.gd, leaderboard_service.gd
  data/
    scoring.json, levels.json, difficulty.json, colours.json
  tests/                  # headless suite (no plugin): run_tests.gd + test_*.gd
```

### 10.2 Determinism and replay

- One `Rng` per concern (refill, special spawn, bomb spawn), seeded per run; the seed is shown in the stats screen.
- A run = `seed + [Command]`. Replaying is exactly re-simulating, and the last run is always replayable.
- The view never mutates core state; it consumes `GameEvent`s. A `fast_forward` mode applies events with no animation (tests, replays, solver).

### 10.3 Testing (headless, no plugin)

`run_tests.cmd` (or `powershell -ExecutionPolicy Bypass -File run_tests.ps1`, or directly
`godot --headless --path . --script res://tests/run_tests.gd`) runs every `tests/test_*.gd` suite and exits
non-zero on failure, so it works as a CI gate. The `.cmd` wrappers pass a per-process execution-policy bypass
because some machines block unsigned `.ps1` files; the scripts are written to run on Windows PowerShell 5.1
(no `pwsh` dependency). The harness is
`tests/test_case.gd` plus `tests/run_tests.gd` — deliberately dependency-free so the project never breaks
because a test plugin changed.

> Godot 4.7 quirk: `quit()` called from `_initialize()` does not stop the main loop, so the runner's
> `_process()` returns `true` to terminate while `quit(code)` records the exit code. A parse error in any
> suite is reported as a failure (never a silent pass) via `can_instantiate()`.

**M0 results (37 tests, 0 failed, ~14.7k assertions):**

- exactly 85 cells; column heights alternate 9/8; adjacency symmetric and irreflexive.
- **exactly 135 rotation vertices**, every one a mutually adjacent triple, all unique.
- **17 staggered half-rows of exactly 5 cells** — matching the independent reverse engineering.
- shifted columns hold the short height (the dangling-corner guard), no cell has fewer than 2 neighbours.
- neighbour centres sit exactly one hex edge apart (`sqrt(3) × size`) and columns stay vertically aligned.
- gravity compacts per column, preserves relative order, is idempotent, never slides sideways.
- the board invariant detects floating pieces (and only those).
- the RNG reproduces identical 32-bit streams per seed, keeps streams independent per label, survives 100k
  draws without collapse, and yields correct ranges for `next_int` / `next_float` / `shuffle` / `pick`.
- piece packing round-trips kind, colour and bomb counter; the palette ramps 5 → 6 → 7 colours.

**Still to build (M1+):** the vertex match predicate truth table (including "a straight line of 3 does not
clear"), cluster sizing 4/5/6, flower precedence, star ×2/×4/×8 stacking, star-cluster area clear, bomb tick
and detonation, bomb + star colour wipe, starflower ring rotation, pearl orientations and the pearl finish,
level thresholds, the Survival lock/refill cycle and the Timed starflower refill.

**Property tests:** 10,000 random legal playouts on all modes never panic, never leave a floating piece, and
always terminate.

**Fixtures:** the tutorial board plus 3–5 transcribable reference boards (the fan project `hectic-hexagons`
transcribes real frames — useful cross-checking) as golden tests for match sets.

**Environment note:** under the current sandbox, Godot cannot create `user://` (it maps to `%APPDATA%`), so
`user://logs` and `editor_settings-4.7.tres` writes fail harmlessly. Autosave/leaderboards in M4 must either
write inside the project (a git-ignored `userdata/` folder) or run with wider filesystem access.

### 10.4 Performance

85 cells is trivial: one `_process` pass, tweens for motion, no per-frame allocation in the resolver, and match detection is O(135 vertices + 85 cells) per step. Target 60 FPS on integrated graphics and in-browser export. Batch gem drawing via a single `MultiMeshInstance2D` or an atlas in one `TileMap`/`Sprite2D` layer if profiling ever demands it.

### 10.5 Hint system

Suggest a legal rotation using a bounded search (depth 2–3) over legal moves, preferring moves that build toward flowers/pearls. Reuse the same code for dead-board detection. Idle delay configurable; hint glow can be disabled.

---

## 11. Deviations from the reference (explicit)

| # | Area | Reference | Hexard v1 | Why |
|---|---|---|---|---|
| 1 | Rotation commit | Non-matching trio spins **revert**; only special-piece rotations persist (high-confidence: official MSN text, a 360-played review, and three fan re-implementations) | One 60° step per press, **any position persists** | User decision. Makes flower/pearl construction tractable and the puzzle about intent rather than luck. `STRICT` mode reproduces the original for comparison |
| 2 | Cascade scoring | Undocumented | ×1.5 per extra cascade depth | We need a defined, tunable curve |
| 3 | Dead board | Undocumented | Auto-shuffle, no penalty | Must not soft-lock |
| 4 | Bomb numbers | Start value and spawn rate undocumented | Config: start 8 at level 3, −1 per level (min 4), spawn rate per level | Fan placeholder; tune by playtest |
| 5 | Palette | Ambiguous (6 vs 7 colours, two greens, pink) | 7 hues, 5 early, pattern overlays | Distinguishability and accessibility |
| 6 | Difficulty names | Exist but unnamed in sources | Easy / Normal / Hard | We must label them |
| 7 | Star colour semantics | Sources conflict | Colour-agnostic 3-star cluster (stars + everything they touch); "3 same-colour stars wipe that colour" **rejected as unsupported** | Follows the stronger official MSN wording |
| 8 | Onboarding | No tutorial (documented weakness) | Six-step interactive tutorial | Biggest cheap win |

### ⚠️ Balance risk from deviation 1

Free rotation collapses the difficulty of building flowers: in the original, gravity RNG must deliver a near-flower before the last rotation can complete it, which is why pearls are rare and prestigious. With free rotation, a skilled player can construct flowers almost at will, so pearls become routine and the score curve inflates.

Mitigations to evaluate in playtesting, in order of preference:

1. Tune bomb pressure (spawn rate, timer) and the combo thresholds, so spending 20 moves assembling a flower is a real cost.
2. Cap how often a given starflower can be used (e.g. a starflower's ring rotation is free but each *use* is a move, so bombs tick).
3. Keep `STRICT` available and let playtest data choose the default.
4. If pearls still trivialise the game, make bonus stars the scarce resource (a flower with no star involvement yields a starflower that cannot be selected, or add a rotation counter to starflowers).

**Do not silently "fix" this by removing features later — pick from the list above deliberately and record the choice here.**

---

## 12. Milestones

| Milestone | Deliverable | Done when |
|---|---|---|
| **M0** ✅ | Repo + this doc + Godot 4.7.2 toolchain + `hex_grid.gd`, `board.gd`, `piece.gd`, `rng.gd` + headless suite | **Done:** 37 tests / 0 failed, including 85 cells, **135 vertices**, 17×5 half-rows, gravity invariants |
| **M1** | Playable core: board, cursor, discrete rotation, match predicate, gravity, refill, cascades, scoring. No specials, dev art | A full Marathon-ish loop is playable in-editor and 10k random playouts pass the property tests |
| **M2** | Specials: bonus stars (×2 + 3-star area clear), starflowers (flower → piece → ring rotation), black pearls (creation, Y rotation, perfect finish), bombs (tick, defuse, colour wipe) | All specials rule-tested; a pearl ring can be built end-to-end in a scripted fixture |
| **M3** | Progression + modes: 7 levels, combo thresholds, content gating, Marathon/Timed/Survival, difficulty, dead-board shuffle, win/lose flows | Each mode playable to its conclusion with correct game-over/win paths |
| **M4** | Presentation + meta: art pass, animations, SFX/music, HUD, menus, options, tutorial, autosave/resume, stats, achievements, local leaderboard | A first-time player can learn the game from the tutorial alone |
| **M5** | Polish + balance: playtest-driven tuning of scoring/RNG/bombs, accessibility pass, replays, exports (Windows + web) | Balance targets met (§13), export builds run at 60 FPS |

---

## 13. Balance targets

- An average first Marathon run on Normal lasts **8–15 minutes** and reaches level 3–5.
- A skilled player reaches **level 7** within 30 minutes.
- First starflower within a player's first ~10 minutes; first black pearl within their first hour.
- Pearl finish should feel like a genuine achievement: on Normal, a skilled player completes it in roughly **1 in 5–10 serious attempts**.
- Bombs kill on Easy <10% of runs, Normal 25–40%, Hard 50%+.
- Never a run-ending situation in the first 2 minutes on Easy.

---

## 14. Open questions

1. Which column parity is short in the real board (cosmetic, but pin it with a frame capture before art lock).
2. Reference frame capture to validate the palette and the board silhouette.
3. Bomb start value, spawn rate and per-level curve — playtest.
4. Base values for 5/6+ clusters and the cascade curve — playtest.
5. Does a *reverted* spin tick a bomb in `STRICT` mode? (Decided: no — a reverted spin is not a move. Revisit if STRICT feels too forgiving.)
6. Difficulty: does Easy merely score lower, or also generate more forgiving refills? (Current design: both.)
7. Whether to expose `STRICT` in the options menu or keep it dev-only.
8. Whether Survival's 50-round win is reachable and worth the achievement.

---

## Appendix A — Fidelity matrix

| Feature | In Hexic HD | Hexard v1 |
|---|---|---|
| 85-cell staggered board, 6-neighbour hexes | ✅ | ✅ |
| Rotate trios around a vertex, CW/CCW, animated | ✅ | ✅ |
| Swap mechanic | ❌ | ❌ |
| Gravity per column + refill from top + cascades | ✅ | ✅ |
| Vertex-triangle match, 3+ clears, size bonuses | ✅ | ✅ |
| Bonus star (coloured, ×2 stacking, colour-agnostic 3-star area clear) | ✅ (level 2+) | ✅ |
| Starflower from a 6-ring; rotates all 6 neighbours | ✅ | ✅ |
| Black pearl from 6 starflowers; Y rotation | ✅ | ✅ |
| Pearl cluster / ring = perfect finish | ✅ | ✅ |
| Bombs: per-move counter, defuse by colour cluster, star synergy wipes colour | ✅ (level 3+) | ✅ |
| 7 levels, advanced by combos, score × level | ✅ | ✅ |
| Marathon / Timed / Survival | ✅ | ✅ |
| 3 difficulty settings | ✅ | ✅ |
| Hint glow, colour-blind patterns, autosave/resume | ✅ | ✅ |
| Achievements / leaderboards | ✅ (Xbox Live) | Local, online-ready |
| Hexic 2 Battle mode, Emerald/Ruby, chain detonation | ❌ / Hexic 2 only | ❌ (non-goal) |
| Hypercube / rainbow wildcard | ❌ (does not exist) | ❌ |
| Tutorial | ❌ | ✅ |
| Undo, zoom/pan, multiplayer | ❌ | ❌ |

## Appendix B — Evidence and confidence

Claim-level sources and confidence ratings live in [`docs/research/sources.md`](research/sources.md). Summary of reliability:

- **Official (Microsoft/MSN/Xbox text):** rotation of trios; rotation-only; automatic spin stop; gravity and top-edge refill; starflower = ring of 6; starflower rotates its 6 neighbours; bonus stars are colour-agnostic; 3-star cluster clears what the stars touch; bomb + bonus star clears that colour; Survival and Timed rules; pearl ring wins.
- **Press / hardware-played reviews:** rotation reverts without a match; star multiplier ×2 stacking; cluster 3 = 5 points, 4 = 10; starflower 1,000; pearl 10,000; pearl ring 250,000; 50/60-combo level thresholds; level ramp (L2 stars, L3 bombs, colours after L4, 7 colours by L5); bomb numbers = moves; hints; colour-blind options.
- **Fan reverse engineering (two independent implementations):** board = 85 cells in 10 columns; 135 rotation vertices; gravity chains of 8/9; resolution order.
- **Undocumented (we own the number):** exact bomb counters and spawn rates, score curve beyond 4-gem clears, cascade summing, starflower/bonus-star spawn rates, difficulty names, dead-board handling.
