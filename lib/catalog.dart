import 'dart:convert';

/// iptv-org's public API: the only data source.
const apiBase = 'https://iptv-org.github.io/api';
const apiFiles = [
  'countries', 'categories', 'languages', 'regions', 'subdivisions', 'timezones', 'blocklist', //
  'channels', 'feeds', 'logos', 'streams',
];

// ---------------------------------------------------------------------------
// Untrusted-input guards: everything below comes from a public, crowd-edited list.

final _control = RegExp(r'[\x00-\x1F\x7F]');

/// Plain single-line text, length-capped. Null if empty.
String? cleanText(Object? v, [int max = 200]) {
  if (v is! String) return null;
  final s = v.replaceAll(_control, ' ').trim();
  if (s.isEmpty) return null;
  return s.length > max ? s.substring(0, max) : s;
}

/// http(s) URL with a host, length-capped; anything else (file:, rtmp:, javascript:…) → null.
String? safeUrl(Object? v) {
  if (v is! String || v.length > 2048) return null;
  final u = Uri.tryParse(v.trim());
  if (u == null || (u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) return null;
  return u.toString();
}

/// Header value without CR/LF (no header injection), length-capped.
String? safeHeader(Object? v) {
  if (v is! String || v.isEmpty || v.length > 512 || v.contains(_control)) return null;
  return v;
}

List<String> _strings(Object? v) => v is List ? [for (final e in v) ?cleanText(e)] : const [];

// ---------------------------------------------------------------------------

class StreamSource {
  final String url;
  final String? title, quality, feed, userAgent, referrer;
  final List<String> labels; // iptv-org labels, e.g. "Not 24/7", "Geo-blocked"
  StreamSource({required this.url, this.title, this.quality, this.feed, this.userAgent, this.referrer, this.labels = const []});

  Map<String, String> get headers => {'User-Agent': ?userAgent, 'Referer': ?referrer};
  bool get geoBlocked => labels.contains('Geo-blocked');
  bool get part247 => labels.contains('Not 24/7');

  Map<String, Object?> toJson() => {'u': url, 't': title, 'q': quality, 'f': feed, 'a': userAgent, 'r': referrer, if (labels.isNotEmpty) 'l': labels};
  factory StreamSource.fromJson(Map<String, dynamic> j) => StreamSource(
    url: j['u'] as String,
    title: j['t'] as String?,
    quality: j['q'] as String?,
    feed: j['f'] as String?,
    userAgent: j['a'] as String?,
    referrer: j['r'] as String?,
    labels: (j['l'] as List?)?.cast<String>() ?? const [],
  );
}

class Channel {
  final String? id; // null = stream with no entry in channels.json
  String get key => id ?? 'title:$name'; // stable across launches, used for My List
  final String name;
  final String? logo, countryCode, countryName, flag, network, website, launched, format, timezone;
  final List<String> categories, altNames, owners, languages, areas, feeds; // display names
  final List<StreamSource> streams;
  Channel({
    required this.id,
    required this.name,
    this.logo,
    this.countryCode,
    this.countryName,
    this.flag,
    this.network,
    this.website,
    this.launched,
    this.format,
    this.timezone,
    this.categories = const [],
    this.altNames = const [],
    this.owners = const [],
    this.languages = const [],
    this.areas = const [],
    this.feeds = const [],
    List<StreamSource>? streams,
  }) : streams = streams ?? [];

  /// iptv-org labels that apply to every source of this channel (shown as badges).
  List<String> get badges => [
    if (streams.isNotEmpty && streams.every((s) => s.part247)) 'Not 24/7',
    if (streams.isNotEmpty && streams.every((s) => s.geoBlocked)) 'Geo-blocked',
  ];

  /// Lower-cased text the search box matches against.
  late final String searchText = [name, ...altNames, ?network, ...owners, ?countryName, ...areas, ...languages].join('\n').toLowerCase();

  Map<String, Object?> toJson() => {
    'i': id, 'n': name, 'lo': logo, 'c': countryCode, 'nw': network, 'w': website, 'la': launched, 'fm': format, 'tz': timezone, //
    if (categories.isNotEmpty) 'ca': categories,
    if (altNames.isNotEmpty) 'an': altNames,
    if (owners.isNotEmpty) 'ow': owners,
    if (languages.isNotEmpty) 'lg': languages,
    if (areas.isNotEmpty) 'ar': areas,
    if (feeds.isNotEmpty) 'fe': feeds,
    's': [for (final s in streams) s.toJson()],
  };
  factory Channel.fromJson(Map<String, dynamic> j, Map<String, ({String name, String flag})> countries) {
    List<String> l(String k) => (j[k] as List?)?.cast<String>() ?? const [];
    final cc = j['c'] as String?;
    return Channel(
      id: j['i'] as String?,
      name: j['n'] as String,
      logo: j['lo'] as String?,
      countryCode: cc,
      countryName: countries[cc]?.name,
      flag: countries[cc]?.flag,
      network: j['nw'] as String?,
      website: j['w'] as String?,
      launched: j['la'] as String?,
      format: j['fm'] as String?,
      timezone: j['tz'] as String?,
      categories: l('ca'),
      altNames: l('an'),
      owners: l('ow'),
      languages: l('lg'),
      areas: l('ar'),
      feeds: l('fe'),
      streams: [for (final s in j['s'] as List) StreamSource.fromJson(s as Map<String, dynamic>)],
    );
  }
}

class Region {
  final String code, name;
  final List<String> countries;
  const Region(this.code, this.name, this.countries);
}

class Catalog {
  final List<Channel> channels; // playable; blocklisted, adult and closed channels left out
  final Map<String, ({String name, String flag})> countryInfo; // code → name/flag, only those in use
  final List<String> categories, languages; // in use, sorted
  final List<Region> regions; // only regions containing countries in use
  final Map<String, int> timezoneOffsets; // IANA id → UTC offset in minutes (fixed, no DST)
  final Map<String, String> replacedBy; // old channel id → new id, so My List follows renames
  final DateTime builtAt;
  Catalog({
    required this.channels,
    required this.countryInfo,
    required this.categories,
    required this.languages,
    required this.regions,
    required this.timezoneOffsets,
    required this.replacedBy,
    required this.builtAt,
  });

  /// code → "🇵🇭 Philippines", sorted by name.
  late final Map<String, String> countries = Map.fromEntries(
    (countryInfo.entries.toList()..sort((a, b) => a.value.name.compareTo(b.value.name))).map((e) => MapEntry(e.key, '${e.value.flag} ${e.value.name}'.trim())),
  );

  String toJsonString() => jsonEncode({
    'v': 1,
    'at': builtAt.toIso8601String(),
    'co': {for (final e in countryInfo.entries) e.key: [e.value.name, e.value.flag]},
    'ca': categories,
    'lg': languages,
    're': [for (final r in regions) [r.code, r.name, r.countries]],
    'tz': timezoneOffsets,
    'rb': replacedBy,
    'ch': [for (final c in channels) c.toJson()],
  });

  static Catalog fromJsonString(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    if (j['v'] != 1) throw const FormatException('old catalog format');
    final countries = {for (final e in (j['co'] as Map<String, dynamic>).entries) e.key: (name: (e.value as List)[0] as String, flag: e.value[1] as String)};
    return Catalog(
      channels: [for (final c in j['ch'] as List) Channel.fromJson(c as Map<String, dynamic>, countries)],
      countryInfo: countries,
      categories: (j['ca'] as List).cast<String>(),
      languages: (j['lg'] as List).cast<String>(),
      regions: [for (final r in j['re'] as List) Region(r[0] as String, r[1] as String, (r[2] as List).cast<String>())],
      timezoneOffsets: (j['tz'] as Map<String, dynamic>).cast<String, int>(),
      replacedBy: (j['rb'] as Map<String, dynamic>).cast<String, String>(),
      builtAt: DateTime.parse(j['at'] as String),
    );
  }
}

/// Image formats Flutter can draw (no SVG/AVIF).
const _drawable = {'PNG', 'JPEG', 'GIF', 'WebP'};

/// "+08:00" → 480
int? _offsetMinutes(Object? v) {
  final m = v is String ? RegExp(r'^([+-])(\d{2}):(\d{2})$').firstMatch(v) : null;
  if (m == null) return null;
  final mins = int.parse(m[2]!) * 60 + int.parse(m[3]!);
  return m[1] == '-' ? -mins : mins;
}

/// Joins iptv-org's files into the app's catalog. [read] returns a file's raw JSON
/// text by name (see [apiFiles]). Files are decoded one at a time and dropped after
/// use to keep peak memory low. Malformed entries are skipped, never fatal.
Catalog buildCatalog(String Function(String name) read) {
  List<Map<String, dynamic>> rows(String name) {
    final v = jsonDecode(read(name));
    return v is List ? [for (final e in v) if (e is Map<String, dynamic>) e] : const [];
  }

  // small lookups: key field → display name
  Map<String, String> names(String file, String keyField, int keyMax) {
    final m = <String, String>{};
    for (final r in rows(file)) {
      final k = cleanText(r[keyField], keyMax);
      if (k != null) m[k] = cleanText(r['name']) ?? k;
    }
    return m;
  }

  final countries = <String, ({String name, String flag})>{};
  for (final c in rows('countries')) {
    final code = cleanText(c['code'], 8);
    if (code != null) countries[code] = (name: cleanText(c['name']) ?? code, flag: cleanText(c['flag'], 16) ?? '');
  }
  final categoryNames = names('categories', 'id', 40);
  final languageNames = names('languages', 'code', 8);
  final allRegions = [
    for (final r in rows('regions'))
      if ((cleanText(r['code'], 16), cleanText(r['name'])) case (final code?, final name?)) Region(code, name, _strings(r['countries'])),
  ];
  final subdivisionNames = names('subdivisions', 'code', 16);
  final timezoneOffsets = {
    for (final t in rows('timezones'))
      if ((cleanText(t['id'], 64), _offsetMinutes(t['utc_offset'])) case (final id?, final off?)) id: off,
  };
  final hidden = {for (final b in rows('blocklist')) ?cleanText(b['channel'], 100)};

  // streams first: only channels that have a stream are worth keeping details for
  final streamRows = rows('streams');
  final wanted = {for (final s in streamRows) ?cleanText(s['channel'], 100)};

  // channels: keep only what the UI needs; closed/adult/blocklisted are hidden
  final replacedBy = <String, String>{};
  final info = <String, Map<String, dynamic>>{};
  for (final c in rows('channels')) {
    final id = cleanText(c['id'], 100);
    if (id == null) continue;
    if (!wanted.contains(id) && c['closed'] == null) continue;
    if (c['closed'] != null) {
      if (cleanText(c['replaced_by'], 100) case final to?) replacedBy[id] = to.split('@').first;
      hidden.add(id);
      continue;
    }
    if (c['is_nsfw'] == true) {
      hidden.add(id);
      continue;
    }
    if (!hidden.contains(id)) info[id] = c;
  }

  // feeds: languages, broadcast areas, format, timezone per channel (main feed first)
  final feedsOf = <String, List<Map<String, dynamic>>>{};
  for (final f in rows('feeds')) {
    final ch = cleanText(f['channel'], 100);
    if (ch != null && info.containsKey(ch)) (feedsOf[ch] ??= []).add(f);
  }
  String areaName(String code) {
    final i = code.indexOf('/');
    final kind = i < 0 ? '' : code.substring(0, i), v = code.substring(i + 1);
    return switch (kind) {
      'c' => countries[v]?.name ?? v,
      'r' => allRegions.where((r) => r.code == v).firstOrNull?.name ?? v,
      's' => subdivisionNames[v] ?? v,
      _ => '', // cities and unknown kinds: skipped
    };
  }

  // logos: best drawable one per channel (channel-wide first, then the widest)
  final logos = <String, ({String url, bool wide, int width})>{};
  for (final l in rows('logos')) {
    final ch = cleanText(l['channel'], 100), url = safeUrl(l['url']);
    if (ch == null || url == null || !info.containsKey(ch) || l['in_use'] == false || !_drawable.contains(l['format'])) continue;
    final cand = (url: url, wide: l['feed'] == null, width: (l['width'] as num?)?.toInt() ?? 0);
    final best = logos[ch];
    if (best == null || (cand.wide && !best.wide) || (cand.wide == best.wide && cand.width > best.width)) logos[ch] = cand;
  }

  Channel makeChannel(String id) {
    final c = info[id]!;
    final feeds = [...?feedsOf[id]]..sort((a, b) => (b['is_main'] == true ? 1 : 0) - (a['is_main'] == true ? 1 : 0));
    final main = feeds.firstOrNull;
    final cc = cleanText(c['country'], 8);
    return Channel(
      id: id,
      name: cleanText(c['name']) ?? id,
      logo: logos[id]?.url,
      countryCode: countries.containsKey(cc) ? cc : null,
      countryName: countries[cc]?.name,
      flag: countries[cc]?.flag,
      network: cleanText(c['network']),
      website: safeUrl(c['website']),
      launched: cleanText(c['launched'], 10)?.split('-').first,
      format: cleanText(main?['format'], 16),
      timezone: main == null ? null : _strings(main['timezones']).firstOrNull,
      categories: [for (final k in _strings(c['categories'])) categoryNames[k] ?? k],
      altNames: _strings(c['alt_names']),
      owners: _strings(c['owners']),
      languages: {for (final f in feeds) for (final code in _strings(f['languages'])) languageNames[code] ?? code}.toList(),
      areas: {for (final code in _strings(main?['broadcast_area'])) areaName(code)}.where((a) => a.isNotEmpty).toList(),
      feeds: feeds.length > 1 ? [for (final f in feeds) ?cleanText(f['name'], 40)] : const [],
    );
  }

  // streams: only http(s), safe headers; grouped by channel (or by title when unknown)
  final byKey = <String, Channel>{};
  for (final s in streamRows) {
    final url = safeUrl(s['url']);
    if (url == null) continue;
    final id = cleanText(s['channel'], 100);
    if (id != null && hidden.contains(id)) continue;
    final title = cleanText(s['title']);
    final Channel ch;
    if (id != null && info.containsKey(id)) {
      ch = byKey.putIfAbsent(id, () => makeChannel(id));
    } else {
      final name = title ?? id ?? Uri.parse(url).host;
      ch = byKey.putIfAbsent('title:$name', () => Channel(id: null, name: name));
    }
    ch.streams.add(StreamSource(
      url: url,
      title: title,
      quality: cleanText(s['quality'], 16),
      feed: cleanText(s['feed'], 40),
      userAgent: safeHeader(s['user_agent']),
      referrer: safeHeader(s['referrer']),
      labels: _strings(s['labels']),
    ));
  }

  final list = byKey.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final usedCountries = {for (final c in list) ?c.countryCode};
  return Catalog(
    channels: list,
    countryInfo: {for (final code in usedCountries) code: countries[code]!},
    categories: {for (final c in list) ...c.categories}.toList()..sort(),
    languages: {for (final c in list) ...c.languages}.toList()..sort(),
    regions: [for (final r in allRegions) if (r.countries.any(usedCountries.contains)) r],
    timezoneOffsets: timezoneOffsets,
    replacedBy: replacedBy,
    builtAt: DateTime.now().toUtc(),
  );
}
