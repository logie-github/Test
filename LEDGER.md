# Project Ledger

Canonical development state for **Pokopia: Log 568**.

Current phase: **Chapter Openings** (build 1.0.370).
Previous phases: LOG 568 Bookend Finale (1.0.369), Rocket Lounge Polish (1.0.368).

---

## Completed

- Gave the Pokémon Mansion an opening. The game previously cut from the black
  LOG 568 screen straight to a player standing on 3F with an alarm running: no
  location, no establishing beat, and no acknowledgement of what the player had
  just been shown. It now dissolves from a composed `CINNABAR ISLAND /
  POKeMON MANSION` card into the live floor and plays four narration beats over
  the room.
- Replaced the `Much earlier...` intertitle's raw `love.graphics.printf` — which
  rendered in LOVE's default font, not the game's — with a real Gen I chapter
  card. The line itself is preserved verbatim.
- Made Celadon open on the city. The three-shot establishing sweep had been in
  the project all along and was unreachable because `cut:enter` jumped straight
  to the Game Corner. It is now the chapter's opening, with a narration beat on
  each shot.
- Composed the two openings as a question and its answer, mirroring at chapter
  scale what the LOG 568 bookend does at game scale.
- Extracted `cinema.lua`, one Gen I presentation layer behind all three
  authored compositions, and rebuilt `finale.lua` on it.
- Fixed a real text-layout defect the new tests exposed (see **Known Issues
  Fixed**).
- Added character personality documents for the Scientist and Giovanni.
- Added two regression suites and a runner; 518 standalone checks in total.

**Not changed:** the opening OakSpeech scene, Mansion gameplay (population,
personality dialogue, Rattata/Persian, the Giovanni briefing, the Pixie rescue,
the PC placement), or Celadon gameplay (Game Corner refund, café jobs, TCG,
Rocket Operations, the card-scalper quest).

## Files Added

| File | Purpose |
|---|---|
| `cinema.lua` | Shared Gen I cinematic presentation for every authored cutscene |
| `chapters.lua` | The Mansion cold open and the Celadon chapter opening |
| `tests/support.lua` | Shared harness: LOVE/font stubs, fake stack and input, frame driver, geometry assertions |
| `tests/cinema.lua` | 98 checks over the presentation layer |
| `tests/chapters.lua` | 127 checks over both chapter openings |
| `tests/run.lua` | Runs every standalone suite |
| `characters/scientist/personality.md` | Character reference for the Scientist |
| `characters/giovanni/personality.md` | Character reference for Giovanni |
| `CHAPTER_OPENINGS.md` | Design record for the two chapter openings and `cinema.lua` |

Added in the previous phase and still current: `finale.lua`, `tests/finale.lua`,
`characters/logan/personality.md`, `LOG568_BOOKEND.md`, `LEDGER.md`.

## Files Modified

| File | Change |
|---|---|
| `main.lua` | Forward-declared `Cinema` and `Chapters`; one loader now constructs all three cutscene modules; `q.chapters` normalization; Mansion cold-open trigger in `input.step`; `muchEarlier` draws a composed card; `cut:enter` arms the Celadon sweep; the sweep's stage machine carries a narration beat per shot |
| `finale.lua` | Runtime rebuilt on `cinema.lua`; script data unchanged; about a third smaller with no change to the ending itself |
| `tests/finale.lua` | Loads `cinema.lua` for the pure helpers; geometry pass exempts verbatim opening rows from the worst-case width check |
| `manifest.json`, `mod.card`, `CHANGELOG.md`, `README.md`, `.modkitignore`, `LOG568_BOOKEND.md` | Version, description and documentation |

## Core Systems

| System | Owner | Responsibility |
|---|---|---|
| Mod entry / content patching | `main.lua` | `mod.content.field:patch`, sprite and follower registration, map overrides |
| Ditto-as-player | `main.lua` | `playerSprites` patch, transform menu, form persistence, movement hooks |
| Dialogue presentation | `main.lua` | `TextBox` wrappers, speaker inference, trainer cutouts, Pokémon portrait cards |
| **Cinematic presentation** | **`cinema.lua`** | **Frame geometry, text layout, typewriter frame, nameplates, trainer cutouts, chapter cards, page runner, overworld input lock, guarded audio** |
| **Chapter openings** | **`chapters.lua`** | **Mansion cold open, Celadon chapter card, montage narration, cold-open gating and save migration** |
| Ending / bookend | `finale.lua` | Departure, liftoff, LOG 568 recreation and continuation, preservation system, closing image |
| Mansion emergency scene | `main.lua` | Map-script overrides, authored cast, alarm, panic scripts |
| Celadon chapter | `main.lua` | `startCeladonEnding` and its cinematic controller, café jobs, Game Corner, scalper line, card quest |
| TCG | `tcg_battle.lua`, `tcg_engine/` | Packs, binder, deck builder, duels |
| Rocket operations | `rocket_quests.lua` | Five sequential save-persistent hideout quests |

