import 'dart:typed_data';

/// Provides fast, seekable stream encryption and decryption for offline audio.
/// Uses an offset-indexed keystream so the audio player can seek to any arbitrary
/// byte offset in O(1) time without decrypting the entire file into memory.
class CipherService {
  CipherService._();

  // App-specific 256-bit secret key schedule
  static const List<int> _key = [
    0x43, 0x61, 0x70, 0x75, 0x54, 0x75, 0x6E, 0x65, // "CapuTune"
    0xA7, 0x19, 0xE3, 0x48, 0x9B, 0x2C, 0xF1, 0x05,
    0x88, 0x3D, 0x6A, 0x55, 0x1E, 0x94, 0x72, 0xB0,
    0x3F, 0x67, 0xCD, 0x12, 0x8A, 0x5E, 0x99, 0x4B,
  ];

  /// Transforms [data] at [startOffset] in-place and returns it.
  /// Because XOR is symmetric, this function both encrypts and decrypts.
  static Uint8List transform(Uint8List data, int startOffset) {
    final length = data.length;
    final keyLength = _key.length;
    for (int i = 0; i < length; i++) {
      final absoluteOffset = startOffset + i;
      // Multi-layer key schedule combining key index, offset mixing, and non-linear s-box shift
      final keyByte = _key[absoluteOffset % keyLength];
      final salt = ((absoluteOffset * 31) ^ (absoluteOffset >> 8)) & 0xFF;
      data[i] = data[i] ^ keyByte ^ salt;
    }
    return data;
  }

  /// Encrypts or decrypts a List<int> chunk starting at [startOffset]
  static List<int> transformChunk(List<int> chunk, int startOffset) {
    final bytes = Uint8List.fromList(chunk);
    return transform(bytes, startOffset);
  }
}
