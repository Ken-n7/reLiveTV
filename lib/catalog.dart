import 'dart:convert';

const apiBase = 'https://iptv-org.github.io/api';
const apiFiles = ['streams', 'channels', 'logos', 'countries', 'categories', 'blocklist'];

class StreamSource {
  final String url, title;
  final String? quality, userAgent, referrer;
  final List<String> labels;
  StreamSource(this.url, this.title, this.quality, this.userAgent, this.referrer, this.labels);

  Map<String, String> get headers => {
        'User-Agent': ?userAgent,
        'Referer': ?referrer,
      };
}

class Channel {
  final String? id; // null = stream with no entry in channels.json
  String get key => id ?? 'title:$name'; // stable across launches, used for My List
  final String name;
  final String? logo, countryCode, countryName, flag, network, website;
  final List<String> categories; // display names
  final List<StreamSource> streams = [];
  Channel({
    required this.id,
    required this.name,
    this.logo,
    this.countryCode,
    this.countryName,
    this.flag,
    this.network,
    this.website,
    this.categories = const [],
  });
}

class Catalog {
  final List<Channel> channels; // playable; blocklisted and adult channels left out
  final Map<String, String> countries; // code -> "🇵🇭 Philippines", only those in use
  final List<String> categories; // in use, sorted
  Catalog(this.channels, this.countries, this.categories);
}

/// Joins the raw iptv-org JSON bodies (keyed by [apiFiles] name). Pure, so it
/// can run in an isolate via compute().
Catalog buildCatalog(Map<String, String> bodies) {
  List<Map<String, dynamic>> j(String k) => (jsonDecode(bodies[k]!) as List).cast<Map<String, dynamic>>();

  final channelsById = {for (final c in j('channels')) c['id'] as String: c};
  final countries = {for (final c in j('countries')) c['code'] as String: c};
  final categoryNames = {for (final c in j('categories')) c['id'] as String: c['name'] as String};

  final logos = <String, String>{};
  for (final l in j('logos')) {
    final id = l['channel'] as String;
    // prefer the channel-wide logo (feed == null) over feed-specific ones
    if (!logos.containsKey(id) || l['feed'] == null) logos[id] = l['url'] as String;
  }

  // left out entirely: channels removed after complaints (blocklist.json) and adult channels
  final hidden = {for (final b in j('blocklist')) b['channel'] as String, for (final c in channelsById.values) if (c['is_nsfw'] == true) c['id'] as String};

  final byKey = <String, Channel>{};
  Channel channel(String? id, String fallbackName) => byKey.putIfAbsent(id ?? 'title:$fallbackName', () {
        final c = id == null ? null : channelsById[id];
        if (c == null) return Channel(id: id, name: fallbackName);
        final country = countries[c['country']];
        return Channel(
          id: id,
          name: c['name'] as String,
          logo: logos[id],
          countryCode: c['country'] as String?,
          countryName: country?['name'] as String?,
          flag: country?['flag'] as String?,
          network: c['network'] as String?,
          website: c['website'] as String?,
          categories: [for (final cat in (c['categories'] as List)) categoryNames[cat] ?? cat as String],
        );
      });

  // optional: only keep streams that tool/check_streams.py found alive
  final alive = bodies['alive'] == null ? null : (jsonDecode(bodies['alive']!) as List).cast<String>().toSet();
  for (final s in j('streams')) {
    if (alive != null && !alive.contains(s['url'])) continue;
    if (hidden.contains(s['channel'])) continue;
    final title = s['title'] as String;
    channel(s['channel'] as String?, title).streams.add(StreamSource(
          s['url'] as String,
          title,
          s['quality'] as String?,
          s['user_agent'] as String?,
          s['referrer'] as String?,
          (s['labels'] as List).cast<String>(),
        ));
  }

  int byName(Channel a, Channel b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  final list = byKey.values.toList()..sort(byName);

  final usedCountries = {
    for (final ch in list)
      if (ch.countryCode != null) ch.countryCode!: '${ch.flag ?? ''} ${ch.countryName ?? ch.countryCode}'.trim(),
  };
  String bare(String label) => label.substring(label.indexOf(' ') + 1); // sort ignoring the flag
  final sortedCountries = Map.fromEntries(usedCountries.entries.toList()..sort((a, b) => bare(a.value).compareTo(bare(b.value))));
  final usedCategories = {for (final ch in list) ...ch.categories}.toList()..sort();
  return Catalog(list, sortedCountries, usedCategories);
}
