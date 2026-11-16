import 'dart:convert';

import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart'
    if (dart.library.io) 'file_download_io.dart'
    as platform;

/// Downloads or shares CSV content, including a UTF-8 BOM for spreadsheet apps.
Future<void> downloadCsv(String filename, String csvContent) =>
    platform.downloadFile(
      filename,
      utf8.encode('\uFEFF$csvContent'),
      'text/csv;charset=utf-8',
    );

/// Downloads or shares a file with the supplied bytes and MIME type.
Future<void> downloadBytes(String filename, List<int> bytes, String mimeType) =>
    platform.downloadFile(filename, bytes, mimeType);
