"""Fetch the Bulbapedia article text each resident is trained on.

Only the three residents' own pages and their evolution pages are used, plus a
small number of directly relevant general pages.  Text is cached on disk so a
rerun does not hit the wiki again.
"""
import json, os, re, sys, time, urllib.parse, urllib.request

API = "https://bulbapedia.bulbagarden.net/w/api.php"
OUT = os.path.join(os.path.dirname(__file__), "corpus_raw")
UA = "pokemon-observer-ai-training/1.0 (offline corpus build)"

PAGES = {
    "bulbasaur": ["Bulbasaur (Pokémon)", "Ivysaur (Pokémon)", "Venusaur (Pokémon)"],
    "charmander": ["Charmander (Pokémon)", "Charmeleon (Pokémon)", "Charizard (Pokémon)"],
    "squirtle": ["Squirtle (Pokémon)", "Wartortle (Pokémon)", "Blastoise (Pokémon)"],
}
SHARED = [
    "Pokémon Day Care", "Egg Group", "Friendship", "Experience", "Evolution",
    "Grass (type)", "Fire (type)", "Water (type)", "Poison (type)",
    "Status condition", "Fainting", "Move", "Level",
]


def fetch(title):
    q = urllib.parse.urlencode({
        "action": "query", "prop": "extracts", "explaintext": "1",
        "format": "json", "redirects": "1", "titles": title,
    })
    req = urllib.request.Request(API + "?" + q, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = json.load(r)
    pages = data.get("query", {}).get("pages", {})
    for _, page in pages.items():
        if "extract" in page:
            return page["extract"]
    return ""


def main():
    os.makedirs(OUT, exist_ok=True)
    wanted = {}
    for species, titles in PAGES.items():
        wanted[species] = list(titles)
    wanted["shared"] = list(SHARED)
    for group, titles in wanted.items():
        for title in titles:
            name = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")
            path = os.path.join(OUT, f"{group}__{name}.txt")
            if os.path.exists(path) and os.path.getsize(path) > 400:
                print("cached", path)
                continue
            try:
                text = fetch(title)
            except Exception as exc:
                print("FAILED", title, exc, file=sys.stderr)
                continue
            if not text:
                print("EMPTY", title, file=sys.stderr)
                continue
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
            print(f"{len(text):7d}  {path}")
            time.sleep(1.0)


if __name__ == "__main__":
    main()
