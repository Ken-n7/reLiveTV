import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog.dart';
import 'main.dart' show store;
import 'schedule.dart';

/// "Now / Next / Later" for the channel on the watch page. Shows nothing when the
/// channel has no schedule. Updates every 30 s, only while the page is open.
class ScheduleCard extends StatefulWidget {
  final Channel c;
  const ScheduleCard(this.c, {super.key});
  @override
  State<ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<ScheduleCard> {
  late Future<List<Programme>> _schedule = schedules.load(widget.c.id);
  late final Timer _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _tick; // start ticking
  }

  @override
  void didUpdateWidget(ScheduleCard old) {
    super.didUpdateWidget(old);
    if (old.c.id != widget.c.id) _schedule = schedules.load(widget.c.id);
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Map<String, int> get _offsets => store.catalog.value?.timezoneOffsets ?? const {};

  /// (offset in minutes or null for device time, label for the chip)
  // ponytail: iptv-org's timezones.json has fixed offsets (no daylight saving), so "channel's
  // time" can be 1 h off in DST zones in summer; use the `timezone` package (IANA rules) if that matters.
  (int?, String) _zone() {
    final z = scheduleZone;
    if (z == 'channel' && widget.c.timezone != null && _offsets.containsKey(widget.c.timezone)) {
      return (_offsets[widget.c.timezone], "Channel's time (${_city(widget.c.timezone!)})");
    }
    if (z != 'local' && z != 'channel' && _offsets.containsKey(z)) return (_offsets[z], _city(z));
    return (null, 'My time');
  }

  String _fmt(BuildContext context, DateTime utc, int? off) => MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(wallClock(utc, off)));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Programme>>(
      future: _schedule,
      builder: (context, snap) {
        final ps = snap.data ?? const [];
        final t = DateTime.now().toUtc();
        final r = nowNext(ps, t);
        if (r.now == null && r.next == null) return const SizedBox.shrink();
        final (off, label) = _zone();
        final dim = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60);
        final channelOff = widget.c.timezone == null ? null : _offsets[widget.c.timezone];
        final deviceOff = DateTime.now().timeZoneOffset.inMinutes;
        return Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r.now case final now?) ...[
                Row(
                  children: [
                    const Text('NOW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const Spacer(),
                    Text('${_fmt(context, now.start, off)} – ${_fmt(context, now.stop, off)}', style: dim),
                  ],
                ),
                const SizedBox(height: 4),
                Text(now.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: t.difference(now.start).inSeconds / now.stop.difference(now.start).inSeconds,
                  minHeight: 3,
                  color: Colors.white,
                  backgroundColor: Colors.white12,
                ),
              ],
              if (r.next case final next?) ...[
                const SizedBox(height: 12),
                Text('NEXT · ${_fmt(context, next.start, off)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(next.title),
              ],
              if (r.later.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final p in r.later)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 76, child: Text(_fmt(context, p.start, off), style: dim)),
                        Expanded(
                          child: Text(p.title, style: dim, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.schedule, size: 16),
                    label: Text('Times: $label'),
                    onPressed: () async {
                      final pick = await showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => _ZoneSheet(channelZone: widget.c.timezone, offsets: _offsets),
                      );
                      if (pick != null) setState(() => scheduleZone = pick);
                    },
                  ),
                  if (channelOff != null && channelOff != deviceOff) Text("It's ${_fmt(context, t, channelOff)} in ${_city(widget.c.timezone!)}", style: dim),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

String _city(String zone) => zone.split('/').last.replaceAll('_', ' ');

String _utc(int minutes) {
  final sign = minutes < 0 ? '−' : '+';
  final m = minutes.abs();
  return 'UTC$sign${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

class _ZoneSheet extends StatefulWidget {
  final String? channelZone;
  final Map<String, int> offsets;
  const _ZoneSheet({required this.channelZone, required this.offsets});
  @override
  State<_ZoneSheet> createState() => _ZoneSheetState();
}

class _ZoneSheetState extends State<_ZoneSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final zones = widget.offsets.entries.where((e) => e.key.toLowerCase().replaceAll('_', ' ').contains(q)).toList()
      ..sort((a, b) => a.value != b.value ? a.value - b.value : a.key.compareTo(b.key));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Show schedule times in', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('My time'),
            subtitle: Text('This device (${DateTime.now().timeZoneName})'),
            onTap: () => Navigator.pop(context, 'local'),
          ),
          if (widget.channelZone != null && widget.offsets.containsKey(widget.channelZone))
            ListTile(
              leading: const Icon(Icons.live_tv),
              title: const Text("Channel's time"),
              subtitle: Text('${_city(widget.channelZone!)} · ${_utc(widget.offsets[widget.channelZone]!)}'),
              onTap: () => Navigator.pop(context, 'channel'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Find a city or zone', prefixIcon: Icon(Icons.search), isDense: true),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: zones.length,
              itemBuilder: (_, i) => ListTile(
                dense: true,
                title: Text(_city(zones[i].key)),
                subtitle: Text(zones[i].key),
                trailing: Text(_utc(zones[i].value), style: const TextStyle(color: Colors.white54)),
                onTap: () => Navigator.pop(context, zones[i].key),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
