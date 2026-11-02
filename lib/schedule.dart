import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'catalog.dart' show cleanText;
import 'data.dart' show cacheRoot;
import 'settings.dart';

/// Published daily by .github/workflows/schedules.yml (iptv-org's grabber).
const scheduleBase = String.fromEnvironment('SCHEDULE_BASE', defaultValue: 'https://ken-n7.github.io/reLiveTV/schedules'); // overridable for tests
final _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$');

class Programme {
  final DateTime start, stop; // UTC
  final String title;
  const Programme(this.start, this.stop, this.title);
}

/// One channel's schedule file → programmes, sorted. Malformed entries are skipped.
List<Programme> parseSchedule(String text) {
  final out = <Programme>[];
  final j = jsonDecode(text);
  final list = j is Map ? j['p'] : null;
  if (list is! List) return out;
  for (final p in list) {
    if (p is! List || p.length < 3 || p[0] is! int || p[1] is! int) continue;
    final title = cleanText(p[2], 120);
    if (title == null || (p[1] as int) <= (p[0] as int)) continue;
    out.add(
      Programme(
        DateTime.fromMillisecondsSinceEpoch((p[0] as int) * 1000, isUtc: true),
        DateTime.fromMillisecondsSinceEpoch((p[1] as int) * 1000, isUtc: true),
        title,
      ),
    );
  }
  return out..sort((a, b) => a.start.compareTo(b.start));
}

/// What's on at [t], what's next, and a few after that.
({Programme? now, Programme? next, List<Programme> later}) nowNext(List<Programme> ps, DateTime t, {int later = 4}) {
  final upcoming = ps.where((p) => p.stop.isAfter(t)).toList();
  final now = upcoming.isNotEmpty && !upcoming.first.start.isAfter(t) ? upcoming.first : null;
  final rest = now == null ? upcoming : upcoming.skip(1).toList();
  return (now: now, next: rest.firstOrNull, later: rest.skip(1).take(later).toList());
}

/// Wall-clock time of [utc] in a zone [offsetMinutes] from UTC; null = this device's zone.
DateTime wallClock(DateTime utc, int? offsetMinutes) => offsetMinutes == null ? utc.toLocal() : utc.toUtc().add(Duration(minutes: offsetMinutes));

/// Which zone schedule times are shown in: 'local' (device), 'channel', or an IANA id.
String get scheduleZone => prefs.getString('scheduleZone') ?? 'local';
set scheduleZone(String v) => prefs.setString('scheduleZone', v);

/// Fetches a channel's schedule only when it's watched; keeps it on the device until
/// its last programme ends. Channels without one are not asked again for 12 hours.
/// A channel's schedule in one language, plus the languages it is available in.
class ScheduleData {
  final List<Programme> programmes;
  final String? lang;
  final List<String> langs;
  const ScheduleData(this.programmes, {this.lang, this.langs = const []});
  static const empty = ScheduleData([]);
}

final _langCode = RegExp(r'^[a-z]{2,3}$');

/// One schedule file → [ScheduleData]. Older files have no "lang"/"langs" fields.
ScheduleData parseScheduleFile(String text) {
  final j = jsonDecode(text);
  final lang = j is Map && j['lang'] is String && _langCode.hasMatch(j['lang'] as String) ? j['lang'] as String : null;
  final langs = j is Map && j['langs'] is List
      ? [
          for (final l in j['langs'] as List)
            if (l is String && _langCode.hasMatch(l)) l,
        ]
      : <String>[];
  return ScheduleData(parseSchedule(text), lang: lang, langs: langs);
}

/// Language the viewer picked for schedules (null = each channel's default). Saved on the device.
String? get scheduleLang => prefs.getString('scheduleLang');
set scheduleLang(String? v) => v == null ? prefs.remove('scheduleLang') : prefs.setString('scheduleLang', v);

/// Which language file to fetch besides the default, if any: the viewer's choice
/// when this channel offers it and it isn't already the default.
String? extraLanguage(ScheduleData def, String? preferred) => preferred != null && preferred != def.lang && def.langs.contains(preferred) ? preferred : null;

