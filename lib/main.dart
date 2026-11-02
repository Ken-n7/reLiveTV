import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'catalog.dart';
import 'data.dart';
import 'layout.dart';
import 'motion.dart';
import 'player.dart';
import 'settings.dart';

const appName = 'reLiveTV';
const bg = Color(0xFF141414);
const card = Color(0xFF2A2A2A);

/// The app name as shown in the top bars.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key});
  @override
  Widget build(BuildContext context) =>
      const Text(appName, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.5));
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
        return FilledButton.tonalIcon(
          style: FilledButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white),
          onPressed: () => toggleSaved(c),
          icon: AnimatedSwitcher(
            duration: motion(context, Durations.short4),
            switchInCurve: Easing.emphasizedDecelerate,
            switchOutCurve: Easing.emphasizedAccelerate,
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: child)),
            child: Icon(inList ? Icons.check : Icons.add, key: ValueKey(inList)),
          ),
          label: const Text('My List'),
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
  runApp(MaterialApp(
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
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      }),
    ),
    navigatorKey: navigatorKey,
    builder: (context, child) => Stack(children: [child!, const MiniPlayer()]),
    home: const HomePage(),
  ));
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text("Couldn't load channels. Check your connection.", textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: store.refresh, child: const Text('Retry')),
            ]),
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
    final screens = [
      MyListScreen(widget.cat, onDiscover: () => _go(1)),
      DiscoverScreen(widget.cat),
    ];
    final d = motion(context, Durations.medium1);
    final rail = useRail(MediaQuery.sizeOf(context));
    // fade-through between tabs; both stay alive so scroll position is kept
    final body = Stack(children: [
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
      ]);
    final indicator = Colors.white.withValues(alpha: 0.2);
    if (rail) {
      return Scaffold(
        body: Row(children: [
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
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
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
      appBar: AppBar(
        title: const Wordmark(),
      ),
      body: ValueListenableBuilder(
        valueListenable: saved,
        builder: (context, keys, _) {
          // ponytail: saved channels whose streams have all died drop out silently
          final mine = cat.channels.where((c) => keys.contains(c.key)).toList();
          if (mine.isEmpty) return FadeSlideIn(child: _EmptyList(onDiscover));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('My List', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            Expanded(child: CardGrid(mine, stagger: true)),
          ]);
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
            onPressed: onDiscover,
            icon: const Icon(Icons.explore),
            label: const Text('Discover channels', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }
}

class DiscoverScreen extends StatefulWidget {
  final Catalog cat;
  const DiscoverScreen(this.cat, {super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late List<(String, List<Channel>)> rows = _rows(widget.cat);

  @override
  void didUpdateWidget(DiscoverScreen old) {
    super.didUpdateWidget(old);
    if (old.cat != widget.cat) rows = _rows(widget.cat); // the daily refresh brought a new catalog
  }

  static List<(String, List<Channel>)> _rows(Catalog cat) {
    final byCategory = <String, List<Channel>>{};
    for (final c in cat.channels) {
      for (final k in c.categories) {
        (byCategory[k] ??= []).add(c);
      }
    }
    // logos first so rows look full, biggest categories first
    int logoFirst(Channel a, Channel b) => (a.logo == null ? 1 : 0) - (b.logo == null ? 1 : 0);
    return [
      for (final e in byCategory.entries.toList()..sort((a, b) => b.value.length - a.value.length)) (e.key, e.value..sort(logoFirst)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.cat;
    return Scaffold(
      appBar: AppBar(
        title: const Wordmark(),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SearchPage(cat))),
          ),
        ],
      ),
      body: ListView(padding: EdgeInsets.zero, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Discover', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        for (final (i, (title, channels)) in rows.indexed)
          i < 5 ? FadeSlideIn(delay: Duration(milliseconds: 50 * i), child: ChannelRow(title, channels)) : ChannelRow(title, channels),
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// "🇵🇭 Philippines • News, Sports" — shared by cards and the watch page.
String channelSubtitle(Channel c) =>
    [if (c.countryName != null) '${c.flag ?? ''} ${c.countryName}'.trim(), ...c.categories].join('  •  ');


/// A titled row of channel cards that scrolls sideways.
class ChannelRow extends StatelessWidget {
  final String title;
  final List<Channel> channels;
  const ChannelRow(this.title, this.channels, {super.key});
  @override
  Widget build(BuildContext context) {
    final cardWidth = cardWidthFor(MediaQuery.sizeOf(context));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      SizedBox(
        height: cardHeightFor(context, cardWidth) + 20, // + vertical room for the hover lift
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          itemCount: channels.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: cardWidth, child: ChannelCard(channels[i])),
        ),
      ),
    ]);
  }
}

/// Logo tile + name + "country • categories". Lifts on hover, sinks on press.
class ChannelCard extends StatefulWidget {
  final Channel c;
  const ChannelCard(this.c, {super.key});
  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  bool _hover = false, _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final d = motion(context, Durations.short3);
    final sub = channelSubtitle(c);
    return InkWell(
      onTap: () {
        // grow the watch page out of this card
        final box = context.findRenderObject() as RenderBox?;
        openChannel(c, from: box == null ? null : box.localToGlobal(Offset.zero) & box.size);
      },
      onHover: (v) => setState(() => _hover = v),
      onHighlightChanged: (v) => setState(() => _pressed = v),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedScale(
          scale: _pressed ? 0.96 : (_hover ? 1.04 : 1),
          duration: d,
          curve: Easing.standard,
          child: AnimatedContainer(
            duration: d,
            curve: Easing.standard,
            decoration: BoxDecoration(
              color: _hover ? const Color(0xFF353535) : card,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [if (_hover) const BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Center(
                      child: c.logo == null
                          ? Text(c.name, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))
                          : Image.network(c.logo!, fit: BoxFit.contain, cacheWidth: 360, frameBuilder: fadeInFrame, errorBuilder: (_, _, _) => const Icon(Icons.live_tv, size: 40)),
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
        Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(sub.isEmpty ? ' ' : sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54)),
      ]),
    );
  }
}

class SearchPage extends StatefulWidget {
  final Catalog cat;
  const SearchPage(this.cat, {super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _query = '';
  String? _country, _category;

  @override
  Widget build(BuildContext context) {
    final cat = widget.cat;
    final q = _query.toLowerCase();
    final shown = cat.channels.where((c) =>
        (_country == null || c.countryCode == _country) &&
        (_category == null || c.categories.contains(_category)) &&
        (q.isEmpty || c.name.toLowerCase().contains(q) || (c.network?.toLowerCase().contains(q) ?? false))).toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search channels, networks', border: InputBorder.none),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: _country,
                hint: const Text('All countries'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All countries')),
                  for (final e in cat.countries.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _country = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: _category,
                hint: const Text('All categories'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All categories')),
                  for (final c in cat.categories) DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(alignment: Alignment.centerLeft, child: Text('${shown.length} channels', style: Theme.of(context).textTheme.labelMedium)),
        ),
        Expanded(child: CardGrid(shown)),
      ]),
    );
  }
}

class CardGrid extends StatelessWidget {
  final List<Channel> channels;
  final bool stagger; // fade the first cards in one after another
  const CardGrid(this.channels, {super.key, this.stagger = false});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
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
          return FadeSlideIn(key: ValueKey(c.key), delay: Duration(milliseconds: 40 * i), child: tile);
        },
      );
    });
  }
}
