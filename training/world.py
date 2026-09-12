"""Shared vocabulary of the simulation, mirrored from main.lua.

Everything the mod can put into a prompt, and everything it can ask a model to
score, is enumerated here so the training corpus and the runtime cannot drift
apart.
"""

SPECIES = ["bulbasaur", "charmander", "squirtle"]

ACTION_PHRASE = {
    "wander": "wander", "rest": "rest", "wall": "wall", "go_sun": "go sun",
    "go_water": "go water", "go_warm": "go warm", "hide": "hide", "guard_food": "guard food",
    "eat": "eat", "drink": "drink", "play": "play",
    "inspect_food": "inspect food", "inspect_water": "inspect water",
    "inspect_toy": "inspect toy", "inspect_wall": "inspect wall",
    "approach": "approach", "speak": "speak", "avoid": "avoid", "follow": "follow",
    "comfort": "comfort", "share_food": "share food", "take_food": "take food",
    "use_move": "use move", "guard_down": "guard", "comfort_down": "comfort",
    "take_from_down": "take food", "wait_near_down": "stay near", "finish_off": "use move down",
}
SOCIAL = {"approach", "speak", "avoid", "follow", "comfort", "share_food", "take_food",
          "use_move", "guard_down", "comfort_down", "take_from_down", "wait_near_down", "finish_off"}
DOWN_ACTIONS = {"guard_down", "comfort_down", "take_from_down", "wait_near_down", "finish_off"}
SPEECH_ACTIONS = SOCIAL | {"wall"}

PLAN_PHRASE = {
    "stay_near": "stay near", "keep_away": "stay away from", "watch": "watch",
    "take_from": "take food from", "make_peace": "forgive", "provoke": "confront",
    "guard_food": "guard the food", "keep_toy": "keep the toy",
    "seek_human": "speak to the human", "keep_away_human": "stay away from the human",
    "teach": "stay near and help",
}
PLAN_SOCIAL = {"stay_near", "keep_away", "watch", "take_from", "make_peace", "provoke", "teach"}

EVENT_TYPES = ["greeted", "shared food", "took food", "attacked", "comforted", "ignored",
               "followed", "threatened", "gave toy", "stayed near", "used move near", "asked for help"]

NEEDS = ["hunger", "thirst", "fatigue", "stress", "social"]
QLEVEL = ["low", "medium", "high"]
HEALTH = ["healthy", "hurt", "badly hurt", "down"]
AFFECTION = ["hate", "dislike", "neutral", "like", "close"]
TRUST = ["low", "medium", "high"]
ANGER = ["calm", "annoyed", "angry", "furious"]
FEAR = ["none", "uneasy", "afraid"]
ATTACH = ["none", "curious", "attached", "strong"]

BELIEF_TEXT = [
    "{o} takes my food", "{o} shares food", "{o} hurts me", "{o} helps me",
    "{o} avoids me", "{o} follows me", "{o} stays near me", "{o} is angry with me",
    "{o} guards food", "{o} kills",
]
SELF_PHRASE = [
    "i usually share food", "i usually take food", "i usually hit", "i usually comfort",
    "i usually avoid", "i usually hide", "i usually guard food", "i usually follow",
    "i usually speak to the human", "i usually speak",
    "i have used a move on a down pokemon", "i am not safe here",
]
VALUE_PHRASE = [
    "i want to share", "i want them down", "i want my part", "i want to hit back",
    "i want to look around", "i want to be safe", "i want space",
]
WANT_PHRASE = [
    "wants food", "wants my food", "wants water", "wants the toy", "wants the food",
    "wants to share", "wants to help", "wants to hit", "wants to be near",
    "wants to talk", "wants space", "wants to rest", "wants the human", "wants them down",
]
COUNTERFACTUAL = [
    "if i hit {o} it might avoid me",
    "if i give the toy to {o} it might stay near me",
    "if i stay away from {o} i might be safe",
    "if i share food with {o} it might share food",
]

# Exactly the retrieval cues main.lua writes into the ledger.
CUES_ABOUT_OTHER = [
    "{o} took my food", "{o} gave me food", "{o} hit me", "{o} helped me",
    "{o} greeted me", "{o} threatened me", "{o} moved away from me", "{o} followed me",
    "{o} stayed near me", "{o} came to me", "{o} guards food", "{o} knocked me down",
    "{o} is down", "{o} changed", "{o} is gone", "{o} killed {p}", "{o} hit {p}",
    "{o} knocked {p} down",
]
CUES_ABOUT_SELF = [
    "i ate", "i played with the toy", "i looked at the food", "i looked at the water",
    "i looked at the toy", "i looked at the wall", "i took food", "i guarded the food",
    "i spoke to the human", "i woke up", "i was knocked down", "i changed my body",
    "i hit {o}", "i killed {o}", "i gave food to {o}", "i stayed with {o}",
    "i guarded {o}", "i waited by {o}", "i am level 6",
]
CUES_WORLD = [
    "the human gave food", "the human took food", "the human gave a toy",
    "the human took a toy", "the human introduced a compatible mate",
    "the human removed a compatible mate", "something changed here",
    "a {o} came here", "an egg is here",
]

SENTINELS = ["<pad>", "<bos>", "<eos>", "<unk>", "<act>", "<thought>", "<speech>"]
