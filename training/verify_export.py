import json, os, sys, subprocess
import numpy as np, torch, torch.nn.functional as F
from train import Model, CTX
from tok import tokenize

species = sys.argv[1]
outdir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", species)
prompt = ("agent %s location pokemon day care hunger high health hurt other charmander "
          "affection dislike trust low anger angry remember charmander took my food "
          "chosen guard food <thought> the food is" % species)
open(os.path.join(outdir, "verify_prompt.txt"), "w").write(prompt)

stoi = {}
itos = []
for line in open(os.path.join(outdir, "vocab.tsv"), encoding="utf-8"):
    line = line.rstrip("\n")
    if not line:
        continue
    sid, t = line.split("\t", 1)
    t = t.replace("\\t", "\t").replace("\\n", "\n").replace("\\r", "\r").replace("\\\\", "\\")
    stoi[t] = int(sid)
    itos.append(t)

model = Model(len(itos))
sd = torch.load(os.path.join(outdir, "model.pt"), map_location="cpu")
model.load_state_dict(sd)
model.eval()
ids = [stoi["<bos>"]] + [stoi.get(t, stoi["<unk>"]) for t in tokenize(prompt)]
with torch.no_grad():
    ref = model(torch.tensor([ids]))[0, -1].numpy()

subprocess.run(["lua5.1", "verify_export.lua", species, outdir], check=True)
lua = np.array([float(x) for x in open(os.path.join(outdir, "verify_lua_logits.txt"))])
assert len(lua) == len(ref), (len(lua), len(ref))
corr = float(np.corrcoef(lua, ref)[0, 1])
mad = float(np.abs(lua - ref).mean())
print(f"tokens={len(ids)} corr={corr:.5f} mean_abs_diff={mad:.4f} "
      f"top1_torch={itos[int(ref.argmax())]!r} top1_lua={itos[int(lua.argmax())]!r}")
tk = set(np.argsort(-ref)[:10]); lk = set(np.argsort(-lua)[:10])
print("top10 overlap:", len(tk & lk), "/10")
