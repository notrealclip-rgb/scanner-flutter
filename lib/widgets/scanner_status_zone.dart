import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/scanner_provider.dart';
import 'glass_card.dart';

/// A single dynamic status strip shown right below the camera preview.
///
/// This replaces what used to be two separate widgets (the persistent
/// status zone + a separate transient feedback toast). It now owns all of
/// the states that can appear in that slot and animates between them, so
/// there's only ever one widget occupying that space:
///  - highest priority: a non-EAN-13 barcode is in view -> prompt asking
///    whether to add it anyway, with a button to do so.
///  - next: a transient feedback message (e.g. "Novo Item: ...") shown for
///    a few seconds right after something happens, then fades back out.
///  - default/fallback: the active list name ("Lista ativa: ..."), which
///    never disappears on its own.
class ScannerStatusZone extends StatelessWidget {
  const ScannerStatusZone({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScannerProvider>();
    final nonEanCode = provider.nonEanCode;
    final feedbackMsg = provider.feedbackText;

    late final Widget content;
    late final String stateKey;

    if (nonEanCode != null) {
      stateKey = 'non_ean';
      content = _NonEanPrompt(code: nonEanCode, format: provider.nonEanFormat);
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

class _NonEanPrompt extends StatelessWidget {
  final String code;
  final String? format;

  const _NonEanPrompt({required this.code, required this.format});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      backgroundColor: Colors.amber.withValues(alpha: 0.12),
      border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.triangleExclamation,
                color: Colors.amber,
                size: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Código não EAN-13 identificado'
                  '${format != null ? ' ($format)' : ''}. '
                  'Adicionar mesmo assim?',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            code,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                final provider = context.read<ScannerProvider>();
                // This came from the camera, so it should vibrate just like
                // any other scan-driven addition.
                provider.addItemToActiveList(code, viaScan: true);
                provider.clearNonEanDetection();
              },
              icon: const Icon(Icons.add_circle, size: 16),
              label: const Text(
                'ADICIONAR MESMO ASSIM',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
