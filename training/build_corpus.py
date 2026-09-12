"""Build one training corpus per resident.

Two sources are mixed:

  1. The Pokemon's own Bulbapedia article text (and its evolution pages), which
     is what gives each model its species knowledge and ordinary English.
  2. A generated social corpus in exactly the four shapes main.lua asks the
     model to score or continue, so the runtime and the training data cannot
     disagree about the format.
"""
import os, random, re, sys, json
import world as W
import voice as V

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "corpus_raw")
OUT = os.path.join(HERE, "corpus")

KEEP_SECTIONS = ("biology", "evolution", "physiology", "behavior", "habitat", "diet",
                 "in animation", "in the anime", "major appearances", "pokédex entries",
                 "pokedex entries", "origin", "name origin", "trivia", "in the manga",
                 "character", "personality", "history")
DROP_SECTIONS = ("game data", "learnset", "sprites", "in other languages", "base stats",
                 "type effectiveness", "held items", "game locations", "side game data",
                 "stats", "tcg", "trading card", "external links", "references",
                 "pokéathlon", "in events", "held item", "by tm", "by breeding")


def clean_article(text):
    """Keep narrative prose, drop the table-shaped game data sections."""
    lines, keep, out = text.split("\n"), True, []
    for line in lines:
        header = re.match(r"^(=+)\s*(.*?)\s*\1$", line.strip())
        if header:
            title = header.group(2).lower()
            if any(d in title for d in DROP_SECTIONS):
                keep = False
            elif any(k in title for k in KEEP_SECTIONS) or header.group(1) == "==":
                keep = any(k in title for k in KEEP_SECTIONS)
            continue
        if keep:
            out.append(line)
    return "\n".join(out)


def sentences(text):
    text = re.sub(r"\([^)]*\)", " ", text)
    text = re.sub(r"[^\x00-\x7f]+", " ", text)
    text = re.sub(r"\s+", " ", text)
    out = []
    for raw in re.split(r"(?<=[.!?])\s+", text):
        s = raw.strip().lower()
        if len(s) < 30 or len(s) > 300:
            continue
        if s.count(",") > 6 or any(ch in s for ch in "|{}[]#*"):
            continue
        words = s.split()
        if len(words) < 6 or len(words) > 45:
            continue
        out.append(s)
    return out


def article_sentences(species):
    out = []
    for name in sorted(os.listdir(RAW)):
        group = name.split("__")[0]
        if group not in (species, "shared"):
            continue
        with open(os.path.join(RAW, name), encoding="utf-8") as fh:
            text = fh.read()
        weight = 3 if group == species else 1
        out.extend(sentences(clean_article(text)) * weight)
    return out


# ----------------------------------------------------------------- state model
def pick(rng, seq):
    return seq[rng.randrange(len(seq))]


def sample_state(rng, me):
    others = [s for s in W.SPECIES if s != me]
    other = pick(rng, others)
    third = pick(rng, [s for s in W.SPECIES if s not in (me, other)] or others)
    st = {
        "me": me, "other": other, "third": third,
        "needs": {n: rng.randrange(3) for n in W.NEEDS},
        "health": pick(rng, ["healthy", "healthy", "healthy", "hurt", "badly hurt"]),
        "affection": pick(rng, W.AFFECTION),
        "trust": pick(rng, W.TRUST),
        "anger": pick(rng, W.ANGER),
        "fear": pick(rng, W.FEAR),
        "attach": pick(rng, W.ATTACH),
        "event": pick(rng, W.EVENT_TYPES + ["none", "none"]),
        "stage": rng.choice([1, 2, 2, 3, 3, 3, 4, 4, 4, 4]),
        "other_down": rng.random() < 0.10,
        "food": rng.random() < 0.7,
        "toy": rng.random() < 0.5,
        "holding_food": rng.random() < 0.3,
        "holding_toy": rng.random() < 0.25,
    }
    st["severe"] = st["other_down"] and st["anger"] in ("angry", "furious") and st["affection"] in ("hate", "dislike")
    return st


