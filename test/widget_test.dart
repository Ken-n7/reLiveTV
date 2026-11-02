import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_channels/catalog.dart';

void main() {
  test('buildCatalog joins files, groups streams, drops blocked + nsfw', () {
    Map<String, dynamic> stream(String? ch, String title, String url, [String? q]) =>
        {'channel': ch, 'feed': null, 'title': title, 'url': url, 'quality': q, 'labels': [], 'user_agent': null, 'referrer': 'https://r'};
    final raw = {
      'streams': jsonEncode([
        stream('A.ph', 'A', 'u1', '720p'),
        stream('A.ph', 'A', 'u2', '1080p'),
        stream('B.us', 'B', 'u3'),
        stream('X.us', 'X', 'u4'),
        stream(null, 'Loose', 'u5'),
      ]),
      'channels': jsonEncode([
        {'id': 'A.ph', 'name': 'Alpha', 'network': 'Net', 'country': 'PH', 'categories': ['news'], 'is_nsfw': false, 'website': 'https://a'},
        {'id': 'B.us', 'name': 'Beta', 'network': null, 'country': 'US', 'categories': [], 'is_nsfw': false, 'website': null},
        {'id': 'X.us', 'name': 'Xxx', 'network': null, 'country': 'US', 'categories': [], 'is_nsfw': true, 'website': null},
      ]),
      'logos': jsonEncode([
        {'channel': 'A.ph', 'feed': 'SD', 'url': 'feed.png'},
        {'channel': 'A.ph', 'feed': null, 'url': 'main.png'},
      ]),
      'countries': jsonEncode([
        {'code': 'PH', 'name': 'Philippines', 'flag': '🇵🇭'},
        {'code': 'US', 'name': 'United States', 'flag': '🇺🇸'},
      ]),
      'categories': jsonEncode([{'id': 'news', 'name': 'News'}]),
      'blocklist': jsonEncode([{'channel': 'B.us', 'reason': 'dmca', 'ref': 'https://issue'}]),
    };
    final c = buildCatalog(raw);

    expect(c.channels.map((ch) => ch.name), ['Alpha', 'Loose']);
    final a = c.channels.first;
    expect(a.streams.map((s) => s.url), ['u1', 'u2']);
    expect(a.logo, 'main.png');
    expect(a.categories, ['News']);
    expect(a.streams.first.headers, {'Referer': 'https://r'});
    expect(c.countries, {'PH': '🇵🇭 Philippines'});

    // with an alive list, dead streams are dropped and channels left with none disappear
    final live = buildCatalog({...raw, 'alive': jsonEncode(['u2', 'u5'])});
    expect(live.channels.map((ch) => '${ch.name}:${ch.streams.map((s) => s.url).join(',')}'), ['Alpha:u2', 'Loose:u5']);
  });
}
