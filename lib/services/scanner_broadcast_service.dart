import 'dart:async';

import 'package:flutter/services.dart';

/// Receives completed barcode strings directly from the M40 scanner service.
///
/// The M40 must be configured for Broadcast Output with:
/// - Broadcast Action: com.service.scanner.data
/// - Broadcast Code Data Label: ScanCode
class ScannerBroadcastService {
  static const EventChannel _channel =
      EventChannel('com.example.scanner/stream');

  Stream<String> get scans => _channel
      .receiveBroadcastStream()
      .where((event) => event != null)
      .map((event) => event.toString().trim())
      .where((value) => value.isNotEmpty);
}