def context_of(rng, st):
    """Mirrors Prompt.build in main.lua, section for section and in the same order."""
    me, o = st["me"], st["other"]
    parts = ["agent %s location pokemon day care" % me]

    ranked = sorted(st["needs"].items(), key=lambda kv: -kv[1])
    need_bits = [f"{n} {W.QLEVEL[v]}" for n, v in ranked[:2] if v > 0]
    parts.append(" ".join(need_bits) if need_bits else "hunger %s" % W.QLEVEL[st["needs"]["hunger"]])

    parts.append("health %s" % st["health"])

    rel = ["other", o, "affection", st["affection"], "trust", st["trust"]]
    if st["anger"] != "calm":
        rel += ["anger", st["anger"]]
    if st["fear"] != "none":
        rel += ["fear", st["fear"]]
    if st["attach"] != "none":
        rel += ["attachment", st["attach"]]
    parts.append(" ".join(rel))

    parts.append("event %s %s" % (st["event"], o) if st["event"] != "none" else "event none")

    n_mem = 2 if st["stage"] >= 3 else 1
    pool = ([c.format(o=o, p=st["third"]) for c in W.CUES_ABOUT_OTHER]
            + [c.format(o=o) for c in W.CUES_ABOUT_SELF]
            + [c.format(o=o) for c in W.CUES_WORLD])
    for cue in rng.sample(pool, n_mem):
        parts.append("remember " + cue)

    if st["stage"] >= 2 and rng.random() < 0.75:
        parts.append("i think " + pick(rng, W.BELIEF_TEXT).format(o=o))
    if st["stage"] >= 3:
        if rng.random() < 0.65:
            parts.append(pick(rng, W.SELF_PHRASE))
        if rng.random() < 0.7:
            plan = pick(rng, list(W.PLAN_PHRASE))
            phrase = W.PLAN_PHRASE[plan]
            parts.append("i want to " + phrase + (" " + o if plan in W.PLAN_SOCIAL else ""))
            st["plan"] = plan
    if st["stage"] >= 4:
        if rng.random() < 0.6:
            parts.append(pick(rng, W.VALUE_PHRASE))
        if rng.random() < 0.6:
            parts.append(o + " " + pick(rng, W.WANT_PHRASE))
        if rng.random() < 0.5:
            parts.append(pick(rng, W.COUNTERFACTUAL).format(o=o))
    return " ".join(parts)


def action_weights(st):
    w = {}
    n = st["needs"]
    w["wander"] = 1.0
    w["rest"] = 0.6 + 2.2 * n["fatigue"]
    w["go_warm"] = 0.3 + 0.8 * n["fatigue"]
    w["go_sun"] = 0.3 + 0.6 * n["fatigue"]
    w["hide"] = 0.3 + 1.6 * n["stress"] + (1.8 if st["fear"] == "afraid" else 0)
    w["wall"] = 0.5
    w["inspect_food"] = 0.5
    w["inspect_water"] = 0.4
    w["inspect_toy"] = 0.4
    w["inspect_wall"] = 0.4
    if st["food"] or st["holding_food"]:
        w["eat"] = 0.4 + 2.6 * n["hunger"]
        w["guard_food"] = 0.3 + 0.9 * n["hunger"]
    w["drink"] = 0.4 + 2.6 * n["thirst"]
    if st["toy"] or st["holding_toy"]:
        w["play"] = 0.6 + 0.8 * n["social"]
    if st["other_down"]:
        w["guard_down"] = 0.8 + (1.6 if st["affection"] in ("like", "close") else 0)
        w["comfort_down"] = 0.6 + (1.8 if st["affection"] in ("like", "close") else 0)
        w["wait_near_down"] = 0.9
        w["avoid"] = 0.7 + (1.2 if st["fear"] == "afraid" else 0)
        w["take_from_down"] = 0.4 + (1.4 if st["affection"] in ("hate", "dislike") else 0)
        if st["severe"]:
            w["finish_off"] = 0.9 + (1.2 if st["anger"] == "furious" else 0)
    else:
        w["approach"] = 0.5 + 1.4 * n["social"] + (1.2 if st["affection"] in ("like", "close") else 0)
        w["speak"] = 0.6 + 1.2 * n["social"]
        w["follow"] = 0.4 + (1.0 if st["attach"] in ("attached", "strong") else 0)
        w["avoid"] = 0.4 + (2.0 if st["fear"] == "afraid" else 0) + (1.2 if st["affection"] == "hate" else 0)
        w["comfort"] = 0.4 + (1.4 if st["affection"] in ("like", "close") else 0)
        if st["holding_food"] or st["food"]:
            w["share_food"] = 0.3 + (1.6 if st["affection"] in ("like", "close") else 0)
            w["take_food"] = 0.4 + 1.2 * n["hunger"] + (1.0 if st["anger"] in ("angry", "furious") else 0)
        w["use_move"] = 0.2 + (2.2 if st["anger"] == "furious" else 0) + (1.2 if st["anger"] == "angry" else 0)
    plan = st.get("plan")
    boost = {"stay_near": "approach", "keep_away": "avoid", "watch": "follow",
             "take_from": "take_food", "make_peace": "comfort", "provoke": "use_move",
             "guard_food": "guard_food", "keep_toy": "play", "seek_human": "wall",
             "keep_away_human": "hide", "teach": "comfort"}.get(plan)
    if boost and boost in w:
        w[boost] += 2.0
    return w


