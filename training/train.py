"""Train and export one resident's microLM.

Each species gets its own vocabulary, its own weights and its own file.  The
three models never share a process, a socket or a checkpoint: the mod loads
three independent q8 blobs and runs them in the LOVE Lua process.
"""
import json, math, os, struct, sys, time
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from tok import tokenize, detokenize, escape
import world as W

torch.set_num_threads(4)
HERE = os.path.dirname(os.path.abspath(__file__))

D_MODEL, N_HEAD, N_LAYER, D_FF, CTX = 160, 4, 4, 640, 192
VOCAB_CAP = 3000
BATCH, STEPS, LR, WARMUP = 24, 2600, 3.0e-3, 150
SENTINELS = W.SENTINELS


class Block(nn.Module):
    def __init__(self, d, h, f):
        super().__init__()
        self.n1 = nn.LayerNorm(d); self.qkv = nn.Linear(d, 3 * d); self.proj = nn.Linear(d, d)
        self.n2 = nn.LayerNorm(d); self.l1 = nn.Linear(d, f); self.l2 = nn.Linear(f, d)
        self.h = h

    def forward(self, x):
        B, T, Dm = x.shape
        q, k, v = self.qkv(self.n1(x)).split(Dm, dim=2)
        hd = Dm // self.h
        q = q.view(B, T, self.h, hd).transpose(1, 2)
        k = k.view(B, T, self.h, hd).transpose(1, 2)
        v = v.view(B, T, self.h, hd).transpose(1, 2)
        y = F.scaled_dot_product_attention(q, k, v, is_causal=True)
        x = x + self.proj(y.transpose(1, 2).reshape(B, T, Dm))
        x = x + self.l2(F.gelu(self.l1(self.n2(x)), approximate="tanh"))
        return x


class Model(nn.Module):
    def __init__(self, V):
        super().__init__()
        self.V = V
        self.tok = nn.Embedding(V, D_MODEL)
        self.pos = nn.Embedding(CTX, D_MODEL)
        self.blocks = nn.ModuleList([Block(D_MODEL, N_HEAD, D_FF) for _ in range(N_LAYER)])
        self.ln = nn.LayerNorm(D_MODEL)
        nn.init.normal_(self.tok.weight, std=0.02)
        nn.init.normal_(self.pos.weight, std=0.02)

    def forward(self, idx):
        T = idx.shape[1]
        x = self.tok(idx) + self.pos(torch.arange(T, device=idx.device))
        for b in self.blocks:
            x = b(x)
        return F.linear(self.ln(x), self.tok.weight)


def build_vocab(lines):
    freq = {}
    for line in lines:
        for t in tokenize(line):
            freq[t] = freq.get(t, 0) + 1
    for s in SENTINELS:
        freq.pop(s, None)
    ranked = sorted(freq.items(), key=lambda kv: (-kv[1], kv[0]))
    keep = [t for t, _ in ranked[:VOCAB_CAP - len(SENTINELS)]]
    itos = list(SENTINELS) + keep
    return {t: i for i, t in enumerate(itos)}, itos


def encode_stream(lines, stoi):
    bos, eos, unk = stoi["<bos>"], stoi["<eos>"], stoi["<unk>"]
    ids = []
    for line in lines:
        ids.append(bos)
        for t in tokenize(line):
            ids.append(stoi.get(t, unk))
        ids.append(eos)
    return np.array(ids, dtype=np.uint16)


# ------------------------------------------------------------------ q8 export
def q8_matrix(w):
    """Symmetric int8 per output row plus a float32 row scale."""
    w = w.detach().float().cpu().numpy()
    rows, cols = w.shape
    scales = np.abs(w).max(axis=1) / 127.0
    scales[scales == 0] = 1e-8
    q = np.clip(np.rint(w / scales[:, None]), -127, 127).astype(np.int8)
    out = struct.pack("<HH", rows, cols) + scales.astype("<f4").tobytes() + q.tobytes()
    return out


def q8_vector(v):
    v = v.detach().float().cpu().numpy().ravel()
    return struct.pack("<H", len(v)) + v.astype("<f4").tobytes()


def export(model, path, maxlen):
    blob = b"MLMQ1"
    blob += struct.pack("<HHHHHH", model.V, D_MODEL, N_HEAD, N_LAYER, D_FF, maxlen)
    blob += q8_matrix(model.tok.weight)
    blob += q8_matrix(model.pos.weight)
    for b in model.blocks:
        blob += q8_matrix(b.qkv.weight) + q8_vector(b.qkv.bias)
        blob += q8_matrix(b.proj.weight) + q8_vector(b.proj.bias)
        blob += q8_matrix(b.l1.weight) + q8_vector(b.l1.bias)
        blob += q8_matrix(b.l2.weight) + q8_vector(b.l2.bias)
        blob += q8_vector(b.n1.weight) + q8_vector(b.n1.bias)
        blob += q8_vector(b.n2.weight) + q8_vector(b.n2.bias)
    blob += q8_vector(model.ln.weight) + q8_vector(model.ln.bias)
    with open(path, "wb") as fh:
        fh.write(blob)
    return len(blob)


