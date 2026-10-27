import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/song.dart';
import '../models/playlist.dart';

class StorageService {
  static final ValueNotifier<int> playlistsRevision = ValueNotifier<int>(0);
  static const String localMusicPlaylistId = 'local-music';

  static late Box _settingsBox;
  static late Box _playlistsBox;
  static late Box _recentsBox;
  static late Box _playCountsBox;
  static late Box _downloadsBox;
  static late Box _searchesBox;
  static late Box _favoritesBox;

  static Future<void> init() async {
    _settingsBox = await Hive.openBox('settings');
    _playlistsBox = await Hive.openBox('playlists');
    _recentsBox = await Hive.openBox('recents');
    _playCountsBox = await Hive.openBox('playCounts');
    _downloadsBox = await Hive.openBox('downloads');
    _searchesBox = await Hive.openBox('searches');
    _favoritesBox = await Hive.openBox('favorites');
  }

  static bool getDarkMode() =>
      _settingsBox.get('darkMode', defaultValue: false);
  static void setDarkMode(bool value) => _settingsBox.put('darkMode', value);

  static bool getAutoplay() => _settingsBox.get('autoplay', defaultValue: true);
  static void setAutoplay(bool value) => _settingsBox.put('autoplay', value);

  static bool getContinueWithSimilarAfterPlaylist() =>
      _settingsBox.get('continueWithSimilarAfterPlaylist', defaultValue: false);
  static void setContinueWithSimilarAfterPlaylist(bool value) =>
      _settingsBox.put('continueWithSimilarAfterPlaylist', value);

  static String getAudioQuality() =>
      _settingsBox.get('audioQuality', defaultValue: '320kbps');
  static void setAudioQuality(String value) =>
      _settingsBox.put('audioQuality', value);

  /// Generic typed settings access (theme system uses these).
  ///
  /// Defensive: a stored value of an unexpected type (e.g. a bool written
  /// under a string key) falls back to [defaultValue] instead of throwing
  /// during startup.
  static T getSetting<T>(T defaultValue, {required String key}) {
    final stored = _settingsBox.get(key);
    if (stored is T) return stored;
    return defaultValue;
  }

  static void setSetting<T>(T value, {required String key}) =>
      _settingsBox.put(key, value);

  // ── Resilient JSON helpers ───────────────────────────────────────────
  //
  // Every stored collection is a JSON string. A truncated write, a manual
  // edit, or a future format drift must never crash startup or wipe the
  // user's data, so reads decode defensively: unreadable entries are
  // skipped, and a wholly unreadable payload is copied to `<key>.corrupt`
  // (once) so it can be recovered instead of silently discarded.

  static List<Map<String, dynamic>> _decodeMapList(Box box, String key) {
    final raw = box.get(key, defaultValue: '[]');
    if (raw is! String) return const [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } on FormatException {
      _preserveCorrupt(box, key, raw);
      return const [];
    }
  }

  static List<String> _decodeStringList(Box box, String key) {
    final raw = box.get(key, defaultValue: '[]');
    if (raw is! String) return const [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList();
    } on FormatException {
      _preserveCorrupt(box, key, raw);
      return const [];
    }
  }

  static void _preserveCorrupt(Box box, String key, String raw) {
    try {
      if (!box.containsKey('$key.corrupt')) {
        box.put('$key.corrupt', raw);
      }
    } catch (_) {
      // Best-effort only: never let diagnostics break a read.
    }
  }

  static List<Playlist> getPlaylists() {
    return _decodeMapList(_playlistsBox, 'playlists')
        .map(Playlist.fromJson)
        .toList();
  }

  static Future<void> savePlaylists(List<Playlist> playlists) async {
    final data = playlists.map((p) => p.toJson()).toList();
    await _playlistsBox.put('playlists', json.encode(data));
    playlistsRevision.value++;
  }

  static Future<void> addPlaylist(Playlist playlist) async {
    final playlists = getPlaylists();
    playlists.add(playlist);
    await savePlaylists(playlists);
  }

