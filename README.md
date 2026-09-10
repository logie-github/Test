# Pokopia: Log 568 v1.0.370

Built directly from the user-selected v0.4.6 baseline.

## LOG 568 is a bookend

The opening OakSpeech scene is a flash-forward. The game spends its running
time explaining how the world reached it, and the ending catches back up to it:
the departure, the liftoff, then the same black screen, the same Scientist, and
the same lines the player saw before they meant anything -- continued past the
point where the intro stopped.

The opening itself is not modified. See `LOG568_BOOKEND.md` for the full
composition, the constraints it holds to, and where to change it, and
`LEDGER.md` for the current canonical project state.

## Chapter openings

Both playable chapters now open the way the game ends. The Mansion dissolves
from a `CINNABAR ISLAND / POKeMON MANSION` card into the live floor and asks
what a DITTO is doing in a building nobody will look down in; Celadon answers
it one chapter later, over the three-shot city sweep that had been sitting
unreachable in the cutscene controller. `Much earlier...` is a composed Gen I
card now rather than a raw `printf`.

See `CHAPTER_OPENINGS.md` for the composition and `cinema.lua` for the shared
presentation layer behind all three authored cutscenes.

Run every regression suite from the mod root, with no engine required:

```
lua5.1 tests/run.lua
```


Added after that baseline:

- Wooper is now introduced through a one-time Route 16 -> Celadon scripted encounter, with persistent relationship/street-cred state and a dedicated character personality reference.
- Mid-disaster Log 568 wording: the experiment and last-ditch Hail Mary project are a complete and total failure.
- No added lines about containment or an effect spreading.
- All four Pokémon Mansion floors are populated.
- Exactly one each: Magnemite, Magneton, Voltorb, Electrode, Koffing, Weezing, Grimer, Muk, Porygon, Vulpix, Rattata, Charmander, Bulbasaur, Totodile, Poliwhirl, Slowpoke, Dodrio, Spinarak, Ampharos, Larvitar, plus guest baby Pokémon Pichu and Togepi beside Weezing.
- Every species has unique personality dialogue.
- Scientist dialogue never identifies the player as Ditto and contains no containment references.
- All Mansion switch/puzzle barriers are forced open on every entry; vanilla Mansion map scripts are overridden so they cannot re-close them.
- Demo ending: scientist puts the player into a PC Box, then `Much earlier...`, then `The demo has ended.`
- Trainer Card requests Ditto's front battle sprite through the player-sprite context.
- Title player-art context requests Ditto's front battle sprite.
- Existing v0.4.6 intro implementation is retained rather than rewritten.

- Fixed the compose-registry crash by embedding the 3F finale directly in the Mansion 3F map-script override.

- Pokemon follower sheets now preserve source colors.
- Two scientists visibly block the Mansion exit while arguing.
- A dedicated basement scientist now triggers the PC Box ending.

- Custom Mansion NPCs are validated against the actual map collision grid on every floor entry; nobody should spawn on tables/furniture/non-walkable cells.
- Native wandering still uses Gen1Recomp collision checks.
- The title screen uses the Scientist battle portrait where Red normally appears.
- Title Pokémon start with Ditto and rotate only through the Mansion population.

- Fixed the B1F PC-ending script compiler error caused by unsupported commands.

- Exit blockers are now immediately above the actual Mansion front-door warp cells.
- Emergency actors use species/personality-specific movement speeds while still obeying normal map collision.
- Several scientists visibly run through the Mansion.

- The two exit scientists now face only each other and never turn toward the player.

- TitleState now directly forces Ditto first, followed only by the Mansion Pokémon list.

- Rotating title Pokémon are now rendered at half size; the Scientist title portrait is unchanged.

- Voltorb now continuously attempts legal rolling movement instead of becoming stuck when its original horizontal patrol has no valid neighbor.

- Several scientists now pace back and forth on deterministic corridor patrols instead of wandering randomly.

- Voltorb now continuously patrols vertically, reversing at obstacles.

- The low-HP alarm is held at 50% volume for the Mansion scene only; other audio is unchanged.

- The two arguing scientists now stand apart at the front entrance.
- Walking between them triggers a warning and pushes Ditto back upward.
- The front-door warp cells are explicitly removed by coordinate, so the player cannot slip onto the exterior warp strip.

- Full Logan/PIXIE rescue quest and PC-box ending added, followed by `Much earlier...` and a three-view Celadon City epilogue.

- Fixed the malformed Logan Lua string and added a syntax-oriented string scan before packaging.

- Fixed Logan/Vulpix text control characters, shortened dialogue pages, delayed PIXIE/LOGIE naming until after Logan's request, moved Squirtle, and lowered the Mansion alarm to 15%.

- PIXIE now follows Ditto's vacated-cell trail, keeping her behind the player instead of overlapping him.

- Mansion warps are no longer modified; original staircase indices are preserved.
- Totodile is at the verified vanilla B1F object coordinate (19,25), replacing Squirtle.
- Pre-quest Vulpix dialogue is anonymous and no longer repeats its species name.
- The alarm now uses a directly owned low-health Source at 10% of normal alarm volume.

- PIXIE now follows asynchronously along Ditto's vacated-cell trail; player movement is never tied to her movement.
- Warp transitions recreate/reseed PIXIE instead of carrying old scripted movement across maps.
- Mansion alarm is back to exactly 50% of the engine's normal alarm source level.

- PIXIE now mirrors the built-in Yellow follower: she starts moving into Ditto's vacated tile the moment Ditto commits a step and stays directly one tile behind.

- The front-door blockade now uses a verified `onStep` interception one row before the actual warp tiles, then pushes Ditto back upward.

## Bundled follower sprite source

Pokopia's Pokémon overworld walkers use the non-shiny `follower_###_normal.png` sheets from `randyadr/Gen2-3D-Sprites`, under `assets/enhanced_overworld/poke_followers/`. The source repository's license and upstream notices are included verbatim in `THIRD_PARTY_LICENSES/Gen2-3D-Sprites_DRAMALESS_LICENSE.txt`; see `CREDITS.md` for the source path and attribution.


## Third-party sprite credit

Pokémon overworld sprites use the NORMAL/non-shiny followsprites from **Pokemon Stadium 2 Overworld Models - Gold/Silver (Gen 2)** by **randyadr** (`randyadr/3D-Pokemon-Sprites-Gen2`). Exact source files and original notices are bundled under `THIRD_PARTY/STADIUM2_OVERWORLD_MODELS/`.


### Enhanced Overworld assets
All Pokopia Pokémon overworld actors use the bundled normal six-frame runtime sheets copied directly from the supplied Pokemon Stadium 2 Overworld Models / Enhanced Overworld package. See `CREDITS.md` and `THIRD_PARTY_LICENSES/` for attribution and license notices.
