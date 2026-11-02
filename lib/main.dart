import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'catalog.dart';
import 'data.dart';
import 'discover.dart';
import 'layout.dart';
import 'motion.dart';
import 'platform.dart';
import 'player.dart';
import 'schedule.dart';
import 'settings.dart';
import 'update.dart';

const appName = 'reLiveTV';

/// Set by release builds (--dart-define=APP_VERSION=1.2.0).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0-dev');
const bg = Color(0xFF141414);
const card = Color(0xFF2A2A2A);

/// The app name as shown in the top bars.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key});
  @override
  Widget build(BuildContext context) => const Text(
    appName,
    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.5),
  );
}

/// Keys of channels in My List, saved on the device.
final saved = ValueNotifier<Set<String>>({});

void toggleSaved(Channel c) {
  final next = {...saved.value};
  if (!next.remove(c.key)) next.add(c.key);
  saved.value = next;
  prefs.setStringList('saved', next.toList());
}

/// "+ My List" / "✓ My List" button that stays in sync everywhere.
class MyListButton extends StatelessWidget {
  final Channel c;
  const MyListButton(this.c, {super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: saved,
      builder: (context, keys, _) {
        final inList = keys.contains(c.key);
        // screen readers hear the state, not just "My List"
        return Semantics(
          toggled: inList,
          label: inList ? 'In My List' : 'Add to My List',
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white),
            onPressed: () => toggleSaved(c),
            icon: AnimatedSwitcher(
              duration: motion(context, Durations.short4),
              switchInCurve: Easing.emphasizedDecelerate,
              switchOutCurve: Easing.emphasizedAccelerate,
              transitionBuilder: (child, a) => ScaleTransition(
                scale: a,
                child: FadeTransition(opacity: a, child: child),
              ),
              child: Icon(inList ? Icons.check : Icons.add, key: ValueKey(inList)),
            ),
            label: const Text('My List'),
          ),
        );
      },
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await initSettings();
  saved.value = {...?prefs.getStringList('saved')};
  // decode logos at card size and keep the in-memory image cache modest
  PaintingBinding.instance.imageCache
    ..maximumSize = 300
    ..maximumSizeBytes = 50 << 20;
  store.catalog.addListener(_followRenames);
  unawaited(store.start());
  initPlatform();
  await detectTv();
  unawaited(schedules.cleanUp().then((_) {}, onError: (_) {})); // drop schedules that ran out
  // quiet daily check for a newer release (never blocks or nags; failures are ignored)
  unawaited(updates.check(appVersion).then((_) {}, onError: (_) {}));
  runApp(
    MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        // monochrome: every generated colour (buttons, chips, selection, cursor) is a shade of grey
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.white,
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
          surface: bg,
        ),
        appBarTheme: const AppBarTheme(backgroundColor: bg, surfaceTintColor: Colors.transparent),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder(), TargetPlatform.linux: FadeForwardsPageTransitionsBuilder()},
        ),
      ),
      navigatorKey: navigatorKey,
      navigatorObservers: [popupObserver],
      builder: (context, child) => _TvFrame(
        child: ValueListenableBuilder(
          valueListenable: inPip,
          // picture-in-picture: only the video; the app stays alive underneath (Offstage keeps state)
          builder: (context, pip, _) => Stack(
            children: [
              Offstage(offstage: pip, child: child),
              if (pip)
                const ColoredBox(
                  color: Colors.black,
                  child: SizedBox.expand(child: PipVideo()),
                )
              else
                const MiniPlayer(),
            ],
          ),
        ),
      ),
      home: const HomePage(),
    ),
  );
}

final store = CatalogStore();

/// Saved channels that iptv-org renamed/replaced follow the new id.
void _followRenames() {
  final renames = store.catalog.value?.replacedBy ?? const {};
  final next = {for (final k in saved.value) renames[k] ?? k};
  if (next.length == saved.value.length && next.containsAll(saved.value)) return;
  saved.value = next;
  prefs.setStringList('saved', next.toList());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store.catalog, store.error]),
      builder: (context, _) => AnimatedSwitcher(duration: motion(context, Durations.medium2), child: _body()),
    );
  }

  Widget _body() {
    final cat = store.catalog.value;
    if (cat != null) return AppShell(cat, key: const ValueKey('app'));
    if (store.error.value != null) {
      return Scaffold(
        key: const ValueKey('error'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Couldn't load channels. Check your connection.", textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: store.refresh, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }
    // first launch only: a thin white bar while the channel list downloads
    return const Scaffold(
      key: ValueKey('loading'),
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          width: 160,
          child: LinearProgressIndicator(minHeight: 2, color: Colors.white, backgroundColor: Colors.white12),
        ),
      ),
    );
  }
}