  static Future<int> addLocalSongs(List<Song> songs) async {
    final playlists = getPlaylists();
    final index = playlists.indexWhere(
      (playlist) => playlist.id == localMusicPlaylistId,
    );
    final currentPlaylist = index == -1
        ? Playlist(id: localMusicPlaylistId, name: 'Local Music')
        : playlists[index];
    final knownPaths = <String>{
      for (final song in currentPlaylist.songs)
        if (song.localSourcePath != null)
          song.localSourcePath!
        else if (song.localPath != null)
          song.localPath!,
    };
    final additions = <Song>[];
    for (final song in songs) {
      final path = song.localSourcePath ?? song.localPath;
      if (path != null && knownPaths.add(path)) additions.add(song);
    }
    if (additions.isEmpty) return 0;

    final updatedPlaylist = currentPlaylist.copyWith(
      songs: [...currentPlaylist.songs, ...additions],
    );
    if (index == -1) {
      playlists.add(updatedPlaylist);
    } else {
      playlists[index] = updatedPlaylist;
    }
    await savePlaylists(playlists);
    return additions.length;
  }

  static Future<void> deletePlaylist(String id) async {
    final playlists = getPlaylists();
    playlists.removeWhere((p) => p.id == id);
    await savePlaylists(playlists);
  }

  static List<Song> getRecentPlays() {
    return _decodeMapList(_recentsBox, 'recents').map(Song.fromJson).toList();
  }

  static Future<void> addRecentPlay(Song song) async {
    final recents = getRecentPlays();
    recents.removeWhere((s) => s.id == song.id);
    recents.insert(0, song);
    if (recents.length > 50) recents.removeLast();
    final data = recents.map((s) => s.toJson()).toList();
    await _recentsBox.put('recents', json.encode(data));
  }

  static int getPlayCount(String songId) =>
      _playCountsBox.get(songId, defaultValue: 0);

  static Future<void> incrementPlayCount(String songId) async {
    final count = getPlayCount(songId);
    await _playCountsBox.put(songId, count + 1);
  }

