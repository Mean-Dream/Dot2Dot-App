import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

Future<void> saveImageBytes(Uint8List bytes, String filename) async {
  // Write to a temp file then hand off to the OS gallery (gal handles
  // NSPhotoLibraryAddUsageDescription on iOS and MediaStore on Android).
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  await Gal.putImage(file.path, album: 'Dot2Dot');
  await file.delete();
}
