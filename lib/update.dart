import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'data.dart' show cacheRoot;
import 'platform.dart';
import 'settings.dart';

const _repo = 'Ken-n7/reLiveTV';
const _latestApi = 'https://api.github.com/repos/$_repo/releases/latest';
const _downloadPrefix = 'https://github.com/$_repo/releases/download/';

class Release {
  final String version; // "1.2.0"
  final String pageUrl;
  final Map<String, String> assets; // file name → download URL (only our repo's release downloads)
  const Release(this.version, this.pageUrl, this.assets);
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

/// GitHub's "latest release" JSON → [Release], keeping only download links that
/// point at this repo's own releases (anything else is ignored).
Release? parseRelease(Object? json) {
  if (json is! Map) return null;
  final tag = json['tag_name'];
  final page = json['html_url'];
  if (tag is! String || !tag.startsWith('v') || compareVersions(tag.substring(1), '0.0.0') == null) return null;
  final assets = <String, String>{};
  for (final a in json['assets'] is List ? json['assets'] as List : const []) {
    if (a is! Map) continue;
    final name = a['name'], url = a['browser_download_url'];
    if (name is String && url is String && url.startsWith(_downloadPrefix) && !name.contains('/')) assets[name] = url;
  }
  return Release(tag.substring(1), page is String && page.startsWith('https://github.com/$_repo/') ? page : 'https://github.com/$_repo/releases', assets);
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
    final res = await http.get(Uri.parse(_latestApi), headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null; // no release published yet
    if (res.statusCode != 200) throw HttpException('update check: HTTP ${res.statusCode}');
    await prefs.setInt('updateCheckedAt', DateTime.now().millisecondsSinceEpoch);
    final r = parseRelease(jsonDecode(res.body));
    final newer = r != null && (compareVersions(r.version, current.split('-').first) ?? 0) > 0;
    available.value = newer ? r : null;
    return newer ? r : null;
  }

  /// Android: download, verify the checksum, hand to the system installer.
  /// Linux: open the release page (manual download).
  Future<void> install(Release r) async {
    if (!Platform.isAndroid) {
      await Process.run('xdg-open', [r.pageUrl]);
      return;
    }
    final abis = (await platform.invokeListMethod<String>('abis')) ?? const [];
    final name = apkFor(r, abis);
    final sumsUrl = r.assets['SHA256SUMS'];
    if (name == null || sumsUrl == null) throw const HttpException('no download for this device');
    final sums = parseSums((await http.get(Uri.parse(sumsUrl)).timeout(const Duration(seconds: 30))).body);
    final expected = sums[name];
    if (expected == null) throw const HttpException('release has no checksum for this file');

    final dir = Directory('${(await cacheRoot()).path}/update');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final file = File('${dir.path}/$name');
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
    await platform.invokeMethod('installApk', file.path);
  }
}

final updates = Updates();
