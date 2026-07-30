import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/scanner_provider.dart';
import '../services/export_service.dart';
import '../utils/ean_validator.dart';
import '../widgets/glass_card.dart';
import '../widgets/scanner_viewport.dart';
import '../widgets/startup_dialog.dart';
import '../widgets/collections_modal.dart';

class ScannerHomeScreen extends StatefulWidget {
  const ScannerHomeScreen({super.key});

  @override
  State<ScannerHomeScreen> createState() => _ScannerHomeScreenState();
}

class _ScannerHomeScreenState extends State<ScannerHomeScreen> {
  final TextEditingController _manualController = TextEditingController();
  bool _showCollectionsModal = false;
  bool _isForcedNewList = false;

  @override
  void dispose() { 
    _manualController.dispose();
    super.dispose();
  }

  void _addManual() {
    final code = _manualController.text.trim();
    if (code.isNotEmpty) {
      context.read<ScannerProvider>().addItemToActiveList(code);
      _manualController.clear();
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
    final feedbackMsg = provider.feedbackText;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // Main App Content
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
                              onTap: _chooseScanDelay,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF9333EA,
                                  ).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(
                                      0xFF9333EA,
                                    ).withValues(alpha: 0.35),
                                  ),
                                ),
                                child: const FaIcon(
                                  FontAwesomeIcons.clock,
                                  color: Color(0xFF9333EA),
                                  size: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
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
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Active List & Total SKU count display
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

                        // Scanner Viewport Widget
                        const ScannerViewport(),
                        const SizedBox(height: 16),

                        // Feedback Notification Banner
                        if (feedbackMsg != null)
                          GlassCard(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            backgroundColor: const Color(
                              0xFFEC4899,
                            ).withValues(alpha: 0.15),
                            border: Border.all(
                              color: const Color(
                                0xFFEC4899,
                              ).withValues(alpha: 0.4),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const FaIcon(
                                  FontAwesomeIcons.circleInfo,
                                  color: Color(0xFFEC4899),
                                  size: 16,
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    feedbackMsg,
                                    style: const TextStyle(
                                      color: Color(0xFFF472B6),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Manual Entry Field
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1F2937,
                            ).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(
                                0xFF374151,
                              ).withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: TextField(
                                    controller: _manualController,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.done,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Digitar código manualmente...',
                                      hintStyle: TextStyle(
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

          // Bottom Navigation Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF111827).withValues(alpha: 0.9),
                border: const Border(top: BorderSide(color: Color(0xFF1F2937))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _isForcedNewList = false;
                          _showCollectionsModal = true;
                        });
                      },
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FaIcon(
                            FontAwesomeIcons.layerGroup,
                            color: Color(0xFFEC4899),
                            size: 18,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'COLEÇÕES',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: const Color(0xFF1F2937),
                  ),
                  Expanded(
                    child: Opacity(
                      opacity: 0.4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          FaIcon(
                            FontAwesomeIcons.chartSimple,
                            color: Colors.grey,
                            size: 18,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'STATS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
