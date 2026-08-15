import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/scanner_provider.dart';
import '../services/export_service.dart';
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
    with WidgetsBindingObserver {
  final TextEditingController _manualController = TextEditingController();
  final FocusNode _manualFocusNode = FocusNode(debugLabel: 'ManualEntry');
  bool _showCollectionsModal = false;
  bool _isForcedNewList = false;
  bool _isFabMenuOpen = false;

  // Support for physical "keyboard wedge" scanners whose output method is
  // set to "Input Method" (e.g. the M40-6761L10 handheld's built-in 2D
  // imager). In that output mode the device registers its scan engine as
  // the active Android input method, so pulling the trigger injects the
  // decoded text straight into whichever text field currently has focus -
  // exactly as if it had been typed - usually followed by an Enter. So the
  // fix is simply to make sure the manual entry field stays focused and
  // ready while this mode is enabled, and to keep re-focusing it after
  // each scan so consecutive trigger-pulls keep working.
  bool _hardwareReaderActive = false;
  Timer? _hardwareReaderDebounce;
  int _lastManualTextLength = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hardwareReaderDebounce?.cancel();
    _manualController.dispose();
    _manualFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-claim focus for the physical reader after coming back from the
    // background (e.g. after switching apps), so the M40-6761L10 keeps
    // working without the user needing to tap the field again.
    if (state == AppLifecycleState.resumed && _hardwareReaderActive) {
      _requestManualFocus();
    }
  }

  void _requestManualFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hardwareReaderActive) {
        FocusScope.of(context).requestFocus(_manualFocusNode);
      }
    });
  }

  void _toggleHardwareReader() {
    setState(() => _hardwareReaderActive = !_hardwareReaderActive);
    final provider = context.read<ScannerProvider>();
    if (_hardwareReaderActive) {
      _requestManualFocus();
      provider.showFeedback(
        'Leitor físico ativo — aponte e dispare (M40-6761L10)',
      );
    } else {
      _manualFocusNode.unfocus();
      provider.showFeedback('Leitor físico desativado');
    }
  }

  void _handleManualTextChanged(String text) {
    _hardwareReaderDebounce?.cancel();

    // Devices in "Input Method" output mode almost always append an Enter,
    // which arrives via onSubmitted below. As a safety net for
    // configurations that don't send one, if a big chunk of text lands in
    // one go (an IME "commitText" call, not a human keystroke) and then
    // nothing changes for a short beat, treat it as a completed scan.
    final grew = text.length - _lastManualTextLength;
    _lastManualTextLength = text.length;

    if (_hardwareReaderActive && grew >= 4) {
      _hardwareReaderDebounce = Timer(const Duration(milliseconds: 350), () {
        if (_manualController.text.trim() == text.trim() && text.isNotEmpty) {
          _addManual();
        }
      });
    }
  }

  void _addManual() {
    final code = _manualController.text.trim();
    if (code.isNotEmpty) {
      if (_hardwareReaderActive) {
        context.read<ScannerProvider>().registerHardwareScan(code);
      } else {
        context.read<ScannerProvider>().addItemToActiveList(code);
      }
      _manualController.clear();
      _lastManualTextLength = 0;
      if (_hardwareReaderActive) {
        _requestManualFocus();
      }
    }
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

                        // Scanner Viewport
                        scanner_viewport.ScannerViewport(),
                        const SizedBox(height: 12),

                        // Dynamic Status Zone
                        scanner_status.ScannerStatusZone(),
                        const SizedBox(height: 12),

                        // Manual Entry Field (also the capture target for
                        // hardware scanners using "Input Method" output,
                        // like the M40-6761L10 - see the toggle button)
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1F2937,
                            ).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _hardwareReaderActive
                                  ? const Color(0xFFEC4899)
                                      .withValues(alpha: 0.6)
                                  : const Color(
                                      0xFF374151,
                                    ).withValues(alpha: 0.5),
                            ),
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
                                    child: Center(
                                      child: FaIcon(
                                        FontAwesomeIcons.microchip,
                                        color: _hardwareReaderActive
                                            ? Colors.white
                                            : Colors.white70,
                                        size: 14,
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
                                    keyboardType: _hardwareReaderActive
                                        ? TextInputType.text
                                        : TextInputType.number,
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
                                    onChanged: _handleManualTextChanged,
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
