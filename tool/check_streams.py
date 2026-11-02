"""Check every iptv-org stream URL; write the live ones to assets/alive.json.
Run: python3 tool/check_streams.py   (takes a few minutes)"""
import json, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
from collections import Counter
from pathlib import Path

API = "https://iptv-org.github.io/api"
OUT = Path(__file__).resolve().parent.parent / "assets" / "alive.json"

def get_json(name):
    with urllib.request.urlopen(f"{API}/{name}.json", timeout=60) as r:
        return json.load(r)

def alive(s):
    """Live = the playlist URL answers 200 and looks like a playlist/video."""
    headers = {"User-Agent": s.get("user_agent") or "VLC/3.0.23 LibVLC/3.0.23"}
    if s.get("referrer"):
        headers["Referer"] = s["referrer"]
    try:
        with urllib.request.urlopen(urllib.request.Request(s["url"], headers=headers), timeout=8) as r:
            head = r.read(512)
            return r.status == 200 and (b"#EXTM3U" in head or b"#EXT" in head or head[:1] == b"G" or "video" in r.headers.get("Content-Type", ""))
    except Exception:
        return False

if __name__ == "__main__":
    streams = get_json("streams")
    countries = {c["id"]: c["country"] for c in get_json("channels")}
    t = time.time()
    with ThreadPoolExecutor(64) as pool:  # ponytail: fixed pool; raise if the check is too slow
        results = list(pool.map(alive, streams))
    live = [s for s, ok in zip(streams, results) if ok]
    OUT.write_text(json.dumps({"checked": time.strftime("%Y-%m-%d %H:%M"), "urls": sorted(s["url"] for s in live)}))

    print(f"checked {len(streams)} streams in {time.time()-t:.0f}s: {len(live)} alive ({100*len(live)/len(streams):.0f}%)")
    tot = Counter(countries.get(s["channel"], "?") for s in streams)
    ok = Counter(countries.get(s["channel"], "?") for s in live)
    print("most live channels by country:")
    for code, n in ok.most_common(10):
        print(f"  {code}: {n}/{tot[code]} alive")
    print(f"  PH: {ok['PH']}/{tot['PH']} alive")
