"""Builds the channel list for iptv-org's schedule grabber: every channel reLiveTV
can play that has a schedule on one of the sites in tool/epg_sites.txt.

Usage: python3 tool/epg_channels.py tool/epg_sites.txt channels.xml
"""
import json
import sys
import urllib.request
from xml.sax.saxutils import escape, quoteattr

API = "https://iptv-org.github.io/api"


def get(name):
    with urllib.request.urlopen(f"{API}/{name}.json", timeout=120) as r:
        return json.load(r)


def build(sites, streams, channels, blocklist, guides):
    """Pure: returns <channel> lines, one site per channel (first site in `sites` wins)."""
    hidden = {b.get("channel") for b in blocklist}
    hidden |= {c["id"] for c in channels if c.get("closed") or c.get("is_nsfw")}
    playable = {
        s["channel"] for s in streams
        if s.get("channel") and str(s.get("url", "")).startswith(("http://", "https://"))
    } - hidden
    rank = {s: i for i, s in enumerate(sites)}
    best = {}  # channel -> guide entry
    for e in guides:
        ch, site = e.get("channel"), e.get("site")
        if ch not in playable or site not in rank or not e.get("site_id"):
            continue
        if ch not in best or rank[site] < rank[best[ch]["site"]]:
            best[ch] = e
    lines = []
    for ch, e in sorted(best.items()):
        xmltv_id = ch + (f"@{e['feed']}" if e.get("feed") else "")
        lines.append(
            f'  <channel site={quoteattr(e["site"])} lang={quoteattr(e.get("lang") or "en")} '
            f'xmltv_id={quoteattr(xmltv_id)} site_id={quoteattr(e["site_id"])}>{escape(e.get("site_name") or ch)}</channel>'
        )
    return lines


def main(sites_file, out):
    sites = [l.strip() for l in open(sites_file) if l.strip() and not l.lstrip().startswith("#")]
    lines = build(sites, get("streams"), get("channels"), get("blocklist"), get("guides"))
    with open(out, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<channels>\n' + "\n".join(lines) + "\n</channels>\n")
    print(f"{len(lines)} channels from {len(sites)} sites")


if __name__ == "__main__":
    main(*sys.argv[1:3])
