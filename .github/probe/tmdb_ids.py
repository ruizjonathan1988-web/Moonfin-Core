# Temporary: finds the TMDB id of each film on Wikidata, by title and year.
import json, urllib.parse, urllib.request

FILMS = [
    ("Qu'est-ce qu'on a tous fait au Bon Dieu", 2022), ("Serial (Bad) Weddings 3", 2022),
    ("Novembre film Jimenez", 2022), ("November Jimenez", 2022), ("Novembre", 2022),
    ("Gourou film", 2026), ("Gourou", 2026),
    ("Les Trois Mousquetaires : Milady", 2023), ("Super-héros malgré lui", 2022),
]

QUERY = """
SELECT ?item ?label ?tmdb (MIN(YEAR(?d)) AS ?year) WHERE {
  SERVICE wikibase:mwapi {
    bd:serviceParam wikibase:api "EntitySearch"; wikibase:endpoint "www.wikidata.org";
      mwapi:search "%s"; mwapi:language "fr"; mwapi:limit "40".
    ?item wikibase:apiOutputItem mwapi:item.
  }
  ?item wdt:P4947 ?tmdb .
  OPTIONAL { ?item wdt:P577 ?d }
  OPTIONAL { ?item rdfs:label ?label FILTER(LANG(?label) = "fr") }
} GROUP BY ?item ?label ?tmdb
"""

lines = []
for title, year in FILMS:
    q = QUERY % title.replace('"', '\\"')
    url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": q, "format": "json"})
    req = urllib.request.Request(url, headers={"User-Agent": "Moonfin-perso/1.0 (probe)"})
    try:
        rows = json.load(urllib.request.urlopen(req, timeout=60))["results"]["bindings"]
    except Exception as e:
        lines.append(f"{title} ({year}): ERROR {e}")
        continue
    found = [(r.get("tmdb", {}).get("value"), r.get("year", {}).get("value"), r.get("label", {}).get("value")) for r in rows]
    best = [f for f in found if f[1] and abs(int(f[1]) - year) <= 1]
    pick = best[0] if len(best) == 1 else None
    lines.append(f"{title} ({year}) -> {pick[0] if pick else '??'} | candidates {found[:5]}")

for i in range(0, len(lines), 6):
    print("::notice title=ids%d::%s" % (i, " || ".join(lines[i:i+6]).replace("\n", " ")))
