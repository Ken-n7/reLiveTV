import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog.dart';
import 'layout.dart';
import 'main.dart' show CardGrid, ChannelCard, SettingsButton, Wordmark;
import 'motion.dart';

/// Browse and search in one place: a search bar and filter chips on top;
/// category rows when nothing is typed or picked, a results grid otherwise.
class DiscoverScreen extends StatefulWidget {
  final Catalog cat;
  final bool active; // this tab is on screen (keyboard shortcuts, Back behaviour)
  const DiscoverScreen(this.cat, {super.key, this.active = true});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late List<(String, List<Channel>)> _rows = _buildRows(widget.cat);
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String? _country, _region, _language, _category;
  List<Channel> _results = const [];

  bool get _filtering => _search.text.trim().isNotEmpty || _country != null || _region != null || _language != null || _category != null;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didUpdateWidget(DiscoverScreen old) {
    super.didUpdateWidget(old);
    if (old.cat != widget.cat) {
      _rows = _buildRows(widget.cat); // the daily refresh brought a new catalog
      _refilter();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  static List<(String, List<Channel>)> _buildRows(Catalog cat) {
    final byCategory = <String, List<Channel>>{};
    for (final c in cat.channels) {
      for (final k in c.categories) {
        (byCategory[k] ??= []).add(c);
      }
    }
    // logos first so rows look full, biggest categories first
    int logoFirst(Channel a, Channel b) => (a.logo == null ? 1 : 0) - (b.logo == null ? 1 : 0);
    return [for (final e in byCategory.entries.toList()..sort((a, b) => b.value.length - a.value.length)) (e.key, e.value..sort(logoFirst))];
  }

  void _refilter() => _results = _filtering
      ? filterChannels(widget.cat, query: _search.text, country: _country, region: _region, language: _language, category: _category)
      : const [];

  void _update(VoidCallback change) => setState(() {
    change();
    _refilter();
  });

  void _clearAll() => _update(() {
    _search.clear();
    _country = _region = _language = _category = null;
  });

  /// `/` or Ctrl+F jumps to search; Esc clears the search, then the filters.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || !widget.active || !mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final key = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if ((key == LogicalKeyboardKey.slash && !_searchFocus.hasFocus) || (ctrl && key == LogicalKeyboardKey.keyF)) {
      _searchFocus.requestFocus();
      return true;
    }
    if (key == LogicalKeyboardKey.escape && _filtering) {
      if (_search.text.isNotEmpty) {
        _update(_search.clear);
      } else {
        _clearAll();
      }
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back clears the search and filters before it leaves the screen
      canPop: !(widget.active && _filtering),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearAll();
      },
      child: Scaffold(
        appBar: AppBar(title: const Wordmark(), actions: const [SettingsButton()]),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _searchBar(),
            _chips(),
            Expanded(
              child: AnimatedSwitcher(duration: motion(context, Durations.short4), child: _filtering ? _resultsView() : _rowsView()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: TextField(
      controller: _search,
      focusNode: _searchFocus,
      textInputAction: TextInputAction.search,
      onChanged: (_) => _update(() {}),
      decoration: InputDecoration(
        hintText: 'Search channels, networks, countries, languages',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close), onPressed: () => _update(_search.clear)),
        filled: true,
        fillColor: const Color(0xFF232323),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
      ),
    ),
  );

  Widget _chips() {
    final cat = widget.cat;
    final where = _region != null ? cat.regions.where((r) => r.code == _region).firstOrNull?.name : (_country != null ? cat.countries[_country] : null);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
            label: where ?? 'Country',
            selected: where != null,
            onTap: () async {
              final pick = await _pick(context, 'Country or region', [
                ('Regions', [for (final r in cat.regions) _Option('r:${r.code}', r.name)]),
                ('Countries', [for (final e in cat.countries.entries) _Option('c:${e.key}', e.value)]),
              ]);
              if (pick == null) return;
              _update(() {
                _country = pick.startsWith('c:') ? pick.substring(2) : null;
                _region = pick.startsWith('r:') ? pick.substring(2) : null;
              });
            },
          ),
          _FilterChip(
            label: _language ?? 'Language',
            selected: _language != null,
            onTap: () async {
              final pick = await _pick(context, 'Language', [
                ('', [for (final l in _byCount(cat, (c) => c.languages)) _Option(l.$1, l.$1, l.$2)]),
              ]);
              if (pick != null) _update(() => _language = pick.isEmpty ? null : pick);
            },
          ),
          _FilterChip(
            label: _category ?? 'Category',
            selected: _category != null,
            onTap: () async {
              final pick = await _pick(context, 'Category', [
                ('', [for (final k in _byCount(cat, (c) => c.categories)) _Option(k.$1, k.$1, k.$2)]),
              ]);
              if (pick != null) _update(() => _category = pick.isEmpty ? null : pick);
            },
          ),
          if (_filtering)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TextButton(onPressed: _clearAll, child: const Text('Clear all')),
            ),
        ],
      ),
    );
  }

  Widget _rowsView() => ListView(
    key: const ValueKey('rows'),
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      for (final (i, (title, channels)) in _rows.indexed)
        i < 5
            ? FadeSlideIn(
                delay: Duration(milliseconds: 50 * i),
                child: ChannelRow(title, channels, onSeeAll: () => _update(() => _category = title)),
              )
            : ChannelRow(title, channels, onSeeAll: () => _update(() => _category = title)),
    ],
  );

  Widget _resultsView() {
    if (_results.isEmpty) {
      final q = _search.text.trim();
      return Center(
        key: const ValueKey('empty'),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 56, color: Colors.white38),
              const SizedBox(height: 12),
              Text(
                q.isEmpty ? 'No channels match these filters' : 'No channels match “$q”',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              // one tap removes each thing that narrowed the results
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (q.isNotEmpty) InputChip(label: Text('“$q”'), onDeleted: () => _update(_search.clear)),
                  if (_country != null) InputChip(label: Text(widget.cat.countries[_country] ?? _country!), onDeleted: () => _update(() => _country = null)),
                  if (_region != null)
                    InputChip(
                      label: Text(widget.cat.regions.where((r) => r.code == _region).firstOrNull?.name ?? _region!),
                      onDeleted: () => _update(() => _region = null),
                    ),
                  if (_language != null) InputChip(label: Text(_language!), onDeleted: () => _update(() => _language = null)),
                  if (_category != null) InputChip(label: Text(_category!), onDeleted: () => _update(() => _category = null)),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _clearAll, child: const Text('Clear all')),
            ],
          ),
        ),
      );
    }
    return Column(
      key: const ValueKey('results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text('${_results.length} ${_results.length == 1 ? 'channel' : 'channels'}', style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(child: CardGrid(_results)),
      ],
    );
  }
}

