import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'catalog.dart';
import 'layout.dart';
import 'main.dart' show MyListButton, card, channelSubtitle;
import 'motion.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// One player for the whole app, so playback survives leaving the channel
/// page and continues in the mini player.
class Playback extends ChangeNotifier {
  late final player = Player(); // created on first play, after MediaKit init
  late final video = VideoController(player);
  Channel? channel;
  int streamIndex = 0;
  String? error;
  List<VideoTrack> qualities = []; // one per HLS variant, highest first
  VideoTrack? quality; // null = auto
  bool mini = false;
  bool _listening = false;

  void _listen() {
    if (_listening) return;
    _listening = true;
    player.stream.error.listen((e) {
      error = e;
      notifyListeners();
    });
    // mpv also reports non-fatal errors (a bad segment, a subtitle track); if playback moves, it works
    player.stream.position.listen((_) {
      if (error == null) return;
      error = null;
      notifyListeners();
    });
    player.stream.tracks.listen((t) {
      // mpv lists each HLS variant as its own video track; keep the best bitrate per height
      final byHeight = <int, VideoTrack>{};
      for (final v in t.video) {
        if (v.h == null) continue; // skips the "auto"/"no" pseudo-tracks
        final prev = byHeight[v.h!];
        if (prev == null || (v.bitrate ?? 0) > (prev.bitrate ?? 0)) byHeight[v.h!] = v;
      }
      qualities = byHeight.values.toList()..sort((a, b) => b.h! - a.h!);
      notifyListeners();
    });
  }

  void play(Channel c, [int index = 0]) {
    _listen();
    channel = c;
    streamIndex = index;
    error = null;
    qualities = [];
    quality = null;
    notifyListeners();
    if (c.streams.isEmpty) {
      player.stop();
      return;
    }
    final s = c.streams[index];
    player.open(Media(s.url, httpHeaders: s.headers));
  }

  void setQuality(VideoTrack? q) {
    quality = q;
    player.setVideoTrack(q ?? VideoTrack.auto());
    notifyListeners();
  }

  void setMini(bool v) {
    mini = v && channel != null;
    notifyListeners();
  }

  void close() {
    channel = null;
    mini = false;
    player.stop();
    notifyListeners();
  }
}

final playback = Playback();

/// Opens the watch page for [c], starting it unless it's already playing.
/// [from] is the on-screen rect of what was tapped (a card); the page grows
/// out of it. Without it, the page grows out of the mini player.
void openChannel(Channel c, {Rect? from}) {
  if (playback.channel != c) playback.play(c);
  playback.setMini(false);
  navigatorKey.currentState!.push(_GrowRoute(from));
}

const _miniMargin = 12.0, _miniBarHeight = 48.0;

/// Where the mini player sits: bottom right, above the bottom bar when there is one.
Rect miniRect(BuildContext context) {
  final mq = MediaQuery.of(context);
  final w = min(mq.size.width * 0.6, 360.0);
  final h = w * 9 / 16 + _miniBarHeight;
  final bottom = _miniMargin + max(bottomBarHeight(context), mq.padding.bottom);
  return Rect.fromLTWH(mq.size.width - _miniMargin - w, mq.size.height - bottom - h, w, h);
}

