## v0.1.83 — voxel startup regression fixed

v0.1.82 accidentally referenced a second weather module (`WeatherFX`) in addition to the packaged `Weather.lua`; that bad require could abort the Gold voxel renderer and force the normal 2D fallback. v0.1.83 removes the duplicate module path and makes all weather hooks fail-safe. **3D VOXEL WORLD remains authoritative even if weather fails.** Rain, fog, moving clouds, sun/moon, camera modes, camera-relative controls, Johto tree geometry, all-Pokemon 3D, Skin Selector compatibility, and visible pause menus are retained.

## v0.1.83 — weather, clouds, and fuller sky background

This build keeps the non-experimental packaging and adds outdoor atmospheric rendering to the Gold voxel world. New **WEATHER FX** options let you use **AUTO**, **CLEAR**, **RAIN**, **FOG**, or **RAIN + FOG**, and **SKY CLOUDS** adds drifting cloud layers behind the scene. The existing day/night sky renderer continues to supply the **sun by day** and **moon by night**. Indoors remain unchanged.

## v0.1.83 — normal release

This build is no longer flagged experimental in `manifest.json`, so it installs as a normal Gen1Recomp mod while retaining all v0.1.80 behavior.

## v0.1.83 — camera-relative Gold controls

THIRD PERSON and FIRST PERSON now steer relative to the 3D camera rather than Gold's original screen/map axes. UP/W is forward in the current view, DOWN/S is backward, and LEFT/RIGHT strafe. Gold still receives one of its native four cardinal movement directions, so doors, collisions, ledges, encounters, scripted movement, and map connections continue to use the normal Gen-2 gameplay path. In FIRST PERSON, pressing A also uses the nearest cardinal to the view direction for talking/reading/interacting. DIORAMA keeps the original controls.

# Pokemon Stadium 2 Overworld Models - Gold/Silver (Gen 2) v0.1.83

## v0.1.79 first-person + third-person Gold cameras

v0.1.79 activates the embedded free-roam camera rigs for the standalone Gold/Game2 voxel renderer. **3D CAMERA MODE** now offers **DIORAMA**, **THIRD PERSON**, and **FIRST PERSON**. The default remains DIORAMA, so upgrading keeps the proven v0.1.78 view until a different camera is selected.

- **Third Person** places the camera behind/above the player and uses the existing collision-aware boom so walls, trees, and buildings pull the camera inward rather than letting it sit inside geometry. The selected Skin Selector character remains visible.
- **First Person** places the eye at the player and hides the player's own model from the lens.
- Mouse motion, right stick, and open-screen touch drag steer the free camera. **F6** cycles `DIORAMA -> THIRD PERSON -> FIRST PERSON -> DIORAMA` while freely roaming.
- Opening START, a textbox, or another Gold overlay releases relative mouse capture and leaves the working v0.1.74 menu-over-3D compositor in charge.
- Gold's normal grid movement/gameplay rules are intentionally unchanged; this release adds camera modes, not a replacement movement system.

All v0.1.78 tree-profile fixes, v0.1.77 all-Pokemon 3D fallback behavior, and v0.1.75 Skin Selector compatibility are retained.


## v0.1.78 Gold tileset-ID bridge / actual tree-profile fix

Current Gold uses runtime tileset keys such as `TILESET_JOHTO`, while the embedded Dramatic Shapes profile uses `TilesetJohto`. Previous tree fixes were correct inside the profile/mesher but current Gold could miss that profile entirely and therefore keep drawing the same generic textured blocks. v0.1.78 fixes the bridge: before voxel terrain is analyzed, `TILESET_*` runtime names are normalized to the profile's `Tileset*` spelling.

This means the already-authored Johto tree rules (`cylinder`, two-cell `planter`, and the stepped tree archetype) now actually own those cells. The engine-facing `map.def.tileset` value is not changed. v0.1.77's all-Pokemon 3D model fix, v0.1.75 Skin Selector compatibility, and v0.1.74 pause/menu compositing remain intact.


