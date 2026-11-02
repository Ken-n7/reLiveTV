import 'package:flutter_test/flutter_test.dart';
import 'package:tv_channels/catalog.dart';
import 'package:tv_channels/failover.dart';

StreamSource s(String url, {String? q, List<String> labels = const []}) => StreamSource(url: url, quality: q, labels: labels);

void main() {
  test('sources: playable here, 24/7, higher quality first; recent failures last', () {
    final sources = [
      s('a', q: '480p'),
      s('geo', q: '1080p', labels: ['Geo-blocked']),
      s('b', q: '1080p'),
      s('part', q: '720p', labels: ['Not 24/7']),
      s('failed', q: '2160p'),
    ];
    expect(orderSources(sources, {'failed'}), [2, 0, 3, 1, 4]);
  });

  test('3 attempts per source with backoff, then next source, then give up', () {
    final f = Failover([2, 0]);
    expect(f.current, 2);
    final steps = [for (var i = 0; i < 6; i++) f.failed()];
    expect(steps[0], isA<RetrySame>().having((r) => r.delay, 'delay', const Duration(seconds: 2)));
    expect(steps[1], isA<RetrySame>().having((r) => r.delay, 'delay', const Duration(seconds: 5)));
    expect(steps[2], isA<NextSource>().having((n) => n.index, 'index', 0));
    expect(f.sourceNumber, 2);
    expect(steps[3], isA<RetrySame>());
    expect(steps[4], isA<RetrySame>());
    expect(steps[5], isA<GiveUp>());
  });

  test('working playback resets attempts; manual pick continues from there', () {
    final f = Failover([0, 1, 2]);
    f.failed();
    f.failed();
    f.succeeded();
    expect(f.failed(), isA<RetrySame>(), reason: 'fresh attempts after it worked');
    f.jumpTo(2);
    expect(f.current, 2);
    expect(f.attempt, 1);
    for (var i = 0; i < 2; i++) {
      f.failed();
    }
    expect(f.failed(), isA<GiveUp>(), reason: 'source 2 was last in order');
  });
}
