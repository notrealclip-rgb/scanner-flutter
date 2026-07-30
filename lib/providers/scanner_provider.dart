import 'dart:async';
import 'package:flutter/material.dart';
import '../models/collection_model.dart';
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

  // Getters
  bool get isLoading => _isLoading;
  bool get showStartupModal => _showStartupModal;
  bool get isScanning => _isScanning;
  bool get torchActive => _torchActive;
  String? get feedbackText => _feedbackText;
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
    addItemToActiveList(code);
    return true;
  }

  void addItemToActiveList(String code) {
    final active = activeCollection;
    if (active == null) return;

    final trimmed = code.trim();
    if (trimmed.isEmpty) return;

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
