import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_channels/schedule.dart';

int s(String iso) => DateTime.parse(iso).millisecondsSinceEpoch ~/ 1000;

void main() {
  final file = jsonEncode({
    'id': 'A.ph',
    'p': [
      [s('2026-11-02T11:00:00Z'), s('2026-11-02T12:00:00Z'), 'Next'],
      [s('2026-11-02T10:00:00Z'), s('2026-11-02T11:00:00Z'), 'Now\nshowing'],
      [s('2026-11-02T09:00:00Z'), s('2026-11-02T10:00:00Z'), 'Over'],
      [s('2026-11-02T12:00:00Z'), s('2026-11-02T12:00:00Z'), 'zero length'],
      ['bad', 1, 'x'],
      [s('2026-11-02T12:00:00Z'), s('2026-11-02T13:00:00Z'), 'Later 1'],
      [s('2026-11-02T13:00:00Z'), s('2026-11-02T14:00:00Z'), 'Later 2'],
    ],
  });

  test('parses, cleans and sorts; skips malformed entries', () {
    final ps = parseSchedule(file);
    expect([for (final p in ps) p.title], ['Over', 'Now showing', 'Next', 'Later 1', 'Later 2']);
    expect(parseSchedule('{"p": "nope"}'), isEmpty);
  });

  test('now, next and later at a moment', () {
    final r = nowNext(parseSchedule(file), DateTime.parse('2026-11-02T10:30:00Z'), later: 1);
    expect(r.now?.title, 'Now showing');
    expect(r.next?.title, 'Next');
    expect([for (final p in r.later) p.title], ['Later 1']);
    final gap = nowNext(parseSchedule(file), DateTime.parse('2026-11-02T08:00:00Z'));
    expect(gap.now, isNull, reason: 'nothing on yet');
    expect(gap.next?.title, 'Over');
  });

  test('times in a chosen zone', () {
    final utc = DateTime.parse('2026-11-02T12:30:00Z');
    final manila = wallClock(utc, 480);
    expect((manila.hour, manila.minute), (20, 30));
    final ny = wallClock(utc, -300);
    expect((ny.hour, ny.minute), (7, 30));
    expect(wallClock(utc, null), utc.toLocal(), reason: 'device time');
  });

  test('schedule languages', () {
    final d = parseScheduleFile(jsonEncode({'id': 'A.ph', 'lang': 'en', 'langs': ['en', 'tl', 'BAD!'], 'p': []}));
    expect(d.lang, 'en');
    expect(d.langs, ['en', 'tl'], reason: 'odd codes dropped');
    expect(parseScheduleFile(file).langs, isEmpty, reason: 'older files have no languages');
    expect(extraLanguage(d, null), isNull, reason: 'no preference: default only');
    expect(extraLanguage(d, 'en'), isNull, reason: 'preference is already the default');
    expect(extraLanguage(d, 'tl'), 'tl');
    expect(extraLanguage(d, 'ru'), isNull, reason: 'channel has no Russian listings');
    expect(languageName('tl'), 'Filipino');
    expect(languageName('xx'), 'XX');
  });
}