/// YouTube-style watch page route: grows out of [from] (or the mini player)
/// and always shrinks back into the mini player, video corner pinned to
/// the target's corner so the video visibly becomes the mini player.
class _GrowRoute extends PageRoute<void> {
  final Rect? from;
  _GrowRoute(this.from);

  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration => Durations.medium4; // growing: 400 ms
  @override
  Duration get reverseTransitionDuration => Durations.medium2; // shrinking: 300 ms

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => const PlayerPage();

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) return child;
    final curved = CurvedAnimation(parent: animation, curve: Easing.emphasizedDecelerate, reverseCurve: Easing.emphasizedAccelerate);
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final shrinking = animation.status == AnimationStatus.reverse;
        final target = shrinking || from == null ? miniRect(context) : from!;
        final t = curved.value;
        final s0 = (target.width / mq.size.width).clamp(0.05, 0.95);
        final scale = s0 + (1 - s0) * t;
        // the page's video starts at (0, top inset); at t=0 that corner sits on the target's corner
        final start = target.topLeft - Offset(0, s0 * mq.padding.top);
        final shift = start * (1 - t);
        return Transform(
          transform: Matrix4.translationValues(shift.dx, shift.dy, 0)..multiply(Matrix4.diagonal3Values(scale, scale, 1)),
          child: Opacity(
            opacity: (t / 0.35).clamp(0.0, 1.0), // invisible while tiny, so the card/mini player reads as the source
            child: ClipRRect(borderRadius: BorderRadius.circular(12 * (1 - t)), child: child),
          ),
        );
      },
    );
  }
}

/// Leaves the watch page; playback continues in the mini player.
void minimize(BuildContext pageContext) => Navigator.of(pageContext).maybePop();

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 8),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
    child: const Text(
      '● LIVE',
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
    ),
  );
}

