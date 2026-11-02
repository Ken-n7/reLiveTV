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
class ScheduleStore {
  final _memory = <String, List<Programme>>{};
  final _none = <String, DateTime>{};
  static const _retryMissing = Duration(hours: 12), _maxBytes = 256 << 10;

  Future<Directory> _dir() async => Directory('${(await cacheRoot()).path}/schedules')..createSync(recursive: true);

  bool _fresh(List<Programme> ps) => ps.isNotEmpty && ps.last.stop.isAfter(DateTime.now().toUtc());

  Future<List<Programme>> load(String? channelId) async {
    if (channelId == null || !_safeId.hasMatch(channelId)) return const [];
    final mem = _memory[channelId];
    if (mem != null && _fresh(mem)) return mem;
    final none = _none[channelId];
    if (none != null && DateTime.now().difference(none) < _retryMissing) return const [];

    final file = File('${(await _dir()).path}/$channelId.json');
    if (file.existsSync()) {
      try {
        final ps = parseSchedule(file.readAsStringSync());
        if (_fresh(ps)) return _memory[channelId] = ps;
      } catch (_) {}
    }
    try {
      final res = await http.get(Uri.parse('$scheduleBase/$channelId.json')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.bodyBytes.length <= _maxBytes) {
        final ps = parseSchedule(res.body);
        if (_fresh(ps)) {
          file.writeAsStringSync(res.body);
          return _memory[channelId] = ps;
        }
      }
    } catch (_) {
      return const []; // offline or slow: just no schedule this time
    }
    _none[channelId] = DateTime.now();
    return const [];
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
