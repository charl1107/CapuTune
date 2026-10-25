import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String?> storePickedAudio(
  String sourcePath,
  String fileName,
  String songId,
) async {
  final source = File(sourcePath);
  if (!await source.exists()) return null;

  final documents = await getApplicationDocumentsDirectory();
  final songDirectory = Directory('${documents.path}/local_music/$songId');
  await songDirectory.create(recursive: true);
  final safeName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  final destination = File('${songDirectory.path}/$safeName');
  return (await source.copy(destination.path)).path;
}
