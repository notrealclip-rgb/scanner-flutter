import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/scanner_provider.dart';
import '../utils/ean_validator.dart';

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

  // Visual tracker state
  Timer? _overlayTimer;
  String? _trackedCode;
  Rect? _targetRect;
  Rect? _currentRect;
  bool _showTrackingOverlay = false;
  bool _isYellowOverlay = false;
  double _holdProgress = 0.0;
  DateTime? _displayStartTime;
  DateTime? _lastDetectTime;
  DateTime? _lastAddCompletedTime;

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

  void _updateOverlay() {
    if (!mounted) return;

    final now = DateTime.now();
    final confirmationMs = context.read<ScannerProvider>().scanConfirmationMs;

    if (_lastDetectTime != null &&
      now.difference(_lastDetectTime!).inMilliseconds > 400) {
      setState(() {
        _trackedCode = null;
        _targetRect = null;
        _currentRect = null;
        _holdProgress = 0.0;
        _displayStartTime = null;
        _lastDetectTime = null;
        _showTrackingOverlay = false;
        _isYellowOverlay = false;
      });
      return;
      }

      if (_targetRect != null && _trackedCode != null) {
        setState(() {
          if (_currentRect == null) {
            _currentRect = _targetRect;
          } else {
            _currentRect = Rect.lerp(_currentRect, _targetRect, 0.35);
          }

          // Run auto-add countdown ONLY for normal auto EAN-13 (non-yellow)
          if (!_isYellowOverlay && _displayStartTime != null) {
            final elapsedMs = now.difference(_displayStartTime!).inMilliseconds;
            _holdProgress = (elapsedMs / confirmationMs).clamp(0.0, 1.0);

            if (elapsedMs >= confirmationMs) {
              if (_lastAddCompletedTime == null ||
                now.difference(_lastAddCompletedTime!).inMilliseconds >
                confirmationMs) {
                _on2SecondDisplayCompleted(_trackedCode!);
                }
            }
          }
        });
      }
  }

  void _on2SecondDisplayCompleted(String code) {
    final provider = context.read<ScannerProvider>();
    provider.addItemToActiveList(code, viaScan: true);
    _lastAddCompletedTime = DateTime.now();

    _displayStartTime = null;
    _holdProgress = 0.0;
  }

  void _handleBarcodeDetect(BarcodeCapture capture, Size viewportSize) {
    final now = DateTime.now();
    final List<Barcode> barcodes = capture.barcodes;
    Barcode? validAutoEanBarcode;
    Barcode? nonAutoBarcode;

    for (final barcode in barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.trim().isNotEmpty) {
        // Only standard EAN-13 (excluding JAN codes starting with 45 or 49) can auto-add
        if (barcode.format == BarcodeFormat.ean13 &&
          EanValidator.validateEAN13(code) &&
          !EanValidator.isJanCode(code)) {
          validAutoEanBarcode = barcode;
        break;
          } else {
            nonAutoBarcode ??= barcode;
          }
      }
    }

    if (validAutoEanBarcode != null) {
      context.read<ScannerProvider>().clearNonEanDetection();

      final code = validAutoEanBarcode.rawValue!;
      final mappedRect = _projectBarcodeToViewport(
        validBarcode: validAutoEanBarcode,
        imageSize: capture.size,
        viewportSize: viewportSize,
      );

      _lastDetectTime = now;
      _isYellowOverlay = false;

      if (_trackedCode != code) {
        _trackedCode = code;
        _displayStartTime = now;
        _holdProgress = 0.0;
        _targetRect = mappedRect;
        _currentRect ??= mappedRect;
        _showTrackingOverlay = true;
      } else {
        _targetRect = mappedRect;
        _displayStartTime ??= now;
      }
    } else if (nonAutoBarcode != null) {
      final code = nonAutoBarcode.rawValue!.trim();
      final isJan = nonAutoBarcode.format == BarcodeFormat.ean13 &&
      EanValidator.validateEAN13(code) &&
      EanValidator.isJanCode(code);
      final formatLabel =
      isJan ? 'JAN' : _barcodeFormatLabel(nonAutoBarcode.format);

      context.read<ScannerProvider>().setNonEanDetection(code, formatLabel);

      final mappedRect = _projectBarcodeToViewport(
        validBarcode: nonAutoBarcode,
        imageSize: capture.size,
        viewportSize: viewportSize,
      );

      _lastDetectTime = now;
      _isYellowOverlay = true;
      _trackedCode = code;
      _targetRect = mappedRect;
      _currentRect ??= mappedRect;
      _showTrackingOverlay = true;
      _holdProgress = 0.0;
      _displayStartTime = null; // Do not auto-add
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
      case BarcodeFormat.upcA:
        return 'UPC-A';
      case BarcodeFormat.upcE:
        return 'UPC-E';
      case BarcodeFormat.code128:
        return 'Code 128';
      case BarcodeFormat.code39:
        return 'Code 39';
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
                                opacity: _showTrackingOverlay ? 1 : 0,
                                child: CustomPaint(
                                  size: viewportSize,
                                  painter: BarcodeTrackingPainter(
                                    targetRect: _currentRect ?? Rect.zero,
                                    code: _trackedCode ?? '',
                                    progress: _holdProgress,
                                    confirmationSeconds:
                                    provider.scanConfirmationMs / 1000,
                                    isYellow: _isYellowOverlay,
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
                      setState(() {
                        _trackedCode = null;
                        _targetRect = null;
                        _currentRect = null;
                        _holdProgress = 0.0;
                        _displayStartTime = null;
                        _lastDetectTime = null;
                        _showTrackingOverlay = false;
                        _isYellowOverlay = false;
                      });
                      provider.clearNonEanDetection();
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

class BarcodeTrackingPainter extends CustomPainter {
  final Rect targetRect;
  final String code;
  final double progress;
  final double confirmationSeconds;
  final bool isYellow;

  BarcodeTrackingPainter({
    required this.targetRect,
    required this.code,
    required this.progress,
    required this.confirmationSeconds,
    this.isYellow = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = targetRect.inflate(8.0);

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

    // 2. Draw confirmation progress ring (only for auto EAN-13 codes)
    if (!isYellow && progress > 0) {
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
        metric.extractPath(0.0, metric.length * progress);
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

    // 4. Draw decoded value and countdown badge
    final String text;
    if (isYellow) {
      text = code;
    } else {
      final remainingSecs = max(
        0.0,
        confirmationSeconds - (progress * confirmationSeconds),
      ).toStringAsFixed(1);
      text = '$code • ${remainingSecs}s';
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
    )..layout();

    final textBgPaint = Paint()
    ..color = isYellow
    ? const Color(0xFFEAB308)
    : Colors.black.withValues(alpha: 0.85)
    ..style = PaintingStyle.fill;

    final textOffset = Offset(
      rect.left + (rect.width - textPainter.width) / 2,
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
    return oldDelegate.targetRect != targetRect ||
    oldDelegate.progress != progress ||
    oldDelegate.code != code ||
    oldDelegate.confirmationSeconds != confirmationSeconds ||
    oldDelegate.isYellow != isYellow;
  }
}
