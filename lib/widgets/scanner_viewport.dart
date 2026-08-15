import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../models/detected_barcode.dart';
import '../providers/scanner_provider.dart';
import '../utils/ean_validator.dart';

/// Mutable per-frame tracking state for a single barcode currently visible
/// in the camera preview. Keyed by raw decoded value in [_trackedItems] so
/// several different barcodes (e.g. an EAN-13, a Code128 and a QR-Code)
/// can all be tracked - and drawn - at the same time.
class _TrackedItem {
  final String code;
  String format;
  bool isAutoEan;
  Rect targetRect;
  Rect currentRect;
  DateTime lastDetectTime;
  DateTime? displayStartTime;
  double holdProgress;

  _TrackedItem({
    required this.code,
    required this.format,
    required this.isAutoEan,
    required this.targetRect,
    required this.currentRect,
    required this.lastDetectTime,
    this.displayStartTime,
    this.holdProgress = 0.0,
  });
}

class ScannerViewport extends StatefulWidget {
  const ScannerViewport({super.key});

  @override
  State<ScannerViewport> createState() => _ScannerViewportState();
}

class _ScannerViewportState extends State<ScannerViewport> {
  MobileScannerController? _scannerController;

  // Focus ring state
  Offset? _focusPos;
  bool _showFocusRing = false;

  // Multi-barcode visual tracker state. Every barcode currently visible in
  // the camera frame gets its own entry so the preview can draw a box
  // around each of them simultaneously, regardless of format.
  Timer? _overlayTimer;
  final Map<String, _TrackedItem> _trackedItems = {};

