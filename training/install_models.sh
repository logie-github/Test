#!/bin/bash
# Copy freshly trained models into the mod.  Each species is independent: its
# own weights, its own vocabulary, its own file.
set -e
cd "$(dirname "$0")"
for s in bulbasaur charmander squirtle; do
  install -d "../pokemon_observer_ai/brains/$s"
  cp "out/$s/model.q8"        "../pokemon_observer_ai/brains/$s/model.q8"
  cp "out/$s/vocab.tsv"       "../pokemon_observer_ai/brains/$s/vocab.tsv"
  cp "out/$s/model_info.json" "../pokemon_observer_ai/brains/$s/model_info.json"
  rm -f "../pokemon_observer_ai/brains/$s/agent_model_info.json"
  echo "installed $s"
done
python3 - <<'PY'
import json, os
out = {"runtime": "embedded_lua_q8", "external_runtime_required": False,
       "independent_models": True, "models": {}}
for s in ("bulbasaur", "charmander", "squirtle"):
    info = json.load(open(f"out/{s}/model_info.json"))
    out["architecture"] = {"d_model": info["d_model"], "heads": info["heads"],
                           "layers": info["layers"], "ff": info["ff"],
                           "max_context": info["max_context"]}
    out["quantization"] = info["quantization"]
    out["models"][s] = {k: info[k] for k in
                        ("parameter_count", "vocab_size", "corpus_tokens",
                         "training_tokens_seen", "steps", "final_loss")}
json.dump(out, open("../pokemon_observer_ai/brains/MODEL_SUMMARY.json", "w"), indent=2)
print("wrote MODEL_SUMMARY.json")
PY
