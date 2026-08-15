import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../models/detected_barcode.dart';
import '../providers/scanner_provider.dart';
import 'glass_card.dart';

/// A single dynamic status strip shown right below the camera preview.
///
/// It owns all of the states that can appear in that slot and animates
/// between them, so there's only ever one widget occupying that space:
///  - highest priority: one or more barcodes are currently detected in the
///    camera preview and need an explicit decision -> a stacked list of
///    "add this?" prompts, one per barcode, regardless of format (EAN-13,
///    Code128, QR-Code, ...) so they can all be reviewed at the same time.
///  - next: a transient feedback message (e.g. "Novo Item: ...") shown for
///    a few seconds right after something happens, then fades back out.
///  - default/fallback: the active list name ("Lista ativa: ..."), which
///    never disappears on its own.
class ScannerStatusZone extends StatelessWidget {
  const ScannerStatusZone({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScannerProvider>();
    final pending = provider.pendingBarcodes;
    final feedbackMsg = provider.feedbackText;

    late final Widget content;
    late final String stateKey;

    if (pending.isNotEmpty) {
      stateKey = 'pending:${pending.map((b) => b.code).join(',')}';
      content = _PendingBarcodesPanel(barcodes: pending);
    } else if (feedbackMsg != null) {
      stateKey = 'feedback:$feedbackMsg';
      content = _FeedbackBanner(message: feedbackMsg);
    } else {
      final activeName = provider.activeCollection?.name;
      stateKey = 'default';
      content = _DefaultStatus(activeName: activeName);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1,
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(stateKey), child: content),
    );
  }
}

class _DefaultStatus extends StatelessWidget {
  final String? activeName;

  const _DefaultStatus({required this.activeName});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const FaIcon(
            FontAwesomeIcons.listCheck,
            color: Color(0xFFEC4899),
            size: 14,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              activeName != null
                  ? 'Lista ativa: $activeName'
                  : 'Nenhuma lista ativa',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  final String message;

  const _FeedbackBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      backgroundColor: const Color(0xFFEC4899).withValues(alpha: 0.15),
      border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.4)),
      child: Row(
        children: [
          const FaIcon(
            FontAwesomeIcons.circleInfo,
            color: Color(0xFFEC4899),
            size: 14,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFF472B6),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stacked list of "add this?" prompts, one per barcode currently detected
/// in the camera preview. Supports any mix of formats shown at once.
class _PendingBarcodesPanel extends StatelessWidget {
  final List<DetectedBarcode> barcodes;

  const _PendingBarcodesPanel({required this.barcodes});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      backgroundColor: Colors.amber.withValues(alpha: 0.10),
      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.barcode,
                color: Colors.amber,
                size: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  barcodes.length == 1
                      ? '1 código detectado. Adicionar à lista?'
                      : '${barcodes.length} códigos detectados. Adicionar à lista?',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: barcodes.length > 3 ? 220 : double.infinity,
            ),
            child: barcodes.length > 3
                ? ListView.separated(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: barcodes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _PendingBarcodeRow(barcode: barcodes[index]),
                  )
                : Column(
                    children: [
                      for (int i = 0; i < barcodes.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _PendingBarcodeRow(barcode: barcodes[i]),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PendingBarcodeRow extends StatelessWidget {
  final DetectedBarcode barcode;

  const _PendingBarcodeRow({required this.barcode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  barcode.format,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  barcode.code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () =>
                context.read<ScannerProvider>().dismissPendingBarcode(
                      barcode.code,
                    ),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: FaIcon(
                FontAwesomeIcons.xmark,
                color: Colors.white.withValues(alpha: 0.5),
                size: 14,
              ),
            ),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => context
                .read<ScannerProvider>()
                .confirmPendingBarcode(barcode.code),
            icon: const Icon(Icons.add_circle, size: 15),
            label: const Text(
              'ADICIONAR',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
