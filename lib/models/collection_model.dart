import 'dart:convert';

/// Represents a single inventory collection (list)
class InventoryCollection {
  final String id;
  String name;
  final int createdAt;
  /// Map of barcode/code -> quantity count
  Map<String, int> items;

  InventoryCollection({
    required this.id,
    required this.name,
    required this.createdAt,
    Map<String, int>? items,
  }) : items = items ?? {};

  int get totalItemCount => items.values.fold(0, (sum, qty) => sum + qty);
  int get uniqueSkuCount => items.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'items': items,
      };

  factory InventoryCollection.fromJson(Map<String, dynamic> json) {
    Map<String, int> parsedItems = {};
    if (json['items'] != null) {
      (json['items'] as Map<String, dynamic>).forEach((key, value) {
        parsedItems[key] = (value as num).toInt();
      });
    }

    return InventoryCollection(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: (json['createdAt'] as num).toInt(),
      items: parsedItems,
    );
  }
}

/// Represents the overall persistent app state structure
class AppStateData {
  Map<String, InventoryCollection> lists;
  String? activeListId;

  AppStateData({
    required this.lists,
    this.activeListId,
  });

  Map<String, dynamic> toJson() {
    Map<String, dynamic> listsJson = {};
    lists.forEach((key, collection) {
      listsJson[key] = collection.toJson();
    });

    return {
      'lists': listsJson,
      'activeListId': activeListId,
    };
  }

  factory AppStateData.fromJson(Map<String, dynamic> json) {
    Map<String, InventoryCollection> parsedLists = {};
    if (json['lists'] != null) {
      (json['lists'] as Map<String, dynamic>).forEach((key, value) {
        parsedLists[key] =
            InventoryCollection.fromJson(value as Map<String, dynamic>);
      });
    }

    return AppStateData(
      lists: parsedLists,
      activeListId: json['activeListId'] as String?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory AppStateData.fromJsonString(String jsonString) {
    return AppStateData.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }
}
