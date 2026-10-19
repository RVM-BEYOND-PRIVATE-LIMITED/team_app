/// A file selected for a multipart upload, decoupled from any picker package so
/// the data layer never depends on file_picker. The UI reads bytes from the
/// platform document picker and hands over this neutral value.
class UploadFile {
  const UploadFile({required this.name, required this.bytes, this.contentType});

  final String name;
  final List<int> bytes;

  /// Optional MIME type (e.g. 'image/jpeg'); the server infers one if absent.
  final String? contentType;
}
