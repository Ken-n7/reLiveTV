// TV mode driven only with remote keys (arrows + Select). Run on the laptop:
//   flutter test integration_test/tv_test.dart -d linux --dart-define=FORCE_TV=true
// Add --dart-define=SHOT_DIR=/some/dir for screenshots.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tv_channels/main.dart' as app;
import 'package:tv_channels/platform.dart';
import 'package:tv_channels/player.dart';

Future<void> wait(WidgetTester t, int ms) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 90}) async {
  for (var i = 0; i < seconds * 5; i++) {
    await t.pump();
    if (f.evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('timed out waiting for $f');
}

Future<void> shot(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('SHOT_DIR');
  await wait(t, 1200);
  if (dir.isEmpty) return;
  final view = t.binding.renderViews.first;
  final image = await (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size);
  File('$dir/$name.png').writeAsBytesSync((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
}

Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k, platform: 'android'); // a TV remote sends Android key events
  await wait(t, 400);
}

app.ChannelCard? focusedCard() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<app.ChannelCard>();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TV: everything reachable with arrows and Select', (t) async {
    expect(isTv, isTrue, reason: 'run with --dart-define=FORCE_TV=true');
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1280, 720); // a TV's 720p logical screen
    addTearDown(t.view.reset);
    app.main();
    await waitFor(t, find.byType(app.ChannelCard).hitTestable().evaluate().isEmpty ? find.byIcon(Icons.explore_outlined) : find.byType(app.ChannelCard));
    await shot(t, 'tv-home');

    // Discover tab (Home may hold saved channels, which would confuse the card checks)
    await t.tap(find.byIcon(Icons.explore_outlined));
    await waitFor(t, find.text('Discover'));
    await wait(t, 800);

    // nothing focused: an arrow key lands somewhere, more arrows reach the cards
    FocusManager.instance.primaryFocus?.unfocus();
    await key(t, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus, isNot(FocusManager.instance.rootScope), reason: 'an arrow key lands focus somewhere');
    for (var i = 0; i < 20 && focusedCard() == null; i++) {
      await key(t, LogicalKeyboardKey.arrowDown);
    }
    final first = focusedCard();
    expect(first, isNotNull, reason: 'arrows reach the channel cards');
    await key(t, LogicalKeyboardKey.arrowRight);
    final second = focusedCard();
    expect(second, isNotNull, reason: 'right stays on cards');
    expect(second!.c, isNot(first!.c), reason: 'right moves to the next card');
    await shot(t, 'tv-focus');

    // left from the first card of a row reaches the side rail
    await key(t, LogicalKeyboardKey.arrowLeft);
    var reachedRail = false;
    for (var i = 0; i < 4 && !reachedRail; i++) {
      await key(t, LogicalKeyboardKey.arrowLeft);
      reachedRail = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<NavigationRail>() != null;
    }
    expect(reachedRail, isTrue, reason: 'left reaches the navigation rail');
    // back to content: right leaves the rail (to whatever is nearest), down reaches the cards
    await key(t, LogicalKeyboardKey.arrowRight);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<NavigationRail>(), isNull, reason: 'right leaves the rail');
    for (var i = 0; i < 6 && focusedCard() == null; i++) {
      await key(t, LogicalKeyboardKey.arrowDown);
    }
    expect(focusedCard(), isNotNull, reason: 'and down reaches the cards again');

    // Select opens the channel
    await key(t, LogicalKeyboardKey.select);
    await waitFor(t, find.byType(PlayerPage));
    for (var i = 0; i < 60 && playback.status != PlayStatus.playing; i++) {
      await wait(t, 500);
    }
    if (playback.status != PlayStatus.playing) {
      // the card the remote landed on may simply be down; use a channel that usually works
      final good = app.store.catalog.value!.channels.where((c) => c.id == 'PremierSports2.ph').firstOrNull;
      if (good != null) playback.play(good);
      for (var i = 0; i < 60 && playback.status != PlayStatus.playing; i++) {
        await wait(t, 500);
      }
    }
    await shot(t, 'tv-player');
    if (playback.status == PlayStatus.playing) {
      // Select toggles play/pause in the player
      await key(t, LogicalKeyboardKey.select);
      await wait(t, 600);
      expect(playback.player.state.playing, isFalse, reason: 'Select pauses');
      await key(t, LogicalKeyboardKey.select);
      await wait(t, 600);
      expect(playback.player.state.playing, isTrue, reason: 'Select plays again');
    } else {
      // ignore: avoid_print
      print('SKIPPED play/pause check: stream did not start (${playback.status.name})');
    }
    navigatorKey.currentState!.maybePop();
    await wait(t, 800);
    playback.close();
  });
}
