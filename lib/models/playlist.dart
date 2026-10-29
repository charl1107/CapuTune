import 'song.dart';

class Playlist {
  final String id;
  final String name;
  final String? description;
  final List<Song> songs;
  final DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    List<Song>? songs,
    DateTime? createdAt,
  })  : songs = songs ?? [],
        createdAt = createdAt ?? DateTime.now();

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      songs: (json['songs'] as List?)
              ?.map((s) => Song.fromJson(s))
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'songs': songs.map((s) => s.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  Playlist copyWith({
    String? name,
    String? description,
    List<Song>? songs,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      songs: songs ?? this.songs,
      createdAt: createdAt,
    );
  }

  /// Returns a copy with the song at [oldIndex] moved to [newIndex].
  ///
  /// Uses list-manipulation semantics (not ReorderableListView's raw drag
  /// indices): the target index already accounts for the removed item, so
  /// `reordered(0, 1)` swaps the first two songs.
  Playlist reordered(int oldIndex, int newIndex) {
    final songs = List<Song>.from(this.songs);
    final song = songs.removeAt(oldIndex);
    songs.insert(newIndex, song);
    return copyWith(songs: songs);
  }

  /// Returns a copy with songs sorted by [sort] (case-insensitive).
  Playlist sorted(PlaylistSort sort) {
    final songs = List<Song>.from(this.songs)
      ..sort(
        (a, b) => switch (sort) {
          PlaylistSort.title => a.title.toLowerCase(),
          PlaylistSort.artist => a.artist.toLowerCase(),
        }
            .compareTo(
              switch (sort) {
                PlaylistSort.title => b.title.toLowerCase(),
                PlaylistSort.artist => b.artist.toLowerCase(),
              },
            ),
      );
    return copyWith(songs: songs);
  }
}

/// Sort orders for a playlist's song list.
enum PlaylistSort { title, artist }
