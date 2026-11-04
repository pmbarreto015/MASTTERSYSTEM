import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/license_provider.dart';
import 'screens/main_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/license_access_gate.dart';
import 'screens/settings/database_connection_screen.dart';
import 'services/database_server_controller.dart';

export 'screens/auth/license_access_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final prefs = await SharedPreferences.getInstance();
  final themeProvider = ThemeProvider(prefs);
  try {
    await DatabaseServerController().startFromPreferences();
  } catch (error) {
    debugPrint('Não foi possível iniciar o servidor de dados: $error');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthProvider(prefs)),
        ChangeNotifierProvider(create: (context) => themeProvider),
        ChangeNotifierProvider(create: (context) => LicenseProvider(prefs)),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final isDark = theme.isDarkMode;

    return MaterialApp(
      title: 'MatterdiSistem ERP',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => LicenseAccessGate(child: child!),
      home: const _AppHome(),
    );
  }

  ThemeData _lightTheme() {
    return ThemeData(
      primaryColor: const Color(0xFF0F62AC),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F62AC),
        primary: const Color(0xFF0F62AC),
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F62AC),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      scaffoldBackgroundColor: Colors.white,
      useMaterial3: true,
    );
  }

  ThemeData _darkTheme() {
    const background = Color(0xFF0F1720);
    const surface = Color(0xFF182431);
    const elevatedSurface = Color(0xFF243447);
    const border = Color(0xFF60758B);
    const primary = Color(0xFF78B7FF);

    return ThemeData(
      primaryColor: const Color(0xFF0F62AC),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F62AC),
        primary: primary,
        onPrimary: const Color(0xFF002B50),
        secondary: const Color(0xFF8FCBFF),
        onSecondary: const Color(0xFF002B45),
        brightness: Brightness.dark,
        surface: surface,
        onSurface: const Color(0xFFF5F7FA),
        onSurfaceVariant: const Color(0xFFD2DCE7),
        surfaceContainerLowest: background,
        surfaceContainerLow: const Color(0xFF131E29),
        surfaceContainer: surface,
        surfaceContainerHigh: const Color(0xFF202E3D),
        surfaceContainerHighest: elevatedSurface,
        outline: border,
        outlineVariant: const Color(0xFF465A70),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF142A3D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: surface,
      dividerColor: border,
      cardTheme: const CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: elevatedSurface,
        labelStyle: TextStyle(color: Color(0xFFD2DCE7)),
        floatingLabelStyle: TextStyle(
          color: primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(color: Color(0xFFAAB8C7)),
        prefixIconColor: Color(0xFFB9C8D8),
        suffixIconColor: Color(0xFFB9C8D8),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFFF8A80), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFFF8A80), width: 2),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(elevatedSurface),
        dataRowColor: WidgetStatePropertyAll(surface),
        dividerThickness: 0.5,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Color(0xFFF5F7FA),
        iconColor: Color(0xFFD2DCE7),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF0F62AC)
              : Colors.grey.shade700,
        ),
      ),
      iconTheme: const IconThemeData(color: Color(0xFFD2DCE7)),
      dividerTheme: const DividerThemeData(color: border, thickness: 0.8),
      useMaterial3: true,
    );
  }
}

class _AppHome extends StatelessWidget {
  const _AppHome();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isInitializing) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DatabaseConnectionScreen(),
                ),
              ),
              icon: const Icon(Icons.dns_outlined),
              label: const Text('Conexão com o banco'),
            ),
          ]),
        ),
      );
    }
    return auth.isAuthenticated ? const MainScreen() : const LoginScreen();
  }
}
