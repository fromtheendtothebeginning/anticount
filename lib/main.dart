import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/env.dart';
import 'providers/ai_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/transaction_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/ai_service.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/settings_service.dart';
import 'services/transaction_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = await DatabaseService.instance.database;
  final prefs = await SharedPreferences.getInstance();

  final authService = AuthService(db);
  final transactionService = TransactionService(db);
  final settingsService = SettingsService(prefs);
  final aiService = AiService();

  runApp(AnticountApp(
    authService: authService,
    transactionService: transactionService,
    settingsService: settingsService,
    aiService: aiService,
  ));
}

class AnticountApp extends StatelessWidget {
  const AnticountApp({
    super.key,
    required this.authService,
    required this.transactionService,
    required this.settingsService,
    required this.aiService,
  });

  final AuthService authService;
  final TransactionService transactionService;
  final SettingsService settingsService;
  final AiService aiService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(authService)..bootstrap(),
        ),
        ChangeNotifierProvider(
          create: (_) => TransactionProvider(transactionService),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(settingsService),
        ),
        ChangeNotifierProvider(
          create: (_) => AiProvider(aiService)..bootstrap(),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          final themeMode = switch (settings.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          return MaterialApp(
            title: currentEnv.appName,
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorSchemeSeed: const Color(0xFF1565C0),
              useMaterial3: true,
              brightness: Brightness.light,
            ),
            darkTheme: ThemeData(
              colorSchemeSeed: const Color(0xFF1565C0),
              useMaterial3: true,
              brightness: Brightness.dark,
            ),
            themeMode: themeMode,
            home: const _RootGate(),
          );
        },
      ),
    );
  }
}

/// 登录态守卫
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return auth.isAuthenticated ? const HomeScreen() : const LoginScreen();
  }
}
