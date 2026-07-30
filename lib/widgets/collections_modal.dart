import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/scanner_provider.dart';

class CollectionsModal extends StatefulWidget {
  final VoidCallback onClose;
  final bool isForcedNew;

  const CollectionsModal({
    super.key,
    required this.onClose,
    this.isForcedNew = false,
  });

  @override
  State<CollectionsModal> createState() => _CollectionsModalState();
}

class _CollectionsModalState extends State<CollectionsModal> {
  final TextEditingController _nameController = TextEditingController();
  bool _hasError = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _handleCreate() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _hasError = true);
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _hasError = false);
      });
      return;
    }

    final provider = context.read<ScannerProvider>();
    provider.createNewCollection(name);
    _nameController.clear();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScannerProvider>();
    final collections = provider.sortedCollections;
    final activeId = provider.activeCollection?.id;

    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFEC4899), Color(0xFF9333EA)],
                  ).createShader(bounds),
                  child: Text(
                    widget.isForcedNew ? "Nova Coleção" : "Coleções",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (!widget.isForcedNew)
                  InkWell(
                    onTap: widget.onClose,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1F2937),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: FaIcon(
                          FontAwesomeIcons.xmark,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // Input field
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF111827), // bg-gray-900
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: _hasError
                      ? Colors.red
                      : const Color(0xFF374151), // border-gray-700
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      keyboardType: TextInputType.text,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Nome da nova lista...',
                        hintStyle: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _handleCreate(),
                    ),
                  ),
                  InkWell(
                    onTap: _handleCreate,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEC4899),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEC4899).withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: const Center(
                        child: FaIcon(
                          FontAwesomeIcons.plus,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // List of Collections (Hidden if forced new)
            if (!widget.isForcedNew)
              Expanded(
                child: ListView.separated(
                  itemCount: collections.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = collections[index];
                    final isActive = item.id == activeId;

                    return InkWell(
                      onTap: () {
                        provider.switchActiveCollection(item.id);
                        widget.onClose();
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFFEC4899).withValues(alpha: 0.1)
                              : const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isActive
                                ? const Color(0xFFEC4899)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              item.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isActive ? Colors.white : Colors.grey[400],
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '${item.uniqueSkuCount} SKU',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFEC4899),
                                  ),
                                ),
                                if (collections.length > 1) ...[
                                  const SizedBox(width: 12),
                                  IconButton(
                                    icon: const FaIcon(
                                      FontAwesomeIcons.trashCan,
                                      size: 14,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () {
                                      provider.deleteCollection(item.id);
                                    },
                                  )
                                ]
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
