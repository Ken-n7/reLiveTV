import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'catalog.dart';
import 'platform.dart';

/// The channel catalog on this device. Starts instantly from the saved compact copy;
/// re-downloads iptv-org's files at most once a day (they publish once a day).
class CatalogStore {
  final catalog = ValueNotifier<Catalog?>(null);
  final error = ValueNotifier<Object?>(null); // only when there is nothing to show yet

  static const maxAge = Duration(hours: 24);
  static const _maxFileBytes = 64 << 20; // largest iptv-org file today is ~8 MB
  late final Directory _dir;
  bool _refreshing = false;

  File get _saved => File('${_dir.path}/catalog.json');
  File get _meta => File('${_dir.path}/meta.json');

  Future<void> start() async {
    final sw = Stopwatch()..start();
    _dir = Directory('${(await cacheRoot()).path}/catalog')..createSync(recursive: true);
    if (_saved.existsSync()) {
      try {
        catalog.value = await compute(_load, _saved.path);
        debugPrint('catalog: loaded saved copy in ${sw.elapsedMilliseconds} ms');
      } catch (e) {
        debugPrint('saved catalog unreadable, rebuilding: $e');
      }
    }
    if (catalog.value == null) {
      await refresh();
      if (catalog.value != null) debugPrint('catalog: downloaded and built in ${sw.elapsedMilliseconds} ms');
    } else if (_age() > maxAge) {
      unawaited(refresh()); // quietly, while the saved copy is already on screen
    }
  }

  Map<String, dynamic> _readMeta() {
    try {
      return jsonDecode(_meta.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Duration _age() {
    final at = DateTime.tryParse(_readMeta()['fetchedAt'] as String? ?? '');
    return at == null ? const Duration(days: 999) : DateTime.now().toUtc().difference(at);
  }

  void _writeMeta(String? etag) => _meta.writeAsStringSync(jsonEncode({'fetchedAt': DateTime.now().toUtc().toIso8601String(), 'etag': etag}));

  /// Downloads iptv-org's files and rebuilds the catalog. One conditional request
  /// first: if streams.json hasn't changed since our copy, nothing else is fetched.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    error.value = null;
    final client = http.Client();
    final raw = Directory('${_dir.path}/raw');
    try {
      raw.createSync(recursive: true);
      final etag = _readMeta()['etag'] as String?;
      String? newEtag;
      for (final f in ['streams', ...apiFiles.where((f) => f != 'streams')]) {
        final req = http.Request('GET', Uri.parse('$apiBase/$f.json'));
        if (f == 'streams' && etag != null && catalog.value != null) req.headers['If-None-Match'] = etag;
        final res = await client.send(req).timeout(const Duration(seconds: 30));
        if (res.statusCode == 304) {
          _writeMeta(etag); // iptv-org hasn't published anything new; check again tomorrow
          return;
        }
        if (res.statusCode != 200) throw HttpException('$f.json: HTTP ${res.statusCode}');
        if (f == 'streams') newEtag = res.headers['etag'];
        await _download(res, File('${raw.path}/$f.json'));
      }
      catalog.value = await compute(_buildAndSave, _dir.path);
      _writeMeta(newEtag);
    } catch (e) {
      debugPrint('catalog refresh failed: $e');
      if (catalog.value == null) error.value = e; // otherwise keep showing the saved copy
    } finally {
      client.close();
      if (raw.existsSync()) raw.deleteSync(recursive: true);
      _refreshing = false;
    }
  }

  /// Streams a response to disk, refusing anything over the size cap.
  Future<void> _download(http.StreamedResponse res, File out) async {
    if ((res.contentLength ?? 0) > _maxFileBytes) throw const HttpException('file too large');
    final sink = out.openWrite();
    var bytes = 0;
    try {
      await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
        bytes += chunk.length;
        if (bytes > _maxFileBytes) throw const HttpException('file too large');
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    // a cut-off download would otherwise fail later as broken JSON. Only comparable when
    // the body wasn't gzip-compressed: the client unpacks it, so sizes differ by design.
    final compressed = res.headers['content-encoding'] != null;
    if (!compressed && res.contentLength != null && bytes != res.contentLength) throw const HttpException('incomplete download');
  }

  /// Deletes the saved catalog; the next launch downloads everything again.
  Future<void> clear() async {
    for (final f in [_saved, _meta]) {
      if (f.existsSync()) f.deleteSync();
    }
  }
}

/// Folder for re-downloadable data: Android's app-private cache dir,
/// %LOCALAPPDATA%\\relivetv on Windows, else the XDG cache dir (~/.cache/relivetv on Linux).
Future<Directory> cacheRoot() async {
  if (Platform.isAndroid) return Directory((await platform.invokeMethod<String>('cacheDir'))!);
  final env = Platform.environment;
  if (Platform.isWindows) return Directory('${env['LOCALAPPDATA'] ?? Directory.systemTemp.path}\\relivetv');
  final base = env['XDG_CACHE_HOME'] ?? '${env['HOME'] ?? Directory.systemTemp.path}/.cache';
  return Directory('$base/relivetv');
}

Catalog _load(String path) => Catalog.fromJsonString(File(path).readAsStringSync());

/// Runs in a background isolate: joins the raw files, saves the compact catalog
/// atomically (write temp, then rename) and returns it.
Catalog _buildAndSave(String dir) {
  final cat = buildCatalog((name) => File('$dir/raw/$name.json').readAsStringSync());
  File('$dir/catalog.json.tmp')
    ..writeAsStringSync(cat.toJsonString())
    ..renameSync('$dir/catalog.json');
  return cat;
}