@torch.no_grad()
def sample(model, stoi, itos, prompt, n=26, temp=0.7):
    ids = [stoi["<bos>"]] + [stoi.get(t, stoi["<unk>"]) for t in tokenize(prompt)]
    out = []
    for _ in range(n):
        x = torch.tensor([ids[-CTX:]], dtype=torch.long)
        logits = model(x)[0, -1] / temp
        logits[stoi["<pad>"]] = -1e9; logits[stoi["<bos>"]] = -1e9; logits[stoi["<unk>"]] = -1e9
        probs = F.softmax(logits, dim=-1)
        nxt = int(torch.multinomial(probs, 1))
        if nxt == stoi["<eos>"]:
            break
        ids.append(nxt); out.append(itos[nxt])
    return detokenize(out)


def main():
    species = sys.argv[1]
    steps = int(sys.argv[2]) if len(sys.argv) > 2 else STEPS
    corpus = os.path.join(HERE, "corpus", species + ".txt")
    outdir = os.path.join(HERE, "out", species)
    os.makedirs(outdir, exist_ok=True)

    with open(corpus, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    print(f"[{species}] {len(lines)} lines", flush=True)

    stoi, itos = build_vocab(lines)
    V = len(itos)
    data = encode_stream(lines, stoi)
    unk_rate = float((data == stoi["<unk>"]).mean())
    print(f"[{species}] vocab {V}  tokens {len(data)/1e6:.2f}M  unk {unk_rate*100:.2f}%", flush=True)

    model = Model(V)
    params = sum(p.numel() for p in model.parameters())
    print(f"[{species}] params {params/1e6:.3f}M", flush=True)
    opt = torch.optim.AdamW(model.parameters(), lr=LR, betas=(0.9, 0.95), weight_decay=0.1)
    rng = np.random.default_rng(7)
    t0 = time.time()
    losses = []
    for step in range(1, steps + 1):
        lr = LR * (step / WARMUP if step < WARMUP else
                   0.5 * (1 + math.cos(math.pi * (step - WARMUP) / max(1, steps - WARMUP))) * 0.95 + 0.05)
        for g in opt.param_groups:
            g["lr"] = lr
        ix = rng.integers(0, len(data) - CTX - 1, size=BATCH)
        xb = torch.from_numpy(np.stack([data[i:i + CTX] for i in ix]).astype(np.int64))
        yb = torch.from_numpy(np.stack([data[i + 1:i + 1 + CTX] for i in ix]).astype(np.int64))
        logits = model(xb)
        loss = F.cross_entropy(logits.view(-1, V), yb.reshape(-1))
        opt.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        opt.step()
        losses.append(float(loss))
        if step % 50 == 0 or step == 1:
            done = time.time() - t0
            eta = done / step * (steps - step) / 60
            print(f"[{species}] step {step}/{steps} loss {np.mean(losses[-50:]):.3f} "
                  f"lr {lr:.2e} {done/step:.2f}s/step eta {eta:.0f}min", flush=True)
        if step % 500 == 0:
            model.eval()
            p = ("agent %s location pokemon day care hunger high health hurt other charmander "
                 "affection dislike trust low anger angry remember charmander took my food "
                 "i think charmander takes my food chosen guard food <thought>" % species)
            print(f"[{species}] sample: {sample(model, stoi, itos, p)}", flush=True)
            model.train()

    model.eval()
    torch.save(model.state_dict(), os.path.join(outdir, "model.pt"))
    size = export(model, os.path.join(outdir, "model.q8"), CTX)
    with open(os.path.join(outdir, "vocab.tsv"), "w", encoding="utf-8") as fh:
        for i, t in enumerate(itos):
            fh.write(f"{i}\t{escape(t)}\n")
    info = {
        "species": species, "parameter_count": int(params), "vocab_size": V,
        "d_model": D_MODEL, "heads": N_HEAD, "layers": N_LAYER, "ff": D_FF, "max_context": CTX,
        "training_tokens_seen": int(steps * BATCH * CTX), "corpus_tokens": int(len(data)),
        "steps": steps, "final_loss": float(np.mean(losses[-50:])),
        "loss_curve": [float(np.mean(losses[i:i + 100])) for i in range(0, len(losses), 100)],
        "unk_rate": unk_rate, "quantization": "symmetric int8 per output row, float32 row scales",
        "blob_bytes": size,
        "sources": ["Bulbapedia article text for this species and its evolutions",
                    "generated Day Care social corpus in the runtime's own prompt format"],
    }
    with open(os.path.join(outdir, "model_info.json"), "w") as fh:
        json.dump(info, fh, indent=2)
    print(f"[{species}] exported {size/1e6:.2f}MB  final loss {info['final_loss']:.3f}", flush=True)


if __name__ == "__main__":
    main()
