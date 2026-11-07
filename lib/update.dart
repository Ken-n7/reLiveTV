import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'data.dart' show cacheRoot;
import 'platform.dart';
import 'settings.dart';

const _repo = 'Ken-n7/reLiveTV';
// A plain release download, not the GitHub API: the API allows only 60 unauthenticated
// requests an hour per IP, and many ISPs put whole neighbourhoods behind one IP.
// This one small file names every asset (with the version) and its checksum.
const _latestSums = 'https://github.com/$_repo/releases/latest/download/SHA256SUMS';
const _downloadPrefix = 'https://github.com/$_repo/releases/download/';

class Release {
  final String version; // "1.2.0"
  final String pageUrl;
  final Map<String, String> assets; // file name → download URL (always this repo's release downloads)
  final Map<String, String> sums; // file name → sha256
  const Release(this.version, this.pageUrl, this.assets, [this.sums = const {}]);
}

/// "1.2.10" vs "1.2.9" → positive. Null if either isn't plain x.y.z.
int? compareVersions(String a, String b) {
  List<int>? parts(String v) {
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(v.trim());
    return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m[i]!)];
  }

  final x = parts(a), y = parts(b);
  if (x == null || y == null) return null;
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] - y[i];
  }
  return 0;
}

/// The latest release's SHA256SUMS → [Release]. Download links are built from
/// this repo's release path, never taken from the file; odd names are ignored.
Release? releaseFromSums(String text) {
  final sums = {
    for (final e in parseSums(text).entries)
      if (RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(e.key)) e.key: e.value,
  };
  final version = [
    for (final name in sums.keys) ?RegExp(r'^relivetv-(\d+\.\d+\.\d+)-').firstMatch(name)?[1],
  ].firstOrNull;
  if (version == null) return null;
  return Release(
    version,
    'https://github.com/$_repo/releases/tag/v$version',
    {for (final name in sums.keys) if (name.startsWith('relivetv-$version-')) name: '${_downloadPrefix}v$version/$name'},
    sums,
  );
}

/// The APK built for this device's CPU (first supported ABI wins).
String? apkFor(Release r, List<String> abis) {
  for (final abi in abis) {
    final name = 'relivetv-${r.version}-android-$abi.apk';
    if (r.assets.containsKey(name)) return name;
  }
  return null;
}

/// `sha256sum` output → file name → hex digest.
Map<String, String> parseSums(String text) => {
  for (final line in const LineSplitter().convert(text))
    if (RegExp(r'^([0-9a-f]{64}) [ *]?(\S+)$').firstMatch(line.trim()) case final m?) m[2]!: m[1]!,
};

/// Checks GitHub Releases at most once a day; offers newer versions.
class Updates {
  final available = ValueNotifier<Release?>(null);
  final progress = ValueNotifier<double?>(null); // 0..1 while downloading
  static const _checkEvery = Duration(hours: 24), _maxApk = 300 << 20;

  /// Development builds (version ends in "-dev") only check when asked.
  Future<Release?> check(String current, {bool force = false}) async {
    if (!force) {
      if (current.contains('-')) return null;
      final last = DateTime.fromMillisecondsSinceEpoch(prefs.getInt('updateCheckedAt') ?? 0);
      if (DateTime.now().difference(last) < _checkEvery) return null;
    }
    final res = await http.get(Uri.parse(_latestSums)).timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null; // no release published yet
    if (res.statusCode != 200) throw HttpException('update check: HTTP ${res.statusCode}');
    await prefs.setInt('updateCheckedAt', DateTime.now().millisecondsSinceEpoch);
    final r = releaseFromSums(res.body);
    final newer = r != null && (compareVersions(r.version, current.split('-').first) ?? 0) > 0;
    available.value = newer ? r : null;
    return newer ? r : null;
  }

  /// Android: download, verify the checksum, hand to the system installer.
  /// Desktop: open the release page in the browser (manual download).
  /// Returns 'needsPermission' when Android first has to allow installs.
  Future<String?> install(Release r) async {
    if (!Platform.isAndroid) {
      // rundll32 opens the URL without going through a shell (no cmd quoting).
      await (Platform.isWindows
          ? Process.run('rundll32', ['url.dll,FileProtocolHandler', r.pageUrl])
          : Process.run('xdg-open', [r.pageUrl]));
      return null;
    }
    final abis = (await platform.invokeListMethod<String>('abis')) ?? const [];
    final name = apkFor(r, abis);
    if (name == null) throw const HttpException('no download for this device');
    final expected = r.sums[name];
    if (expected == null) throw const HttpException('release has no checksum for this file');

    final dir = Directory('${(await cacheRoot()).path}/update');
    final file = File('${dir.path}/$name');
    // already downloaded and verified (e.g. before Android asked to allow installs)
    if (file.existsSync() && await platform.invokeMethod<String>('sha256', file.path) == expected) {
      return platform.invokeMethod<String>('installApk', file.path);
    }
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(r.assets[name]!)));
      if (res.statusCode != 200) throw HttpException('download: HTTP ${res.statusCode}');
      final total = res.contentLength ?? 0;
      if (total > _maxApk) throw const HttpException('download too large');
      final sink = file.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
          got += chunk.length;
          if (got > _maxApk) throw const HttpException('download too large');
          sink.add(chunk);
          if (total > 0) progress.value = got / total;
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
      progress.value = null;
    }
    final actual = await platform.invokeMethod<String>('sha256', file.path);
    if (actual != expected) {
      file.deleteSync();
      throw const HttpException('download failed verification; not installed');
    }
    return platform.invokeMethod<String>('installApk', file.path);
  }
}

final updates = Updates();
