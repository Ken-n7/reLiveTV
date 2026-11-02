import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_channels/catalog.dart';

Map<String, dynamic> stream(String? ch, String url, {String? feed, String? q, List<String> labels = const [], String? ua, String? ref}) =>
    {'channel': ch, 'feed': feed, 'title': ch ?? 'Loose', 'url': url, 'quality': q, 'labels': labels, 'user_agent': ua, 'referrer': ref};

Map<String, dynamic> channel(String id, String name, String country, {bool nsfw = false, String? closed, String? replacedBy, List<String> cats = const []}) => {
  'id': id, 'name': name, 'alt_names': ['$name Alt'], 'network': 'Net', 'owners': ['Owner Co'], 'country': country, 'categories': cats, //
  'is_nsfw': nsfw, 'launched': '1999-05-01', 'closed': closed, 'replaced_by': replacedBy, 'website': 'https://$id.example',
};

final fixtures = <String, Object>{
  'countries': [
    {'code': 'PH', 'name': 'Philippines', 'flag': '🇵🇭'},
    {'code': 'US', 'name': 'United States', 'flag': '🇺🇸'},
  ],
  'categories': [{'id': 'news', 'name': 'News'}],
  'languages': [{'code': 'eng', 'name': 'English'}, {'code': 'fil', 'name': 'Filipino'}],
  'regions': [
    {'code': 'ASIA', 'name': 'Asia', 'countries': ['PH']},
    {'code': 'EUR', 'name': 'Europe', 'countries': ['FR']},
  ],
  'subdivisions': [{'country': 'US', 'code': 'US-CA', 'name': 'California', 'parent': null}],
  'timezones': [{'id': 'Asia/Manila', 'utc_offset': '+08:00', 'countries': ['PH']}, {'id': 'America/New_York', 'utc_offset': '-05:00', 'countries': ['US']}],
  'blocklist': [{'channel': 'Blocked.us', 'reason': 'dmca', 'ref': 'x'}],
  'channels': [
    channel('A.ph', 'Alpha', 'PH', cats: ['news']),
    channel('Blocked.us', 'Blocked', 'US'),
    channel('Adult.us', 'Adult', 'US', nsfw: true),
    channel('Old.us', 'Old', 'US', closed: '2020-01-01', replacedBy: 'New.us@HD'),
    channel('New.us', 'New', 'US'),
  ],
  'feeds': [
    {'channel': 'A.ph', 'id': 'SD', 'name': 'SD', 'is_main': false, 'broadcast_area': ['c/PH'], 'timezones': ['Asia/Manila'], 'languages': ['eng'], 'format': '480i'},
    {'channel': 'A.ph', 'id': 'HD', 'name': 'HD', 'is_main': true, 'broadcast_area': ['r/ASIA', 'ct/PHMNL'], 'timezones': ['Asia/Manila'], 'languages': ['fil'], 'format': '1080i'},
    {'channel': 'New.us', 'id': 'HD', 'name': 'HD', 'is_main': true, 'broadcast_area': ['s/US-CA'], 'timezones': ['America/New_York'], 'languages': ['eng'], 'format': '720p'},
  ],
  'logos': [
    {'channel': 'A.ph', 'feed': null, 'in_use': true, 'width': 512, 'format': 'SVG', 'url': 'https://l/a.svg'}, // can't draw
    {'channel': 'A.ph', 'feed': 'HD', 'in_use': true, 'width': 900, 'format': 'PNG', 'url': 'https://l/a-feed.png'},
    {'channel': 'A.ph', 'feed': null, 'in_use': true, 'width': 200, 'format': 'PNG', 'url': 'https://l/a-small.png'},
    {'channel': 'A.ph', 'feed': null, 'in_use': true, 'width': 400, 'format': 'PNG', 'url': 'https://l/a-big.png'},
    {'channel': 'A.ph', 'feed': null, 'in_use': false, 'width': 999, 'format': 'PNG', 'url': 'https://l/a-old.png'},
    {'channel': 'New.us', 'feed': null, 'in_use': true, 'width': 100, 'format': 'PNG', 'url': 'file:///etc/passwd'},
  ],
  'streams': [
    stream('A.ph', 'https://s/a1.m3u8', feed: 'SD', q: '480p'),
    stream('A.ph', 'http://s/a2.m3u8', feed: 'HD', q: '1080p', labels: ['Geo-blocked'], ua: 'VLC/3', ref: 'https://ref'),
    stream('A.ph', 'rtmp://s/a3'), // not http(s): dropped
    stream('A.ph', 'https://s/a4.m3u8', ua: 'Evil\r\nX-Injected: 1'), // header with CR/LF: header dropped, stream kept
    stream('Blocked.us', 'https://s/b.m3u8'),
    stream('Adult.us', 'https://s/x.m3u8'),
    stream('Old.us', 'https://s/old.m3u8'),
    stream('New.us', 'https://s/new.m3u8'),
    stream(null, 'https://s/loose.m3u8'),
    stream(null, 'javascript:alert(1)'),
    {'channel': 'A.ph', 'url': 12345}, // malformed: skipped
  ],
};

