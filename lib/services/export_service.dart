import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExportService {
  /// Export items map to TXT and trigger Share
  static Future<bool> exportToCsv(String collectionName, Map<String, int> items) async {
    if (items.isEmpty) return false;

    final StringBuffer csvBuffer = StringBuffer();

    items.forEach((code, quantity) {
      csvBuffer.writeln('$code,$quantity');
    });

    final csvData = csvBuffer.toString();
    final sanitizedName = collectionName.replaceAll(RegExp(r'[^\w\s\-]'), '_');
    final filename = '$sanitizedName.txt';

    if (kIsWeb) {
      // On web, share text directly or trigger download
      await Share.share(csvData, subject: filename);
      return true;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$filename');
      await file.writeAsString(csvData);

      final xFile = XFile(file.path, mimeType: 'text/plain');
      await Share.shareXFiles([xFile], text: 'Exportação: $collectionName');
      return true;
    } catch (e) {
      debugPrint("Export error: $e");
      // Fallback share text
      await Share.share(csvData, subject: filename);
      return true;
    }
  }
}      debugPrint("Export error: $e");
      // Fallback share text
      await Share.share(csvData, subject: filename);
      return true;
    }
  }
}
