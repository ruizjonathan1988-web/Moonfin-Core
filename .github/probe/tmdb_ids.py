# Temporary: finds the TMDB id of each film on Wikidata, by title and year.
import json, urllib.parse, urllib.request

FILMS = [
    ("Un p'tit truc en plus", 2024), ("Le Comte de Monte-Cristo", 2024),
    ("Marsupilami", 2026), ("L'Amour ouf", 2024),
    ("Astérix et Obélix : L'Empire du Milieu", 2023), ("Alibi.com 2", 2023),
    ("Les Trois Mousquetaires : D'Artagnan", 2023), ("God Save the Tuche", 2025),
    ("Kaamelott : Premier Volet", 2021), ("Qu'est-ce qu'on a tous fait au Bon Dieu ?", 2022),
    ("Simone, le voyage du siècle", 2022), ("Novembre", 2022), ("BAC Nord", 2020),
    ("Gourou", 2026), ("Juste une illusion", 2026),
    ("Intouchables", 2011), ("Qu'est-ce qu'on a fait au Bon Dieu ?", 2014),
    ("Rien à déclarer", 2010), ("La Famille Bélier", 2014),
    ("Qu'est-ce qu'on a encore fait au Bon Dieu ?", 2019), ("Les Tuche 3", 2018),
    ("La Ch'tite Famille", 2018), ("Les Petits Mouchoirs", 2010),
    ("Sur la piste du Marsupilami", 2012), ("Supercondriaque", 2014),
    ("Bienvenue chez les Ch'tis", 2008), ("La Grande Vadrouille", 1966),
    ("Astérix et Obélix : Mission Cléopâtre", 2002), ("Les Visiteurs", 1993),
    ("Le Petit Monde de don Camillo", 1952), ("Le Corniaud", 1965), ("Taxi 2", 2000),
]

QUERY = """
SELECT ?item ?label ?tmdb (MIN(YEAR(?d)) AS ?year) WHERE {
  SERVICE wikibase:mwapi {
    bd:serviceParam wikibase:api "EntitySearch"; wikibase:endpoint "www.wikidata.org";
      mwapi:search "%s"; mwapi:language "fr"; mwapi:limit "10".
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