/// Fetches a channel's schedule only when it's watched; keeps it on the device until
/// its last programme ends. Channels without one are not asked again for 12 hours.
class ScheduleStore {
  final _memory = <String, ScheduleData>{};
  final _none = <String, DateTime>{};
  static const _retryMissing = Duration(hours: 12), _maxBytes = 256 << 10;

  Future<Directory> _dir() async => Directory('${(await cacheRoot()).path}/schedules')..createSync(recursive: true);

  bool _fresh(ScheduleData d) => d.programmes.isNotEmpty && d.programmes.last.stop.isAfter(DateTime.now().toUtc());

  /// The default-language schedule, or the viewer's preferred language when available.
  Future<ScheduleData> load(String? channelId) async {
    if (channelId == null || !_safeId.hasMatch(channelId)) return ScheduleData.empty;
    final def = await _fetch('$channelId.json');
    final extra = extraLanguage(def, scheduleLang);
    if (extra == null) return def;
    final alt = await _fetch('$channelId.$extra.json');
    return alt.programmes.isEmpty ? def : alt;
  }

  Future<ScheduleData> _fetch(String name) async {
    final mem = _memory[name];
    if (mem != null && _fresh(mem)) return mem;
    final none = _none[name];
    if (none != null && DateTime.now().difference(none) < _retryMissing) return ScheduleData.empty;

    final file = File('${(await _dir()).path}/$name');
    if (file.existsSync()) {
      try {
        final d = parseScheduleFile(file.readAsStringSync());
        if (_fresh(d)) return _memory[name] = d;
      } catch (_) {}
    }
    try {
      final res = await http.get(Uri.parse('$scheduleBase/$name')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.bodyBytes.length <= _maxBytes) {
        final d = parseScheduleFile(res.body);
        if (_fresh(d)) {
          file.writeAsStringSync(res.body);
          return _memory[name] = d;
        }
      }
    } catch (_) {
      return ScheduleData.empty; // offline or slow: just no schedule this time
    }
    _none[name] = DateTime.now();
    return ScheduleData.empty;
  }

  /// Deletes schedules that have run out (called at start-up).
  Future<void> cleanUp() async {
    final now = DateTime.now().toUtc();
    for (final f in (await _dir()).listSync().whereType<File>()) {
      try {
        final ps = parseSchedule(f.readAsStringSync());
        if (ps.isEmpty || !ps.last.stop.isAfter(now)) f.deleteSync();
      } catch (_) {
        f.deleteSync();
      }
    }
  }
}

final schedules = ScheduleStore();

/// Language names in their own language, for the schedule's language menu.
const _languageNames = {
  'en': 'English',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
  'it': 'Italiano',
  'pt': 'Português',
  'ru': 'Русский',
  'uk': 'Українська',
  'pl': 'Polski',
  'nl': 'Nederlands',
  'ro': 'Română',
  'cs': 'Čeština',
  'sk': 'Slovenčina',
  'hu': 'Magyar',
  'el': 'Ελληνικά',
  'tr': 'Türkçe',
  'ar': 'العربية',
  'he': 'עברית',
  'fa': 'فارسی',
  'hi': 'हिन्दी',
  'bn': 'বাংলা',
  'ta': 'தமிழ்',
  'te': 'తెలుగు',
  'zh': '中文',
  'ja': '日本語',
  'ko': '한국어',
  'th': 'ไทย',
  'vi': 'Tiếng Việt',
  'id': 'Bahasa Indonesia',
  'ms': 'Bahasa Melayu',
  'tl': 'Filipino',
  'sv': 'Svenska',
  'da': 'Dansk',
  'no': 'Norsk',
  'fi': 'Suomi',
  'hr': 'Hrvatski',
  'sr': 'Српски',
  'bs': 'Bosanski',
  'sl': 'Slovenščina',
  'bg': 'Български',
  'sq': 'Shqip',
  'mk': 'Македонски',
  'lt': 'Lietuvių',
  'lv': 'Latviešu',
  'et': 'Eesti',
  'ka': 'ქართული',
  'hy': 'Հայերեն',
  'az': 'Azərbaycanca',
  'kk': 'Қазақ',
  'ca': 'Català',
};

String languageName(String code) => _languageNames[code] ?? code.toUpperCase();