All four extracted modules follow the same contract: `main.lua` loads the chunk
with `loadfile` and constructs it with an explicit API table. None of them reach
into `main.lua`'s locals, and all four can be exercised standalone.

## Save Schema

Namespace: `save.modData.pokopia_log568`. Schema version **5**.

New in this phase — `q.chapters`:

| Field | Type | Meaning |
|---|---|---|
| `version` | number | Chapter schema version |
| `mansionOpeningSeen` | boolean | The cold open has played |
| `mansionOpeningRunning` | nil | Transient; explicitly cleared on load |
| `celadonOpeningSeen` | boolean | The Celadon montage has played |
| `migrated` | boolean | One-shot latch: progress-derivation has run for this save |

Still current from the previous phase — `q.finale`: `version`,
`prequelComplete`, `logSeen`, `completed`, `playCount`, `lastScene`, transient
`running`.

Migration: `mansionOpeningSeen` is derived once from real story progress
(`Chapters.PROGRESS_MARKERS`, plus any learned transformation) so a save made
before this build is never handed a cold open. The `migrated` latch means a
later pass cannot undo a deliberate replay from a developer scene jump. No
existing field is renamed, cleared or reinterpreted; unknown fields are still
preserved and the schema number is still never downgraded.

## Transformations

Unchanged this phase.

| Form | Obtained | Notes |
|---|---|---|
| DITTO | default | Base form |
| PERSIAN | Mansion B1F Rattata/Persian scene | Faster movement; passes the Rocket guard |
| ELECTRODE | Celadon chapter | Momentum-based speed ramp |
| PORYGON | Celadon chapter | Used in the Game Corner prize scene |
| HITMONLEE / HITMONCHAN | Celadon spar, player choice | One of the two, persisted |

A learned form now also counts as evidence that a save is inside the story, and
therefore suppresses the cold open.

## Characters

| Character | State variables | Documented |
|---|---|---|
| The Scientist | — (the LOG 568 voice and the Conservation Project briefing) | `characters/scientist/personality.md` (new) |
| Giovanni | `giovanniMeetingDone`, `giovanniWrongFormPending` | `characters/giovanni/personality.md` (new) |
| Logan | `loganAsked`, `pixieFollowing`, `pixieStored` | `characters/logan/personality.md` |
| Wooper | `characters.WOOPER.streetCred` | `characters/wooper/personality.md` |
| Pixie (Vulpix) | `pixieFollowing`, `pixieStored`; appears in the finale's storage roll under her nickname | — |
| Hypno | Card Club hub and the developer scene jumps | — |
| Super Nerd | `refundDemanded`, `policeCalled`, `superNerdArrested` | — |

## Relationships

Unchanged this phase. `q.characters.<NAME>` remains the per-character
relationship namespace; Wooper's `streetCred` is the only tracked value so far.

## Quests

Unchanged this phase. Mansion: Rattata distraction → Giovanni meeting → Pixie
rescue → PC placement. Celadon: café delivery jobs, card-scalper quest, Game
Corner refund sequence. Rocket Operations: five sequential quests.

## Minigames

Unchanged this phase: café delivery jobs, Cue Bones, TCG duels, pack opening.

## World State

Unchanged this phase. Both chapter openings are presentational: they move no
NPCs, open no paths and alter no map geometry, so neither can desynchronise an
existing reconciliation pass. Each locks the live overworld's player input and
restores the previous value on close.

## Story Progress

Playable, in play order:

1. Title → OakSpeech LOG 568 (flash-forward).
2. **`CINNABAR ISLAND / POKeMON MANSION` card → the Mansion cold open.**
3. Pokémon Mansion: emergency, Rattata/Persian, Giovanni's Conservation Project
   briefing, Pixie rescue, PC placement.
4. **`CELADON CITY / Much earlier...` card → the city sweep with narration.**
5. Celadon City prequel: Game Corner refund, café jobs, TCG, Rocket Hideout
   operations, card-scalper quest.
6. Ending: departure → liftoff → LOG 568 → preservation system → Ditto dormant.

Every transition in the game is now composed. Nothing cuts.

## Dependencies

Later phases can rely on:

- `Cinema.layout` / `Cinema.pages` / `Cinema.authoredRows` — pure Gen I text
  helpers with a pluggable width measure.
- `Cinema.new(api)` — the whole renderer: `drawTextFrame`, `drawCard`,
  `drawSpeakerArt`, `drawFade`, `drawFrame`, `newPageRunner`, `lockOverworld`,
  `silenceMusic` / `playMusic` / `restoreMusic`.
- `Chapters.SCRIPT`-equivalent data tables (`MANSION_CARD`, `CELADON_CARD`,
  `MANSION_OPENING`, `CELADON_MONTAGE`) and `Chapters.hasProgress` /
  `reconcile` for any future "has this save started?" question.
