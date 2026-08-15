import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/collection_model.dart';
import '../models/detected_barcode.dart';
import '../services/storage_service.dart';

class ScannerProvider extends ChangeNotifier {
  AppStateData _appState = AppStateData(lists: {});
  bool _isLoading = true;
  bool _showStartupModal = true;
  bool _isScanning = false;
  bool _torchActive = false;

  DateTime? _lastScanTime;
  int _scanConfirmationMs = 2000;

  // Toast / feedback message state
  String? _feedbackText;
  Timer? _feedbackTimer;

  // Barcodes currently visible in the camera preview (or just captured by an
  // external hardware scanner) that are awaiting user confirmation before
  // being added to the active list. Keyed by raw code so multiple distinct
  // formats (EAN-13, Code128, QR-Code, ...) can be tracked at once. Using a
  // LinkedHashMap (the default Map literal) keeps insertion order stable so
  // the UI list doesn't jump around between frames.
  final Map<String, DetectedBarcode> _pendingBarcodes = {};

  // Codes that were just added (or explicitly dismissed) and should be
  // ignored for a little while even if the camera keeps reporting them,
  // so a confirmed/dismissed prompt doesn't instantly reappear while the
  // same physical barcode is still sitting in front of the lens.
  final Map<String, DateTime> _recentlyHandled = {};
  static const _pendingCooldown = Duration(milliseconds: 2500);

  // Getters
  bool get isLoading => _isLoading;
  bool get showStartupModal => _showStartupModal;
  bool get isScanning => _isScanning;
  bool get torchActive => _torchActive;
  String? get feedbackText => _feedbackText;
  List<DetectedBarcode> get pendingBarcodes =>
      List.unmodifiable(_pendingBarcodes.values);
  bool get hasPendingBarcodes => _pendingBarcodes.isNotEmpty;
  int get scanConfirmationMs => _scanConfirmationMs;

  AppStateData get appState => _appState;

  InventoryCollection? get activeCollection {
    if (_appState.activeListId == null) return null;
    return _appState.lists[_appState.activeListId];
  }

