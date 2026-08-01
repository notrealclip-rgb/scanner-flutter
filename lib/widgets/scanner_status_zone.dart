import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/scanner_provider.dart';
import 'glass_card.dart';

/// A persistent status strip shown right below the camera preview.
///
/// Unlike the transient feedback toast (which auto-hides after a few
/// seconds), this zone always shows something relevant to the current
/// scanning state and never disappears on its own:
///  - by default, the active list name ("Lista ativa: ...")
///  - when the camera is seeing a non-EAN-13 barcode, a prompt asking
///    whether to add it anyway, with a button to do so.
class ScannerStatusZone extends StatelessWidget {
  const ScannerStatusZone({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScannerProvider>();
    final nonEanCode = provider.nonEanCode;

    if (nonEanCode != null) {
      return _NonEanPrompt(code: nonEanCode, format: provider.nonEanFormat);
    }

    final activeName = provider.activeCollection?.name;
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
