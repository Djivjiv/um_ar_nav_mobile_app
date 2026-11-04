import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show consolidateHttpClientResponseBytes, debugPrint;
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:path_provider/path_provider.dart';

import '../../core/config/maptiler_config.dart';

/// One tile layer whose campus tiles are kept on disk.
class CampusTileSource {
  /// Folder name on disk — stable even if the API key in the URL changes.
  final String id;
  final String urlTemplate;
  const CampusTileSource(this.id, this.urlTemplate);

  static const base = CampusTileSource('base', MapTilerConfig.baseTileUrl);
  static const overlay =
      CampusTileSource('overlay', MapTilerConfig.umOverlayTileUrl);
  static const all = [base, overlay];

  Uri url(int z, int x, int y) => Uri.parse(urlTemplate
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y'));
}

/// The server has no tile here (HTTP 204 / 404) — e.g. outside the UM
/// overlay's extent. Remembered on disk so it isn't asked for again.
class NoTileException implements Exception {
  final Uri url;
  const NoTileException(this.url);
  @override
  String toString() => 'No tile at $url';
}

/// Inclusive tile x / y range at one zoom.
typedef TileRange = ({int minX, int maxX, int minY, int maxY});

/// Outcome of [CampusTileCache.warm].
class TileWarmResult {
  final int downloaded;
  final int alreadySaved;
  final int failed;
  const TileWarmResult(
      {this.downloaded = 0, this.alreadySaved = 0, this.failed = 0});
}

/// Persistent on-disk cache of map tiles for the campus only: tiles inside
/// [bounds] (plus a one-tile border so the screen edges aren't blank) at
/// zoom [minZoom]–[maxZoom], capped at [maxBytes].
///
/// - [load] is cache-first, so the base map shows after a restart with no
///   internet. Copies older than [refreshAfter] are re-downloaded in the
///   background when possible.
/// - [warm] downloads every campus tile not yet saved (run by OfflineSync
///   while online).
/// - Over [maxBytes], the oldest tiles are deleted ([prune]).
///
/// Files live under the app-support directory (not the OS cache folder,
/// which Android may clear when storage is low).
class CampusTileCache {
  CampusTileCache({
    LatLngBounds? bounds,
    this.minZoom = 16,
    this.maxZoom = 19,
    this.borderTiles = 1,
    this.maxBytes = 200 * 1024 * 1024,
    this.refreshAfter = const Duration(days: 30),
    this.concurrency = 4,
    Future<Directory> Function()? directory,
    Future<List<int>> Function(Uri url)? download,
    DateTime Function()? now,
  })  : bounds = bounds ?? MapTilerConfig.campusBounds,
        _directory = directory ?? _defaultDirectory,
        _download = download ?? _httpDownload,
        _now = now ?? DateTime.now;

  static final CampusTileCache instance = CampusTileCache();

  final LatLngBounds bounds;
  final int minZoom;
  final int maxZoom;
  final int borderTiles;
  final int maxBytes;
  final Duration refreshAfter;
  final int concurrency;
  final Future<Directory> Function() _directory;
  final Future<List<int>> Function(Uri url) _download;
  final DateTime Function() _now;

  /// Consecutive network failures after which [warm] gives up for now.
  static const int maxConsecutiveFailures = 5;

  Future<Directory>? _root;
  int _bytesSincePrune = 0;
  bool _warming = false;

  // ───────────────────────── tile maths ─────────────────────────

  /// Slippy-map tile column of [lng] at zoom [z].
  static int tileX(double lng, int z) {
    final n = 1 << z;
    return ((lng + 180) / 360 * n).floor().clamp(0, n - 1);
  }

  /// Slippy-map tile row of [lat] at zoom [z].
  static int tileY(double lat, int z) {
    final n = 1 << z;
    final r = lat * math.pi / 180;
    final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
    return y.floor().clamp(0, n - 1);
  }

  /// Tiles covering [b] at zoom [z], widened by [border] tiles per side.
  static TileRange tileRange(LatLngBounds b, int z, {int border = 0}) {
    final max = (1 << z) - 1;
    return (
      minX: (tileX(b.west, z) - border).clamp(0, max),
      maxX: (tileX(b.east, z) + border).clamp(0, max),
      minY: (tileY(b.north, z) - border).clamp(0, max),
      maxY: (tileY(b.south, z) + border).clamp(0, max),
    );
  }

  /// Whether tile [z]/[x]/[y] is one this cache keeps.
  bool covers(int z, int x, int y) {
    if (z < minZoom || z > maxZoom) return false;
    final r = tileRange(bounds, z, border: borderTiles);
    return x >= r.minX && x <= r.maxX && y >= r.minY && y <= r.maxY;
  }

  /// Every campus tile, as (z, x, y).
  Iterable<(int, int, int)> allTiles() sync* {
    for (var z = minZoom; z <= maxZoom; z++) {
      final r = tileRange(bounds, z, border: borderTiles);
      for (var x = r.minX; x <= r.maxX; x++) {
        for (var y = r.minY; y <= r.maxY; y++) {
          yield (z, x, y);
        }
      }
    }
  }

  // ───────────────────────── storage ─────────────────────────

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}campus_tiles');

  Future<File> _file(CampusTileSource s, int z, int x, int y) async {
    final root = await (_root ??= _directory());
    final sep = Platform.pathSeparator;
    return File('${root.path}$sep${s.id}$sep$z$sep$x$sep$y.tile');
  }

