import 'package:flutter_test/flutter_test.dart';
import 'package:scanner/main.dart';

void main() {
  testWidgets('App renders startup screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ScannerProApp());
    expect(find.text('Scanner Pro'), findsOneWidget);
  });
}