/// Bottom-bar shell: Home (My List) and Discover.
class AppShell extends StatefulWidget {
  final Catalog cat;
  const AppShell(this.cat, {super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  final _visited = {0}; // tabs are built on first visit, so their entrance plays then

  void _go(int i) => setState(() {
    _tab = i;
    _visited.add(i);
  });

  @override
  Widget build(BuildContext context) {
    final screens = [MyListScreen(widget.cat, onDiscover: () => _go(1)), DiscoverScreen(widget.cat, active: _tab == 1)];
    final d = motion(context, Durations.medium1);
    final rail = useRail(MediaQuery.sizeOf(context));
    // fade-through between tabs; both stay alive so scroll position is kept
    final body = Stack(
      children: [
        for (var i = 0; i < screens.length; i++)
          if (_visited.contains(i))
            IgnorePointer(
              ignoring: i != _tab,
              child: ExcludeFocus(
                excluding: i != _tab,
                child: ExcludeSemantics(
                  excluding: i != _tab,
                  child: AnimatedOpacity(
                    opacity: i == _tab ? 1 : 0,
                    duration: d,
                    curve: i == _tab ? Easing.emphasizedDecelerate : Easing.emphasizedAccelerate,
                    child: AnimatedScale(
                      scale: i == _tab ? 1 : 0.97,
                      duration: d,
                      curve: Easing.emphasizedDecelerate,
                      child: TickerMode(enabled: i == _tab, child: screens[i]),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
    final indicator = Colors.white.withValues(alpha: 0.2);
    final content = Column(
      children: [
        Expanded(child: body),
        const UpdateBanner(),
      ],
    );
    if (rail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: Colors.black,
              indicatorColor: indicator,
              selectedIndex: _tab,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.9,
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: Text('Home')),
                NavigationRailDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: Text('Discover')),
              ],
            ),
            Expanded(child: content),
          ],
        ),
      );
    }
    return Scaffold(
      body: content,
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.black,
        indicatorColor: indicator,
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Discover'),
        ],
      ),
    );
  }
}

/// Home: the channels the user saved to My List.
class MyListScreen extends StatelessWidget {
  final Catalog cat;
  final VoidCallback onDiscover;
  const MyListScreen(this.cat, {super.key, required this.onDiscover});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Wordmark(), actions: const [SettingsButton()]),
      body: ValueListenableBuilder(
        valueListenable: saved,
        builder: (context, keys, _) {
          // ponytail: saved channels whose streams have all died drop out silently
          final mine = cat.channels.where((c) => keys.contains(c.key)).toList();
          if (mine.isEmpty) return FadeSlideIn(child: _EmptyList(onDiscover));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('My List', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ),
              Expanded(child: CardGrid(mine, stagger: true)),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  final VoidCallback onDiscover;
  const _EmptyList(this.onDiscover);
  @override
  Widget build(BuildContext context) {
    return Center(
      // scrolls instead of overflowing on short (landscape) screens
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.live_tv_outlined, size: 72, color: Colors.white38),
            const SizedBox(height: 20),
            const Text('Your list is empty', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Find channels you like and tap + My List to keep them here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 15),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
              onPressed: onDiscover,
              icon: const Icon(Icons.explore),
              label: const Text('Discover channels', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "🇵🇭 Philippines • News, Sports" — shared by cards and the watch page.
String channelSubtitle(Channel c) => [if (c.countryName != null) '${c.flag ?? ''} ${c.countryName}'.trim(), ...c.categories].join('  •  ');

/// Logo tile + name + "country • categories". Lifts on hover, sinks on press.
class ChannelCard extends StatefulWidget {
  final Channel c;
  const ChannelCard(this.c, {super.key});
  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  bool _hover = false, _pressed = false, _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final d = motion(context, Durations.short3);
    final sub = channelSubtitle(c);
    final lifted = _hover || _focused; // mouse over it, or keyboard/TV-remote focus on it
    // one screen-reader item: "SMNI, Philippines • News, button"
    return MergeSemantics(
      child: InkWell(
        onTap: () {
          // grow the watch page out of this card
          final box = context.findRenderObject() as RenderBox?;
          openChannel(c, from: box == null ? null : box.localToGlobal(Offset.zero) & box.size);
        },
        onHover: (v) => setState(() => _hover = v),
        onFocusChange: (v) => setState(() => _focused = v),
        onHighlightChanged: (v) => setState(() => _pressed = v),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedScale(
              scale: _pressed ? 0.96 : (lifted ? 1.04 : 1),
              duration: d,
              curve: Easing.standard,
              child: AnimatedContainer(
                duration: d,
                curve: Easing.standard,
                decoration: BoxDecoration(
                  color: lifted ? const Color(0xFF353535) : card,
                  borderRadius: BorderRadius.circular(8),
                  // focus ring for keyboard and TV remotes (hover alone gets no ring)
                  border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 2),
                  boxShadow: [if (lifted) const BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 8))],
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Center(
                          child: c.logo == null
                              ? Text(
                                  c.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                )
                              : Image.network(
                                  c.logo!,
                                  fit: BoxFit.contain,
                                  cacheWidth: 360,
                                  frameBuilder: fadeInFrame,
                                  errorBuilder: (_, _, _) => const Icon(Icons.live_tv, size: 40),
                                ),
                        ),
                      ),
                      if (c.badges.isNotEmpty)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(3)),
                            child: Text(c.badges.join(' · '), style: const TextStyle(fontSize: 10, color: Colors.white70)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              sub.isEmpty ? ' ' : sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class CardGrid extends StatelessWidget {
  final List<Channel> channels;
  final bool stagger; // fade the first cards in one after another
  const CardGrid(this.channels, {super.key, this.stagger = false});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // columns of at most ~240 px; height follows the 16:9 tile + text
        const pad = 16.0, gap = 12.0;
        final target = cardWidthFor(MediaQuery.sizeOf(context)) + 20; // columns a bit wider than row cards at most
        final cols = max(1, ((box.maxWidth - 2 * pad + gap) / (target + gap)).ceil());
        final itemWidth = (box.maxWidth - 2 * pad - gap * (cols - 1)) / cols;
        return GridView.builder(
          padding: const EdgeInsets.all(pad),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisExtent: cardHeightFor(context, itemWidth) + 8,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
          ),
          itemCount: channels.length,
          itemBuilder: (_, i) {
            final c = channels[i];
            final tile = ChannelCard(c);
            if (!stagger || i >= 12) return tile;
            return FadeSlideIn(
              key: ValueKey(c.key),
              delay: Duration(milliseconds: 40 * i),
              child: tile,
            );
          },
        );
      },
    );
  }
}

class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.settings_outlined),
    tooltip: 'Settings',
    onPressed: () => showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => const SettingsSheet()),
  );
}

