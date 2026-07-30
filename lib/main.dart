import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/scanner_provider.dart';
import 'views/scanner_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScannerProApp());
}

class ScannerProApp extends StatelessWidget {
  const ScannerProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScannerProvider(),
      child: MaterialApp(
        title: 'Scanner Pro',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF121212),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFEC4899),
            secondary: Color(0xFF9333EA),
            surface: Color(0xFF1F2937),
          ),
          textTheme: GoogleFonts.nunitoTextTheme(
            ThemeData.dark().textTheme,
          ),
        ),
        home: const ScannerHomeScreen(),
      ),
    );
  }
}
