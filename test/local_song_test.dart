import 'package:flutter_test/flutter_test.dart';
import 'package:caputune/models/song.dart';

void main() {
  test('local file references survive song JSON round-trip', () {
    final song = Song(
      id: 'local-test',
      title: 'Local track',
      artist: 'Local audio',
      localPath: '/app/local_music/local-test/track.mp3',
      localSourcePath: '/picked/track.mp3',
    );

    final restored = Song.fromJson(song.toJson());

    expect(restored.localPath, song.localPath);
    expect(restored.localSourcePath, song.localSourcePath);
  });
}
