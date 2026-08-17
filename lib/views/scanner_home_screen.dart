import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/scanner_provider.dart';
import '../services/export_service.dart';
import '../services/scanner_broadcast_service.dart';
import '../utils/ean_validator.dart';
import '../widgets/glass_card.dart';
import '../widgets/scanner_viewport.dart' as scanner_viewport;
import '../widgets/scanner_status_zone.dart' as scanner_status;
import '../widgets/startup_dialog.dart';
import '../widgets/collections_modal.dart';

class ScannerHomeScreen extends StatefulWidget {
  const ScannerHomeScreen({super.key});

  @override
  State<ScannerHomeScreen> createState() => _ScannerHomeScreenState();
}

class _ScannerHomeScreenState extends State<ScannerHomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final TextEditingController _manualController = TextEditingController();
  final FocusNode _manualFocusNode = FocusNode(debugLabel: 'ManualEntry');
  bool _showCollectionsModal = false;
  bool _isForcedNewList = false;
  bool _isFabMenuOpen = false;

  // Physical reader mode uses the M40 scanner's Broadcast Output directly.
  // No TextField focus, keyboard emulation, or TextInput.hide is involved.
  bool _hardwareReaderActive = false;
  String? _lastHardwareBarcode;
  late final AnimationController _readerPulseController;
  late final AnimationController _readerSweepController;
  bool _appIsFocused = false;
  StreamSubscription<String>? _scannerSubscription;
  final ScannerBroadcastService _scannerBroadcastService =
      ScannerBroadcastService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _readerSweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    _appIsFocused =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerSubscription?.cancel();
    _readerPulseController.dispose();
    _readerSweepController.dispose();
    _manualController.dispose();
    _manualFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final focused = state == AppLifecycleState.resumed;
    if (_appIsFocused == focused) return;

    _appIsFocused = focused;

    // Do not leave the M40 broadcast receiver subscribed while another app is
    // in the foreground. This is important because the scanner can continue
    // broadcasting even when this Flutter app is paused/backgrounded.
    if (!_appIsFocused) {
      _stopScannerBroadcastListener();
      return;
    }

    if (_hardwareReaderActive) {
      _startScannerBroadcastListener();
    }
  }

  void _toggleHardwareReader() {
    final next = !_hardwareReaderActive;
    setState(() {
      _hardwareReaderActive = next;
      _manualFocusNode.canRequestFocus = !next;
      if (!next) _lastHardwareBarcode = null;
    });

    if (next) {
      _readerPulseController.repeat(reverse: true);
      _readerSweepController.repeat();
      _manualFocusNode.unfocus();
      if (_appIsFocused) {
        _startScannerBroadcastListener();
      }
      context.read<ScannerProvider>().showFeedback(
        'Leitor físico ativo — aponte e dispare (M40-6761L10)',
      );
    } else {
      _readerPulseController.stop();
      _readerPulseController.value = 0;
      _readerSweepController.stop();
      _readerSweepController.value = 0;
      _stopScannerBroadcastListener();
      _manualFocusNode.canRequestFocus = true;
      _manualFocusNode.unfocus();
      context.read<ScannerProvider>().showFeedback('Leitor físico desativado');
    }
  }

  Future<void> _startScannerBroadcastListener() async {
    await _scannerSubscription?.cancel();
    _scannerSubscription = null;

    if (!mounted || !_hardwareReaderActive || !_appIsFocused) return;

    _scannerSubscription = _scannerBroadcastService.scans.listen(
      (barcode) {
        // A broadcast can already be queued when Android transitions the app
        // to the background. Guard the delivery as well as unregistering the
        // receiver in didChangeAppLifecycleState, so a background scan can
        // never mutate the inventory.
        if (!mounted || !_hardwareReaderActive || !_appIsFocused) return;
        setState(() => _lastHardwareBarcode = barcode);
        context.read<ScannerProvider>().registerHardwareScan(barcode);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || !_hardwareReaderActive) return;
        context
            .read<ScannerProvider>()
            .showFeedback('Erro no leitor físico: $error');
      },
    );
  }

  Future<void> _stopScannerBroadcastListener() async {
    await _scannerSubscription?.cancel();
    _scannerSubscription = null;
  }

  Widget _buildPhysicalReaderPanel() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _readerPulseController,
        _readerSweepController,
      ]),
      builder: (context, child) {
        final pulse = _readerPulseController.value;
        final glow = 0.10 + (pulse * 0.12);

        return Container(
          key: const ValueKey('physical-reader-mode'),
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFEC4899).withValues(alpha: 0.13),
                const Color(0xFF9333EA).withValues(alpha: 0.10),
                const Color(0xFF1F2937).withValues(alpha: 0.45),
              ],
            ),
            border: Border.all(
              color: const Color(0xFFEC4899).withValues(alpha: 0.42 + pulse * 0.25),
              width: 1.2 + pulse * 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEC4899).withValues(alpha: glow),
                blurRadius: 24 + pulse * 10,
                spreadRadius: pulse * 2,
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFEC4899).withValues(alpha: 0.16 + pulse * 0.10),
                      border: Border.all(
                        color: const Color(0xFFEC4899).withValues(alpha: 0.45),
                      ),
                    ),
                    child: Center(
                      child: Transform.scale(
                        scale: 1.0 + pulse * 0.08,
                        child: const FaIcon(
                          FontAwesomeIcons.barcode,
                          color: Color(0xFFF9A8D4),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF34D399),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF34D399).withValues(alpha: 0.45 + pulse * 0.25),
                                    blurRadius: 8 + pulse * 4,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'LEITOR FÍSICO ATIVO',
                              style: TextStyle(
                                color: Color(0xFFF9A8D4),
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'M40 • Broadcast Output',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;
                  final beamWidth = (trackWidth * 0.30).clamp(64.0, 150.0);
                  final sweep = _readerSweepController.value;
                  final beamLeft =
                      -beamWidth + ((trackWidth + beamWidth) * sweep);

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 7,
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.045),
                                  const Color(0xFFEC4899).withValues(alpha: 0.10),
                                  const Color(0xFFA855F7).withValues(alpha: 0.07),
                                ],
                              ),
                            ),
                            child: const SizedBox.expand(),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 2,
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFFEC4899).withValues(alpha: 0.20),
                                    const Color(0xFFA855F7).withValues(alpha: 0.28),
                                    const Color(0xFFEC4899).withValues(alpha: 0.20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: beamLeft,
                            top: 0,
                            width: beamWidth,
                            height: 7,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0x00EC4899),
                                    Color(0xFFEC4899),
                                    Color(0xFFA855F7),
                                    Color(0x00A855F7),
                                  ],
                                  stops: [0.0, 0.38, 0.62, 1.0],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFEC4899)
                                        .withValues(alpha: 0.34 + pulse * 0.18),
                                    blurRadius: 10 + pulse * 5,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: FractionallySizedBox(
                              widthFactor: 0.12 + pulse * 0.04,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFFA855F7).withValues(alpha: 0.0),
                                      const Color(0xFFA855F7).withValues(alpha: 0.24),
                                    ],
                                  ),
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
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: child,
                  ),
                ),
                child: _lastHardwareBarcode == null
                    ? const Text(
                        'Aguardando leitura…',
                        key: ValueKey('waiting-for-scan'),
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Row(
                        key: ValueKey(_lastHardwareBarcode),
                        children: [
                          const FaIcon(
                            FontAwesomeIcons.circleCheck,
                            color: Color(0xFF34D399),
                            size: 13,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Recebido: $_lastHardwareBarcode',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _addManual() {
    final code = _manualController.text.trim();
    if (code.isEmpty || _hardwareReaderActive) return;

    context.read<ScannerProvider>().addItemToActiveList(code);
    _manualController.clear();
  }

  Future<void> _handleExport() async {
    final provider = context.read<ScannerProvider>();
    final active = provider.activeCollection;

    if (active == null || active.items.isEmpty) {
      _showErrorDialog(context, 'Lista Vazia', 'Não há itens para exportar.');
      return;
    }

    final success = await ExportService.exportToCsv(active.name, active.items);
    if (!success) {
      if (mounted) {
        _showErrorDialog(
          context,
          'Erro ao Exportar',
          'Não foi possível gerar o arquivo CSV.',
        );
      }
    }
  }

  Future<void> _confirmClearList() async {
    final active = context.read<ScannerProvider>().activeCollection;
    if (active == null || active.items.isEmpty) return;

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text(
          'Limpar lista?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Todos os itens da lista ativa serão removidos.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Limpar',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (shouldClear == true && mounted) {
      context.read<ScannerProvider>().clearActiveList();
    }
  }

  Future<void> _editItemQuantity(String code, int currentQuantity) async {
    final controller = TextEditingController(text: '$currentQuantity');
    final quantity = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text(
          'Definir quantidade',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Quantidade',
            labelStyle: TextStyle(color: Colors.white70),
          ),
          onSubmitted: (value) =>
          Navigator.pop(ctx, int.tryParse(value.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () =>
            Navigator.pop(ctx, int.tryParse(controller.text.trim())),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (quantity != null && mounted) {
      context.read<ScannerProvider>().setItemQuantity(code, quantity);
    }
  }

  Future<void> _chooseScanDelay() async {
    final provider = context.read<ScannerProvider>();
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text(
          'Tempo para confirmar código',
          style: TextStyle(color: Colors.white),
        ),
        children: [500, 1000, 2000]
        .map(
          (milliseconds) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, milliseconds),
            child: Text(
              '${milliseconds ~/ 1000 == 0 ? '0,5' : milliseconds ~/ 1000} segundo${milliseconds == 1000 ? '' : 's'}',
              style: TextStyle(
                color: milliseconds == provider.scanConfirmationMs
                ? const Color(0xFFEC4899)
                : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        )
        .toList(),
      ),
    );

    if (selected != null && mounted) {
      context.read<ScannerProvider>().setScanConfirmationMs(selected);
    }
  }

  void _showErrorDialog(BuildContext context, String title, String msg) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1F2937),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const FaIcon(
                    FontAwesomeIcons.triangleExclamation,
                    color: Colors.red,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                msg,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Fechar',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScannerProvider>();

    if (provider.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFEC4899)),
        ),
      );
    }

    final activeCollection = provider.activeCollection;
    final itemsMap = activeCollection?.items ?? {};
    final itemCodes = itemsMap.keys.toList().reversed.toList();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // Main Content
          SafeArea(
            child: Column(
              children: [
                // Top Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEC4899),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFEC4899,
                                    ).withValues(alpha: 0.3),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: FaIcon(
                                  FontAwesomeIcons.barcode,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Scanner',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            InkWell(
                              onTap: _confirmClearList,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.1,
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.redAccent.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                child: const FaIcon(
                                  FontAwesomeIcons.trash,
                                  color: Colors.redAccent,
                                  size: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _handleExport,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFEC4899,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFEC4899,
                                    ).withValues(alpha: 0.3),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    FaIcon(
                                      FontAwesomeIcons.shareNodes,
                                      color: Color(0xFFEC4899),
                                      size: 12,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Exportar',
                                      style: TextStyle(
                                        color: Color(0xFFEC4899),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Scrollable Content Body
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Active List & Total SKU count
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'LISTA ATIVA',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF6B7280),
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    activeCollection?.name ?? '...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF1F2937,
                                ).withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF1F2937),
                                ),
                              ),
                              child: Text(
                                '${activeCollection?.uniqueSkuCount ?? 0}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: Color(0xFFF472B6),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 420),
                          reverseDuration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(
                              begin: const Offset(0, 0.08),
                              end: Offset.zero,
                            ).animate(animation);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            );
                          },
                          child: _hardwareReaderActive
                              ? Column(
                                  key: const ValueKey('physical-reader-mode-stack'),
                                  children: [
                                    _buildPhysicalReaderPanel(),
                                    const SizedBox(height: 12),
                                    // Keep the same status zone visible in
                                    // physical-reader mode. The camera is
                                    // removed, but status/feedback must not
                                    // disappear with it.
                                    const scanner_status.ScannerStatusZone(),
                                    const SizedBox(height: 12),
                                  ],
                                )
                              : Column(
                                  key: const ValueKey('camera-mode'),
                                  children: [
                                    scanner_viewport.ScannerViewport(),
                                    const SizedBox(height: 12),
                                    scanner_status.ScannerStatusZone(),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                        ),

                        // Manual entry remains available when the physical
                        // reader is disabled. In physical-reader mode it is
                        // deliberately read-only and cannot request focus.
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _hardwareReaderActive
                                ? const Color(0xFFEC4899).withValues(alpha: 0.08)
                                : const Color(0xFF1F2937).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(
                              _hardwareReaderActive ? 24 : 20,
                            ),
                            border: Border.all(
                              color: _hardwareReaderActive
                                  ? const Color(0xFFEC4899).withValues(alpha: 0.65)
                                  : const Color(0xFF374151).withValues(alpha: 0.5),
                              width: _hardwareReaderActive ? 1.4 : 1,
                            ),
                            boxShadow: _hardwareReaderActive
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFEC4899)
                                          .withValues(alpha: 0.12),
                                      blurRadius: 18,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            children: [
                              Tooltip(
                                message: _hardwareReaderActive
                                    ? 'Leitor físico ativo (toque para desativar)'
                                    : 'Ativar leitor físico M40-6761L10',
                                child: InkWell(
                                  onTap: _toggleHardwareReader,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _hardwareReaderActive
                                          ? const Color(0xFFEC4899)
                                          : const Color(0xFF374151),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: AnimatedScale(
                                      scale: _hardwareReaderActive ? 1.08 : 1.0,
                                      duration: const Duration(milliseconds: 260),
                                      curve: Curves.easeOutBack,
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 220),
                                        child: FaIcon(
                                          _hardwareReaderActive
                                              ? FontAwesomeIcons.barcode
                                              : FontAwesomeIcons.microchip,
                                          key: ValueKey(_hardwareReaderActive),
                                          color: _hardwareReaderActive
                                              ? Colors.white
                                              : Colors.white70,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: TextField(
                                    controller: _manualController,
                                    focusNode: _manualFocusNode,
                                    readOnly: _hardwareReaderActive,
                                    showCursor: !_hardwareReaderActive,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.done,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: _hardwareReaderActive
                                          ? 'Aguardando leitor físico...'
                                          : 'Digitar código manualmente...',
                                      hintStyle: const TextStyle(
                                        color: Color(0xFF9CA3AF),
                                        fontSize: 14,
                                      ),
                                      border: InputBorder.none,
                                    ),
                                    onSubmitted: (_) => _addManual(),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: _addManual,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF374151),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Center(
                                    child: FaIcon(
                                      FontAwesomeIcons.plus,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Inventory Items List / Empty State
                        if (itemCodes.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40.0),
                            child: Center(
                              child: Column(
                                children: [
                                  FaIcon(
                                    FontAwesomeIcons.boxOpen,
                                    size: 48,
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'NENHUM ITEM LIDO',
                                    style: TextStyle(
                                      color: Color(0xFF4B5563),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: itemCodes.length,
                              separatorBuilder: (_, index) =>
                              const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final code = itemCodes[index];
                                final qty = itemsMap[code] ?? 0;
                                final isEan13 = EanValidator.validateEAN13(code);

                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF1F2937,
                                    ).withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.05),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              code,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: Colors.white,
                                                letterSpacing: 1.0,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              isEan13 ? 'EAN-13' : 'MANUAL',
                                              style: const TextStyle(
                                                fontSize: 9,
                                                color: Color(0xFF6B7280),
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 1.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.3,
                                              ),
                                              borderRadius: BorderRadius.circular(
                                                16,
                                              ),
                                              border: Border.all(
                                                color: const Color(
                                                  0xFF374151,
                                                ).withValues(alpha: 0.5),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                InkWell(
                                                  onTap: () =>
                                                  provider.updateItemQuantity(
                                                    code,
                                                    -1,
                                                  ),
                                                  borderRadius:
                                                  BorderRadius.circular(12),
                                                  child: Container(
                                                    width: 32,
                                                    height: 32,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFF374151,
                                                      ),
                                                      borderRadius:
                                                      BorderRadius.circular(
                                                        12,
                                                      ),
                                                    ),
                                                    child: const Center(
                                                      child: Text(
                                                        '-',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                          FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                InkWell(
                                                  onTap: () => _editItemQuantity(
                                                    code,
                                                    qty,
                                                  ),
                                                  borderRadius:
                                                  BorderRadius.circular(8),
                                                  child: SizedBox(
                                                    width: 40,
                                                    child: Text(
                                                      '$qty',
                                                      textAlign: TextAlign.center,
                                                      style: const TextStyle(
                                                        color: Color(0xFFEC4899),
                                                        fontWeight:
                                                        FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                InkWell(
                                                  onTap: () =>
                                                  provider.updateItemQuantity(
                                                    code,
                                                    1,
                                                  ),
                                                  borderRadius:
                                                  BorderRadius.circular(12),
                                                  child: Container(
                                                    width: 32,
                                                    height: 32,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFF374151,
                                                      ),
                                                      borderRadius:
                                                      BorderRadius.circular(
                                                        12,
                                                      ),
                                                    ),
                                                    child: const Center(
                                                      child: Text(
                                                        '+',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                          FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Right Expandable Floating Menu
          Positioned(
            bottom: 24,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_isFabMenuOpen) ...[
                  // Floating sub-button: Delay settings
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2937),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: const Text(
                          'Tempo de Leitura',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'fab_delay',
                        backgroundColor: const Color(0xFF9333EA),
                        onPressed: () {
                          setState(() => _isFabMenuOpen = false);
                          _chooseScanDelay();
                        },
                        child: const FaIcon(
                          FontAwesomeIcons.clock,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Floating sub-button: Collections
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2937),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: const Text(
                          'Coleções',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'fab_collections',
                        backgroundColor: const Color(0xFFEC4899),
                        onPressed: () {
                          setState(() {
                            _isFabMenuOpen = false;
                            _isForcedNewList = false;
                            _showCollectionsModal = true;
                          });
                        },
                        child: const FaIcon(
                          FontAwesomeIcons.layerGroup,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Main Floating Action Button
                FloatingActionButton(
                  heroTag: 'fab_main',
                  backgroundColor: const Color(0xFFEC4899),
                  onPressed: () {
                    setState(() {
                      _isFabMenuOpen = !_isFabMenuOpen;
                    });
                  },
                  child: FaIcon(
                    _isFabMenuOpen
                    ? FontAwesomeIcons.xmark
                    : FontAwesomeIcons.layerGroup,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          // Collections Modal Overlay
          if (_showCollectionsModal)
            Positioned.fill(
              child: CollectionsModal(
                isForcedNew: _isForcedNewList,
                onClose: () {
                  setState(() {
                    _showCollectionsModal = false;
                    _isForcedNewList = false;
                  });
                },
              ),
            ),

            // Startup Dialog Overlay
            if (provider.showStartupModal)
              Positioned.fill(
                child: StartupDialog(
                  onStartNewColection: () {
                    setState(() {
                      _isForcedNewList = true;
                      _showCollectionsModal = true;
                    });
                  },
                ),
              ),
        ],
      ),
    );
  }
}
