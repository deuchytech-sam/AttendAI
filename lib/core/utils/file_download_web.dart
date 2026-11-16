import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> downloadFile(
  String filename,
  List<int> bytes,
  String mimeType,
) async {
  final data = Uint8List.fromList(bytes);
  final blob = web.Blob([data.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final objectUrl = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = objectUrl
    ..download = filename
    ..style.display = 'none';

  web.document.body?.append(anchor);
  try {
    anchor.click();
  } finally {
    anchor.remove();
    web.URL.revokeObjectURL(objectUrl);
  }
}
