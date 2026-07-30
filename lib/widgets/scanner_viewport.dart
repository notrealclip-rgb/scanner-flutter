import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Keep the visual tracker responsive between camera callbacks.
  Timer? _overlayTimer;
  String? _trackedCode;
  Rect? _targetRect;
  Rect? _currentRect;
  bool _showTrackingOverlay = false;
  String? _nonEanCode;
  String? _nonEanFormat;
  double _holdProgress = 0.0; // 0.0 to 1.0 over 2 seconds
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
      // `noDuplicates` reports a code only once, which freezes its tracker.
      // Unrestricted callbacks keep the target rectangle moving; item
      // insertion is still protected by the confirmation period below.
      detectionSpeed: DetectionSpeed.unrestricted,
      torchEnabled: false,
      returnImage: false,
      // We call start()/stop() ourselves from the button handler below.
      // Leaving this at the default (true) makes the MobileScanner widget
      // *also* call start() internally as soon as it remounts, racing our
      // manual start() call. That double-start is what left the preview
      // black/frozen the second time the camera was started.
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

    // Short grace window: keep the square displayed across a couple of
    // skipped camera frames, but clear quickly once the barcode is
    // actually gone so we don't keep "tracking" a ghost box.
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
      });
      return;
    }

    // Smooth the overlay without forcing the camera preview to rebuild at 60fps.
    if (_targetRect != null && _trackedCode != null) {
      setState(() {
        if (_currentRect == null) {
          _currentRect = _targetRect;
        } else {
          _currentRect = Rect.lerp(_currentRect, _targetRect, 0.35);
        }

        // Calculate elapsed display time
        if (_displayStartTime != null) {
          final elapsedMs = now.difference(_displayStartTime!).inMilliseconds;
          _holdProgress = (elapsedMs / confirmationMs).clamp(0.0, 1.0);

          // A short confirmation avoids duplicate reads without making the
          // scanner feel unresponsive.
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
    provider.addItemToActiveList(code);
    HapticFeedback.mediumImpact();
    _lastAddCompletedTime = DateTime.now();

    // Pause the countdown instead of restarting it here. Restarting it
    // immediately reused the last known (possibly stale) bounding box, so
    // if the barcode had already left the frame the ring would silently
    // fill up again and re-add the same item using a "ghost" position that
    // no camera frame actually confirmed. Only a genuine new detection in
    // _handleBarcodeDetect (below) is allowed to restart the timer.
    _displayStartTime = null;
    _holdProgress = 0.0;
  }

  void _handleBarcodeDetect(BarcodeCapture capture, Size viewportSize) {
    final now = DateTime.now();
    final List<Barcode> barcodes = capture.barcodes;
    Barcode? validEanBarcode;

    Barcode? nonEanBarcode;
    for (final barcode in barcodes) {
      final code = barcode.rawValue;
      if (code != null &&
          barcode.format == BarcodeFormat.ean13 &&
          EanValidator.validateEAN13(code)) {
        validEanBarcode = barcode;
        break;
      }
      if (code != null && code.trim().isNotEmpty) {
        nonEanBarcode ??= barcode;
      }
    }

    if (validEanBarcode == null) {
      final code = nonEanBarcode?.rawValue?.trim();
      if (code != null && code != _nonEanCode) {
        setState(() {
          _nonEanCode = code;
          _nonEanFormat = _barcodeFormatLabel(nonEanBarcode!.format);
        });
      }
      return;
    }

    if (_nonEanCode != null) {
      setState(() {
        _nonEanCode = null;
        _nonEanFormat = null;
      });
    }

    final code = validEanBarcode.rawValue!;
    final imageSize = capture.size;

    // Calculate accurate bounding box projected onto portrait viewport screen
    final mappedRect = _projectBarcodeToViewport(
      validEanBarcode: validEanBarcode,
      imageSize: imageSize,
      viewportSize: viewportSize,
    );

    _lastDetectTime = now;

    if (_trackedCode != code) {
      // New barcode target displayed -> start 2-second countdown AFTER displayed
      _trackedCode = code;
      _displayStartTime = now;
      _holdProgress = 0.0;
      _targetRect = mappedRect;
      _currentRect ??= mappedRect;
      _showTrackingOverlay = true;
    } else {
      // Update target position for 60 fps tracking lerp
      _targetRect = mappedRect;
      _displayStartTime ??= now;
    }
  }

  /// Projects raw camera sensor barcode coordinates onto the portrait viewport screen
  Rect _projectBarcodeToViewport({
    required Barcode validEanBarcode,
    required Size imageSize,
    required Size viewportSize,
  }) {
    final corners = validEanBarcode.corners;

    if (imageSize.width <= 0 || imageSize.height <= 0 || corners.isEmpty) {
      // Fallback center box if corners missing
      return Rect.fromCenter(
        center: Offset(viewportSize.width / 2, viewportSize.height / 2),
        width: 200,
        height: 120,
      );
    }

    // On Android, ML Kit has already rotated the barcode coordinates to the
    // portrait preview, while BarcodeCapture.size remains the raw landscape
    // camera buffer. Therefore the coordinate-space dimensions are swapped;
    // applying a second point rotation is incorrect, but using the raw width
    // and height is also incorrect and produces an error that grows at the
    // right and lower edges.
    final imgW = imageSize.height;
    final imgH = imageSize.width;

    // Calculate BoxFit.cover scale & offsets for viewport container
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

    // Keep only a small floor for unstable corner data. The prior 120x80
    // floor made the overlay look detached from small or distant barcodes.
    double boxWidth = max(maxX - minX, 24.0);
    double boxHeight = max(maxY - minY, 24.0);
    double centerX = (minX + maxX) / 2;
    double centerY = (minY + maxY) / 2;

    // Clamp box to viewport bounds
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

                        // Keep the overlay mounted so AnimatedOpacity can
                        // animate both its entrance and its disappearance.
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
                              ),
                            ),
                          ),

                        // Focus Ring animation
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

                        if (_nonEanCode != null)
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 16,
                            child: Material(
                              color: Colors.transparent,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  8,
                                  10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF1F2937,
                                  ).withValues(alpha: 0.94),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.amber.withValues(alpha: 0.7),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Detectado: ${_nonEanFormat ?? 'Outro formato'}',
                                        style: TextStyle(
                                          color: Colors.amber,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _nonEanCode!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'Adicionar à lista',
                                      onPressed: () {
                                        context
                                            .read<ScannerProvider>()
                                            .addItemToActiveList(_nonEanCode!);
                                        HapticFeedback.mediumImpact();
                                        setState(() {
                                          _nonEanCode = null;
                                          _nonEanFormat = null;
                                        });
                                      },
                                      icon: const Icon(Icons.add_circle),
                                      color: Colors.amber,
                                    ),
                                  ],
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

          // Start / Stop Scanner Button Overlay
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isScanning ? Colors.redAccent : Colors.white,
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
                    });
                  } else {
                    // autoStart is false, so we are always the one who
                    // (re)starts the camera. start() on the same controller
                    // after a stop() is what used to leave the preview
                    // black, so we start it explicitly here and nowhere else.
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

/// CustomPainter rendering the tracking square and a short confirmation ring.
class BarcodeTrackingPainter extends CustomPainter {
  final Rect targetRect;
  final String code;
  final double progress;
  final double confirmationSeconds;

  BarcodeTrackingPainter({
    required this.targetRect,
    required this.code,
    required this.progress,
    required this.confirmationSeconds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = targetRect.inflate(8.0);

    const pinkColor = Color(0xFFEC4899);
    const purpleColor = Color(0xFF9333EA);

    // 1. Draw only the base bounding box border; the camera image remains
    // unobscured while the confirmation progress travels around the edge.
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      borderPaint,
    );

    // 2. Draw confirmation progress ring along the perimeter
    if (progress > 0) {
      final progressPaint = Paint()
        ..shader = const LinearGradient(
          colors: [pinkColor, purpleColor],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;

      final path = Path()
        ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)));

      final pathMetrics = path.computeMetrics();
      for (final metric in pathMetrics) {
        final extractPath = metric.extractPath(0.0, metric.length * progress);
        canvas.drawPath(extractPath, progressPaint);
      }
    }

    // 3. Draw Corner Brackets (L-shapes)
    final bracketPaint = Paint()
      ..color = pinkColor
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

    // 4. Draw the decoded value and the short confirmation countdown badge
    final remainingSecs = max(
      0.0,
      confirmationSeconds - (progress * confirmationSeconds),
    ).toStringAsFixed(1);
    final textSpan = TextSpan(
      text: '$code • ${remainingSecs}s',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final textBgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.85)
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
        oldDelegate.confirmationSeconds != confirmationSeconds;
  }
}
