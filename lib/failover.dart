import 'catalog.dart';

/// Order to try a channel's sources: playable-here first (not geo-blocked), 24/7
/// before part-time, higher quality first; sources that failed on this device in
/// the last day go last (never removed — they may be back).
List<int> orderSources(List<StreamSource> sources, Set<String> recentlyFailed) {
  int height(StreamSource s) => int.tryParse(RegExp(r'\d+').stringMatch(s.quality ?? '') ?? '') ?? 0;
  int rank(StreamSource s) => (recentlyFailed.contains(s.url) ? 4 : 0) + (s.geoBlocked ? 2 : 0) + (s.part247 ? 1 : 0);
  final order = [for (var i = 0; i < sources.length; i++) i];
  order.sort((a, b) {
    final r = rank(sources[a]) - rank(sources[b]);
    if (r != 0) return r;
    final h = height(sources[b]) - height(sources[a]);
    return h != 0 ? h : a - b; // stable: iptv-org order breaks ties
  });
  return order;
}

sealed class FailoverStep {}

/// Try the same source again after [delay].
class RetrySame extends FailoverStep {
  final Duration delay;
  RetrySame(this.delay);
}

/// Move on to source [index] (into the channel's stream list).
class NextSource extends FailoverStep {
  final int index;
  NextSource(this.index);
}

/// Every source failed every attempt.
class GiveUp extends FailoverStep {}

/// Decides what to do after a failed attempt. A slow or flaky first response is
/// not enough to call a stream dead: each source gets [attemptsPerSource] tries
/// with growing pauses before the next source is tried.
class Failover {
  static const attemptsPerSource = 3;
  static const backoff = [Duration(seconds: 2), Duration(seconds: 5)];

  final List<int> order;
  int _pos = 0;
  int attempt = 1;
  Failover(this.order);

  int get current => order[_pos];
  int get sourceNumber => _pos + 1; // 1-based, for "source 2 of 3"

  /// Playback is working again: a later stall gets fresh attempts.
  void succeeded() => attempt = 1;

  FailoverStep failed() {
    if (attempt < attemptsPerSource) return RetrySame(backoff[attempt++ - 1]);
    if (_pos + 1 >= order.length) return GiveUp();
    _pos++;
    attempt = 1;
    return NextSource(current);
  }

  /// User picked a source by hand: continue from there.
  void jumpTo(int index) {
    final p = order.indexOf(index);
    if (p >= 0) _pos = p;
    attempt = 1;
  }
}