/// Values used by the catalog's channels, most common first: (value, count).
List<(String, int)> _byCount(Catalog cat, List<String> Function(Channel) values) {
  final counts = <String, int>{};
  for (final c in cat.channels) {
    for (final v in values(c)) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
  }
  return [for (final e in counts.entries) (e.key, e.value)]..sort((a, b) => b.$2 - a.$2);
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Row(mainAxisSize: MainAxisSize.min, children: [Text(label), const Icon(Icons.arrow_drop_down, size: 18)]),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
    ),
  );
}

class _Option {
  final String value, label;
  final int? count;
  const _Option(this.value, this.label, [this.count]);
}

/// Searchable picker sheet. Returns the picked value, '' for "Any", null if dismissed.
Future<String?> _pick(BuildContext context, String title, List<(String, List<_Option>)> sections) {
  return showModalBottomSheet<String>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _PickerSheet(title, sections));
}

class _PickerSheet extends StatefulWidget {
  final String title;
  final List<(String, List<_Option>)> sections;
  const _PickerSheet(this.title, this.sections);
  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final total = widget.sections.fold<int>(0, (n, s) => n + s.$2.length);
    final rows = <Widget>[
      ListTile(title: Text('Any ${widget.title.toLowerCase()}'), onTap: () => Navigator.pop(context, '')),
      for (final (header, options) in widget.sections) ...[
        if (header.isNotEmpty && options.any((o) => o.label.toLowerCase().contains(q)))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(header, style: Theme.of(context).textTheme.labelLarge),
          ),
        for (final o in options)
          if (o.label.toLowerCase().contains(q))
            ListTile(
              title: Text(o.label),
              trailing: o.count == null ? null : Text('${o.count}', style: const TextStyle(color: Colors.white54)),
              onTap: () => Navigator.pop(context, o.value),
            ),
      ],
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))],
            ),
          ),
          if (total > 12)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: !isTouchOnly(context),
                decoration: InputDecoration(hintText: 'Find ${widget.title.toLowerCase()}', prefixIcon: const Icon(Icons.search), isDense: true),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          Expanded(child: ListView(children: rows)),
        ],
      ),
    );
  }
}

/// A titled row of channel cards that scrolls sideways, with "See all".
class ChannelRow extends StatelessWidget {
  final String title;
  final List<Channel> channels;
  final VoidCallback? onSeeAll;
  const ChannelRow(this.title, this.channels, {super.key, this.onSeeAll});
  @override
  Widget build(BuildContext context) {
    final cardWidth = cardWidthFor(MediaQuery.sizeOf(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              if (onSeeAll != null) TextButton(onPressed: onSeeAll, child: Text('See all ${channels.length} ›')),
            ],
          ),
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
      ],
    );
  }
}