/// Everything here is stored on this device only.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder(
              valueListenable: backgroundPlay,
              builder: (_, on, _) => SwitchListTile(
                title: const Text('Background play'),
                subtitle: const Text(
                  'Keep playing when you leave the app. On Android: picture-in-picture for video, a notification for audio. Uses more battery and data.',
                ),
                value: on,
                onChanged: (v) {
                  backgroundPlay.value = v;
                  if (v) requestNotificationPermission();
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('Clear cache'),
              subtitle: const Text('Saved channel list and images. Your list and settings stay.'),
              onTap: () async {
                await store.clear();
                PaintingBinding.instance.imageCache.clear();
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared. The channel list downloads again next launch.')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: const Text('Check for updates'),
              subtitle: const Text('Version $appVersion'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                try {
                  final r = await updates.check(appVersion, force: true);
                  messenger.showSnackBar(SnackBar(content: Text(r == null ? "You're on the latest version." : 'reLiveTV ${r.version} is available.')));
                } catch (_) {
                  messenger.showSnackBar(const SnackBar(content: Text("Couldn't check for updates. Check your connection.")));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About reLiveTV'),
              subtitle: const Text('Version $appVersion'),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: appName,
                applicationVersion: appVersion,
                applicationLegalese: 'Channel data comes from iptv-org (github.com/iptv-org), released into the public domain.',
                children: const [
                  SizedBox(height: 12),
                  Text('reLiveTV hosts no streams. It shows links that iptv-org lists publicly and plays them on your device.'),
                  SizedBox(height: 8),
                  Text('No accounts, no tracking. Your list and settings stay on this device.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "reLiveTV 1.2.0 is available" — shown above the navigation until dismissed.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: updates.available,
      builder: (context, r, _) {
        if (r == null) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFF232323),
          child: SafeArea(
            top: false,
            child: ValueListenableBuilder(
              valueListenable: updates.progress,
              builder: (context, progress, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (progress != null) LinearProgressIndicator(value: progress, minHeight: 2, color: Colors.white, backgroundColor: Colors.white12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                    child: Row(
                      children: [
                        const Icon(Icons.system_update_outlined, size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(progress == null ? 'reLiveTV ${r.version} is available' : 'Downloading ${(progress * 100).round()}%')),
                        if (progress == null) ...[
                          TextButton(onPressed: () => updates.available.value = null, child: const Text('Later')),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                if (await updates.install(r) == 'needsPermission') {
                                  messenger.showSnackBar(const SnackBar(content: Text('Allow installing from reLiveTV, then tap Update again.')));
                                }
                              } catch (e) {
                                messenger.showSnackBar(SnackBar(content: Text("Update didn't install: $e")));
                              }
                            },
                            child: const Text('Update'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// On TVs: keep everything inside the 5% overscan margin TVs may crop, and make
/// text a little bigger for viewing across a room. Elsewhere: no change.
class _TvFrame extends StatelessWidget {
  final Widget child;
  const _TvFrame({required this.child});
  @override
  Widget build(BuildContext context) {
    if (!isTv) return child;
    final mq = MediaQuery.of(context);
    final margin = EdgeInsets.symmetric(horizontal: mq.size.width * 0.05, vertical: mq.size.height * 0.05);
    return ColoredBox(
      color: Colors.black,
      child: Padding(
        padding: margin,
        child: MediaQuery(
          data: mq.copyWith(
            size: Size(mq.size.width - margin.horizontal, mq.size.height - margin.vertical),
            textScaler: TextScaler.linear(mq.textScaler.scale(1) * 1.15),
          ),
          child: child,
        ),
      ),
    );
  }
}
