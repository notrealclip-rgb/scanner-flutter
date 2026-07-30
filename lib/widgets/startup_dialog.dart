import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/scanner_provider.dart';

class StartupDialog extends StatelessWidget {
  final VoidCallback onStartNewColection;

  const StartupDialog({
    super.key,
    required this.onStartNewColection,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.9),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937), // bg-gray-800
              borderRadius: BorderRadius.circular(40.0), // rounded-[2.5rem]
              border: Border.all(color: const Color(0xFF374151)), // border-gray-700
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 25,
                  offset: Offset(0, 10),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gradient Icon Box
                Transform.rotate(
                  angle: 0.05, // rotate-3
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFEC4899), // from-pink-500
                          Color(0xFF9333EA), // to-purple-600
                        ],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEC4899).withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: const Center(
                      child: FaIcon(
                        FontAwesomeIcons.barcode,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Scanner Pro',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Gerencie seu inventário de forma rápida e organizada.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9CA3AF), // gray-400
                  ),
                ),
                const SizedBox(height: 32),
                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEC4899), // pink-500
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    onPressed: () {
                      context
                          .read<ScannerProvider>()
                          .handleStartupChoice('continue', context: context);
                    },
                    icon: const FaIcon(FontAwesomeIcons.rotateLeft, size: 16),
                    label: const Text(
                      'Continuar Última Lista',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF374151), // bg-gray-700
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      context
                          .read<ScannerProvider>()
                          .handleStartupChoice('new', context: context);
                      onStartNewColection();
                    },
                    child: const Text(
                      '+ Iniciar Nova Coleção',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