## v0.1.76 Gold tree voxel-shape fix

Gold outdoor tree borders no longer fall through to the generic solid-volume path that produced tall rectangular blocks covered in repeated tree texture. The renderer now recognizes Gold outdoor maps from their Gen-2 environment, confirms that the repeated border block actually contains tree-profile graphics, and keeps that scenery on the existing round voxel-tree hull path.

There is also a conservative in-map fallback for changed/extracted Gold blocksets: if an otherwise-unresolved solid 16x16 cell is made mostly from tiles the active profile explicitly identifies as `cylinder`, `planter`, or `canopy`, it is promoted to a round tree hull instead of a box. Explicit/authored geometry always wins, so this does not globally round walls, houses, cliffs, fences, or signs.

This release keeps the v0.1.75 3D Character Selector bridge and the v0.1.74 visible pause/menu-over-voxel fix unchanged.

## v0.1.71 visible-only encounter fix

Normal Gold grass/cave step encounters are now **OFF by default** while Show Wild Mons is enabled. This fixes the remaining battles that could start without a Pokemon visible on the map. Upgrading from v0.1.70 automatically flips the old saved Random Enc default OFF once and also clears Hidden Mons.

The fix also guards Gold's roaming-beast path, which runs before the public `encounter.roll` hook in current Gold. With **Classic Step Enc = OFF**, ordinary automatic step battles are blocked before that path and battles come from touching/chased-by visible roaming Pokemon. Sweet Scent, fishing, Headbutt, Rock Smash, scripted encounters, and the Bug Catching Contest remain separate. `Water Mons = Classic Enc` is still an explicit opt-in to classic water encounters.


Standalone Gold/Generation-2 build for current Gen1Recomp. It combines a Gold voxel-world renderer, visible roaming wild Pokemon, and a user-supplied Pokemon Stadium 2 ROM importer for National Dex 1-251.

## v0.1.70 compose + visible-Wilds fix

The Stadium 2 importer was already reaching all 251 Pokemon, but v0.1.69 could still leave the Gold overworld completely unchanged. Two Gold-specific runtime assumptions were wrong:

1. Current Gold stores its generated encounter database in `game.data.gen2Encounters` / `world.encounters`, grouped as `grass[mapId]` and `water[mapId]`, with `MORN`, `DAY`, and `NITE` grass slots. The embedded Wilds adapter now reads that structure directly.
2. Gold's native people draw pass Y-sorts the player, `world.npcs`, and ghosts. Wilds roaming Pokemon are independent entities, so merely appending them to `world.entities` does not make them visible. v0.1.70 renders them through the current Gold `render.compose` frame hook instead.

The 2D visible-Wilds pass is deliberately independent of voxel rendering. If voxel rendering is unavailable, still building chunks, or errors on a map, v0.1.70 draws the already-finished Gold scene and overlays the roaming Pokemon sprites on it. A failed voxel frame should therefore no longer make Wilds look disabled.

The compose pass also self-heals Wilds map initialization once per second when needed. This covers event-order differences where Gold entered a map before the embedded Wilds listener was fully ready.

## v0.1.75 3D Character Selector compatibility

This build is compatible with **red_3d_player v3.1.10** in Gold's standalone voxel mode. The selector already patches Gold's normal `src.world.gen2.Player:draw()`, but the standalone voxel scene bypasses that 2D draw method entirely. v0.1.75 now detects the selector's live `Player.red3dPlayerRenderer` and calls its own `drawVoxel()` / `drawVoxelShadow()` methods for the human player pose.

The bridge resolves the selector renderer every frame, so changing characters in **Skin Selector** updates the Gold voxel-world player immediately without hardcoding the selector's character list. Built-in skins, imported skins, per-character scale, and selector-owned accessories remain owned by `red_3d_player`. Pokémon-control player modes still use Stadium models, while Gold fishing, surfing, and bicycle states continue to use their special native cards.

