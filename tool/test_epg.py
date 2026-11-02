"""Self-check for the schedule tools: python3 tool/test_epg.py"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
from epg_channels import build  # noqa: E402
from split_epg import parse_time, publish, split  # noqa: E402
import json  # noqa: E402
from pathlib import Path  # noqa: E402


def test_build():
    lines, _ = build(
        sites=["first.com", "second.com"],
        streams=[{"channel": c, "url": "https://x/" + c} for c in ("A.ph", "B.us", "Old.us", "Blocked.us")]
        + [{"channel": "Rtmp.us", "url": "rtmp://x"}],
        channels=[{"id": "Old.us", "closed": "2020-01-01"}],
        blocklist=[{"channel": "Blocked.us"}],
        guides=[
            {"channel": "A.ph", "feed": "HD", "site": "second.com", "site_id": "a2", "site_name": "A", "lang": "fil"},
            {"channel": "A.ph", "feed": None, "site": "first.com", "site_id": "a1", "site_name": "A & Co", "lang": "fil"},
            {"channel": "B.us", "feed": None, "site": "other.com", "site_id": "b", "site_name": "B"},
            {"channel": "Old.us", "site": "first.com", "site_id": "o"},
            {"channel": "Blocked.us", "site": "first.com", "site_id": "x"},
            {"channel": "Rtmp.us", "site": "first.com", "site_id": "r"},
            {"channel": "Gone.us", "site": "first.com", "site_id": "g"},  # no stream
        ],
    )
    assert len(lines) == 1, lines  # both A.ph sources are Filipino: first.com wins; other.com is not a chosen site
    assert 'site="first.com"' in lines[0] and 'xmltv_id="A.ph"' in lines[0] and "A &amp; Co" in lines[0]


def test_languages():
    guides = [
        {"channel": "CN.us", "site": "ru-site.com", "site_id": "1", "lang": "ru"},
        {"channel": "CN.us", "site": "mx-site.com", "site_id": "6", "lang": "es"},
        {"channel": "CN.us", "site": "us-site.com", "site_id": "2", "lang": "en"},
        {"channel": "CN.us", "site": "other-en.com", "site_id": "7", "lang": "en"},  # same language, lower priority
        {"channel": "Canal.mx", "site": "ru-site.com", "site_id": "3", "lang": "ru"},
        {"channel": "Canal.mx", "site": "us-site.com", "site_id": "4", "lang": "en"},
        {"channel": "Canal.mx", "site": "mx-site.com", "site_id": "5", "lang": "es"},
    ]
    feeds = [
        {"channel": "CN.us", "is_main": False, "languages": ["spa"]},  # Spanish audio feed
        {"channel": "CN.us", "is_main": True, "languages": ["eng", "spa"]},
        {"channel": "Canal.mx", "is_main": True, "languages": ["spa"]},
    ]
    streams = [{"channel": c, "url": "https://x/" + c} for c in ("CN.us", "Canal.mx")]
    sites = ["ru-site.com", "mx-site.com", "us-site.com", "other-en.com"]
    lines, order = build(sites, streams, [], [], guides, feeds)
    assert len(lines) == 6, lines  # every language once per channel
    assert not any("other-en.com" in l for l in lines), "one site per channel and language"
    assert order["CN.us"] == ["en", "es", "ru"], order  # main language, then other spoken, then the rest
    assert order["Canal.mx"] == ["es", "en", "ru"], order
    _, order = build(sites[:3], streams[:1], [], [], guides[:3], [])
    assert order["CN.us"][0] == "en", "without language info, English first"


def test_publish():
    progs = [[100, 200, "Show"]]
    by_lang = {"ru": {"CN.us": progs}, "en": {"CN.us": progs, "B.uk": progs}}
    with tempfile.TemporaryDirectory() as d:
        n = publish(by_lang, {"CN.us": ["en", "es", "ru"]}, Path(d), now=50)
        assert n == 2
        default = json.loads((Path(d) / "CN.us.json").read_text())
        assert default["lang"] == "en" and default["langs"] == ["en", "ru"], default  # es had no listings
        assert json.loads((Path(d) / "CN.us.ru.json").read_text())["lang"] == "ru"
        assert json.loads((Path(d) / "B.uk.json").read_text())["langs"] == ["en"]
        assert json.loads((Path(d) / "index.json").read_text())["channels"] == ["B.uk", "CN.us"]


def test_split():
    now = parse_time("20261102100000 +0000")
    assert parse_time("20261102180000 +0800") == now, "offsets become UTC"
    assert parse_time("20261102100000") == now, "no offset = UTC"
    xml = """<tv>
  <programme channel="A.ph@HD" start="20261102090000 +0000" stop="20261102095900 +0000"><title>Over</title></programme>
  <programme channel="A.ph@HD" start="20261102100000 +0000" stop="20261102110000 +0000"><title>Now
 news </title></programme>
  <programme channel="A.ph@HD" start="20261102110000 +0000" stop="20261102120000 +0000"><title>Next</title></programme>
  <programme channel="A.ph@SD" start="20261102100000 +0000" stop="20261102120000 +0000"><title>Thin feed</title></programme>
  <programme channel="A.ph@HD" start="20261105100000 +0000" stop="20261105110000 +0000"><title>Too far</title></programme>
  <programme channel="../evil" start="20261102100000 +0000" stop="20261102110000 +0000"><title>x</title></programme>
  <programme channel="B.us" start="bad" stop="20261102110000 +0000"><title>x</title></programme>
</tv>"""
    with tempfile.NamedTemporaryFile("w", suffix=".xml", delete=False) as f:
        f.write(xml)
    try:
        out = split(f.name, now, hours=48)
    finally:
        os.unlink(f.name)
    assert list(out) == ["A.ph"], out  # feeds merge to the channel id; unsafe/bad dropped
    assert [p[2] for p in out["A.ph"]] == ["Now news", "Next"], out  # fullest feed, cleaned, finished/far dropped


if __name__ == "__main__":
    test_build()
    test_languages()
    test_publish()
    test_split()
    print("ok")