Catalog build() => buildCatalog((name) => jsonEncode(fixtures[name]));

void main() {
  test('joins iptv-org files; hides blocklisted, adult and closed channels', () {
    final c = build();
    expect(c.channels.map((ch) => ch.name), ['Alpha', 'Loose', 'New']);
    expect(c.replacedBy, {'Old.us': 'New.us'}, reason: 'My List can follow renamed channels');
  });

  test('channel details come from channels, feeds, languages, regions, subdivisions', () {
    final a = build().channels.first;
    expect(a.categories, ['News']);
    expect(a.altNames, ['Alpha Alt']);
    expect(a.owners, ['Owner Co']);
    expect(a.launched, '1999');
    expect(a.format, '1080i', reason: 'main feed first');
    expect(a.timezone, 'Asia/Manila');
    expect(a.languages, ['Filipino', 'English']);
    expect(a.areas, ['Asia'], reason: 'cities skipped');
    expect(a.feeds, ['HD', 'SD']);
    expect(build().channels.last.areas, ['California']);
    expect(a.searchText, contains('owner co'));
  });

  test('untrusted input is filtered', () {
    final a = build().channels.first;
    expect(a.streams.map((s) => s.url), ['https://s/a1.m3u8', 'http://s/a2.m3u8', 'https://s/a4.m3u8']);
    expect(a.streams[1].headers, {'User-Agent': 'VLC/3', 'Referer': 'https://ref'});
    expect(a.streams[1].geoBlocked, isTrue);
    expect(a.streams[2].headers, isEmpty, reason: 'CR/LF header rejected');
    expect(build().channels.last.logo, isNull, reason: 'file: logo URL rejected');
    expect(safeUrl('https://ok.example/x'), isNotNull);
    for (final bad in ['file:///etc/passwd', 'javascript:x', 'rtsp://x/y', 'https://', 'x' * 3000]) {
      expect(safeUrl(bad), isNull, reason: bad);
    }
    expect(cleanText('a\u0000b\nc'), 'a b c');
  });

  test('best logo: drawable, in use, channel-wide, widest', () {
    expect(build().channels.first.logo, 'https://l/a-big.png');
  });

  test('countries, languages, regions, timezones in use', () {
    final c = build();
    expect(c.countries, {'PH': '🇵🇭 Philippines', 'US': '🇺🇸 United States'});
    expect(c.languages, ['English', 'Filipino']);
    expect(c.regions.map((r) => r.name), ['Asia'], reason: 'Europe has no channels here');
    expect(c.timezoneOffsets, {'Asia/Manila': 480, 'America/New_York': -300});
  });

  test('compact catalog round-trips', () {
    final c = build();
    final back = Catalog.fromJsonString(c.toJsonString());
    expect(back.channels.map((ch) => ch.toJson()), c.channels.map((ch) => ch.toJson()));
    expect(back.channels.first.flag, '🇵🇭');
    expect(back.countries, c.countries);
    expect(back.regions.single.countries, ['PH']);
    expect(back.timezoneOffsets, c.timezoneOffsets);
    expect(back.replacedBy, c.replacedBy);
    expect(() => Catalog.fromJsonString('{"v":0}'), throwsFormatException);
  });
}
