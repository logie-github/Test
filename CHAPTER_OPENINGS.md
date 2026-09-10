# Chapter Openings — Design and Implementation

The game's two playable chapters now open the way its ending closes. This
document records what was wrong, what each opening is doing, and where to
change it.

## What was there before

**The Mansion had no opening at all.** OakSpeech finished on the black LOG 568
screen and the very next frame the player was standing on Pokémon Mansion 3F
with a low-health alarm running. No location, no establishing beat, no reason
given for a DITTO being loose in a secure research building full of evacuating
humans — and no acknowledgement that the player had just been shown something
they could not place.

**Celadon opened on a `printf`.** The `Much earlier...` intertitle was:

```lua
love.graphics.printf("Much earlier...",0,66,160,"center")
```

That renders in LOVE's default font rather than the game's, sits on black with
nothing composed around it, and holds for 120 frames. It then cut directly into
the middle of a Super Nerd buying a prize — a scene with no setup, no location,
and no connection to the apocalypse the player had just walked out of.

**The city establishing sweep already existed and was unreachable.** `views`,
`frameCityView`, `panCityView`, the `cameraPan` tween and the whole
`cityPanStage` machine were all live code in the Celadon cutscene controller.
`cut:enter()` called `beginGameCornerStory()` directly and skipped past them,
with a comment recording the skip but not the reason.

## The composition

Both openings do the job the LOG 568 flash-forward does: plant something the
player cannot yet place, and pay it off later.

```
   OakSpeech: LOG 568          <-- a log with no context
          |
   CINNABAR ISLAND             <-- where
   POKeMON MANSION
          |
   "No one has time to         <-- the question
    ask what a DITTO
    is doing here."
          |
       [ chapter ]
          |
   "Much earlier..."           <-- when
   CELADON CITY                <-- where
          |
   "Somewhere in that          <-- the answer, one chapter late
    crowd is a DITTO."
          |
       [ chapter ]
          |
   LOG 568, continued          <-- the answer to the first one, one game late
```

The Mansion asks a question in its third beat. Celadon answers it in its third
beat. That is the same structural move the bookend makes across the whole game,
at chapter scale, and `tests/chapters.lua` asserts both halves so a copy edit
cannot quietly remove one.

## The Mansion cold open

One non-opaque state over the live Mansion floor, in three phases.

| Phase | Frames | What happens |
|---|---|---|
| `CARD` | 176 | Full black over the map; the location card assembles on it |
| `REVEAL` | 64 | The black lifts and the Mansion appears underneath |
| `NARRATE` | player-paced | Four narration beats over the live floor |

Not being opaque is the point: the overworld draws underneath, so the card
**dissolves into the room the player is standing in** instead of cutting to it.

The four beats:

> The alarm has been going a while now.
>
> No one in this building has looked down once.
>
> No one has time to ask what a DITTO is doing here.
>
> The stairs are still open.

Beat 3 is load-bearing. It names DITTO to the *player* while keeping the
project's existing rule that no character in the Mansion ever identifies them —
it is narration, not attributed speech, and the test suite checks that no beat
in the opening contains a `:` for exactly that reason. Beat 4 is the only
direction the chapter gives, in the Gen I register: a fact, not an objective
marker.

**Trigger.** `input.step`, the first time the player is in ordinary overworld
control on a Mansion floor — which is the frame after OakSpeech hands the world
over. Gating on live control rather than a map-entry hook means it can never
land on top of a scripted scene, a menu, or a warp.

**Saves made before this existed** must never be handed a cold open.
`Chapters.reconcile` derives "already seen" from real story progress
(`Chapters.PROGRESS_MARKERS`, plus any learned transformation) the first time a
save is seen, behind a one-shot `migrated` latch so it can never undo a
deliberate replay from a developer scene jump.

## The Celadon chapter opening

Three parts, in order.

**1. The chapter card.** `Much earlier...` is preserved verbatim — it is the
story's own chronology marker and predates this work — and is now the second
line of a composed card that matches the Mansion's exactly:

```
      CELADON CITY
     Much earlier...
```

Where, then when. Both cards use one timing curve so the chapters open at
identical pace:

| Frames | |
|---|---|
| 0–26 | rules grow out from the centre, text still absent |
| 26–56 | text fades up between them |
| 56–146 | hold |
| 146–176 | rules and text leave together |

