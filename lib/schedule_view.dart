import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog.dart';
import 'main.dart' show store;
import 'schedule.dart';

/// The channel's schedule: "Schedule" header with the time-zone choice, then the
/// programmes from now on, grouped by day, the live one highlighted. On wide screens
/// it fills the side panel and scrolls by itself ([embedded] false); in portrait it is
/// part of the page's scroll. Says so when the channel has no schedule.
/// Updates every 30 s, only while the watch page is open.
class SchedulePanel extends StatefulWidget {
  final Channel c;
  final bool embedded;
  const SchedulePanel(this.c, {super.key, this.embedded = false});
  @override
  State<SchedulePanel> createState() => _SchedulePanelState();
}

class _SchedulePanelState extends State<SchedulePanel> {
  late Future<List<Programme>> _schedule = schedules.load(widget.c.id);
  late final Timer _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _tick; // start ticking
  }

  @override
  void didUpdateWidget(SchedulePanel old) {
    super.didUpdateWidget(old);
    if (old.c.id != widget.c.id) _schedule = schedules.load(widget.c.id);
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Map<String, int> get _offsets => store.catalog.value?.timezoneOffsets ?? const {};

  /// (offset in minutes or null for device time, label for the button)
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

  String _time(BuildContext context, DateTime utc, int? off) => MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(wallClock(utc, off)));

  String _day(BuildContext context, DateTime wall, DateTime today) {
    final d = DateTime(wall.year, wall.month, wall.day);
    final diff = d.difference(DateTime(today.year, today.month, today.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return MaterialLocalizations.of(context).formatMediumDate(d);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Programme>>(
      future: _schedule,
      builder: (context, snap) {
        final now = DateTime.now().toUtc();
        final upcoming = (snap.data ?? const <Programme>[]).where((p) => p.stop.isAfter(now)).toList();
        final (off, label) = _zone();
        final channelOff = widget.c.timezone == null ? null : _offsets[widget.c.timezone];
        final deviceOff = DateTime.now().timeZoneOffset.inMinutes;

        final header = Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text('Schedule', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              if (upcoming.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.schedule, size: 16),
                  label: Text('Times: $label', overflow: TextOverflow.ellipsis),
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
            ],
          ),
        );

        final Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: SizedBox(
                width: 120,
                child: LinearProgressIndicator(minHeight: 2, color: Colors.white, backgroundColor: Colors.white12),
              ),
            ),
          );
        } else if (upcoming.isEmpty) {
          body = const _NoSchedule();
        } else {
          final today = wallClock(now, off);
          final rows = <Widget>[
            if (channelOff != null && channelOff != deviceOff && off != channelOff)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  "It's ${_time(context, now, channelOff)} in ${_city(widget.c.timezone!)}",
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
          ];
          String? lastDay;
          for (final p in upcoming) {
            final day = _day(context, wallClock(p.start.isBefore(now) ? now : p.start, off), today);
            if (day != lastDay) {
              lastDay = day;
              rows.add(_DayHeader(day));
            }
            rows.add(_ProgrammeRow(p, live: !p.start.isAfter(now), start: _time(context, p.start, off), stop: _time(context, p.stop, off), now: now));
          }
          body = widget.embedded
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)
              : Expanded(
                  child: ListView(padding: const EdgeInsets.only(bottom: 16), children: rows),
                );
        }

        // in the side panel everything below the header scrolls, so a short panel never overflows
        final content = widget.embedded || body is Expanded ? body : Expanded(child: SingleChildScrollView(child: body));
        return Container(
          decoration: BoxDecoration(color: const Color(0xFF181818), borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [header, content],
          ),
        );
      },
    );
  }
}

class _NoSchedule extends StatelessWidget {
  const _NoSchedule();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(16, 20, 16, 28),
    child: Column(
      children: [
        Icon(Icons.event_busy_outlined, size: 36, color: Colors.white38),
        SizedBox(height: 10),
        Text('No schedule available', style: TextStyle(fontWeight: FontWeight.w600)),
        SizedBox(height: 4),
        Text(
          "iptv-org doesn't list this channel's programmes yet.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    ),
  );
}

class _DayHeader extends StatelessWidget {
  final String label;
  const _DayHeader(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white54),
    ),
  );
}

String _duration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h == 0 ? '${m}m' : (m == 0 ? '${h}h' : '${h}h ${m}m');
}

/// One programme: time, title, length. The live one gets a LIVE tag, a
/// progress bar and the time left.
class _ProgrammeRow extends StatelessWidget {
  final Programme p;
  final bool live;
  final String start, stop;
  final DateTime now;
  const _ProgrammeRow(this.p, {required this.live, required this.start, required this.stop, required this.now});

  @override
  Widget build(BuildContext context) {
    final length = p.stop.difference(p.start);
    if (!live) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(start, style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ),
            Expanded(
              child: Text(p.title, style: const TextStyle(fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Text(_duration(length), style: const TextStyle(fontSize: 12, color: Colors.white38)),
          ],
        ),
      );
    }
    final left = p.stop.difference(now);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: Colors.white, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
                child: const Text(
                  '● LIVE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$start – $stop', style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ),
              Text('${_duration(left)} left', style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ],
          ),
          const SizedBox(height: 6),
          Text(p.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (now.difference(p.start).inSeconds / length.inSeconds).clamp(0.0, 1.0),
              minHeight: 3,
              color: Colors.white,
              backgroundColor: Colors.white12,
            ),
          ),
        ],
      ),
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
