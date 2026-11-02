"""Turns the grabbed XMLTV guides (one file per language) into small JSON files per
channel, which the app downloads only for the channel being watched.

Usage: python3 tool/split_epg.py guides_dir channel_langs.json site_dir [hours]
Reads guides_dir/<lang>.xml. Writes site_dir/schedules/:
  <id>.<lang>.json   the channel's listings in that language
  <id>.json          the default language (first available in channel_langs.json order)
  index.json         {"updated": ..., "channels": [ids]}
File format: {"id": "SMNI.ph", "updated": 1793600000, "lang": "en", "langs": ["en", "es"],
              "p": [[start, stop, "title"], ...]}
(start/stop in UTC seconds, sorted, only programmes not yet over and starting within `hours`).
"""
import json
import re
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$")  # becomes a file name
CONTROL = re.compile(r"[\x00-\x1f\x7f]+")
MAX_PER_CHANNEL = 300


def parse_time(s):
    """XMLTV '20261102010000 +0800' → UTC seconds (no offset = UTC). None if malformed."""
    if not s:
        return None
    s = s.strip()
    for fmt in ("%Y%m%d%H%M%S %z", "%Y%m%d%H%M%S"):
        try:
            t = datetime.strptime(s, fmt)
            return int((t if t.tzinfo else t.replace(tzinfo=timezone.utc)).timestamp())
        except ValueError:
            pass
    return None


def clean(text, limit):
    if not text:
        return ""
    text = " ".join(CONTROL.sub(" ", text).split())
    return text[:limit]


def split(guide_path, now, hours=48):
    """Pure-ish: returns {channel_id: [[start, stop, title, desc], ...]}."""
    horizon = now + hours * 3600
    by_source = {}  # full xmltv id (may include @feed) -> programmes
    for _, el in ET.iterparse(guide_path, events=("end",)):
        if el.tag != "programme":
            continue
        source = el.get("channel") or ""
        start, stop = parse_time(el.get("start")), parse_time(el.get("stop"))
        title = clean(el.findtext("title"), 120)
        el.clear()
        if not title or start is None or stop is None or stop <= now or start > horizon or stop <= start:
            continue
        by_source.setdefault(source, []).append([start, stop, title, ""])
    # (descriptions are dropped: they make files several times bigger for little use on a phone)
    result = {}
    for source, progs in by_source.items():
        cid = source.split("@")[0]
        if not SAFE_ID.match(cid):
            continue
        # several feeds/sites for one channel: keep the fullest
        if cid not in result or len(progs) > len(result[cid]):
            result[cid] = progs
    for cid, progs in result.items():
        progs.sort(key=lambda p: p[0])
        dedup = []
        for p in progs:
            if not dedup or p[0] >= dedup[-1][1] or p[0] != dedup[-1][0]:
                dedup.append(p)
        result[cid] = [[a, b, t] for a, b, t, _ in dedup[:MAX_PER_CHANNEL]]
    return result


LANG = re.compile(r"^[a-z]{2,3}$")


def publish(by_lang, order, out, now):
    """by_lang: {lang: {channel: programmes}}; order: {channel: [langs, best first]}.
    Writes the per-language files, the default file and the index. Returns channel count."""
    out.mkdir(parents=True, exist_ok=True)
    channels = {cid for data in by_lang.values() for cid in data}
    for cid in channels:
        have = [l for l in by_lang if cid in by_lang[l]]
        langs = [l for l in order.get(cid, []) if l in have] + sorted(l for l in have if l not in order.get(cid, []))
        for lang in langs:
            doc = {"id": cid, "updated": now, "lang": lang, "langs": langs, "p": by_lang[lang][cid]}
            text = json.dumps(doc, ensure_ascii=False, separators=(",", ":"))
            (out / f"{cid}.{lang}.json").write_text(text)
            if lang == langs[0]:
                (out / f"{cid}.json").write_text(text)  # default; also what older app versions read
    (out / "index.json").write_text(json.dumps({"updated": now, "channels": sorted(channels)}, separators=(",", ":")))
    return len(channels)


def main(guides_dir, langs_file, site_dir, hours="48"):
    now = int(time.time())
    order = json.loads(Path(langs_file).read_text())
    by_lang = {}
    for f in sorted(Path(guides_dir).glob("*.xml")):
        if LANG.match(f.stem):
            by_lang[f.stem] = split(f, now, int(hours))
    n = publish(by_lang, order, Path(site_dir) / "schedules", now)
    print(f"{n} channels; " + ", ".join(f"{lang}: {len(d)}" for lang, d in sorted(by_lang.items(), key=lambda kv: -len(kv[1]))[:8]))


if __name__ == "__main__":
    main(*sys.argv[1:5])
