// Drives the real app on the laptop. Run:
//   flutter test integration_test -d linux
// Screenshots: add --dart-define=SHOT_DIR=/some/dir to save PNGs of each checkpoint.
// Any layout overflow fails the test.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tv_channels/main.dart' as app;
import 'package:tv_channels/player.dart';

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
final rowCard = find.descendant(of: find.byType(app.ChannelRow), matching: find.byType(app.ChannelCard));

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
  });
}
