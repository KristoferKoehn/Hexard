# Hexic research — evidence ledger

Companion to [`docs/design.md`](../design.md). Every design-relevant claim, its source, and how much we trust it.

**Confidence keys**

- **OFFICIAL** — Microsoft / MSN Games / Xbox.com text.
- **PRESS** — a review or guide written by someone who played the shipped game.
- **FAN-RE** — fan reverse engineering (two independent implementations where noted).
- **CONFLICT** — sources disagree; the design doc records our resolution.
- **UNKNOWN** — no source found; the number is ours to choose.

---

## 1. Board

| Claim | Confidence | Source |
|---|---|---|
| 85 cells, 10 columns, alternating heights 9/8, no blocked cells | FAN-RE (×2) | [`hexic-solver`](https://raw.githubusercontent.com/dmitrykrivaltsevich/hexic-solver/master/src/main/java/com/intetics/HexicSolver.java) (`NUMBER_OF_CELLS = 85`), [`hectic-hexagons`](https://raw.githubusercontent.com/ncmiller/hectic-hexagons/master/src/include/constants.h) (`HEX_NUM_COLUMNS 10`, `HEX_NUM_ROWS 9`, even columns drop the last row) |
| 135 rotation vertices | FAN-RE | `ROTATION_POINTS` table of 135 trios in `hexic-solver` |
| Zigzag ("brick") outline, not a tapering hexagon | FAN-RE + screenshots | Both implementations; our own inspection of Hexic HD screenshots (`docs/research/`) |
| 6-neighbour edge adjacency, flat-top hexes | FAN-RE (×2) | Both implementations |
| Board = 90 cells, "8 in odd and 10 in even columns" | CONFLICT (rejected) | [Giant Bomb wiki](https://www.giantbomb.com/wiki/Games/Hexic) — inconsistent with two independent REs and with our screenshot count; treated as a garbled 9/8 = 85 |
| Real Hexic HD board frame transcribed into the 10×9-minus-notches grid | FAN-RE | [`test_boards.c`](https://raw.githubusercontent.com/ncmiller/hectic-hexagons/master/src/test/test_boards.c) (video cited in-file: <https://www.youtube.com/watch?v=WIoabsFQv1s>) |

## 2. Rotation and input

| Claim | Confidence | Source |
|---|---|---|
| Rotate a trio of 3 hexes sharing a vertex; rotation only, no swap | OFFICIAL | [Xbox.com Hexic HD (archived 2007)](https://web.archive.org/web/20070101013956/http://www.xbox.com/en-US/games/h/hexichdlivearcadebox360/default.htm); [Xbox.com Hexic 2 (archived 2009)](https://web.archive.org/web/20090101051357/http://www.xbox.com/en-US/games/h/hexic2xboxlivearcade/) |
| "Click on a group of three hexagonal tiles to rotate them. Hit the SPACEBAR to change the direction of rotation." | OFFICIAL | [MSN Games Hexic (archived 2014)](https://web.archive.org/web/20140714165753/https://zone.msn.com/en/hexic/default.htm) |
| Non-matching trio spins stop at a match or **revert**; only special-piece rotations persist | OFFICIAL + PRESS + FAN-RE (high) | MSN text above; [2006 Wikipedia revision](https://web.archive.org/web/20060913000000/http://en.wikipedia.org:80/wiki/Hexic); [Giant Bomb mechanics analysis](https://giantbomb.com/users/3929/articles/black-pearl-the-surprising-complexity-of-hexic-hd) ("to move pieces, you need to match pieces"); [The Game Hoard review](https://thegamehoard.com/2019/12/08/hexic-hd-xbox-360/) ("you can't rearrange the board for bigger matches"); all three clones |
| Starflower rotation is one 60° step and persists without a match | PRESS | Giant Bomb mechanics analysis: "you don't need to match them for the rotation to stop" |
| Black pearl rotates the hex above, bottom-left and bottom-right freely | PRESS | Giant Bomb mechanics analysis; The Game Hoard ("adjacent hexagons in a Y shape are rotated freely around the pearl") |
| X / A rotate CW / CCW; triggers also rotate; cursor on stick/D-pad | PRESS | [GameFAQs user review](https://gamefaqs.gamespot.com/xbox360/930853-hexic-hd/reviews/121643); [TrueAchievements walkthrough (archived)](https://web.archive.org/web/20160403030133/http://www.trueachievements.com/walkthroughfull.aspx?walkthroughid=124) |
| Flower formation takes precedence over a plain 3-colour match in the same rotation | PRESS | TrueAchievements walkthrough |
| Hold-to-spin control model | UNKNOWN / rejected | No source found; we implement discrete 60° presses |

## 3. Matching, gravity, cascades

| Claim | Confidence | Source |
|---|---|---|
| 3+ same-coloured pieces touching clear; bigger clears score more | OFFICIAL + WIKI | Xbox.com blurbs; [Wikipedia: Hexic](https://en.wikipedia.org/wiki/Hexic) |
| Cluster = cells around one vertex (mutually adjacent triangle); larger groups extend by adjacency | FAN-RE | `hex_has_cluster_match` in [`game.c`](https://raw.githubusercontent.com/ncmiller/hectic-hexagons/master/src/game.c) |
| Resolution order: flowers → colour clusters → bombs → remaining mixed | FAN-RE | `check_for_matches` in the same file |
| **Gravity exists**: per column downward, new gems from the top edge, cascades | OFFICIAL + WIKI (×2) + FAN-RE (×2) | [Official MSN tips](https://web.archive.org/web/20081218183405id_/http://zone.msn.com/en/hexic/article/hxictips.htm) ("tiles that fall to fill in the gaps"; "the flower tiles will fall out of position"); Wikipedia 2006 + current; both clones (`handle_gravity`, `fallDown`) |
| Every clear counts as a "combo" (stat + level unit) | PRESS | TrueAchievements walkthrough; GameFAQs review |
| "No gravity / refill from the sides" | CONFLICT (rejected) | No source supports it |
| Combo timer / "combometer" in classic modes | UNKNOWN (rejected) | No source found; the only fill-meter is Hexic 2's Battle tanks |

## 4. Pieces

| Claim | Confidence | Source |
|---|---|---|
| Starflower = ring of 6 same-coloured gems around a centre; the centre becomes the star | OFFICIAL + PRESS | MSN tips ("make a ring of same-colored tiles around a single tile… the single tile in the center will turn into a starflower"); Giant Bomb mechanics analysis |
| Bonus star = a coloured gem with a star, arrives as a new piece from level 2, ×2 per star stacking | PRESS (×2) | TrueAchievements walkthrough (Star Gazer); [Windows Mobile port review](https://www.windowsphonethoughts.com/news/show/89064/hexic-for-windows-mobile-reviewed.html) ("Level 2 introduces bonus star pieces… add extra points"); GameFAQs review ("multiplied by 2… multiplied by 4") |
| Bonus stars cluster regardless of colour; the cluster clears the stars plus everything they touch | OFFICIAL + PRESS | MSN tips ("Bonus pieces do not have to be the same color in order to create a cluster"; "along with every tile each of the bonus pieces is touching"); The Game Hoard |
| "Three same-coloured stars clear every gem of that colour" | CONFLICT (rejected as unsupported) | Only [Giant Bomb wiki](https://www.giantbomb.com/wiki/Games/Hexic); every readable source applies the colour-wide board clear to **bomb + bonus star** instead |
| Black pearl = one piece surrounded by 6 starflowers; rotates 3 neighbours in Y / inverted-Y | PRESS + WIKI | [XboxAchievements Hexic HD guide (archived)](https://web.archive.org/web/20221203023339/https://www.xboxachievements.com/game/hexic-hd/guide/) ("A Black Pearl is created by surrounding one piece with 6 Starflowers"); Giant Bomb mechanics analysis; MSN page ("Use starflower pieces to make another flower and earn the elusive black pearl") |
| Pearl cluster **or** ring ends/wins the game with a large bonus | OFFICIAL + WIKI + PRESS | MSN; Wikipedia (2006 + current); Giant Bomb |
| Bomb = coloured gem with a number = moves remaining; ticks per move; detonates at 0 → game over | PRESS + WIKI (×2) | GameFAQs review; The Game Hoard; Wikipedia 2006 + current |
| Bomb + ≥1 bonus star of the same colour clears every gem of that colour | OFFICIAL + PRESS | MSN tips; Windows Mobile review; Wikipedia |
| Bombs first appear at level 3 | PRESS (×2) | Windows Mobile review ("Level 2 introduces bonus star pieces… Level 3 introduces bombs"); fan clone level table |
| Bomb timer shortens with level; bomb start value / spawn rate | PRESS for direction / UNKNOWN for numbers | Giant Bomb mechanics analysis for the direction; only fan placeholder `bombExplosionCounter = 8` ([UnityHexicGame](https://raw.githubusercontent.com/yasirkula/UnityHexicGame/master/Assets/Scripts/Manager.cs)) exists |
| Hypercube / rainbow wildcard | UNKNOWN (does not exist) | Not in any official text, Wikipedia revision, achievement list, review or clone. The name belongs to Bejeweled |

## 5. Levels, scoring, modes, meta

| Claim | Confidence | Source |
|---|---|---|
| 7 levels; advanced by combos: 50 to reach level 2, 60 for level 3, then +10 | PRESS + FAN-RE | GameFAQs review; the clone hard-codes 7 levels and `combos_remaining = 50` |
| Score = base value × current level | PRESS | Giant Bomb mechanics analysis; GameFAQs review (3-red cluster = 5 points at level 1, 10 at level 2) |
| Base values: cluster 3 = 5, cluster 4 = 10, starflower = 1,000, pearl = 10,000, six-pearl ring = 250,000 | PRESS | Giant Bomb mechanics analysis |
| Level ramp: L1 five colours no specials; L2 bonus stars; L3 bombs; more colours after L4; 7 colours by level 5 | PRESS (×2) + WIKI | Windows Mobile review; Giant Bomb mechanics analysis; [2006 Wikipedia](https://web.archive.org/web/20060913000000/http://en.wikipedia.org:80/wiki/Hexic) |
| Three difficulty settings; lower = fewer points but more opportunities, higher = more points | PRESS | TrueAchievements walkthrough; The Game Hoard; Joystiq review |
| Difficulty option names | UNKNOWN | No source names them |
| Modes: Marathon, Timed, Survival; no fourth mode | PRESS (×2) | [Joystiq review](https://www.engadget.com/2005-11-19-joystiq-review-hexic-hd.html); [Joystiq QuickTake](https://www.engadget.com/2005-12-03-fanboy-quicktake-hexic.html) |
| Timed: timer refilled by clears and level-ups; starflower refills it and raises the cap by 10 s; cap 2 minutes; starts ~50 s on Normal | PRESS + WIKI | Giant Bomb wiki; Wikipedia; GameFAQs review; [Cheatbook](https://www.cheatbook.de/cfiles/hexichdxbox360.htm) (50 s, medium confidence) |
| Survival: no refill in a round; leftovers lock when no moves remain; board refills over them; star clusters unlock; flower unlocks all and clears the centre colour; win = clear the board or 50 rounds; lose = all locked; no bombs/pearls | WIKI (×2) + PRESS | Wikipedia 2006 + current; Giant Bomb wiki; GameFAQs review |
| HUD shows Level and "Combos Remaining / Combos To Go" | OFFICIAL visual | Verified by us in Hexic HD and MSN screenshots (`docs/research/`) |
| Hint glow after idle | PRESS | The Game Hoard; Joystiq ("Bejeweled-like hints") |
| Colour-blind pattern option; Hexic 2 extends patterns to bombs | PRESS | GameFAQs review; [GameSpot Hexic 2 review (archived)](https://web.archive.org/web/20090208022019/http://www.gamespot.com/xbox360/puzzle/hexic2/review.html) |
| Auto-save per mode with resume | PRESS | [thoughthead review](http://thoughthead.com/10) |
| Leaderboards (global + friends) | PRESS + WIKI | Joystiq QuickTake; GameFAQs review; Wikipedia |
| No multiplayer in Hexic HD; no documented undo, zoom or pan | PRESS | GameFAQs review |
| 12 achievements / 200 GS, with the pearl ladder | PRESS | [XboxAchievements guide](https://web.archive.org/web/20221203023339/https://www.xboxachievements.com/game/hexic-hd/guide/); [Vandal DB](https://vandal.elespanol.com/logros/x360/hexic-hd-xbla/6865) |
| Hexic 2 additions: Battle mode, Emerald (line of 5), Ruby (row of 5 starflowers), chain detonation, per-colour attack tanks, board shrink/lock attacks | WIKI + PRESS | [Wikipedia: Hexic 2](https://en.wikipedia.org/wiki/Hexic_2) (Emerald/Ruby detail is uncited → medium); GameSpot review |

## 6. Version map (for scope discipline)

| Version | Modes | Notes |
|---|---|---|
| Hexic (MSN web, 2003) | Marathon, Timed, Survival | Original; one-click spin control |
| Hexic Deluxe (PC, 2005/2006) | Marathon, Timed, Survival | Flash; same rules; difficulty options |
| **Hexic HD (Xbox 360, 2005)** | **Marathon, Timed, Survival** | **Our reference.** Achievements, leaderboards, colour-blind patterns, autosave |
| Hexic 2 (XBLA, 2007) | + Battle | Emerald/Ruby tiers, chain detonation, multiplayer |
| Hexic Rush (WP7, 2010) | Marathon, Rush | Colour unlocking, board freeze |
| Hexic (Windows Store, 2014) | Level-based F2P | Different game — lives, boosts, 49 levels. Out of scope |
