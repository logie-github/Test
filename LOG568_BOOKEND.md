# LOG 568 — Bookend Design and Implementation

The game's first scene and one of its last scenes are now the same scene, seen
twice. This document records how that composition is built, why each decision
was made, and where to change it.

## The problem this solves

The opening runs on the engine's real `OakSpeech` screen with its content
replaced (`main.lua`, the `intro.oak_speech.build` wrap): black field, the
`OPP_SCIENTIST` trainer portrait, and six lines of a log with no date, no
speaker attribution, and no context.

```
LOG 568:
"The experiment has failed."
"Our last-ditch Hail Mary project..."
"A complete and total failure."
"Estimations show within a few days..."
"Life on this planet as we know it will come to an end."
```

Before this change that scene had no payoff. It read as atmosphere. The player
never learned what experiment, whose project, or when — so the opening stayed
an isolated ominous intro instead of the last page of the story they had just
played.

## The composition

```
        TITLE
          |
   OakSpeech: LOG 568         <-- flash-forward, no context
          |
   Pokemon Mansion            <-- the disasters, the Conservation Project,
          |                       Pokemon placed into the PC system
   "Much earlier..."
          |
   Celadon City               <-- the prequel: how the world got here
          |
   [card quest complete]
          |
   FINALE  1. Departure       <-- humanity leaving, believing it is temporary
           2. Liftoff         <-- allowed to look like a success
           3. fade to black
           4. LOG 568         <-- the same screen, the same lines, in order
           5. ...continued    <-- past the point the intro stopped
           6. the same two closing lines, now devastating
           7. hold on black
           8. the preservation system, still running
           9. DITTO, dormant
```

The recognition beat is the reason the first four pages of the finale's log are
byte-identical to the opening's. The reframing beat is the reason the last two
are.

## Mapping the brief to the implementation

| # | Requirement | Where it lives |
|---|---|---|
| 1 | Complete the emotional departure scene first | `finale.lua` → `DEPARTURE`, scene `DEPARTURE` |
| 2 | Show liftoff; let the apparent success sit | modes `LIFTOFF_RISE` → `LIFTOFF_TEXT` → `LIFTOFF_HOLD` (150 frames of nothing) |
| 3 | Fade completely to black | mode `TO_BLACK`, 70-frame fade then a 60-frame hold |
| 4 | Recreate the opening's visual language exactly | mode `LOG568`: `love.graphics.clear(0,0,0,1)`, `drawScientist` (the `OPP_SCIENTIST` cutout at 2x, bottom-anchored, right-aligned to the text frame, exactly as `drawTrainerSpeaker` places it), no nameplate — because the opening has none |
| 5 | Display "LOG 568:" and enough of the original dialogue to be recognised | `Finale.OPENING_LINES`, quoted verbatim as pages 1-4, page 1 carrying the opening's `reveal="fade"` |
| 6 | Continue the log; no over-explaining | `LOG568_CONTINUATION`, nine pages |
| 7 | Reuse the opening's final two lines | `Finale.OPENING_CLOSING_LINES`, quoted verbatim as the last two pages |
| 8 | Hold on black for several seconds | mode `LOG_HOLD`, 300 frames, deliberately not skippable |
| 9 | Transition to the preservation system; stored data persists; Ditto is among it | modes `SYSTEM` / `SYSTEM_CONTINGENCY`, `SYSTEM_RECORDS` |
| 10 | Indicate the system is still active and the release contingency still exists; do not show humans returning | `SYSTEM_STATUS`, `SYSTEM_CONTINGENCY`, `SYSTEM_NARRATION` |
| 11 | End on Ditto dormant inside the system | modes `DORMANT` → `DORMANT_HOLD` → `OUTRO` → `END` |

## Preserved ambiguity

The brief forbids inventing answers the source material leaves open. Three
specific things are therefore *not* in the ending, and `tests/finale.lua`
enforces all three with a banned-vocabulary sweep:

1. **No cause for the disasters.** The log never names one. The word list the
   test rejects includes `meteor`, `virus`, `nuclear`, `war`, `climate`,
   `caused by`, and others.
2. **No mechanism for humanity's failure to return.** The Scientist states the
   outcome ("There will be no return survey", "No one is going back for them")
   and never the reason.
3. **No humans returning successfully.** The test rejects `we returned`,
   `rescue arrived`, and similar.