void showQualitySheet() {
  showModalBottomSheet(
    context: navigatorKey.currentContext!,
    backgroundColor: const Color(0xFF212121),
    builder: (sheet) => ListenableBuilder(
      listenable: playback,
      builder: (_, _) {
        Widget option(String label, VideoTrack? q) => ListTile(
          leading: Icon(playback.quality == q ? Icons.check : null),
          title: Text(label),
          onTap: () {
            playback.setQuality(q);
            Navigator.pop(sheet);
          },
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Quality', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              option('Auto', null),
              for (final q in playback.qualities) option('${q.h}p', q),
              if (playback.qualities.length < 2)
                const ListTile(
                  dense: true,
                  title: Text('This stream has only one quality.', style: TextStyle(color: Colors.white54)),
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// YouTube-style watch page: video on top (theater width), details below.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _videoKey = GlobalKey<VideoState>();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // any way of leaving (back button, chevron, i key) shrinks to the mini player
      onPopInvokedWithResult: (didPop, _) => didPop ? playback.setMini(true) : null,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: playback,
            builder: (context, _) {
              final c = playback.channel;
              if (c == null) return const SizedBox.shrink();
              final maxVideoHeight = MediaQuery.sizeOf(context).height * 0.7;
              return ListView(
                children: [
                  // full width on phones; on wide screens capped at 70% height (theater mode)
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxVideoHeight),
                      child: AspectRatio(aspectRatio: 16 / 9, child: _video(context, c)),
                    ),
                  ),
                  Center(
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: _details(c)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _video(BuildContext context, Channel c) {
    final chevron = MaterialCustomButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => minimize(context));
    final gear = MaterialCustomButton(icon: const Icon(Icons.settings_outlined), onPressed: showQualitySheet);
    final mobile = MaterialVideoControlsThemeData(
      displaySeekBar: false, // live TV: nothing to seek
      seekGesture: false,
      seekOnDoubleTap: false,
      speedUpOnLongPress: false,
      volumeGesture: false,
      brightnessGesture: false,
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
      topButtonBar: [chevron, const Spacer(), gear],
      primaryButtonBar: const [Spacer(), MaterialPlayOrPauseButton(iconSize: 56), Spacer()],
      bottomButtonBar: const [LiveBadge(), Spacer(), MaterialFullscreenButton()],
    );
    final mobileFull = mobile.copyWith(topButtonBar: [const Spacer(), gear]);

    final desktop = MaterialDesktopVideoControlsThemeData(
      displaySeekBar: false,
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
      topButtonBar: [MaterialDesktopCustomButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => minimize(context))],
      bottomButtonBar: [
        const MaterialDesktopPlayOrPauseButton(),
        const MaterialDesktopVolumeButton(),
        const LiveBadge(),
        const Spacer(),
        MaterialDesktopCustomButton(icon: const Icon(Icons.settings_outlined), onPressed: showQualitySheet),
        MaterialDesktopCustomButton(icon: const Icon(Icons.picture_in_picture_alt_outlined), onPressed: () => minimize(context)),
        const MaterialDesktopFullscreenButton(),
      ],
      // YouTube keys, minus seeking
      keyboardShortcuts: {
        const SingleActivator(LogicalKeyboardKey.space): () => playback.player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.keyK): () => playback.player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () => playback.player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.keyM): () => playback.player.setVolume(playback.player.state.volume > 0 ? 0 : 100),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => playback.player.setVolume(min(100, playback.player.state.volume + 5)),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => playback.player.setVolume(max(0, playback.player.state.volume - 5)),
        const SingleActivator(LogicalKeyboardKey.keyF): () => _videoKey.currentState?.toggleFullscreen(),
        const SingleActivator(LogicalKeyboardKey.escape): () => _videoKey.currentState?.exitFullscreen(),
        const SingleActivator(LogicalKeyboardKey.keyI): () {
          if (_videoKey.currentState?.isFullscreen() ?? false) return;
          minimize(context);
        },
      },
    );
    final desktopFull = desktop.copyWith(topButtonBar: const []);

    return MaterialVideoControlsTheme(
      normal: mobile,
      fullscreen: mobileFull,
      child: MaterialDesktopVideoControlsTheme(
        normal: desktop,
        fullscreen: desktopFull,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(key: _videoKey, controller: playback.video),
            if (c.streams.isEmpty)
              const IgnorePointer(
                child: ColoredBox(
                  color: Colors.black87,
                  child: Center(child: Text('No streams for this channel.')),
                ),
              )
            else if (playback.error != null)
              IgnorePointer(
                child: Container(
                  color: Colors.black87,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(16),
                  child: Text('This stream is not working right now.${c.streams.length > 1 ? '\nTry another source below.' : ''}', textAlign: TextAlign.center),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _details(Channel c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(channelSubtitle(c), style: const TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: card, shape: BoxShape.circle),
                child: c.logo == null
                    ? const Icon(Icons.live_tv, size: 20)
                    : ClipOval(
                        child: Image.network(c.logo!, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.live_tv, size: 20)),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  c.network ?? c.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              MyListButton(c),
            ],
          ),
          if (c.streams.length > 1) ...[
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < c.streams.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('Source ${i + 1}${c.streams[i].quality == null ? '' : ' · ${c.streams[i].quality}'}'),
                        selected: playback.streamIndex == i,
                        onSelected: (_) => playback.play(c, i),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Floating player shown above every screen while a channel is minimized.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context) {
    final r = miniRect(context);
    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      child: ListenableBuilder(
        listenable: playback,
        builder: (context, _) {
          final c = playback.channel;
          final show = playback.mini && c != null;
          // a plain fade: the watch page itself shrinks into / grows out of this spot
          return AnimatedSwitcher(
            duration: motion(context, Durations.short4),
            switchInCurve: Easing.emphasizedDecelerate,
            switchOutCurve: Easing.emphasizedAccelerate,
            child: show ? _MiniCard(c, key: const ValueKey('mini')) : const SizedBox.shrink(key: ValueKey('none')),
          );
        },
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final Channel c;
  const _MiniCard(this.c, {super.key});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: card,
      elevation: 12,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => openChannel(c),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Video(controller: playback.video, controls: NoVideoControls),
            ),
          ),
          // fixed height so miniRect (the shrink animation's target) matches on every screen density
          SizedBox(
            height: _miniBarHeight,
            child: Row(
              children: [
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => openChannel(c),
                    child: Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                StreamBuilder<bool>(
                  stream: playback.player.stream.playing,
                  initialData: playback.player.state.playing,
                  builder: (_, snap) => IconButton(icon: Icon(snap.data! ? Icons.pause : Icons.play_arrow), onPressed: playback.player.playOrPause),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: playback.close),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
