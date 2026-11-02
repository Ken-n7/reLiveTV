"""Turns the grabbed XMLTV guide into one small JSON file per channel, which the
app downloads only for the channel being watched.

Usage: python3 tool/split_epg.py guide.xml site_dir [hours]
Writes site_dir/schedules/<channel id>.json and site_dir/schedules/index.json.
File format: {"id": "SMNI.ph", "updated": 1793600000, "p": [[start, stop, "title"], ...]}
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


def main(guide, site_dir, hours="48"):
    now = int(time.time())
    data = split(guide, now, int(hours))
    out = Path(site_dir) / "schedules"
    out.mkdir(parents=True, exist_ok=True)
    for cid, progs in data.items():
        (out / f"{cid}.json").write_text(json.dumps({"id": cid, "updated": now, "p": progs}, ensure_ascii=False, separators=(",", ":")))
    (out / "index.json").write_text(json.dumps({"updated": now, "channels": sorted(data)}, separators=(",", ":")))
    print(f"{len(data)} channels, {sum(len(p) for p in data.values())} programmes")


if __name__ == "__main__":
    main(*sys.argv[1:4])