  static List<Song> getMostPlayed({int limit = 10}) {
    final allSongs = getRecentPlays();
    final songMap = {for (var s in allSongs) s.id: s};

    // Get songs with play counts, sorted by count. Play counts are stored as
    // ints; a malformed value is ignored rather than crashing the sort.
    final entries = _playCountsBox
        .toMap()
        .entries
        .where((e) => e.key is String && e.value is int)
        .toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));

    final result = <Song>[];
    final addedIds = <String>{};

    // Add songs with play counts first
    for (var entry in entries) {
      if (result.length >= limit) break;
      final key = entry.key as String;
      if (songMap.containsKey(key)) {
        result.add(songMap[key]!);
        addedIds.add(key);
      }
    }

    // Fill remaining with recent songs not yet added
    for (var song in allSongs) {
      if (result.length >= limit) break;
      if (!addedIds.contains(song.id)) {
        result.add(song);
        addedIds.add(song.id);
      }
    }

    return result;
  }

  static List<Song> getDownloads() {
    return _decodeMapList(_downloadsBox, 'downloads')
        .map(Song.fromJson)
        .toList();
  }

  static Future<void> addDownload(Song song) async {
    final downloads = getDownloads();
    if (downloads.any((s) => s.id == song.id)) return;
    downloads.insert(0, song);
    await _downloadsBox.put(
        'downloads', json.encode(downloads.map((s) => s.toJson()).toList()));
  }

  static Future<void> removeDownload(String songId) async {
    final downloads = getDownloads();
    downloads.removeWhere((s) => s.id == songId);
    await _downloadsBox.put(
        'downloads', json.encode(downloads.map((s) => s.toJson()).toList()));
  }

  static bool isDownloaded(String songId) =>
      getDownloads().any((s) => s.id == songId);

  static List<String> getRecentSearches() {
    return _decodeStringList(_searchesBox, 'searches');
  }

  static Future<void> addRecentSearch(String query) async {
    if (query.trim().isEmpty) return;
    final searches = getRecentSearches();
    searches.remove(query);
    searches.insert(0, query);
    if (searches.length > 20) searches.removeLast();
    await _searchesBox.put('searches', json.encode(searches));
  }

  static Future<void> removeRecentSearch(String query) async {
    final searches = getRecentSearches();
    searches.remove(query);
    await _searchesBox.put('searches', json.encode(searches));
  }

  static Future<void> clearRecentSearches() async {
    await _searchesBox.put('searches', json.encode([]));
  }

  static List<Song> getFavorites() {
    return _decodeMapList(_favoritesBox, 'favorites')
        .map(Song.fromJson)
        .toList();
  }

  static Future<void> addFavorite(Song song) async {
    final favorites = getFavorites();
    if (favorites.any((s) => s.id == song.id)) return;
    favorites.insert(0, song);
    await _favoritesBox.put(
        'favorites', json.encode(favorites.map((s) => s.toJson()).toList()));
  }

  static Future<void> removeFavorite(String songId) async {
    final favorites = getFavorites();
    favorites.removeWhere((s) => s.id == songId);
    await _favoritesBox.put(
        'favorites', json.encode(favorites.map((s) => s.toJson()).toList()));
  }

  static bool isFavorite(String songId) =>
      getFavorites().any((s) => s.id == songId);

  // ── Update dismissal ─────────────────────────────────────────────────

  static String? getDismissedUpdateVersion() =>
      _settingsBox.get('dismissedUpdateVersion') as String?;

  static void setDismissedUpdateVersion(String version) =>
      _settingsBox.put('dismissedUpdateVersion', version);

  // ── Playlist rename ──────────────────────────────────────────────────

  static Future<void> renamePlaylist(String id, String newName) async {
    final playlists = getPlaylists();
    final index = playlists.indexWhere((p) => p.id == id);
    if (index == -1) return;
    playlists[index] = playlists[index].copyWith(name: newName);
    await savePlaylists(playlists);
  }

  // ── Library import ───────────────────────────────────────────────────

  /// Imports playlists from a previously exported caputune-library JSON
  /// string. Returns the number of playlists imported. Existing playlists
  /// with the same ID are skipped (not overwritten) to avoid data loss.
  ///
  /// Both the current `caputune-library` marker and the legacy
  /// `nekomusic-library` marker are accepted, so exports made before the
  /// rename still import.
  ///
  /// Throws [FormatException] when [jsonString] is not valid JSON; the caller
  /// surfaces that as a clear, non-destructive error.
  static Future<int> importLibraryJson(String jsonString) async {
    final parsed = json.decode(jsonString);
    if (parsed is! Map<String, dynamic>) return 0;
    final format = parsed['format'];
    if (format != 'caputune-library' && format != 'nekomusic-library') {
      return 0;
    }

    final importedPlaylists = <Playlist>[];
    final rawPlaylists = parsed['playlists'];
    if (rawPlaylists is! List) return 0;
    for (final raw in rawPlaylists) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id'];
      if (id is! String || id.trim().isEmpty) continue; // malformed entry
      final rawTracks = raw['tracks'];
      final tracks = <Song>[];
      if (rawTracks is List) {
        for (final t in rawTracks) {
          if (t is Map<String, dynamic>) tracks.add(Song.fromJson(t));
        }
      }
      final name = raw['name'];
      importedPlaylists.add(Playlist(
        id: id,
        name: (name is String && name.trim().isNotEmpty) ? name : 'Imported',
        description:
            raw['description'] is String ? raw['description'] as String : null,
        songs: tracks,
        createdAt: raw['createdAt'] is String
            ? DateTime.tryParse(raw['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      ));
    }

    if (importedPlaylists.isEmpty) return 0;

    // Never overwrite an existing playlist: an import is additive.
    final existing = getPlaylists();
    final existingIds = existing.map((p) => p.id).toSet();
    final toAdd =
        importedPlaylists.where((p) => !existingIds.contains(p.id)).toList();
    if (toAdd.isEmpty) return 0;

    await savePlaylists([...existing, ...toAdd]);
    return toAdd.length;
  }
}