def weighted(rng, weights):
    total = sum(weights.values())
    r = rng.random() * total
    for k, v in weights.items():
        r -= v
        if r <= 0:
            return k
    return list(weights)[-1]


# --------------------------------------------------------------- thought voice
def theme_weights(st, action):
    n, w = st["needs"], {}
    w["hunger"] = 0.2 + 2.0 * n["hunger"]
    w["thirst"] = 0.2 + 1.6 * n["thirst"]
    w["fatigue"] = 0.2 + 1.6 * n["fatigue"]
    w["stress"] = 0.2 + 1.8 * n["stress"]
    w["social"] = 0.2 + 1.6 * n["social"]
    w["boredom"] = 0.7
    w["curiosity"] = 0.7
    w["comfort"] = 0.5
    w["beauty"] = 0.35
    w["routine"] = 0.5
    w["ownership"] = 0.5 + (1.2 if st["holding_toy"] or st["holding_food"] else 0)
    w["fairness"] = 0.6
    w["loneliness"] = 0.4 + 0.8 * n["social"]
    w["observer"] = 0.6
    w["day_care"] = 0.4
    w["self_doubt"] = 0.4
    w["mastery"] = 0.4
    w["future"] = 0.6
    w["past"] = 0.6
    if st["affection"] in ("like", "close"):
        w["affection_high"] = 2.0
    if st["affection"] in ("hate", "dislike"):
        w["affection_low"] = 1.8
    if st["anger"] in ("angry", "furious"):
        w["anger"] = 2.6
        w["betrayal"] = 1.0
        w["reconcile"] = 0.8
    if st["fear"] in ("uneasy", "afraid"):
        w["fear"] = 2.2
    if st["attach"] in ("attached", "strong"):
        w["attachment"] = 1.8
    if st["trust"] == "low":
        w["betrayal"] = w.get("betrayal", 0) + 0.8
    w["jealousy"] = 0.5
    w["theory"] = 0.8
    if st["other_down"]:
        w["helpless_other"] = 3.0
        w["protect"] = 1.4 if st["affection"] in ("like", "close") else 0.4
    if st["health"] in ("hurt", "badly hurt"):
        w["unconscious"] = 0.8
    if st["event"] == "attacked":
        w["anger"] = w.get("anger", 0) + 1.6
    act_theme = {
        "eat": "act_eat", "drink": "act_drink", "play": "act_play", "rest": "act_rest",
        "go_warm": "act_rest", "go_sun": "act_rest", "hide": "act_hide",
        "guard_food": "act_guard", "inspect_food": "act_inspect", "inspect_water": "act_inspect",
        "inspect_toy": "act_inspect", "inspect_wall": "act_inspect", "wall": "act_wall",
        "approach": "act_approach", "speak": "act_speak", "avoid": "act_avoid",
        "follow": "act_follow", "comfort": "act_comfort", "comfort_down": "act_comfort",
        "share_food": "act_share", "take_food": "act_take", "take_from_down": "act_take",
        "use_move": "act_move", "finish_off": "act_move", "guard_down": "act_guard",
        "wait_near_down": "act_follow", "wander": "act_wander",
    }.get(action)
    if act_theme:
        w[act_theme] = 3.2
    return w