  /// An empty file marks "the server has no tile here".
  static bool _isNoTileMarker(List<int> bytes) => bytes.isEmpty;

  Future<void> _save(File f, List<int> bytes) async {
    await f.parent.create(recursive: true);
    // Write-then-rename, so a crash never leaves a half-written tile.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
    _bytesSincePrune += bytes.length;
    if (_bytesSincePrune > 5 * 1024 * 1024) {
      _bytesSincePrune = 0;
      unawaited(prune());
    }
  }

  Future<List<int>> _fetchAndSave(
      CampusTileSource s, int z, int x, int y, File f) async {
    final url = s.url(z, x, y);
    try {
      final bytes = await _download(url);
      await _save(f, bytes);
      return bytes;
    } on NoTileException {
      await _save(f, const []);
      rethrow;
    }
  }

  /// Tile bytes for the map: the saved copy when there is one (refreshed
  /// in the background once older than [refreshAfter]), else downloaded and
  /// saved. Throws [NoTileException] or the network error otherwise.
  Future<List<int>> load(CampusTileSource s, int z, int x, int y) async {
    final f = await _file(s, z, x, y);
    if (await f.exists()) {
      final bytes = await f.readAsBytes();
      final age = _now().difference(await f.lastModified());
      if (age > refreshAfter) {
        unawaited(_fetchAndSave(s, z, x, y, f)
            .then<void>((_) {}, onError: (Object _) {}));
      }
      if (_isNoTileMarker(bytes)) throw NoTileException(s.url(z, x, y));
      return bytes;
    }
    return _fetchAndSave(s, z, x, y, f);
  }

  /// Downloads every campus tile of [sources] not yet saved. Stops early
  /// after [maxConsecutiveFailures] network failures in a row (offline).
  /// Throws when any tile failed, so the caller retries on its next run.
  Future<TileWarmResult> warm(
      {List<CampusTileSource> sources = CampusTileSource.all}) async {
    if (_warming) return const TileWarmResult();
    _warming = true;
    var downloaded = 0, saved = 0, failed = 0, failStreak = 0;
    try {
      final todo = <(CampusTileSource, int, int, int, File)>[];
      for (final s in sources) {
        for (final (z, x, y) in allTiles()) {
          final f = await _file(s, z, x, y);
          if (await f.exists()) {
            saved++;
          } else {
            todo.add((s, z, x, y, f));
          }
        }
      }
      var next = 0;
      Future<void> worker() async {
        while (next < todo.length && failStreak < maxConsecutiveFailures) {
          final (s, z, x, y, f) = todo[next++];
          try {
            await _fetchAndSave(s, z, x, y, f);
            downloaded++;
            failStreak = 0;
          } on NoTileException {
            failStreak = 0; // the server answered — not a failure
          } catch (e) {
            failed++;
            failStreak++;
            debugPrint('🗺 Tile $z/$x/$y (${s.id}) failed: ${e.runtimeType}');
          }
        }
      }

      await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
      // Tiles never tried because the warm-up stopped early count as failed.
      failed += todo.length - next;
      await prune();
    } finally {
      _warming = false;
    }
    debugPrint('🗺 Campus tiles: $downloaded downloaded, $saved already '
        'saved, $failed failed');
    final result = TileWarmResult(
        downloaded: downloaded, alreadySaved: saved, failed: failed);
    if (failed > 0) {
      throw Exception('$failed campus map tile(s) could not be downloaded');
    }
    return result;
  }

  /// Total bytes of saved tiles.
  Future<int> sizeBytes() async =>
      (await _tileFiles()).fold<int>(0, (sum, e) => sum + e.$2.size);

  Future<List<(File, FileStat)>> _tileFiles() async {
    final root = await (_root ??= _directory());
    if (!await root.exists()) return const [];
    final out = <(File, FileStat)>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File && e.path.endsWith('.tile')) out.add((e, await e.stat()));
    }
    return out;
  }

  /// Deletes the oldest tiles until the cache is at most 90% of [maxBytes].
  /// Never throws.
  Future<void> prune() async {
    try {
      final files = await _tileFiles();
      var total = files.fold<int>(0, (sum, e) => sum + e.$2.size);
      if (total <= maxBytes) return;
      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      final target = maxBytes * 0.9;
      for (final (f, stat) in files) {
        if (total <= target) break;
        try {
          await f.delete();
          total -= stat.size;
        } catch (_) {}
      }
      debugPrint('🗺 Tile cache pruned to ${(total / 1048576).round()} MB');
    } catch (e) {
      debugPrint('🗺 Tile cache prune failed: $e');
    }
  }

  // ───────────────────────── network ─────────────────────────

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  static Future<List<int>> _httpDownload(Uri url) async {
    final req = await _http.getUrl(url).timeout(const Duration(seconds: 15));
    req.headers.set(HttpHeaders.userAgentHeader,
        'flutter_map (${MapTilerConfig.userAgentPackageName})');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode == HttpStatus.noContent ||
        res.statusCode == HttpStatus.notFound) {
      await res.drain<void>();
      throw NoTileException(url);
    }
    if (res.statusCode != HttpStatus.ok) {
      await res.drain<void>();
      throw HttpException('HTTP ${res.statusCode}', uri: url);
    }
    return consolidateHttpClientResponseBytes(res)
        .timeout(const Duration(seconds: 30));
  }
}
