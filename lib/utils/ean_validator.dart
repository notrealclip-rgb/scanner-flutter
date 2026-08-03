/// Utility for EAN-13 barcode validation matching validateEAN13 in JS.
class EanValidator {
  static bool validateEAN13(String code) {
    if (!RegExp(r'^\d{13}$').hasMatch(code)) return false;

    int sum = 0;
    for (int i = 0; i < 12; i++) {
      int digit = int.parse(code[i]);
      sum += digit * (i % 2 == 0 ? 1 : 3);
    }

    int checkDigit = (10 - (sum % 10)) % 10;
    return checkDigit == int.parse(code[12]);
  }

  /// JAN (Japanese Article Number) barcodes are EAN-13 starting with 45 or 49.
  static bool isJanCode(String code) {
    return code.startsWith('45') || code.startsWith('49');
  }
}
