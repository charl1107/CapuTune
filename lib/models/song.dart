class Song {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? thumbnail;
  final String? duration;
  final String? localPath;
  final String? localSourcePath;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.thumbnail,
    this.duration,
    this.localPath,
    this.localSourcePath,
  });

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
    };
  }
}
