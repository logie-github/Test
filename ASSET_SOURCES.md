# Asset Sources

## Pokemon TCG GB duel animations

- `assets/tcg/graphics/duel_anims/*.png` — the 62 original Game Boy duel-animation
  sprite sheets from `pret/poketcg/src/gfx/duel/anims/`.
- `tcg_engine/attack_animations.lua` — generated from the per-card animation bytes in
  `src/data/cards.asm` and the ordered command tables in
  `src/data/duel/animations/attack_animations.asm`.

Source repository: https://github.com/pret/poketcg

## Celadon Cafe berry inventory sprites

The following non-outline 32×32 inventory berry sprites are from the PokéSprite project by Michiel Sikma and contributors:

- `assets/cafe/berries/cheri.png` — `items/berry/cheri.png`
- `assets/cafe/berries/chesto.png` — `items/berry/chesto.png`
- `assets/cafe/berries/pecha.png` — `items/berry/pecha.png`
- `assets/cafe/berries/rawst.png` — `items/berry/rawst.png`
- `assets/cafe/berries/aspear.png` — `items/berry/aspear.png`
- `assets/cafe/berries/leppa.png` — `items/berry/leppa.png`
- `assets/cafe/berries/oran.png` — `items/berry/oran.png`
- `assets/cafe/berries/persim.png` — `items/berry/persim.png`
- `assets/cafe/berries/lum.png` — `items/berry/lum.png`
- `assets/cafe/berries/sitrus.png` — `items/berry/sitrus.png`

Source project: PokéSprite (`msikma/pokesprite`), inventory item sprite collection, non-outline `items/berry/` set.
Project page: https://msikma.github.io/pokesprite/overview/inventory.html
Repository: https://github.com/msikma/pokesprite

PokéSprite's code and project files are MIT-licensed. Pokémon sprite imagery is © Nintendo / Creatures Inc. / GAME FREAK Inc., as stated by the PokéSprite project.

At runtime Pokopia converts each source image to four luminance-indexed Game Boy shades while preserving transparency, then caches the resulting LÖVE image. This retains the original PokéSprite silhouette while allowing the game's active palette processing to recolor the four shades consistently.

## OLD PHOTO background

- `assets/old_photo/celadon_gym_background.jpg` — supplied directly by the user for the OLD PHOTO quest scene; included unchanged as the photo background.