  List<InventoryCollection> get sortedCollections {
    final list = _appState.lists.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  ScannerProvider() {
    init();
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    final loadedState = await StorageService.loadAppState();
    if (loadedState != null && loadedState.lists.isNotEmpty) {
      _appState = loadedState;
      if (_appState.activeListId == null ||
        !_appState.lists.containsKey(_appState.activeListId)) {
        _appState.activeListId = sortedCollections.first.id;
        }
        _showStartupModal = true;
    } else {
      // Create initial default list if none exists
      final defaultId = DateTime.now().millisecondsSinceEpoch.toString();
      final defaultCollection = InventoryCollection(
        id: defaultId,
        name: 'Lista Principal',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      _appState = AppStateData(
        lists: {defaultId: defaultCollection},
        activeListId: defaultId,
      );
      await _saveState();
      _showStartupModal = true;
    }

    _isLoading = false;
    notifyListeners();
  }

  void handleStartupChoice(String choice, {BuildContext? context}) {
    _showStartupModal = false;
    if (choice == 'new') {
      // Open new collection modal flow
    } else {
      // Continue last list
      showFeedback('Lista ativa: ${activeCollection?.name ?? ""}');
    }
    notifyListeners();
  }

  // Camera & Scanning Controls
  void setScanning(bool scanning) {
    _isScanning = scanning;
    if (!scanning) {
      _torchActive = false;
    }
    notifyListeners();
  }

  void setScanConfirmationMs(int milliseconds) {
    _scanConfirmationMs = milliseconds;
    notifyListeners();
  }

  void toggleTorch() {
    _torchActive = !_torchActive;
    notifyListeners();
  }

  /// Process a scanned barcode while suppressing immediate duplicate frames.
  bool onBarcodeScanned(String code) {
    final now = DateTime.now();
    if (_lastScanTime != null &&
      now.difference(_lastScanTime!).inMilliseconds < _scanConfirmationMs) {
      // Cooldown active, ignore scan
      return false;
      }

      _lastScanTime = now;
    addItemToActiveList(code, viaScan: true);
    return true;
  }

  /// Called (every camera frame) by the viewport with the full set of
  /// barcodes currently visible that require explicit confirmation — i.e.
  /// everything except a lone auto-adding EAN-13, which is handled by its
  /// own hold-to-confirm countdown directly on the preview. Supports any
  /// mix of formats (EAN-13, Code128, QR-Code, etc.) shown simultaneously.
  void syncDetectedBarcodes(List<DetectedBarcode> detected) {
    final now = DateTime.now();
    _recentlyHandled.removeWhere(
      (_, handledAt) => now.difference(handledAt) > _pendingCooldown,
    );

    final filtered = _recentlyHandled.isEmpty
        ? detected
        : detected.where((d) => !_recentlyHandled.containsKey(d.code)).toList();

    final newKeys = filtered.map((d) => d.code).toSet();
    final currentKeys = _pendingBarcodes.keys.toSet();
    if (newKeys.length == currentKeys.length &&
        newKeys.containsAll(currentKeys)) {
      // Same set of codes as last frame (labels/format for a given code
      // never change), nothing to update.
      return;
    }

    _pendingBarcodes.removeWhere((code, _) => !newKeys.contains(code));
    for (final barcode in filtered) {
      _pendingBarcodes[barcode.code] = barcode;
    }
    notifyListeners();
  }

  /// User confirmed they want a detected barcode added to the active list.
  void confirmPendingBarcode(String code) {
    final barcode = _pendingBarcodes[code];
    if (barcode == null) return;
    _pendingBarcodes.remove(code);
    _recentlyHandled[code] = DateTime.now();
    addItemToActiveList(code, viaScan: barcode.fromCamera);
  }

  /// User dismissed a detected barcode without adding it.
  void dismissPendingBarcode(String code) {
    if (_pendingBarcodes.remove(code) != null) {
      _recentlyHandled[code] = DateTime.now();
      notifyListeners();
    }
  }

  void clearPendingBarcodes() {
    _recentlyHandled.clear();
    if (_pendingBarcodes.isEmpty) return;
    _pendingBarcodes.clear();
    notifyListeners();
  }

  /// Handles a code captured by an external keyboard-wedge hardware
  /// scanner (e.g. the M40-6761L10 handheld's built-in 2D imager, or any
  /// Bluetooth/USB scanner configured in "keyboard emulation" mode). Those
  /// devices are triggered by a deliberate button press, so — unlike the
  /// passive camera preview, which may see several codes at once — the
  /// scanned code is added immediately, mirroring fast hand-held inventory
  /// workflows.
  void registerHardwareScan(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    // addItemToActiveList already raises a descriptive feedback toast
    // ("Novo Item: ..." / "Adicionado: ... (xN)"), so nothing else to do.
    addItemToActiveList(trimmed, viaScan: true);
  }

  void addItemToActiveList(String code, {bool viaScan = false}) {
    final active = activeCollection;
    if (active == null) return;

    final trimmed = code.trim();
    if (trimmed.isEmpty) return;

    // Prevents this exact code from instantly reappearing in the pending
    // confirmation list while it's still sitting in the camera's view
    // right after being added (covers the auto-add hold-timer path too).
    _recentlyHandled[trimmed] = DateTime.now();

    // Trigger haptic vibration for camera additions
    if (viaScan) {
      HapticFeedback.vibrate();
      HapticFeedback.heavyImpact();
    }

    if (active.items.containsKey(trimmed)) {
      active.items[trimmed] = (active.items[trimmed] ?? 0) + 1;
      showFeedback('Adicionado: $trimmed (x${active.items[trimmed]})');
    } else {
      active.items[trimmed] = 1;
      showFeedback('Novo Item: $trimmed');
    }

    _saveState();
    notifyListeners();
  }

  void clearActiveList() {
    final active = activeCollection;
    if (active == null || active.items.isEmpty) return;

    active.items.clear();
    _saveState();
    showFeedback('Lista limpa');
    notifyListeners();
  }

  void updateItemQuantity(String code, int delta) {
    final active = activeCollection;
    if (active == null) return;

    if (!active.items.containsKey(code)) return;

    final currentQty = active.items[code] ?? 0;
    final newQty = currentQty + delta;

    if (newQty <= 0) {
      active.items.remove(code);
      showFeedback('Item removido: $code');
    } else {
      active.items[code] = newQty;
    }

    _saveState();
    notifyListeners();
  }

  void setItemQuantity(String code, int quantity) {
    final active = activeCollection;
    if (active == null || !active.items.containsKey(code)) return;

    if (quantity <= 0) {
      active.items.remove(code);
      showFeedback('Item removido: $code');
    } else {
      active.items[code] = quantity;
      showFeedback('Quantidade atualizada: $code (x$quantity)');
    }

    _saveState();
    notifyListeners();
  }

  // Collection Management
  String createNewCollection(String name) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return '';

    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final newCollection = InventoryCollection(
      id: newId,
      name: trimmedName,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    _appState.lists[newId] = newCollection;
    _appState.activeListId = newId;

    _saveState();
    showFeedback('Coleção "$trimmedName" criada');
    notifyListeners();
    return newId;
  }

  void switchActiveCollection(String id) {
    if (_appState.lists.containsKey(id)) {
      _appState.activeListId = id;
      _saveState();
      showFeedback('Alternou para: ${activeCollection?.name}');
      notifyListeners();
    }
  }

  void deleteCollection(String id) {
    if (_appState.lists.length <= 1) {
      showFeedback('Não é possível excluir a única lista.');
      return;
    }

    _appState.lists.remove(id);
    if (_appState.activeListId == id) {
      _appState.activeListId = sortedCollections.first.id;
    }

    _saveState();
    showFeedback('Coleção excluída');
    notifyListeners();
  }

  // Feedback notifications
  void showFeedback(String msg) {
    _feedbackText = msg;
    _feedbackTimer?.cancel();
    notifyListeners();

    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      _feedbackText = null;
      notifyListeners();
    });
  }

  Future<void> _saveState() async {
    await StorageService.saveAppState(_appState);
  }
}
