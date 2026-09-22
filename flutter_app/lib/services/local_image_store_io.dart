import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

Future<String?> saveLocalImage(XFile image) async {
  final root = await getApplicationDocumentsDirectory();
  final imageDirectory = Directory('${root.path}/server_images');
  await imageDirectory.create(recursive: true);
  final extension =
      image.name.contains('.') ? image.name.split('.').last : 'jpg';
  final destination = File(
    '${imageDirectory.path}/server_cover_${DateTime.now().millisecondsSinceEpoch}.$extension',
  );
  await File(image.path).copy(destination.path);

  final database = await _openDatabase();
  await database.insert('local_images', {
    'path': destination.path,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });
  await database.close();
  return destination.path;
}

Future<Database> _openDatabase() async {
  final databasePath = await getDatabasesPath();
  return openDatabase(
    '$databasePath/local_images.db',
    version: 1,
    onCreate: (database, _) => database.execute('''
      CREATE TABLE local_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    '''),
  );
}
