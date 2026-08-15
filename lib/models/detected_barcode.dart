/// Represents a single barcode that is currently visible in the camera
/// viewport (or was just captured by an external hardware scanner) and is
/// awaiting the user's decision to add it to the active list.
///
/// This is transient, in-memory state only — it is never persisted.
class DetectedBarcode {
  /// The raw decoded value of the barcode.
  final String code;

  /// Human readable format label, e.g. "EAN-13", "Code 128", "QR Code".
  final String format;

  /// Whether this entry came from the on-screen camera preview (true) or
  /// from an external keyboard-wedge hardware scanner (false).
  final bool fromCamera;

  const DetectedBarcode({
    required this.code,
    required this.format,
    this.fromCamera = true,
  });

  DetectedBarcode copyWith({String? code, String? format, bool? fromCamera}) {
    return DetectedBarcode(
      code: code ?? this.code,
      format: format ?? this.format,
      fromCamera: fromCamera ?? this.fromCamera,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DetectedBarcode &&
      other.code == code &&
      other.format == format &&
      other.fromCamera == fromCamera;

  @override
  int get hashCode => Object.hash(code, format, fromCamera);
}