  @override
  void initState() {
    super.initState();
    _initScanner();

    _overlayTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _updateOverlay(),
    );
  }

  void _initScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      torchEnabled: false,
      returnImage: false,
      autoStart: false,
    );
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _scannerController?.dispose();
    super.dispose();
  }

  void _resetTracking() {
    _trackedItems.clear();
    context.read<ScannerProvider>().clearPendingBarcodes();
  }

  void _updateOverlay() {
    if (!mounted) return;

    final now = DateTime.now();
    final provider = context.read<ScannerProvider>();
    final confirmationMs = provider.scanConfirmationMs;

    // Drop anything the camera hasn't reported for a little while.
    _trackedItems.removeWhere(
      (_, item) => now.difference(item.lastDetectTime).inMilliseconds > 400,
    );

    if (_trackedItems.isEmpty) {
      _syncPendingBarcodesToProvider();
      return;
    }

    String? completedAutoAddCode;

    setState(() {
      for (final item in _trackedItems.values) {
        item.currentRect =
            Rect.lerp(item.currentRect, item.targetRect, 0.35) ??
                item.targetRect;

        // Run the auto-add hold countdown ONLY while this code is the sole
        // barcode in frame and it is a plain (non-JAN) EAN-13.
        if (item.isAutoEan) {
          item.displayStartTime ??= now;
          final elapsedMs =
              now.difference(item.displayStartTime!).inMilliseconds;
          item.holdProgress = (elapsedMs / confirmationMs).clamp(0.0, 1.0);

          if (elapsedMs >= confirmationMs) {
            completedAutoAddCode = item.code;
          }
        } else {
          item.displayStartTime = null;
          item.holdProgress = 0.0;
        }
      }
    });

    if (completedAutoAddCode != null) {
      final code = completedAutoAddCode!;
      provider.addItemToActiveList(code, viaScan: true);
      final refreshed = _trackedItems[code];
      if (refreshed != null) {
        refreshed.displayStartTime = null;
        refreshed.holdProgress = 0.0;
      }
    }

    _syncPendingBarcodesToProvider();
  }

  /// Pushes every currently tracked barcode that needs an explicit user
  /// decision (i.e. everything except a lone auto-adding EAN-13) up to the
  /// provider, so the confirmation panel below the preview can show them.
  void _syncPendingBarcodesToProvider() {
    final detected = <DetectedBarcode>[
      for (final item in _trackedItems.values)
        if (!item.isAutoEan)
          DetectedBarcode(code: item.code, format: item.format),
    ];
    context.read<ScannerProvider>().syncDetectedBarcodes(detected);
  }

  void _handleBarcodeDetect(BarcodeCapture capture, Size viewportSize) {
    final now = DateTime.now();
    final List<Barcode> barcodes = capture.barcodes;

    // De-duplicate multiple detections of the same value within one frame.
    final Map<String, Barcode> validByCode = {};
    for (final barcode in barcodes) {
      final code = barcode.rawValue?.trim();
      if (code != null && code.isNotEmpty) {
        validByCode.putIfAbsent(code, () => barcode);
      }
    }

    if (validByCode.isEmpty) return;

    // A barcode only auto-adds via the hold-to-confirm ring when it is the
    // *sole* code visible in the frame AND it's a plain (non-JAN) EAN-13.
    // The instant a second barcode enters the frame, every code - including
    // that EAN-13 - falls back to the explicit "add?" confirmation flow, so
    // several different formats can be reviewed side by side.
    String? soleAutoEanCode;
    if (validByCode.length == 1) {
      final only = validByCode.values.first;
      final code = only.rawValue!.trim();
      if (only.format == BarcodeFormat.ean13 &&
          EanValidator.validateEAN13(code) &&
          !EanValidator.isJanCode(code)) {
        soleAutoEanCode = code;
      }
    }

    for (final entry in validByCode.entries) {
      final code = entry.key;
      final barcode = entry.value;
      final isAutoEan = code == soleAutoEanCode;

      final isJan = barcode.format == BarcodeFormat.ean13 &&
          EanValidator.validateEAN13(code) &&
          EanValidator.isJanCode(code);
      final formatLabel = isJan ? 'JAN' : _barcodeFormatLabel(barcode.format);

      final mappedRect = _projectBarcodeToViewport(
        validBarcode: barcode,
        imageSize: capture.size,
        viewportSize: viewportSize,
      );

      final existing = _trackedItems[code];
      if (existing != null) {
        existing.targetRect = mappedRect;
        existing.lastDetectTime = now;
        existing.format = formatLabel;
        existing.isAutoEan = isAutoEan;
      } else {
        _trackedItems[code] = _TrackedItem(
          code: code,
          format: formatLabel,
          isAutoEan: isAutoEan,
          targetRect: mappedRect,
          currentRect: mappedRect,
          lastDetectTime: now,
          displayStartTime: isAutoEan ? now : null,
        );
      }
    }
  }

  Rect _projectBarcodeToViewport({
    required Barcode validBarcode,
    required Size imageSize,
    required Size viewportSize,
  }) {
    final corners = validBarcode.corners;

    if (imageSize.width <= 0 || imageSize.height <= 0 || corners.isEmpty) {
      return Rect.fromCenter(
        center: Offset(viewportSize.width / 2, viewportSize.height / 2),
        width: 200,
        height: 120,
      );
    }

    final imgW = imageSize.height;
    final imgH = imageSize.width;

    final scale = max(viewportSize.width / imgW, viewportSize.height / imgH);
    final offsetX = (viewportSize.width - (imgW * scale)) / 2;
    final offsetY = (viewportSize.height - (imgH * scale)) / 2;

    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final pt in corners) {
      final normX = pt.dx / imgW;
      final normY = pt.dy / imgH;

      double screenX = offsetX + (normX * imgW * scale);
      double screenY = offsetY + (normY * imgH * scale);

      minX = min(minX, screenX);
      maxX = max(maxX, screenX);
      minY = min(minY, screenY);
      maxY = max(maxY, screenY);
    }

    double boxWidth = max(maxX - minX, 24.0);
    double boxHeight = max(maxY - minY, 24.0);
    double centerX = (minX + maxX) / 2;
    double centerY = (minY + maxY) / 2;

    centerX = centerX.clamp(
      boxWidth / 2 + 10,
      viewportSize.width - boxWidth / 2 - 10,
    );
    centerY = centerY.clamp(
      boxHeight / 2 + 10,
      viewportSize.height - boxHeight / 2 - 10,
    );

    return Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: boxWidth,
      height: boxHeight,
    );
  }

  void _onTapViewport(TapDownDetails details) {
    setState(() {
      _focusPos = details.localPosition;
      _showFocusRing = true;
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showFocusRing = false);
    });
  }

  String _barcodeFormatLabel(BarcodeFormat format) {
    switch (format) {
      case BarcodeFormat.ean8:
        return 'EAN-8';
      case BarcodeFormat.ean13:
        return 'EAN-13';
      case BarcodeFormat.upcA:
        return 'UPC-A';
      case BarcodeFormat.upcE:
        return 'UPC-E';
      case BarcodeFormat.code128:
        return 'Code 128';
      case BarcodeFormat.code39:
        return 'Code 39';
      case BarcodeFormat.code93:
        return 'Code 93';
      case BarcodeFormat.codabar:
        return 'Codabar';
      case BarcodeFormat.itf:
        return 'ITF';
      case BarcodeFormat.dataMatrix:
        return 'Data Matrix';
      case BarcodeFormat.pdf417:
        return 'PDF417';
      case BarcodeFormat.aztec:
        return 'Aztec';
      case BarcodeFormat.qrCode:
        return 'QR Code';
      default:
        return 'Outro formato';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScannerProvider>();
    final isScanning = provider.isScanning;
    final torchActive = provider.torchActive;

    final boxes = _trackedItems.values
        .map(
          (item) => _BoxPaintData(
            rect: item.currentRect,
            code: item.code,
            format: item.format,
            progress: item.holdProgress,
            isYellow: !item.isAutoEan,
          ),
        )
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(40.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Viewport area
          GestureDetector(
            onTapDown: isScanning ? _onTapViewport : null,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewportSize = Size(constraints.maxWidth, 280);

                return Container(
                  height: 280,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(28.0),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28.0),
                    child: Stack(
                      children: [
                        if (isScanning && _scannerController != null)
                          MobileScanner(
                            controller: _scannerController!,
                            onDetect: (capture) =>
                                _handleBarcodeDetect(capture, viewportSize),
                          )
                        else
                          const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FaIcon(
                                  FontAwesomeIcons.camera,
                                  color: Colors.white24,
                                  size: 48,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Câmera Desativada',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (isScanning)
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            opacity: boxes.isNotEmpty ? 1 : 0,
                            child: CustomPaint(
                              size: viewportSize,
                              painter: BarcodeTrackingPainter(
                                boxes: boxes,
                                confirmationSeconds:
                                    provider.scanConfirmationMs / 1000,
                              ),
                            ),
                          ),

                        if (_showFocusRing && _focusPos != null)
                          Positioned(
                            left: _focusPos!.dx - 40,
                            top: _focusPos!.dy - 40,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFEC4899),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Torch Light Toggle Button
          if (isScanning)
            Positioned(
              top: 20,
              right: 20,
              child: InkWell(
                onTap: () {
                  provider.toggleTorch();
                  _scannerController?.toggleTorch();
                },
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: torchActive
                        ? Colors.amber
                        : Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: torchActive
                          ? Colors.amberAccent
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Center(
                    child: FaIcon(
                      FontAwesomeIcons.bolt,
                      color: torchActive ? Colors.black : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),

          // Start / Stop Scanner Button
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isScanning ? Colors.redAccent : Colors.white,
                  foregroundColor: isScanning ? Colors.white : Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                ),
                onPressed: () async {
                  if (isScanning) {
                    await _scannerController?.stop();
                    provider.setScanning(false);
                    setState(_resetTracking);
                  } else {
                    await _scannerController?.start();
                    if (!mounted) return;
                    provider.setScanning(true);
                  }
                },
                icon: FaIcon(
                  isScanning ? FontAwesomeIcons.stop : FontAwesomeIcons.camera,
                  size: 16,
                ),
                label: Text(
                  isScanning ? 'PARAR CÂMERA' : 'INICIAR CÂMERA',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Immutable snapshot of one tracked barcode's box, ready to be painted.
class _BoxPaintData {
  final Rect rect;
  final String code;
  final String format;
  final double progress;
  final bool isYellow;

  const _BoxPaintData({
    required this.rect,
    required this.code,
    required this.format,
    required this.progress,
    required this.isYellow,
  });
}

/// Draws a bounding box (with corner brackets, optional confirmation
/// progress ring, and a decoded-value label) for every barcode currently
/// visible in the camera preview - so an EAN-13, a Code128 and a QR-Code
/// can all be highlighted on screen at once.
class BarcodeTrackingPainter extends CustomPainter {
  final List<_BoxPaintData> boxes;
  final double confirmationSeconds;

  BarcodeTrackingPainter({
    required this.boxes,
    required this.confirmationSeconds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in boxes) {
      _paintBox(canvas, box);
    }
  }

  void _paintBox(Canvas canvas, _BoxPaintData box) {
    final rect = box.rect.inflate(8.0);
    final isYellow = box.isYellow;

    final primaryColor =
        isYellow ? const Color(0xFFEAB308) : const Color(0xFFEC4899);
    final secondaryColor =
        isYellow ? const Color(0xFFFACC15) : const Color(0xFF9333EA);

    // 1. Draw base bounding box border
    final borderPaint = Paint()
      ..color = isYellow
          ? const Color(0xFFEAB308).withValues(alpha: 0.8)
          : Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      borderPaint,
    );

    // 2. Draw confirmation progress ring (only for the lone auto-add EAN-13)
    if (!isYellow && box.progress > 0) {
      final progressPaint = Paint()
        ..shader = LinearGradient(
          colors: [primaryColor, secondaryColor],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;

      final path = Path()
        ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)));

      final pathMetrics = path.computeMetrics();
      for (final metric in pathMetrics) {
        final extractPath =
            metric.extractPath(0.0, metric.length * box.progress);
        canvas.drawPath(extractPath, progressPaint);
      }
    }

    // 3. Draw Corner Brackets
    final bracketPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    const cornerLength = 18.0;

    // Top-Left corner
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + const Offset(cornerLength, 0),
      bracketPaint,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + const Offset(0, cornerLength),
      bracketPaint,
    );

    // Top-Right corner
    canvas.drawLine(
      rect.topRight,
      rect.topRight - const Offset(cornerLength, 0),
      bracketPaint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + const Offset(0, cornerLength),
      bracketPaint,
    );

    // Bottom-Left corner
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + const Offset(cornerLength, 0),
      bracketPaint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft - const Offset(0, cornerLength),
      bracketPaint,
    );

    // Bottom-Right corner
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight - const Offset(cornerLength, 0),
      bracketPaint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight - const Offset(0, cornerLength),
      bracketPaint,
    );

    // 4. Draw format + decoded value / countdown badge
    final String text;
    if (isYellow) {
      text = '${box.format} • ${box.code}';
    } else {
      final remainingSecs = max(
        0.0,
        confirmationSeconds - (box.progress * confirmationSeconds),
      ).toStringAsFixed(1);
      text = '${box.code} • ${remainingSecs}s';
    }

    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: isYellow ? Colors.black : Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        shadows: isYellow
            ? null
            : const [Shadow(color: Colors.black, blurRadius: 4)],
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 220);

    final textBgPaint = Paint()
      ..color = isYellow
          ? const Color(0xFFEAB308)
          : Colors.black.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final textOffset = Offset(
      rect.left.clamp(0, double.infinity),
      (rect.top - 30) < 10 ? rect.bottom + 10 : rect.top - 30,
    );

    final bgRect = Rect.fromLTWH(
      textOffset.dx - 8,
      textOffset.dy - 4,
      textPainter.width + 16,
      textPainter.height + 8,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(10)),
      textBgPaint,
    );

    textPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant BarcodeTrackingPainter oldDelegate) {
    return true;
  }
}
