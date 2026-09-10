-- Pokemon Trading Card Game (GBC) - Booster Pack scene sprite placement (VERIFIED, not inferred)
-- Source: src/data/scenes.asm (Scene_ColosseumBooster/EvolutionBooster/MysteryBooster/
--         LaboratoryBooster), src/data/duel/animations/anims3.asm (AnimData189 + AnimFrameTable87)
--
-- === WHY THIS FILE EXISTS ===
-- Earlier work on the DUEL screen's card-art placement had to be marked "inferred" because the
-- FillRectangle call's exact x/y-vs-size register convention couldn't be disambiguated from the
-- disassembly alone. This is a DIFFERENT rendering path -- the booster-pack-opening screen uses
-- real Game Boy hardware sprites (OAM) with an explicit per-tile frame table, not a background-tile
-- FillRectangle call -- and that frame table gives EXACT, unambiguous pixel coordinates. Nothing
-- here is a guess.
--
-- === WHAT THE SOURCE DATA ACTUALLY SAYS ===
-- Every booster pack scene (Colosseum/Evolution/Mystery/Laboratory) points at the same sprite
-- animation, internally named SPRITE_ANIM_189 in the source (AnimData189). Its frame_table entry
-- names AnimFrameTable87, a 32-tile layout table. Each entry in that table is 4 bytes:
-- (x_offset, y_offset, tile_index, oam_attribute) -- confirmed directly from the `frame_data` /
-- tile-entry macro definitions in src/macros/data.asm, not assumed.
--
-- 32 tiles at 8x8 pixels each = a 32x64 pixel sprite block (4 tiles wide, 8 tiles tall). The
-- x/y offsets in the table are RELATIVE to the sprite's own anchor point, not absolute screen
-- coordinates -- i.e. this table tells you exactly how the 32 tiles are arranged relative to each
-- other, verified byte-for-byte, but the screen-space anchor point (where that whole 32x64 block
-- sits on the 160x144 screen) is set by a separate OAM-placement routine this file does not cover
-- (see the honest note at the bottom).
--
-- AnimData189 itself also confirms the sprite does NOT translate/move during the reveal animation
-- -- all three of its frame_data entries have x_translation=0, y_translation=0. The only thing
-- that changes frame-to-frame is an animation-count/duration value, consistent with a static
-- shimmer/sparkle effect on the pack art rather than any repositioning.

local BoosterSceneSprite = {}

-- The exact 32-tile layout, verified from AnimFrameTable87. Each tile is 8x8 native pixels.
-- Note the tile_index values are NOT in simple raster order -- the source graphic's tiles are
-- stored in a specific interleaved order (this is exactly what this table exists to record).
BoosterSceneSprite.tiles = {
  { x = 0,  y = 0,  tile_index = 0,  attr = 0 },
  { x = 0,  y = 8,  tile_index = 1,  attr = 0 },
  { x = 0,  y = 16, tile_index = 2,  attr = 0 },
  { x = 0,  y = 24, tile_index = 3,  attr = 0 },
  { x = 0,  y = 32, tile_index = 4,  attr = 0 },
  { x = 0,  y = 40, tile_index = 5,  attr = 0 },
  { x = 0,  y = 48, tile_index = 6,  attr = 0 },
  { x = 0,  y = 56, tile_index = 7,  attr = 0 },
  { x = 8,  y = 0,  tile_index = 16, attr = 0 },
  { x = 8,  y = 8,  tile_index = 17, attr = 0 },
  { x = 8,  y = 16, tile_index = 18, attr = 0 },
  { x = 8,  y = 24, tile_index = 19, attr = 0 },
  { x = 8,  y = 32, tile_index = 20, attr = 0 },
  { x = 8,  y = 40, tile_index = 21, attr = 0 },
  { x = 8,  y = 48, tile_index = 22, attr = 0 },
  { x = 8,  y = 56, tile_index = 23, attr = 0 },
  { x = 16, y = 0,  tile_index = 8,  attr = 0 },
  { x = 16, y = 8,  tile_index = 9,  attr = 0 },
  { x = 16, y = 16, tile_index = 10, attr = 0 },
  { x = 16, y = 24, tile_index = 11, attr = 0 },
  { x = 16, y = 32, tile_index = 12, attr = 0 },
  { x = 16, y = 40, tile_index = 13, attr = 0 },
  { x = 16, y = 48, tile_index = 14, attr = 0 },
  { x = 16, y = 56, tile_index = 15, attr = 0 },
  { x = 24, y = 0,  tile_index = 24, attr = 0 },
  { x = 24, y = 8,  tile_index = 25, attr = 0 },
  { x = 24, y = 16, tile_index = 26, attr = 0 },
  { x = 24, y = 24, tile_index = 27, attr = 0 },
  { x = 24, y = 32, tile_index = 28, attr = 0 },
  { x = 24, y = 40, tile_index = 29, attr = 0 },
  { x = 24, y = 48, tile_index = 30, attr = 0 },
  { x = 24, y = 56, tile_index = 31, attr = 0 },
}

BoosterSceneSprite.block_width_px = 32   -- 4 tiles wide
BoosterSceneSprite.block_height_px = 64  -- 8 tiles tall

-- The animation itself: 3 frame_data entries, all with zero translation -- the sprite does not
-- move during the reveal, confirming this is a shimmer/idle effect, not a slide-in or bounce.
BoosterSceneSprite.animation = {
  { x_translation = 0, y_translation = 0 },
  { x_translation = 0, y_translation = 0 },
  { x_translation = 0, y_translation = 0 },
}

-- All 4 booster scenes (Colosseum/Evolution/Mystery/Laboratory) use this exact same sprite
-- animation and tile layout -- confirmed by each Scene_*Booster entry in data/scenes.asm pointing
-- at the same SPRITE_BOOSTER_PACK_OAM / SPRITE_ANIM_189 pair; only the palette and background
-- tilemap differ per set (see rules below).
BoosterSceneSprite.used_by_scenes = {
  "Scene_ColosseumBooster", "Scene_EvolutionBooster", "Scene_MysteryBooster", "Scene_LaboratoryBooster",
}

-- === HONEST NOTE: what is verified vs. what remains open ===
-- VERIFIED: the internal 32-tile layout above, the sprite's total pixel dimensions, and the fact
-- that the animation doesn't translate the sprite -- all read directly from the frame table data,
-- not inferred from context.
-- NOT YET TRACED: the absolute screen-space (x, y) anchor point where this 32x64 tile block is
-- placed within the 160x144 screen. That's set by the OAM-writing routine that consumes this
-- scene's sprite data (in engine/scenes.asm's scene-loading code), which assigns hardware sprite
-- slots directly rather than storing a single anchor coordinate in the data table itself -- fully
-- resolving that would mean tracing the OAM slot assignment logic, not just this data table. This
-- file makes no claim about that anchor point; everything above is limited to what the frame
-- table itself unambiguously specifies.

return BoosterSceneSprite
