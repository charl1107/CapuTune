import '../models/song.dart';
import 'storage_service.dart';

/// Which attribute songs are grouped by in the Albums/Artists view.
enum CollectionSource { albums, artists }

/// Builds the song universe behind the Albums/Artists view.
///
/// Songs are gathered from every place the library stores or has seen them
/// (favorites, downloads, recent/most played, playlists incl. Local Music)
/// and deduplicated by id, first occurrence wins. Grouping keys fall back to
/// "Unknown …" since some sources (e.g. older persisted data) may lack
/// album metadata; artist is always present on a Song.
class CollectionService {
  /// Every distinct song visible to the library's grouping views.
  static List<Song> collectSongs() {
    final seen = <String>{};
    final songs = <Song>[];
    for (final song in [
      ...StorageService.getFavorites(),
      ...StorageService.getDownloads(),
      ...StorageService.getRecentPlays(),
      ...StorageService.getMostPlayed(limit: 100),
      ...StorageService.getPlaylists().expand((p) => p.songs),
    ]) {
      if (seen.add(song.id)) songs.add(song);
    }
    return songs;
  }

  /// Groups [songs] by album or artist, keys sorted alphabetically.
  static Map<String, List<Song>> groupSongs(
    List<Song> songs,
    CollectionSource source,
  ) {
    final groups = <String, List<Song>>{};
    for (final song in songs) {
      final key = switch (source) {
        CollectionSource.albums => song.album ?? 'Unknown Album',
        CollectionSource.artists => song.artist,
      };
      groups.putIfAbsent(key, () => []).add(song);
    }
    final sortedKeys = groups.keys.toList()..sort();
    return {for (final key in sortedKeys) key: groups[key]!};
  }

  /// Convenience for the screen: collect + group in one call.
  static Map<String, List<Song>> buildGroups(CollectionSource source) =>
      groupSongs(collectSongs(), source);
}
