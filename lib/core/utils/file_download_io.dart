import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> downloadFile(
  String filename,
  List<int> bytes,
  String mimeType,
) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      title: filename,
      files: [XFile(file.path, mimeType: mimeType)],
      fileNameOverrides: [filename],
    ),
  );
}