Install both mods normally. `red_3d_player` is an optional dependency, so this Stadium build still works by itself; when the selector is absent or its 3D renderer is unavailable, the player cleanly falls back to the normal voxel sprite card.

## Stadium 2 ROM importer

Use **Mods -> Pokemon Stadium 2 Overworld Models -> Options -> STADIUM 2 ROM FILE (GEN 2)** and choose your legally obtained Stadium 2 ROM (`.z64`, `.n64`, or `.v64`).

The ROM is not included in this mod. Extracted Nintendo model data is not shipped in this ZIP. Model packs are built locally from the ROM selected by the user.

The Stadium 2 path supports National Dex 1-251 and reads Stadium 2's separate model and skeletal-animation archives. Animation-context routing is still provisional; model import is the current priority.

## Visible roaming Pokemon

**Show Wild Mons** defaults ON. On a supported Gold encounter map, the embedded Wilds runtime:

- reads the active Gold encounter table for the current time of day,
- finds valid grass/cave/water cells from Gold's Gen-2 map predicates,
- creates visible roaming Pokemon,
- draws them as 2D fallback sprites even if voxel is not working,
- feeds the same entities into the voxel/Stadium scene so imported Stadium 2 models can replace them in 3D.

Hidden wild behavior defaults OFF in this Gen-2 build.

## Voxel world

**3D VOXEL WORLD** defaults ON. v0.1.70 no longer patches `World:drawWorldBody()` and does not depend on the old Gen-1 `drawWorld` pipeline. The embedded voxel renderer is invoked from Gold's current whole-window `render.compose` hook.

The current-map voxel scene is the first target. Connected-neighbor voxel stitching remains conservative while the Gold renderer is being proven in real gameplay.

## Install / test order

1. Remove or disable older `STADIUM2_OVERWORLD_MODELS` builds.
2. Install this ZIP and confirm the card says **v0.1.82 / GEN 2**.
3. Leave **3D VOXEL WORLD = ON** and **Show Wild Mons = ON**.
4. Start Gold and walk onto an outdoor route with grass.
5. First verify that roaming Pokemon sprites appear even if the world is still flat.
6. Then select/import the Stadium 2 ROM and test the voxel/Stadium model path.

If both voxel and roaming sprites are still absent, capture the mod error/status shown by Gen1Recomp. v0.1.70 exposes compose, voxel, and Wilds bridge status through `mod.exports` so the next failure can be isolated instead of guessed.

## Included third-party components

This standalone package incorporates compatible runtime pieces from the user-supplied Wilds of Kanto 1.12.2 and DRAMALESS_SHAPE 1.6.4 packages. Their license/permission files are retained as `WILDS_LICENSE.txt` and `DRAMALESS_LICENSE.txt`.

No Pokemon ROM is included.
## v0.1.74 pause/menu visibility fix

Opening the START/pause menu now keeps the Gold overworld in voxel mode **and** keeps the menu visible and interactive. Gold's current `render.compose` payload contains one already-composited scene (its world/UI canvas references point to the same texture), so v0.1.74 does not use the Gen-1 `worldOverride` strategy. Instead it paints the voxel frame, then redraws only Gold's active state stack at the same `world:fitScale()` / centered 160x144 transform used by `Game2:drawScene()`. Opaque/full-screen pages remain owned by Gold because `worldActive` is false for those frames.

## v0.1.72 voxel-focus fix

This release intentionally leaves the v0.1.71 Wilds/encounter behavior unchanged and focuses on the Gold voxel world. Two remaining Gen-1 map assumptions in the embedded mesh analyzer were causing Gold terrain builds to fail inside the asynchronous mesher. The current Gold map is now synchronously primed once, and a failed mesh is reported instead of silently falling back to flat 2D forever.



## v0.1.82 Weather
Use **3D WEATHER** to select Auto, Clear, Rain, Fog, or Rain + Fog. **MOVING CLOUDS** controls the background cloud layer. The day/night sky continues to show the sun and moon. Weather only appears outdoors.
