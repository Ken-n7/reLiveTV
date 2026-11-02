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


# feeds.json uses ISO 639-3 ("eng"), guides.json uses ISO 639-1 ("en")
ISO3_TO_1 = {
    "eng": "en", "spa": "es", "fra": "fr", "por": "pt", "deu": "de", "ita": "it", "rus": "ru", "ara": "ar",
    "zho": "zh", "cmn": "zh", "yue": "zh", "hin": "hi", "tur": "tr", "pol": "pl", "nld": "nl", "ron": "ro",
    "ces": "cs", "slk": "sk", "ell": "el", "hun": "hu", "swe": "sv", "dan": "da", "nor": "no", "nob": "no",
    "fin": "fi", "hrv": "hr", "srp": "sr", "bos": "bs", "slv": "sl", "bul": "bg", "ukr": "uk", "bel": "be",
    "sqi": "sq", "mkd": "mk", "lit": "lt", "lav": "lv", "est": "et", "kor": "ko", "jpn": "ja", "ind": "id",
    "msa": "ms", "zsm": "ms", "tha": "th", "vie": "vi", "fil": "tl", "tgl": "tl", "heb": "he", "fas": "fa",
    "pes": "fa", "urd": "ur", "ben": "bn", "tam": "ta", "tel": "te", "mar": "mr", "guj": "gu", "kan": "kn",
    "mal": "ml", "pan": "pa", "cat": "ca", "glg": "gl", "eus": "eu", "isl": "is", "gle": "ga", "kat": "ka",
    "hye": "hy", "aze": "az", "kaz": "kk", "uzb": "uz", "mon": "mn", "swa": "sw", "afr": "af", "amh": "am",
}


def build(sites, streams, channels, blocklist, guides, feeds=()):
    """Pure: returns <channel> lines, one guide source per channel. Picks a source in the
    channel's own language first, then English, then anything; ties go to the first site
    in `sites` (a US channel listed by a Russian site must not get Russian listings)."""
    hidden = {b.get("channel") for b in blocklist}
    hidden |= {c["id"] for c in channels if c.get("closed") or c.get("is_nsfw")}
    playable = {
        s["channel"] for s in streams
        if s.get("channel") and str(s.get("url", "")).startswith(("http://", "https://"))
    } - hidden
    rank = {s: i for i, s in enumerate(sites)}
    main_lang, spoken = {}, {}  # channel -> main language / all its languages, as ISO 639-1
    for f in sorted(feeds, key=lambda f: not f.get("is_main")):  # main feed first
        langs = [ISO3_TO_1[c] for c in f.get("languages") or () if c in ISO3_TO_1]
        if langs:
            main_lang.setdefault(f.get("channel"), langs[0])
            spoken.setdefault(f.get("channel"), set()).update(langs)

    def score(e):
        lang, ch = e.get("lang"), e["channel"]
        if lang == main_lang.get(ch):
            fit = 0  # the channel's main language
        elif lang in spoken.get(ch, ()):
            fit = 1  # another language it broadcasts in (e.g. a second audio track)
        elif lang == "en":
            fit = 2
        else:
            fit = 3
        return (fit, rank[e["site"]])

    best = {}  # channel -> guide entry
    for e in guides:
        ch, site = e.get("channel"), e.get("site")
        if ch not in playable or site not in rank or not e.get("site_id"):
            continue
        if ch not in best or score(e) < score(best[ch]):
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
    lines = build(sites, get("streams"), get("channels"), get("blocklist"), get("guides"), get("feeds"))
    with open(out, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<channels>\n' + "\n".join(lines) + "\n</channels>\n")
    print(f"{len(lines)} channels from {len(sites)} sites")


if __name__ == "__main__":
    main(*sys.argv[1:3])