**2. The establishing sweep.** `cut:enter()` now arms the first shot instead of
skipping to the Game Corner. The camera machinery is unchanged — this is the
code that was already there, finally reached.

**3. A narration beat on each shot**, pushed as ordinary `TextBox`es through
the cutscene's own `box()` helper so the montage inherits the mod's real
dialogue presentation rather than a second one:

> CELADON CITY is loud in the afternoon.
>
> The GAME CORNER is busy. It is always busy.
>
> Somewhere in that crowd is a DITTO.

The tone is deliberately the opposite of the Mansion's. The Mansion is an alarm
and people who will not look down; this is an ordinary loud afternoon in a city
that has not heard any of it yet. `tests/chapters.lua` asserts the Mansion
opening mentions the alarm and the Celadon opening does not.

Each `say_*` stage sets the stage to `"waiting"` before pushing its box. While
that box is the top state the cutscene's `update` does not run at all, so the
box's own callback advances the montage — the same wait-on-callback pattern the
rest of that cutscene already uses for its `storyStep=-1` sentinel.

## cinema.lua

All three authored compositions — the two chapter openings and the LOG 568
bookend — now draw through one module.

| | |
|---|---|
| Frame geometry | The cinematic box at tile `(0,11,20,7)`, whose three interior rows at y=96/112/128 are what the opening's longest page needs |
| `layout` / `pages` / `authoredRows` | Pure text helpers, no LOVE dependency, unit-tested directly |
| `drawTextFrame` | Gen I frame, typewriter reveal, blinking cursor, optional nameplate, plus a machine-voice variant for the storage display |
| `drawSpeakerArt` | Trainer-class cutout, positioned exactly where the mod's dialogue renderer puts it |
| `drawCard` | Composed chapter card with independently-alpha'd rules so a card can assemble rather than appear |
| `newPageRunner` | Reveal, complete-on-press, advance-on-next-press |
| `lockOverworld` | Input lock that restores the previous value rather than assuming it was unlocked |
| Audio | `silenceMusic` / `playMusic` / `restoreMusic`, every entry point `pcall`-guarded |

### The line-breaking rule, and why it is what it is

Authored line breaks always win. The wrap is a backstop, and it is only
accepted when it actually helps — that is, when the wrapped result still fits
the three interior rows. If wrapping would need a fourth row, the authored
breaks are used instead, because clamping a wrapped result to three rows
silently deletes the end of the page.

This is not hypothetical. The opening page

```
Life on this planet
as we know it will
come to an end.
```

is three authored rows and its first row is 19 characters. Under any measure
that calls 19 characters too wide, wrapping produces four rows and the bookend
loses *"come to an end."* — the single most important line in the ending. The
test harness measures a worst-case fixed 8px glyph and caught exactly that.

On top of that, a page marked `quoted="opening"` is never re-broken at any
width. Re-wrapping *"Our last-ditch / Hail Mary project..."* into three rows
would still say the right words while no longer looking like the scene it is
quoting, and looking like it is the entire point.

## Testing

```
lua5.1 tests/run.lua        # from the mod root; no engine required
```

| Suite | Checks | Covers |
|---|---|---|
| `tests/cinema.lua` | 98 | Frame geometry, layout and wrapping rules, page splitting, typewriter, nameplates, card composition, page runner, input-lock contract |
| `tests/chapters.lua` | 127 | Card content, beat fit, the question/answer composition, tone separation, save gating and migration, headless runs of both openings, main.lua wiring |
| `tests/finale.lua` | 293 | Bookend fidelity, the opening's continued presence in main.lua, preserved ambiguity, headless run of the whole ending, geometry |

`tests/chapters.lua` also asserts the negative cases that matter: the raw
`printf` is gone, and the comment that used to record skipping the city sweep
is gone.

## What is deliberately unchanged

- Mansion gameplay: the population, the personality dialogue, the
  Rattata/Persian distraction, the Giovanni briefing, the Pixie rescue and the
  PC placement are untouched.
- Celadon gameplay: the Game Corner refund sequence, café jobs, TCG, Rocket
  Operations and the card-scalper quest are untouched.
- The opening OakSpeech scene. Still never modified; still asserted.
