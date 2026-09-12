# Resident model training

Each Day Care resident runs its own small decoder-only Transformer. The three
models are built and shipped separately: separate corpora, separate
vocabularies, separate weight files. At runtime they are loaded and executed
inside the game's own Lua process, one independent model per Pokemon, with no
server, socket, shared checkpoint or cross-model state.

## Pipeline

```
fetch_bulbapedia.py   ->  corpus_raw/   cached article text
build_corpus.py       ->  corpus/       per-species training text
train.py <species>    ->  out/<species>/model.q8, vocab.tsv, model_info.json
verify_export.py      ->  checks the exported blob against the float model
install_models.sh     ->  copies the three models into the mod
```

`train_all.sh` runs train + verify for all three in sequence.

## What each model is trained on

1. **Its own Bulbapedia article text**, plus the articles for the forms it
   evolves into, plus a small set of directly relevant general pages (Day Care,
   Egg Group, Evolution, Experience, its own types, Fainting, Move, Level).
   Game-data tables, learnsets, sprite tables and TCG sections are stripped;
   narrative prose is kept. This is what gives each model species knowledge and
   ordinary English sentence structure.

2. **A generated Day Care social corpus** written in exactly the four shapes the
   runtime asks a model for, so training data and runtime prompts cannot drift
   apart:

   ```
   <context> <act> <action phrase> [<species>]
   <context> chosen <action phrase> [<species>] <thought> <thought text>
   <context> chosen <action phrase> [<species>] <speech> <speech text>
   <context> i want to <plan phrase> [<species>]
   ```

   The context is assembled by the same section list `Prompt.build` uses in
   `main.lua`: needs, health, directional relationship, current event, retrieved
   memory cues, a belief, a self-concept line, the current plan, a value, what
   it reads the other one as wanting, and a counterfactual.

   Thoughts are composed, not drawn from a fixed bank: one to three clauses are
   sampled from themes weighted by the state the Pokemon is actually in, joined
   with varied connectives, occasionally carrying a species-specific line. The
   action is itself sampled from state-dependent weights, so the model learns a
   mapping from situation to behavior rather than a marginal distribution over
   actions.

## Architecture

| | |
|---|---|
| d_model | 160 |
| heads | 4 |
| layers | 4 |
| feed-forward | 640 |
| context | 192 tokens |
| vocabulary | 3000 per species (word level, tied input/output embedding) |
| parameters | ~1.75M per species |
| quantization | symmetric int8 per output row, float32 row scales |
| blob size | ~1.8MB per species |

## Honest limits

These are still small models. They produce short, varied, species-flavored
sentences and react to the state they are given. They do not carry out multi
step reasoning, and they do not hold a conversation. The cognitive
infrastructure around them - the permanent ledger, retrieval, beliefs,
self-concept, theory of mind and plans - is what gives them continuity over a
long run; the network itself supplies association and language.

## Reproducing

```
pip install numpy torch
python3 fetch_bulbapedia.py
python3 build_corpus.py 90000
./train_all.sh
./install_models.sh
```

Article text is from Bulbapedia (bulbapedia.bulbagarden.net) and is used here to
train the in-game characters on their own species' documented biology and
behavior.
