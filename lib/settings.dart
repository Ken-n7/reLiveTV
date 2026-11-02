import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything reLiveTV remembers lives here, on this device only.
late final SharedPreferences prefs;

/// Keep playing (audio, picture-in-picture on Android) after leaving the app. Off by default.
final backgroundPlay = ValueNotifier(false);

Future<void> initSettings() async {
  prefs = await SharedPreferences.getInstance();
  backgroundPlay.value = prefs.getBool('backgroundPlay') ?? false;
  backgroundPlay.addListener(() => prefs.setBool('backgroundPlay', backgroundPlay.value));
}

/// Stream URLs that failed every attempt on this device, with when. Used only to
/// try them last for a day; never uploaded, never used to hide anything.
const _failedKey = 'failedStreams', _failedFor = Duration(hours: 24);

Set<String> recentlyFailed() {
  final cutoff = DateTime.now().subtract(_failedFor).millisecondsSinceEpoch;
  final kept = <String>[];
  final urls = <String>{};
  for (final entry in prefs.getStringList(_failedKey) ?? const <String>[]) {
    final i = entry.indexOf(' ');
    if (i < 0 || (int.tryParse(entry.substring(0, i)) ?? 0) < cutoff) continue; // expired
    kept.add(entry);
    urls.add(entry.substring(i + 1));
  }
  prefs.setStringList(_failedKey, kept);
  return urls;
}

void rememberFailed(String url) {
  final list = [...?prefs.getStringList(_failedKey), '${DateTime.now().millisecondsSinceEpoch} $url'];
  prefs.setStringList(_failedKey, list.length > 500 ? list.sublist(list.length - 500) : list);
}
