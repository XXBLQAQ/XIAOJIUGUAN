import 'package:image_picker/image_picker.dart';

Future<String?> saveLocalImage(XFile image) async => image.path;