- `Finale.SCRIPT`, `Finale.state`, `markPrequelComplete` / `shouldAutoPlay`.
- `tests/support.lua` — the harness. A new suite is roughly ten lines of setup.

## Known Issues

- `SYSTEM_RECORDS` in the finale is an authored list, not a read of the
  player's actual storage.
- The chapter cards, the launch and the storage display are drawn from
  primitives and the existing DMG logo; no authored art exists for them yet.
- The Celadon montage's shot compositions (`views = {{10,10},{18,12},{28,16}}`)
  are inherited from the original unreachable code and have never been seen
  running in-engine. They are the most likely thing to need re-framing after a
  real playtest.
- `tests/core.lua` still requires the engine harness and was not folded into
  `tests/run.lua`.

## Known Issues Fixed

- **A three-row page could lose its last row.** The wrapper re-broke authored
  rows and then clamped the result to three, which silently deleted the end of
  the page. The opening's `Life on this planet / as we know it will / come to an
  end.` has a 19-character first row; under a strict measure the re-wrap
  produced four rows and clamped away `come to an end.` — the most important
  line in the ending. Authored breaks now always win, the wrap is only accepted
  when it still fits three rows, and a page quoted from the opening is never
  re-broken at any width.
- **The Hypno scene picker painted its last row below its own frame** (fixed in
  1.0.369 when the two finale entries were added).

## Regression Risks

| Risk | Protection |
|---|---|
| The opening OakSpeech lines are edited or removed | `tests/finale.lua` asserts each is still present in `main.lua` as source |
| The bookend's quote drifts from the opening | Pages 1-4 and the last two compared byte-for-byte |
| A cause is invented for the disasters, or humans are shown returning | Banned-vocabulary sweep |
| The Mansion question or the Celadon answer is edited away | `tests/chapters.lua` asserts both halves and their DITTO references |
| `Much earlier...` is reworded | Asserted verbatim |
| Someone re-skips the Celadon city sweep | `tests/chapters.lua` asserts `cut:enter` arms `hold_first`, frames shot one, and carries three narration beats; and that the old skip comment is gone |
| The raw `printf` intertitle returns | Asserted absent |
| A dialogue edit overruns the text frame | Per-page row/width assertions plus a geometry pass over every string the headless runs draw |
| The cold open fires on an in-progress save | `hasProgress` / `reconcile` tests, including the latch that must not undo a replay |
| A cutscene leaves the player input-locked | Both openings and the ending assert lock-and-restore in their headless runs |
| A save written mid-cutscene resumes stuck | `running` flags cleared in `normalizePokopiaSave` |

## Testing Completed

- `lua5.1 tests/run.lua` — 518 checks across three suites, all passing
  (`cinema` 98, `chapters` 127, `finale` 293).
- Deliberate-regression verification: erasing the Celadon answer beat and
  re-disabling the city sweep were each confirmed to fail the suite, as was
  moving a storage-display row under the dialogue frame.
- Headless drives of all three authored compositions — the Mansion cold open
  (`CARD`/`REVEAL`/`NARRATE`), the standalone chapter card, and the whole
  ending — with `update` and `draw` executed every frame, asserting each state
  pops itself and restores player input.
- Geometry pass asserting every string those runs draw fits 160×144 and never
  lands under the dialogue frame border, with one documented exemption for rows
  quoted verbatim from the opening.
- Lua 5.1 (LuaJIT-compatible) parse sweep over every packaged file.
- Bytecode symbol audit confirming `cinema.lua`, `chapters.lua` and
  `finale.lua` write no globals, and that every new `main.lua` call site
  resolves as a local or upvalue rather than an accidental global.
- `manifest.json` re-parsed as JSON; `mod.card` re-parsed as Lua.

**Not performed:** in-engine playtesting. Gen1Recomp is not available in this
environment, so every engine-facing call was matched against a call site that
already ships in `main.lua`/`tcg_battle.lua`, and everything optional is
`pcall`-guarded with a working fallback.

## Next Phase

Suggested, in dependency order:

1. **In-engine verification pass.** Three things cannot be checked outside the
   engine: whether the Scientist cutout lands in exactly the intro's screen
   position, whether the Celadon sweep's three shot compositions frame anything
   worth looking at, and whether the engine font's real advance widths let the
   opening's 20-character rows sit inside the frame.
2. **Re-frame the Celadon sweep** against what the playtest shows, now that it
   is reachable for the first time.
3. **Wire the finale's storage roll to real data** instead of the authored
   `SYSTEM_RECORDS` list.
4. **Stage the departure scene** as an overworld beat (Logan walking out, lights
   failing bank by bank) rather than a text scene over the sealed-system view.
   It attaches at `enterScene("DEPARTURE")` without touching anything else.