def compose_thought(rng, st, action):
    weights = theme_weights(st, action)
    clauses, used = [], set()
    count = rng.choice([1, 2, 2, 2, 3, 3])
    for _ in range(count):
        for _try in range(6):
            theme = weighted(rng, weights)
            if theme not in used:
                used.add(theme)
                break
        clauses.append(pick(rng, V.T[theme]).format(o=st["other"], p=st["third"]))
    if rng.random() < 0.16:
        clauses.insert(rng.randrange(len(clauses) + 1), pick(rng, V.SPECIES_T[st["me"]]))
    text = clauses[0]
    for c in clauses[1:]:
        text += pick(rng, V.CONNECT) + c
    return text.strip().rstrip(".") + "."


SPEECH_FOR_ACTION = {
    "approach": ["greet", "ask"], "speak": ["greet", "ask", "ownership", "peace"],
    "avoid": ["warn", "fear"], "follow": ["ask", "greet"],
    "comfort": ["comfort"], "comfort_down": ["comfort"],
    "share_food": ["share"], "take_food": ["dominance", "ownership"],
    "take_from_down": ["dominance"], "use_move": ["angry", "warn", "dominance"],
    "finish_off": ["dominance", "angry"], "guard_down": ["warn", "comfort"],
    "wait_near_down": ["ask", "comfort"], "wall": ["human"],
}


def compose_speech(rng, st, action):
    banks = SPEECH_FOR_ACTION.get(action)
    if not banks:
        return None
    if st["anger"] in ("angry", "furious") and rng.random() < 0.5:
        banks = banks + ["angry", "warn"]
    if st["fear"] == "afraid" and rng.random() < 0.5:
        banks = banks + ["fear"]
    if st["affection"] in ("like", "close") and rng.random() < 0.4:
        banks = banks + ["greet", "peace"]
    line = pick(rng, V.S[pick(rng, banks)])
    if rng.random() < 0.3:
        line = line + ", " + pick(rng, V.S[pick(rng, banks)])
    if rng.random() < 0.25 and action in W.SOCIAL:
        line = line.replace("you", st["other"], 1)
    return line.strip().rstrip(".") + "."


# ------------------------------------------------------------------- emit
def build_species(species, n_social, seed):
    rng = random.Random(seed)
    lines = []
    arts = article_sentences(species)
    rng.shuffle(arts)
    for s in arts:
        lines.append(s)
    # Species knowledge phrased as the Pokemon's own thought, so facts can
    # actually surface in what it thinks rather than only in plain prose.
    for s in V.SPECIES_T[species] * 40:
        stt = sample_state(rng, species)
        lines.append(context_of(rng, stt) + " <thought> " + s + ".")

    for _ in range(n_social):
        st = sample_state(rng, species)
        ctx = context_of(rng, st)
        action = weighted(rng, action_weights(st))
        phrase = W.ACTION_PHRASE[action]
        if action in W.SOCIAL:
            phrase += " " + st["other"]
        lines.append(ctx + " <act> " + phrase)
        lines.append(ctx + " chosen " + phrase + " <thought> " + compose_thought(rng, st, action))
        sp = compose_speech(rng, st, action)
        if sp:
            lines.append(ctx + " chosen " + phrase + " <speech> " + sp)
        if st.get("plan") and rng.random() < 0.45:
            plan = st["plan"]
            tail = W.PLAN_PHRASE[plan] + (" " + st["other"] if plan in W.PLAN_SOCIAL else "")
            lines.append(ctx + " i want to " + tail)
    rng.shuffle(lines)
    return lines


def main():
    os.makedirs(OUT, exist_ok=True)
    n_social = int(sys.argv[1]) if len(sys.argv) > 1 else 90000
    for i, species in enumerate(W.SPECIES):
        lines = build_species(species, n_social, 1000 + i)
        path = os.path.join(OUT, species + ".txt")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines))
        words = sum(len(l.split()) for l in lines)
        print(f"{species:11s} {len(lines):7d} lines  {words/1e6:.2f}M words  -> {path}")


if __name__ == "__main__":
    main()