What the ending *does* commit to is only what the game already established. The
release contingency, the habitat check, and the promise of a return survey all
come from Giovanni's Conservation Project briefing in `main.lua`
(`giovanniMeetingTalk`):

> "When Earth can support POKéMON again, the system will release them into
> suitable habitats."

The finale shows that contingency still armed and still waiting. Nothing
resolves it.

## The tragedy is in the departure, not the log

The brief's last paragraph is the load-bearing one: everyone leaves believing
this is temporary. The departure scene is written so that every human line is
sincere and every human line is wrong.

- Logan: *"We're coming back. That's the whole point of all this."*
- The Scientist: *"The first return survey is already scheduled."*
- The Scientist: *"Storage is stable. Contingency armed."*

Then the log revokes each one in turn. `tests/finale.lua` asserts that both
halves are present — the promise in the departure and its revocation in the
log — so a future edit cannot quietly remove one side of the pair.

## Presentation notes

- **No new image assets.** The launch is drawn from LÖVE primitives in a
  four-shade-friendly palette (black sky, white stars, white vehicle, outlined
  silhouettes). The closing card reuses the existing
  `assets/pokopia_logo_dmg.png` and degrades to text if it cannot be loaded.
- **Text frame.** The finale draws its own Gen I frame at tile `(0,11,20,7)`,
  which gives three interior rows at y=96/112/128 — the opening's longest page
  is three rows, so the box has to be one tile taller than the standard
  dialogue box.
- **Line width.** Newly authored copy is hand-broken to 18 characters, matching
  the project's existing convention. The quoted opening rows run to 20 and are
  passed through untouched; `Finale.layout` honours authored `\n` breaks and
  only wraps as a backstop, measuring with the engine's real `Font.width` at
  runtime.
- **The speaker plate is deliberately inconsistent.** The departure uses the
  normal nameplate so it reads like ordinary game dialogue. The log has none,
  because the opening has none. The change in presentation is the cue.
- **Audio.** The Pokopia theme plays under the liftoff and is stopped the
  instant the Scientist appears, so LOG 568 plays in silence exactly like the
  intro does.

## Triggers

| Path | Condition |
|---|---|
| End of the Celadon chapter | `startCardHeroEnding` → `finishCardHero()` marks the prequel complete and auto-plays the ending once |
| Mansion PC placement | `loganTalk` plays the finale instead of `Much earlier...` when the prequel has already been completed, then hands off to `Much earlier...` so the demo loop still works |
| Reconciliation | `input.step` fires the ending when the player is in ordinary overworld control, outside the Mansion timeline, and the save is armed but unplayed. This covers a schema-4 save that had already finished the card quest, and a session quit part-way through the ending |
| Developer | Hypno's Card Club → SCENE JUMPS → `SCENE 3` (whole ending) or `FINALE LOG` (straight to the bookend). Developer runs pass `dev=true` and do not consume the real ending. |

`Finale.shouldAutoPlay` gates on `prequelComplete and not completed`, so the
ending fires exactly once per save regardless of which path reaches it first.

## Save data

Everything lives under `save.modData.pokopia_log568.finale`:

| Field | Meaning |
|---|---|
| `version` | finale schema version |
| `prequelComplete` | the Celadon chapter has been finished; arms the ending |
| `logSeen` | the LOG 568 scene has been reached |
| `completed` | the ending has played to the end; prevents a second automatic play |
| `playCount` | diagnostics |
| `lastScene` | diagnostics; the last scene entered |
| `running` | transient; cleared on load so a save written mid-cutscene never resumes "running" |

The mod's save schema went from 4 to 5. The migration is purely additive:
`prequelComplete` is reconstructed from the pre-existing `cardQuestComplete`
flag, so a save made before this change reaches the ending without a replay.

## Testing

```
lua5.1 tests/finale.lua      # from the mod root; no engine required
```

292 checks covering bookend fidelity, the opening's continued presence in
`main.lua`, preserved ambiguity, text-frame fit, the pure helpers, a headless
run of the entire state machine through every mode, on-screen geometry for
every string the run draws, and trigger gating.

## What is deliberately still open

- Why the evacuation failed.
- Where humanity is.
- Whether the habitat check ever passes.
- Whether anything ever releases the Pokémon.

The last image is a record that is still intact. That is the whole claim.
