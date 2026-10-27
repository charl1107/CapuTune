class Song {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? thumbnail;
  final String? duration;
  final String? localPath;
  final String? localSourcePath;

  /// True when this song was appended via recommendation / similar-song autoplay.
  final bool isRecommended;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.thumbnail,
    this.duration,
    this.localPath,
    this.localSourcePath,
    this.isRecommended = false,
  });

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? thumbnail,
    String? duration,
    String? localPath,
    String? localSourcePath,
    bool? isRecommended,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      thumbnail: thumbnail ?? this.thumbnail,
      duration: duration ?? this.duration,
      localPath: localPath ?? this.localPath,
      localSourcePath: localSourcePath ?? this.localSourcePath,
      isRecommended: isRecommended ?? this.isRecommended,
    );
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      album: json['album'],
      thumbnail: json['thumbnail'],
      duration: json['duration'],
      localPath: json['localPath'] as String?,
      localSourcePath: json['localSourcePath'] as String?,
      isRecommended: json['isRecommended'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'thumbnail': thumbnail,
      'duration': duration,
      'localPath': localPath,
      'localSourcePath': localSourcePath,
      if (isRecommended) 'isRecommended': true,
    };
  }
}
