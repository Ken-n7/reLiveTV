// Drives the real app on the laptop. Run:
//   flutter test integration_test -d linux
// Screenshots: add --dart-define=SHOT_DIR=/some/dir to save PNGs of each checkpoint.
// Any layout overflow fails the test.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tv_channels/catalog.dart';
import 'package:tv_channels/discover.dart';
import 'package:tv_channels/failover.dart';
import 'package:tv_channels/main.dart' as app;
import 'package:tv_channels/player.dart';
import 'package:tv_channels/schedule.dart';
import 'package:tv_channels/schedule_view.dart';
import 'package:tv_channels/settings.dart';

Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 90}) async {
  for (var i = 0; i < seconds * 5; i++) {
    await t.pump();
    if (f.evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('timed out waiting for $f');
}

/// Real-time wait that keeps frames coming.
Future<void> wait(WidgetTester t, int ms) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

const shotDir = String.fromEnvironment('SHOT_DIR');

/// Saves the app's current frame as SHOT_DIR/name.png (no-op without SHOT_DIR).
Future<void> capture(WidgetTester t, String name) async {
  if (shotDir.isEmpty) return;
  await t.pump();
  final view = t.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final image = await layer.toImage(Offset.zero & view.size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File('$shotDir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
}

/// Screenshot without waiting for animations (for mid-animation frames).
Future<void> mark(WidgetTester t, String name) => capture(t, name);

Future<void> shot(WidgetTester t, String name) async {
  await wait(t, 1200); // let animations settle
  await capture(t, name);
}

/// Renders the app at [size] logical pixels (scaled to fit the real window).
Future<void> resize(WidgetTester t, Size size) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  await wait(t, 800);
}

/// Cards in Discover's rows (the hidden Home grid has cards too).
final rowCard = find.descendant(of: find.byType(ChannelRow), matching: find.byType(app.ChannelCard));

final miniCard = find.descendant(of: find.byType(MiniPlayer), matching: find.byType(Material)).first;

/// Opens the first visible channel card, then minimizes it into the mini player.
Future<void> openAndMinimize(WidgetTester t) async {
  await t.tap(rowCard.hitTestable().first);
  await waitFor(t, find.byType(PlayerPage));
  await wait(t, 1500);
  navigatorKey.currentState!.maybePop();
  await waitFor(t, miniCard);
  await wait(t, 1000);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('responsive layout, grow/shrink player, mini player placement', (t) async {
    addTearDown(() {
      t.view.reset();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      timeDilation = 1;
    });
    await resize(t, const Size(1300, 760)); // expanded: like the laptop window
    app.main();
    await waitFor(t, find.byIcon(Icons.explore_outlined));
    await t.tap(find.byIcon(Icons.explore_outlined));
    await waitFor(t, find.text('News'));

    // ---- expanded (≥ 1200): side rail, 280 px cards
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(t.getSize(rowCard.first).width, 280);
    expect(find.text('Play'), findsNothing, reason: 'featured banner removed');
    await shot(t, 'expanded');

    // grow out of a card, shrink into the mini player (slowed 8x to capture)
    timeDilation = 8;
    await t.tap(rowCard.hitTestable().first);
    await wait(t, 900);
    await mark(t, 'grow-mid');
    await wait(t, 3000);
    expect(find.byType(PlayerPage), findsOneWidget);
    navigatorKey.currentState!.maybePop();
    await wait(t, 700);
    await mark(t, 'shrink-mid');
    await wait(t, 3000);
    timeDilation = 1;
    expect(playback.mini, isTrue);
    // no bottom bar on wide windows: mini player sits in the corner
    final screen = t.view.physicalSize;
    expect(screen.height - t.getRect(miniCard).bottom, closeTo(12, 1));
    await shot(t, 'expanded-mini');
    playback.close();

    // ---- medium (600–1199): still a rail, 240 px cards
    await resize(t, const Size(900, 700));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(t.getSize(rowCard.first).width, 240);
    await shot(t, 'medium');

    // ---- compact (< 600): bottom bar, 220 px cards, mini player above the bar
    await resize(t, const Size(400, 760));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(t.getSize(rowCard.first).width, 220);
    await shot(t, 'compact');
    await openAndMinimize(t);
    final bar = t.getRect(find.byType(NavigationBar));
    expect(bar.top - t.getRect(miniCard).bottom, closeTo(12, 1), reason: 'mini player clears the bottom bar');
    await shot(t, 'compact-mini');
    playback.close();

    // ---- large text (accessibility): cards grow instead of overflowing
    t.platformDispatcher.textScaleFactorTestValue = 2;
    await wait(t, 800);
    await shot(t, 'compact-bigtext');
    await resize(t, const Size(1300, 760));
    await shot(t, 'expanded-bigtext');
    // reaching here without a "RenderFlex overflowed" error is the check
    t.platformDispatcher.clearTextScaleFactorTestValue();

    // ---- failover: a dead source (connection refused) is retried 3x, then the next source
    const dead = 'http://127.0.0.1:9/dead.m3u8';
    await prefs.remove('failedStreams'); // earlier runs remembered the dead URL (tried last for 24 h)
    final real = app.store.catalog.value!.channels.firstWhere((c) => c.id == 'PremierSports2.ph', orElse: () => app.store.catalog.value!.channels.first);
    final mixed = Channel(id: null, name: 'Failover test', streams: [StreamSource(url: dead, quality: '2160p'), ...real.streams]);
    openChannel(mixed);
    final seen = <String>{};
    for (var i = 0; i < 90 && playback.sourceNumber < 2; i++) {
      seen.add('${playback.status.name} ${playback.attempt}');
      await wait(t, 500);
    }
    expect(seen, containsAll(['retrying 2', 'retrying 3']), reason: 'retried the dead source before moving on');
    expect(playback.sourceNumber, 2, reason: 'moved to the next source');
    expect(recentlyFailed(), contains(dead), reason: 'remembered on this device');
    expect(orderSources(mixed.streams, recentlyFailed()).last, 0, reason: 'so next time it is tried last');
    await shot(t, 'failover-next');
    for (var i = 0; i < 40 && playback.status != PlayStatus.playing; i++) {
      await wait(t, 500);
    }
    // ignore: avoid_print
    print('real source after failover: ${playback.status.name}');
    navigatorKey.currentState!.maybePop();
    await wait(t, 800);
    playback.close();

    // ---- only dead sources: ends with a clear message and Try again
    openChannel(Channel(id: null, name: 'Dead test', streams: [StreamSource(url: dead)]));
    for (var i = 0; i < 90 && playback.status != PlayStatus.failed; i++) {
      await wait(t, 500);
    }
    expect(playback.status, PlayStatus.failed);
    await waitFor(t, find.text('Try again'));
    expect(find.textContaining("isn't responding"), findsOneWidget);
    await shot(t, 'failed');
    navigatorKey.currentState!.maybePop();
    await wait(t, 800);
    playback.close();

    // ---- leaving the app: background play off → pause and resume; on → keep playing
    // while hidden Flutter draws no frames, so wait on the clock, not on pump()
    Future<void> leave() async {
      for (final st in [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
        t.binding.handleAppLifecycleStateChanged(st);
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    Future<void> comeBack() async {
      for (final st in [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        t.binding.handleAppLifecycleStateChanged(st);
      }
      await wait(t, 1500);
    }
    openChannel(real);
    for (var i = 0; i < 60 && playback.status != PlayStatus.playing; i++) {
      await wait(t, 500);
    }
    if (playback.status == PlayStatus.playing) {
      expect(backgroundPlay.value, isFalse, reason: 'off by default');
      await leave();
      expect(playback.player.state.playing, isFalse, reason: 'paused when the app is hidden');
      await Future<void>.delayed(const Duration(seconds: 17)); // longer than the stall limit: must not count as a failure
      expect(playback.status, PlayStatus.playing);
      await comeBack();
      expect(playback.player.state.playing, isTrue, reason: 'resumes on return');
      backgroundPlay.value = true;
      await leave();
      expect(playback.player.state.playing, isTrue, reason: 'background play keeps going');
      await comeBack();
      backgroundPlay.value = false;
    } else {
      // ignore: avoid_print
      print('SKIPPED background checks: real stream did not start (${playback.status.name})');
    }
    navigatorKey.currentState!.maybePop();
    await wait(t, 800);
    playback.close();

    // ---- Discover = browse + search in one screen
    final discover = find.byType(DiscoverScreen);
    final searchField = find.descendant(of: discover, matching: find.byType(TextField));
    expect(find.byTooltip('Search'), findsNothing, reason: 'separate search page is gone');
    await t.enterText(searchField, 'news');
    await wait(t, 800);
    expect(find.textContaining(RegExp(r'^\d+ channels?$')), findsOneWidget);
    await shot(t, 'search');

    // Esc clears the search, rows come back
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await wait(t, 800);
    expect(find.byType(ChannelRow), findsWidgets);

    // "See all" applies that category
    await t.tap(find.textContaining('See all').first);
    await wait(t, 800);
    expect(find.text('Clear all'), findsOneWidget);
    await t.tap(find.text('Clear all'));
    await wait(t, 800);

    // Country picker: searchable, filters the results
    await t.tap(find.text('Country'));
    await waitFor(t, find.text('Country or region'));
    await t.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)), 'philipp');
    await wait(t, 500);
    await shot(t, 'country-picker');
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining('Philippines')).first);
    await wait(t, 1000);
    final shown = t.widgetList<app.ChannelCard>(find.byType(app.ChannelCard).hitTestable());
    expect(shown, isNotEmpty);
    expect(shown.every((card) => card.c.countryCode == 'PH'), isTrue, reason: 'only Philippine channels');
    await shot(t, 'country-results');

    // no results: says so, with one tap to drop each filter
    await t.enterText(searchField, 'zzqqxx');
    await wait(t, 800);
    expect(find.textContaining('No channels match'), findsOneWidget);
    expect(find.byType(InputChip), findsNWidgets(2), reason: 'the query and the country');
    await shot(t, 'no-results');
    await t.tap(find.text('Clear all').last);
    await wait(t, 800);
    expect(find.byType(ChannelRow), findsWidgets);

    // keyboard: '/' focuses search; arrows move between cards with a visible focus ring
    FocusManager.instance.primaryFocus?.unfocus();
    await wait(t, 300);
    await t.sendKeyEvent(LogicalKeyboardKey.slash);
    await wait(t, 300);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>(), isNotNull, reason: '/ focuses search');
    app.ChannelCard? focusedCard() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<app.ChannelCard>();
    for (var i = 0; i < 12 && focusedCard() == null; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await wait(t, 150);
    }
    final first = focusedCard();
    expect(first, isNotNull, reason: 'Tab reaches the cards');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await wait(t, 400);
    expect(focusedCard(), isNotNull);
    expect(focusedCard()!.c, isNot(first!.c), reason: 'arrow keys move to the next card');
    await shot(t, 'focus');

    // screen readers: a card is one item with its name and details
    final sem = t.ensureSemantics();
    final label = t.getSemantics(find.byType(app.ChannelCard).hitTestable().first).label;
    expect(label, contains(t.widget<app.ChannelCard>(find.byType(app.ChannelCard).hitTestable().first).c.name));
    sem.dispose();
    FocusManager.instance.primaryFocus?.unfocus();

    // ---- watch page layouts + schedule panel (schedule served by a local test server)
    if (const String.fromEnvironment('SCHEDULE_BASE').isNotEmpty) {
      final cat = app.store.catalog.value!;
      final smni = cat.channels.where((c) => c.id == 'SMNI.ph').firstOrNull;
      if (smni != null) {
        theater.value = false;
        scheduleZone = 'local'; // a previous run may have left another choice saved
        await resize(t, const Size(1300, 760));
        openChannel(smni);
        await waitFor(t, find.text('Test show now'), seconds: 20);
        expect(find.textContaining('LIVE'), findsWidgets);
        expect(find.text('Test show next'), findsOneWidget);
        expect(find.textContaining('Times: My time'), findsOneWidget);
        final screen = t.view.physicalSize;
        Rect videoRect() => t.getRect(find.descendant(of: find.byType(PlayerPage), matching: find.byType(Video)).first);
        Rect nameRect() => t.getRect(find.descendant(of: find.byType(PlayerPage), matching: find.text('SMNI')).first);
        final panel = find.byType(SchedulePanel);
        // side by side: info fits under the video, schedule panel to the right
        expect(nameRect().bottom, lessThanOrEqualTo(screen.height), reason: 'info fits, no scrolling');
        expect(t.getRect(panel).left, greaterThanOrEqualTo(videoRect().right - 1), reason: 'schedule on the right');
        final normalWidth = videoRect().width;
        await shot(t, 'watch-wide');

        // theater (T key on the focused player): video full width, info + schedule below, still fits
        await t.tap(find.descendant(of: find.byType(PlayerPage), matching: find.byType(Video)).first);
        await wait(t, 300);
        await t.sendKeyEvent(LogicalKeyboardKey.keyT);
        await wait(t, 1000);
        expect(theater.value, isTrue, reason: 'T toggles theater mode');
        expect(videoRect().width, greaterThan(normalWidth * 1.1), reason: 'theater video is clearly bigger');
        expect(nameRect().bottom, lessThanOrEqualTo(screen.height));
        expect(t.getRect(panel).top, greaterThanOrEqualTo(videoRect().bottom - 1), reason: 'schedule below the video');
        await shot(t, 'watch-theater');
        theater.value = false;

        // phone held sideways: info moves into the side panel
        await resize(t, const Size(780, 360));
        expect(nameRect().left, greaterThanOrEqualTo(videoRect().right - 1), reason: 'info in the side panel');
        await shot(t, 'watch-landscape-phone');

        // portrait: video pinned while the schedule scrolls
        await resize(t, const Size(400, 760));
        final before = videoRect();
        await t.drag(find.descendant(of: find.byType(PlayerPage), matching: find.byType(ListView)).first, const Offset(0, -300));
        await wait(t, 500);
        expect(videoRect(), before, reason: 'video stays put');
        await shot(t, 'watch-portrait');
        await resize(t, const Size(1300, 760));

        // time zone switch
        await t.tap(find.textContaining('Times: My time'));
        await waitFor(t, find.text("Channel's time"));
        await wait(t, 800); // let the sheet finish sliding up before tapping
        await t.tap(find.text("Channel's time"));
        await wait(t, 800);
        expect(find.textContaining("Times: Channel's time (Manila)"), findsOneWidget);
        scheduleZone = 'local';

        // a channel with no schedule says so
        final other = cat.channels.firstWhere((c) => c.id != null && c.id != 'SMNI.ph' && c.streams.isNotEmpty);
        openChannel(other);
        await waitFor(t, find.text('No schedule available'), seconds: 20);
        await shot(t, 'watch-no-schedule');
        navigatorKey.currentState!.popUntil((r) => r.isFirst); // two watch pages were opened
        await wait(t, 800);
        playback.close();
      }
    }

    // ---- settings sheet
    await t.tap(find.byTooltip('Settings').hitTestable().first);
    await waitFor(t, find.text('Background play'));
    await shot(t, 'settings');
    await t.tap(find.text('Background play'));
    await wait(t, 500);
    expect(backgroundPlay.value, isTrue);
    expect(prefs.getBool('backgroundPlay'), isTrue, reason: 'saved on the device');
    await t.tap(find.text('Background play'));
    await wait(t, 500);
    expect(backgroundPlay.value, isFalse);
  });
}
