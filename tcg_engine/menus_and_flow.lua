-- Pokemon Trading Card Game (GBC) - Menus and game flow, deck building through play
-- Source: src/engine/menus/*.asm, src/engine/auto_deck_machines.asm, src/engine/starter_deck.asm,
--         src/constants/duel_interface_constants.asm, src/constants/menu_constants.asm,
--         src/constants/card_data_constants.asm, src/constants/deck_constants.asm
--
-- === HOW THIS FILE CONNECTS TO THE OTHERS ===
-- Menus.deck_building_rules restates constants that also appear in rules.lua/card database
-- generation (deck_size_required=60 matches Rules.deck.deck_size, max_copies_per_named_card=4 is
-- MAX_NUM_SAME_NAME_CARDS) -- kept here too since they're UI-enforced validation rules, not just
-- abstract duel rules. Menus.auto_deck_machines.machines[].decks[].name/.description are the same
-- values as auto_deck_full_lists.lua's AutoDeckLists.decks[label].name/.description (verified
-- exact match, all 45) -- that file has the actual card contents this one omits.
-- Menus.new_game_setup.starter_choice[].main_deck/.extra_cards_deck are deck "label"s (e.g.
-- "CharmanderAndFriendsDeck") -- the SAME key used in ai_and_deck_mechanics.lua's AI.decks[].label.
-- For the in-duel menu system's card-level detail, card_database.lua's card_type field is what
-- determines which of Menus.card_check_pages a given card shows.

local Menus = {}

-- Top-level game flow. The player moves between these major screens/modes.
Menus.game_flow = {
  "Title Screen / Continue",
  "Overworld (talk to NPCs, walk between rooms -- this is also where NPC duels are triggered)",
  "Card Album -- browse the player's entire owned card collection",
  "Booster Pack Room -- open Booster Packs won from duels or otherwise obtained, 10 cards each",
  "Deck Machine Room -- build/edit up to 4 custom Decks, or use an Auto Deck Machine",
  "Duel -- the actual card game, against an NPC/AI opponent or (in the original hardware) a linked player",
}

-- Deck building rules (enforced in src/engine/menus/deck_configuration.asm).
Menus.deck_building_rules = {
  deck_size_required = 60,        -- DECK_SIZE; a deck cannot be saved unless it has exactly 60 cards
  max_copies_per_named_card = 4,  -- MAX_NUM_SAME_NAME_CARDS; applies by card NAME, so e.g. different-art/
                                   -- different-level reprints of the "same" Pokemon still share the cap
                                   -- if they share a display name
  max_copies_basic_energy = "unlimited", -- basic Energy cards (Grass/Fire/Water/Lightning/Fighting/Psychic/
                                          -- Colorless) are explicitly exempt from the 4-copy cap
  max_copies_double_colorless_energy = 4, -- Double Colorless Energy is NOT a basic Energy card, so the
                                           -- normal 4-copy cap applies to it
  max_saved_decks = 4,            -- NUM_DECKS; the player can have up to 4 named custom Decks at once
  can_only_use_owned_cards = true, -- TryAddCardToDeck checks the player's owned-copy count in
                                    -- wOwnedCardsCountList before allowing a card to be added
  save_requires_exact_size = "If the deck does not total exactly 60 cards when the player tries to save " ..
    "and exit, the game shows \"This isn't a 60-card Deck!\" and \"The Deck must include 60 cards.\" and " ..
    "blocks saving until fixed (or the player reverts their changes).",
}

-- Deck Selection menu (src/engine/menus/deck_selection.asm): choose which of your decks to
-- edit, use in a duel, or (via Deck Machine) build fresh from an Auto Deck Machine template.
Menus.deck_selection = {
  description = "Lists the player's saved Decks (max 4). From here the player can pick a Deck to " ..
    "battle with (must be valid, i.e. non-empty/60 cards), enter Deck Configuration to edit an existing " ..
    "Deck, or start a brand-new Deck from scratch.",
  requires_at_least_one_valid_deck_to_duel = true,
}

-- Deck Configuration menu (src/engine/menus/deck_configuration.asm): the actual card-by-card
-- deck editor.
Menus.deck_configuration = {
  description = "Card-list browser split by type filter (Pokemon/Trainer/Energy or similar), showing " ..
    "how many of each card the player owns vs. how many are currently in the deck being edited. " ..
    "Pressing the add/remove input calls TryAddCardToDeck / a corresponding remove routine, live-updating " ..
    "the running total shown on screen (PrintCardTypeCounts / PrintTotalCardCount).",
  add_card_checks_in_order = {
    "1. Is the deck already at wMaxNumCardsAllowed (60) cards? If so, reject.",
    "2. Would this card exceed the 4-copies-of-this-name limit (skipped entirely for basic Energy)? " ..
      "If so, reject.",
    "3. Does the player actually own that many copies of the card in their collection " ..
      "(wOwnedCardsCountList)? If not, reject.",
    "4. Otherwise, add it to the first empty slot in the deck buffer and update all on-screen counts.",
  },
  exit_confirmation = "Leaving without saving prompts a Yes/No confirmation " ..
    "(\"Quit modifying the Deck?\") only if changes were actually made.",
}

-- Card Album (src/engine/menus/card_album.asm): read-only browser of the player's full card
-- collection (not just what's in a deck), typically filterable/sortable, letting the player inspect
-- any owned card's full text via the same card detail page used elsewhere.
Menus.card_album = {
  description = "Browse every card the player owns, regardless of which Deck (if any) it's currently " ..
    "in. Used purely for inspection, not deck editing.",
}

-- Booster Pack opening (src/engine/menus/booster_pack.asm, give_booster_pack.asm; contents/odds
-- are documented in expansions.lua / booster generation tables already covered separately).
Menus.booster_pack_opening = {
  description = "After a Booster Pack is awarded, the game deals its 10 cards (NUM_CARDS_IN_BOOSTER) " ..
    "into a temporary list and opens a card-list viewer over them so the player can examine each new " ..
    "card before they're added to the permanent collection.",
}

-- Auto Deck Machines (src/engine/auto_deck_machines.asm, data/auto_deck_machines.asm):
-- an alternate way to obtain a ready-built 60-card Deck, found in specific overworld locations.
-- There are 9 Auto Deck Machines (one per energy type, plus a "Legendary" machine), each offering
-- 5 pre-built Deck templates (45 total). Building one requires DISMANTLING one or more of the
-- player's existing saved Decks (freeing up the physical cards) rather than paying any in-game
-- currency -- the game tries every combination of 1, 2, 3, then all 4 of the player's decks to
-- find a set that contains enough of the needed cards, and reports failure if none work.
Menus.auto_deck_machines = {
  slots_per_machine = 5,
  num_machines = 9,
  build_method = "Dismantle (break down) one or more of the player's own saved Decks to supply the " ..
    "needed physical cards -- no currency cost. See AutoDeckMachines_TryToDismantleDecks in " ..
    "src/engine/auto_deck_machines.asm for the combination search (tries single decks first, then " ..
    "pairs, then triples, then all four).",
  machines = {

    {
      machine = "Fighting",
      decks = {
        { name = "All Fighting Pokémon", description = "A Deck of Fighting Pokémon: Feel their Fighting power!" },
        { name = "Bench Attack", description = "A Deck of Pokémon that can attack the Bench." },
        { name = "Battle Contest", description = "A Deck which uses Fighting Attacks such as Slash and Punch." },
        { name = "Heated Battle", description = "A powerful Deck with both Fire and Fighting Pokémon." },
        { name = "First-Strike", description = "A Deck for fast and furious  attacks." },
      },
    },
    {
      machine = "Rock",
      decks = {
        { name = "Squeaking Mouse", description = "A Deck made of Mouse Pokémon. Uses PlusPower to Power up!" },
        { name = "Great Quake", description = "Use Dugtrio's Earthquake to cause great damage." },
        { name = "Bone Attack", description = "A Deck of Cubone and Marowak -  A call for help." },
        { name = "Excavation", description = "A Deck which creates Pokémon by evolving Mysterious Fossils." },
        { name = "Rock Crusher", description = "A Deck of Rock Pokémon. It's Strong against Lightning Pokémon." },
      },
    },
    {
      machine = "Water",
      decks = {
        { name = "Blue Water", description = "A Deck of Water Pokémon: Their Blue Horror washes over enemies." },
        { name = "On the Beach", description = "A well balanced Deck of Sandshrew and Water Pokémon!" },
        { name = "Paralyze!", description = "Paralyze the opponent's Pokémon: Stop 'em and drop 'em!" },
        { name = "Energy Removal", description = "Uses Whirlpool and Hyper Beam to remove opponents' Energy cards." },
        { name = "Rain Dancer", description = "Use Rain Dance to attach Water Energy for powerful Attacks!" },
      },
    },
    {
      machine = "Lightning",
      decks = {
        { name = "Cute Pokémon", description = "A Deck of cute Pokémon such as Pikachu and Eevee." },
        { name = "Pokémon Flute", description = "Use the Pokémon Flute to revive opponents' Pokémon and Attack!" },
        { name = "Yellow Flash", description = "A deck of Pokémon that use Lightning Energy to zap opponents." },
        { name = "Electric Shock", description = "A Deck which Shocks and Paralyzes opponents with its Attacks." },
        { name = "Zapping Selfdestruct", description = "Selfdestruct causes great damage  - even to the opponent's Bench." },
      },
    },
    {
      machine = "Grass",
      decks = {
        { name = "Insect Collection", description = "A Deck made of Insect Pokémon Go Bug Power!" },
        { name = "Jungle", description = "A Deck of Grass Pokémon: There  are many dangers in the Jungle." },
        { name = "Flower Garden", description = "A Deck of Flower Pokémon: Beautiful but Dangerous" },
        { name = "Kaleidoscope", description = "Uses Venomoth's Pokémon Power to change the opponent's Weakness." },
        { name = "Flower Power", description = "A powerful Big Eggsplosion  and Energy Transfer combo!" },
      },
    },
    {
      machine = "Psychic",
      decks = {
        { name = "Psychic Power", description = "Use the Psychic power of the Psychic Pokémon to Attack!" },
        { name = "Dream Eater Haunter", description = "Uses Haunter's Dream Eater to cause great damage!" },
        { name = "Scavenging Slowbro", description = "Continually draw Trainer  Cards from the Discard Pile!" },
        { name = "Strange Power", description = "Confuse opponents with mysterious power!" },
        { name = "Strange Psyshock", description = "Use Alakazam's Damage Swap to move damage counters!" },
      },
    },
    {
      machine = "Science",
      decks = {
        { name = "Lovely Nidoran", description = "Uses Nidoqueen's Boyfriends to cause great damage to the opponent." },
        { name = "Science Corps", description = "The march of the Science Corps! Attack with the power of science!" },
        { name = "Flyin' Pokémon", description = "Pokémon with feathers flock  together! Retreating is easy!" },
        { name = "Poison", description = "A Deck that uses Poison to  slowly Knock Out the opponent." },
        { name = "Wonders of Science", description = "Block Pokémon Powers with  Muk and attack with Mewtwo!" },
      },
    },
    {
      machine = "Fire",
      decks = {
        { name = "Replace 'Em All", description = "A Deck that shuffles the opponent's cards" },
        { name = "Chari-Saur", description = "Attack with Charizard - with  just a few Fire Energy cards!" },
        { name = "Traffic Light", description = "Pokémon that can Attack with Fire, Water or Lightning Energy!" },
        { name = "Fire Pokémon", description = "With Fire Pokémon like Charizard,  Rapidash and Magmar, it's hot!" },
        { name = "Fire Charge", description = "Desperate attacks Damage your  opponent and you!" },
      },
    },
    {
      machine = "Legendary",
      decks = {
        { name = "Legendary Moltres", description = "Gather Fire Energy with the Legendary Moltres!" },
        { name = "Legendary Zapdos", description = "Zap opponents with the Legandary Zapdos!" },
        { name = "Legendary Articuno", description = "Paralyze opponents with the Legendary Articuno!" },
        { name = "Legendary Dragonite", description = "Heal your Pokémon with the Legendary Dragonite!" },
        { name = "Mysterious Pokémon", description = "A very special Deck made of very rare Pokémon cards!" },
      },
    },
  },
}

-- In-duel menu system (src/engine/duel/core.asm, src/constants/duel_interface_constants.asm).

-- At the start of a duel, both players place their opening Basic Pokemon.
Menus.duel_setup_menus = {
  {
    step = "Place Active Pokemon",
    description = "Player is shown their hand (as a card list) and must choose one Basic Pokemon " ..
      "to place as their Active/Arena Pokemon. This step cannot be skipped/cancelled.",
  },
  {
    step = "Place Bench Pokemon",
    description = "Player may place additional Basic Pokemon from hand onto the Bench (up to " ..
      "MAX_BENCH_POKEMON = 5). This step CAN be skipped/cancelled (bench may be left empty).",
  },
  {
    step = "Prize cards",
    description = "6 cards (or 1, in a Sudden Death rematch) are automatically dealt face-down from " ..
      "the top of each player's deck as Prizes; this is automatic, not a menu.",
  },
}

-- The main in-duel menu (DuelMenuData), shown on the turn holder's turn once setup is complete.
-- Six options laid out in a 3x2 grid on screen.
Menus.duel_main_menu = {
  { option = "Hand", position = {x=3, y=14},
    description = "Open the player's hand as a card list. From here a card can be inspected (Check) " ..
      "or played: a Basic Pokemon (placed on Bench if room), an Evolution card (placed on a matching " ..
      "Pokemon if it hasn't evolved yet this turn), a Trainer card (resolves its effect), or an Energy " ..
      "card (attached to a Play Area Pokemon, once per turn)." },
  { option = "Check", position = {x=9, y=14},
    description = "Inspect any Pokemon currently in play (Active or Bench, either side) in detail: " ..
      "full stats, attack text, current damage, attached cards, and status condition." },
  { option = "Retreat", position = {x=15, y=14},
    description = "Switch the Active Pokemon with a chosen Bench Pokemon, discarding Energy cards " ..
      "attached to the Active Pokemon equal to its retreat cost. Disabled if Active Pokemon is Asleep " ..
      "or Paralyzed, if there's no Bench Pokemon to switch to, or if already retreated this turn." },
  { option = "Attack", position = {x=3, y=16},
    description = "Choose one of the Active Pokemon's two attack slots to use (if enough Energy is " ..
      "attached and any extra requirements, e.g. a coin flip cost, are met). Using an attack ends the " ..
      "turn. Disabled entirely if Active Pokemon is Asleep, Paralyzed, or Confused-and-failed-its-flip." },
  { option = "PKMN Power", position = {x=9, y=16},
    description = "Use the Active Pokemon's Pokemon Power, if it has one and it hasn't already been " ..
      "used this turn (most Powers are once-per-turn) and the Pokemon isn't Asleep/Confused/Paralyzed." },
  { option = "Done", position = {x=15, y=16},
    description = "End the turn without attacking." },
}

-- Card list selection sub-menus that many of the above options open into
-- (wCardListItemSelectionMenuType constants).
Menus.card_list_selection_types = {
  PLAY_CHECK   = "Selecting a card offers to either Play it or Check (inspect) it -- used for the hand.",
  SELECT_CHECK = "Selecting a card offers to either Select it (confirm the choice) or Check (inspect) " ..
    "it -- used e.g. for choosing a retreat target or an attack's card-selection effect.",
}

-- wDuelDisplayedScreen states -- the distinct full-screen views the duel can be showing at any time.
Menus.duel_screen_states = {
  "DUEL_MAIN_SCENE -- the main battlefield view with the 6-option menu",
  "PLAY_AREA_CARD_LIST -- viewing all cards attached to/stacked under one Play Area Pokemon",
  "COIN_TOSS -- coin flip animation (used constantly: confusion, sleep, paralysis-inducing attacks, etc.)",
  "DRAW_CARDS -- card draw animation",
  "LARGE_CARD_PICTURE -- full-size card art view (from Check)",
  "SHUFFLE_DECK -- deck shuffle animation",
  "CHECK_PLAY_AREA -- the Check menu's Pokemon inspector",
}

-- Card detail "pages" the player can flip through when checking a Pokemon or Trainer/Energy card
-- (wCardPageNumber constants) -- these are the actual screens behind "Check".
Menus.card_check_pages = {
  "Overview -- name, HP, type, stage, weakness/resistance/retreat cost",
  "Attack 1, page 1 -- attack name/cost/damage",
  "Attack 1, page 2 -- attack's full effect text",
  "Attack 2, page 1 -- attack name/cost/damage",
  "Attack 2, page 2 -- attack's full effect text",
  "Description -- Pokedex-style flavor text",
  "(Energy cards use a single dedicated page)",
  "Trainer card, page 1 -- name/rarity",
  "Trainer card, page 2 -- full effect text",
}

-- New game setup (src/engine/starter_deck.asm) -- what happens before the player ever reaches the
-- Deck Selection menu for the first time.
Menus.new_game_setup = {
  description = "On a brand new save file, all 3 starter decks (Charmander & Friends, Squirtle & " ..
    "Friends, Bulbasaur & Friends) are pre-written into the player's 3 saved-deck slots, and every " ..
    "card in the collection is marked not-owned. The player is then asked to choose a starter.",
  starter_choice = {
    { choice = "Charmander", main_deck = "CharmanderAndFriendsDeck", extra_cards_deck = "CharmanderExtraDeck" },
    { choice = "Squirtle", main_deck = "SquirtleAndFriendsDeck", extra_cards_deck = "SquirtleExtraDeck" },
    { choice = "Bulbasaur", main_deck = "BulbasaurAndFriendsDeck", extra_cards_deck = "BulbasaurExtraDeck" },
  },
  effect_of_choice = {
    "The chosen deck's 60 cards become the player's actual Deck 1 (playable immediately) and are " ..
      "marked owned in the collection.",
    "The corresponding '...Extra' deck's 30 cards (a different card pool, see ai_and_deck_mechanics.lua's " ..
      "AI.decks for their exact contents) are added directly to the player's card COLLECTION only -- " ..
      "not into any deck -- giving immediate raw material to customize a deck with at the Deck Machine.",
    "The two decks NOT chosen remain in their pre-written saved-deck slots, but their cards are not " ..
      "owned, so those slots show as invalid/unusable until the player acquires those specific cards.",
  },
}

return Menus
