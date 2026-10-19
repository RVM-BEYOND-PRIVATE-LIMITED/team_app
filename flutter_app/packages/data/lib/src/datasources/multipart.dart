import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Content-type for a filename, so the multipart part carries a correct MIME
/// header. Some backends (e.g. the avatar endpoint) validate `file.type`, so
/// an absent/incorrect content-type would be rejected.
DioMediaType? mediaTypeFor(String filename) {
  final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'pdf' => DioMediaType('application', 'pdf'),
    'jpg' || 'jpeg' => DioMediaType('image', 'jpeg'),
    'png' => DioMediaType('image', 'png'),
    'webp' => DioMediaType('image', 'webp'),
    _ => null,
  };
}

/// Builds a dio [MultipartFile] from in-memory bytes (works on every platform,
/// including web where there is no file path). Avoids copying the buffer when
/// the picker already handed us a [Uint8List] (it does), so peak memory during
/// an upload isn't transiently doubled.
MultipartFile multipartFromBytes(List<int> bytes, String filename) => MultipartFile.fromBytes(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      filename: filename,
      contentType: mediaTypeFor(filename),
    );
